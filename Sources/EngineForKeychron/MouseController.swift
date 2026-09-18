import Foundation
import SwiftUI

@MainActor
final class MouseController: ObservableObject {
    enum Status: Equatable {
        case searching
        case loading
        case ready
        case mouseOffline          // receiver found, mouse asleep/off
        case bluetooth             // connected over Bluetooth: info only, settings can't be changed
        case unsupported(String)
        case failed(String)
    }

    struct LightingState: Equatable {
        var effect: LightEffect = .off
        var brightness: Double = 255
        var speed: Double = 128
        var color: Color = .white
    }

    @Published private(set) var status: Status = .searching
    @Published private(set) var model: MouseModel?
    @Published private(set) var link: LinkKind = .wired
    @Published private(set) var mouseFirmware = ""
    @Published private(set) var receiverFirmware = ""
    @Published private(set) var battery: Int?
    @Published private(set) var charging = false
    @Published private(set) var busy = false
    @Published var lastError: String?

    @Published var settings = MouseSettings()
    @Published var lighting = LightingState()
    @Published var buttons: [UInt8: ButtonAction] = [:]
    /// Settings last read over the receiver/cable, shown while the mouse is on Bluetooth.
    @Published private(set) var lastKnown: StoredSnapshot?

    struct StoredSnapshot: Codable, Equatable {
        var settings: MouseSettings
        var lightEffect: String?
        var buttons: [String: String]      // button name -> assignment title
        var date: Date
    }

    private let bluetoothInfo = BluetoothInfo()

    private let transport = HIDTransport()
    private var endpoint: HIDEndpoint?
    private var slot: Int { link == .wired ? 0 : 1 }
    private var batteryTimer: Timer?

    init() {
        transport.onDevicesChanged = { [weak self] in self?.scheduleRescan() }
        bluetoothInfo.onUpdate = { [weak self] info in
            guard let self, self.status == .bluetooth else { return }
            if !info.firmware.isEmpty { self.mouseFirmware = info.firmware }
            self.battery = info.battery
        }
        scheduleRescan()
        batteryTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refreshBattery() }
        }
    }

    // MARK: Discovery

    private var rescanTask: Task<Void, Never>?

    func scheduleRescan() {
        rescanTask?.cancel()
        rescanTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            await self?.connect()
        }
    }

    func connect() async {
        let eps = transport.endpoints()
        let classic = eps.filter { $0.usagePage == HIDTransport.configUsagePage }
            .sorted { !$0.isBluetooth && $1.isBluetooth }
        guard let ep = classic.first(where: { Models.receiverPIDs.contains($0.productID) || Models.model(forPID: $0.productID) != nil })
            ?? classic.first else {
            transport.close()
            endpoint = nil
            if enterBluetoothIfPresent(eps) { return }
            model = nil
            if let nordic = eps.first(where: { $0.usagePage == HIDTransport.nordicUsagePage }) {
                let name = Models.model(forPID: nordic.productID)?.name ?? "4K receiver"
                status = .unsupported("Found a Keychron \(name). The 4K models use a different protocol that this app doesn't support yet.")
            } else {
                status = .searching
            }
            return
        }
        let newLink: LinkKind = Models.receiverPIDs.contains(ep.productID) ? .receiver : .wired
        let btPresent = eps.contains { $0.isBluetooth }
        if ep == endpoint {
            // Same receiver: nothing to do unless the mouse switched between 2.4 GHz and Bluetooth.
            if status == .ready && !(link == .receiver && btPresent) { return }
            if status == .bluetooth && btPresent { return }
        }
        if status == .bluetooth { bluetoothInfo.stop() }
        endpoint = ep
        link = newLink
        await load()
    }

    // MARK: Loading

    func reload() { Task { await load() } }

    func load() async {
        guard let ep = endpoint else { return }
        status = .loading
        lastError = nil
        let link = self.link
        let transport = self.transport
        do {
            try transport.open(ep, link: link)

            var pid = ep.productID
            if link == .receiver {
                let r = try await io { try transport.transact(Cmd.connectedMouse, length: Cmd.short, expectReply: true) }
                let vid = Int(r[3]) | Int(r[4]) << 8
                pid = Int(r[5]) | Int(r[6]) << 8
                // 51 06 byte 10 bit 3: the mouse is currently linked to this receiver.
                let info = try await io { try transport.transact(Cmd.deviceInfo, length: Cmd.short, expectReply: true) }
                let linked = info.count > 10 && info[10] & 0x08 != 0
                if (vid == 0 && pid == 0) || !linked {
                    // Receiver is plugged in but the mouse may be on Bluetooth instead.
                    if !enterBluetoothIfPresent(transport.endpoints()) { status = .mouseOffline }
                    return
                }
            }
            guard let m = Models.model(forPID: pid) else {
                status = .unsupported(String(format: "Unknown Keychron mouse (PID 0x%04X).", pid))
                return
            }
            if m.usesNordicProtocol {
                status = .unsupported("The Keychron \(m.name) uses a newer protocol that this app doesn't support yet.")
                return
            }
            model = m

            let fw = try await io { try transport.transact(Cmd.firmwareVersion + [0x00], length: Cmd.short, expectReply: true) }
            mouseFirmware = Parse.ascii(fw)
            if link == .receiver {
                let rf = try await io { try transport.transact(Cmd.firmwareVersion + [0xAA], length: Cmd.short, expectReply: true) }
                receiverFirmware = Parse.ascii(rf)
            } else {
                receiverFirmware = ""
            }
            await refreshBattery()

            let slot = self.slot
            var s = MouseSettings()
            let prof = try await io { try transport.transact(Cmd.profileData, length: Cmd.long, expectReply: true, asyncReply: link == .receiver) }
            Parse.profile(prof, slot: slot, into: &s)
            let snap = try await io { try transport.transact(Cmd.settingsSnapshot, length: Cmd.short, expectReply: true) }
            s.pollingRate = Parse.pollingRate(snap, slot: slot) ?? .hz1000
            settings = s

            if m.hasLighting {
                let li = try await io { try transport.transact(Cmd.lightingInfo, length: Cmd.short, expectReply: true, asyncReply: link == .receiver) }
                var l = storedLighting(for: m)
                l.effect = LightEffect(rawValue: Int(li[4])) ?? .off
                lighting = l
            }

            try await loadButtons(m)
            status = .ready
            saveSnapshot(m)
        } catch {
            // With the receiver plugged in but the mouse switched to Bluetooth, the receiver can't reach it.
            if link == .receiver, enterBluetoothIfPresent(transport.endpoints()) { return }
            status = .failed(error.localizedDescription)
        }
    }

    func loadButtons(_ m: MouseModel) async throws {
        let transport = self.transport
        let async = link == .receiver
        let types = try await io { try transport.transact(Cmd.buttonTypes, length: Cmd.long, expectReply: true, asyncReply: async) }
        var result: [UInt8: ButtonAction] = [:]
        for slot in m.buttons {
            let i = Int(slot.index)
            let t = 2 + i < types.count ? types[2 + i] : 0
            if t == 0 { result[slot.index] = .factoryDefault; continue }
            if t == 4 { result[slot.index] = .unsupported(type: 4, data: []); continue }
            let d = try await io { try transport.transact(Cmd.buttonData(slot.index), length: Cmd.long, expectReply: true, asyncReply: async) }
            result[slot.index] = ButtonAction.decode(type: d[4], data: Array(d[5...10]))
        }
        buttons = result
    }

    func refreshBattery() async {
        guard endpoint != nil, status != .searching, status != .bluetooth else { return }
        let transport = self.transport
        guard let r = try? await io({ try transport.transact(Cmd.deviceInfo, length: Cmd.short, expectReply: true) }),
              r.count > 12 else { return }
        if r[2] == 0 && link == .receiver { battery = nil; return }
        battery = Int(r[11]) <= 100 ? Int(r[11]) : nil
        charging = r[12] != 0
    }

    // MARK: Writing

    func send(_ packet: [UInt8], length: Int = Cmd.short) async -> Bool {
        let transport = self.transport
        busy = true
        defer { busy = false }
        do {
            _ = try await io { try transport.transact(packet, length: length, expectReply: false) }
            if let m = model { saveSnapshot(m) }
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func applyDPI() {
        let s = settings
        Task { await send(Cmd.dpi(values: s.dpiValues, stage: s.dpiStage)) }
    }

    func applyPollingRate() {
        let r = settings.pollingRate
        Task { await send(Cmd.pollingRate(r)) }
    }

    func applySensor() {
        let s = settings.sensor
        Task { await send(Cmd.sensor(s)) }
    }

    func applyDebounce() {
        let d = settings.debounceMs
        Task { await send(Cmd.debounce(d)) }
    }

    func applyLightEffect() {
        let l = lighting
        storeLighting()
        Task {
            guard await send(Cmd.lightEffect(l.effect)) else { return }
            guard l.effect != .off else { return }
            _ = await send(Cmd.lightBrightness(l.effect, Int(l.brightness)))
            if l.effect.hasSpeed { _ = await send(Cmd.lightSpeed(l.effect, Int(l.speed))) }
            if l.effect.hasColor { await sendColor(l) }
        }
    }

    func applyLightBrightness() {
        let l = lighting
        storeLighting()
        guard l.effect != .off else { return }
        Task { await send(Cmd.lightBrightness(l.effect, Int(l.brightness))) }
    }

    func applyLightSpeed() {
        let l = lighting
        storeLighting()
        guard l.effect.hasSpeed else { return }
        Task { await send(Cmd.lightSpeed(l.effect, Int(l.speed))) }
    }

    func applyLightColor() {
        let l = lighting
        storeLighting()
        guard l.effect.hasColor else { return }
        Task { await sendColor(l) }
    }

    private func sendColor(_ l: LightingState) async {
        let c = NSColor(l.color).usingColorSpace(.sRGB) ?? .white
        let r = UInt8(max(0, min(255, (c.redComponent * 255).rounded())))
        let g = UInt8(max(0, min(255, (c.greenComponent * 255).rounded())))
        let b = UInt8(max(0, min(255, (c.blueComponent * 255).rounded())))
        _ = await send(Cmd.lightColor(l.effect, r: r, g: g, b: b))
    }

    func assign(_ action: ButtonAction, to slot: ButtonSlot) {
        Task {
            if await send(Cmd.setButton(slot.index, action), length: Cmd.long) {
                buttons[slot.index] = action
            }
        }
    }

    func resetAllButtons() {
        Task {
            if await send(Cmd.resetAllButtons, length: Cmd.reset), let m = model {
                try? await Task.sleep(nanoseconds: 300_000_000)
                try? await loadButtons(m)
            }
        }
    }

    func factoryReset() {
        Task {
            if await send(Cmd.factoryReset, length: Cmd.reset) {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                await load()
            }
        }
    }

    // MARK: Bluetooth

    /// Bluetooth exposes only standard HID input reports plus GATT Device Information/Battery
    /// (and a Telink OTA service), so the app shows info and the last-read settings.
    private func enterBluetoothIfPresent(_ eps: [HIDEndpoint]) -> Bool {
        guard let bt = eps.first(where: { $0.isBluetooth }),
              let m = Models.model(forPID: bt.productID) ?? Models.all.first(where: { bt.product.hasSuffix(" " + $0.name) }) else {
            return false
        }
        if status == .bluetooth && model == m { return true }
        model = m
        link = .bluetooth
        receiverFirmware = ""
        mouseFirmware = ""
        battery = nil
        charging = false
        lastKnown = loadSnapshot(m)
        status = .bluetooth
        bluetoothInfo.stop()
        bluetoothInfo.start()
        return true
    }

    private func snapshotKey(_ m: MouseModel) -> String { "snapshot.\(m.typeID)" }

    private func saveSnapshot(_ m: MouseModel) {
        var names: [String: String] = [:]
        for slot in m.buttons {
            let a = buttons[slot.index] ?? .factoryDefault
            names[slot.name] = a == .factoryDefault ? "Default (\(slot.factory.title))" : a.title
        }
        let snap = StoredSnapshot(settings: settings, lightEffect: m.hasLighting ? lighting.effect.title : nil,
                                  buttons: names, date: Date())
        if let data = try? JSONEncoder().encode(snap) { UserDefaults.standard.set(data, forKey: snapshotKey(m)) }
    }

    private func loadSnapshot(_ m: MouseModel) -> StoredSnapshot? {
        guard let data = UserDefaults.standard.data(forKey: snapshotKey(m)) else { return nil }
        return try? JSONDecoder().decode(StoredSnapshot.self, from: data)
    }

    // MARK: Helpers

    private func io<T>(_ work: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                cont.resume(with: Result { try work() })
            }
        }
    }

    // Brightness, speed and colour are write-only on these mice, so remember what was set.
    private func lightingKey(_ m: MouseModel) -> String { "lighting.\(m.typeID)" }

    private func storedLighting(for m: MouseModel) -> LightingState {
        var l = LightingState()
        if let d = UserDefaults.standard.dictionary(forKey: lightingKey(m)) {
            l.brightness = d["brightness"] as? Double ?? 255
            l.speed = d["speed"] as? Double ?? 128
            if let rgb = d["rgb"] as? [Double], rgb.count == 3 {
                l.color = Color(.sRGB, red: rgb[0], green: rgb[1], blue: rgb[2])
            }
        }
        return l
    }

    private func storeLighting() {
        guard let m = model else { return }
        let c = NSColor(lighting.color).usingColorSpace(.sRGB) ?? .white
        UserDefaults.standard.set([
            "brightness": lighting.brightness,
            "speed": lighting.speed,
            "rgb": [Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent)],
        ], forKey: lightingKey(m))
    }
}
