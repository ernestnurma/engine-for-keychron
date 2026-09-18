import Foundation
import KeychronKit

/// App state for the connected mouse. Orchestrates discovery, the protocol driver, the
/// Bluetooth reader and local persistence; views read from it and call `apply`.
@MainActor
final class MouseStore: ObservableObject {
    enum Status: Equatable {
        case searching
        case loading
        case ready
        /// A receiver is attached but can't reach the mouse (off or asleep).
        case mouseOffline
        /// The mouse is on Bluetooth: information only.
        case bluetooth
        case unsupported(String)
        case failed(String)
    }

    @Published private(set) var status: Status = .searching
    @Published private(set) var model: MouseModel?
    @Published private(set) var link: LinkKind = .wired
    @Published private(set) var info = DeviceInfo()
    @Published private(set) var battery: BatteryStatus?
    @Published private(set) var busy = false
    @Published var lastError: String?

    @Published var settings = MouseSettings()
    @Published var lighting = LightingSettings()
    @Published private(set) var buttons: [UInt8: ButtonAction] = [:]
    @Published private(set) var lastKnown: StoredSnapshot?

    private let transport = HIDTransport()
    private let bluetooth = BluetoothInfoReader()
    private let cache = SettingsCache()
    private var endpoint: HIDEndpoint?
    private var driver: MouseDriver?
    private var rescanTask: Task<Void, Never>?
    private var batteryTimer: Timer?

    init() {
        transport.onDevicesChanged = { [weak self] in self?.scheduleRescan() }
        bluetooth.onUpdate = { [weak self] update in
            guard let self, self.status == .bluetooth else { return }
            if !update.firmware.isEmpty { self.info.mouseFirmware = update.firmware }
            self.battery = update.battery.map { BatteryStatus(percent: $0, charging: false) }
        }
        batteryTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refreshBattery() }
        }
        scheduleRescan()
    }

    // MARK: Discovery

    func scheduleRescan() {
        rescanTask?.cancel()
        rescanTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            await self?.refreshConnection()
        }
    }

    private func refreshConnection() async {
        let endpoints = transport.endpoints()
        switch DeviceDiscovery.classify(endpoints, info: \.info) {
        case .nothing:
            disconnect()
            model = nil
            status = .searching
        case .unsupported(let message):
            disconnect()
            model = nil
            status = .unsupported(message)
        case .bluetooth(let model):
            disconnect()
            enterBluetooth(model)
        case .configurable(let ep, let newLink):
            let bluetoothPresent = DeviceDiscovery.isBluetoothPresent(in: endpoints.map(\.info))
            if ep == endpoint {
                // Same interface: only reload if the mouse may have switched between 2.4 GHz and Bluetooth.
                if status == .ready && !(link == .receiver && bluetoothPresent) { return }
                if status == .bluetooth && bluetoothPresent { return }
            }
            endpoint = ep
            link = newLink
            await load()
        }
    }

    private func disconnect() {
        transport.close()
        endpoint = nil
        driver = nil
    }

    // MARK: Loading

    func reload() {
        Task { await load() }
    }

    private func load() async {
        guard let ep = endpoint else { return }
        bluetooth.stop()
        status = .loading
        lastError = nil
        do {
            try transport.open(ep, viaReceiver: link == .receiver)
            switch try await ClassicDriver.connect(channel: transport, productID: ep.info.productID, link: link) {
            case .connected(let driver):
                self.driver = driver
                model = driver.model
                let snapshot = try await driver.readAll()
                info = snapshot.info
                battery = snapshot.battery
                settings = snapshot.settings
                buttons = snapshot.buttons
                var l = cache.lighting(for: driver.model)
                l.effect = snapshot.lightEffect ?? .off
                lighting = l
                status = .ready
                saveSnapshot()
            case .mouseNotLinked:
                // The receiver is plugged in but the mouse may be on Bluetooth instead.
                if !fallBackToBluetooth() { status = .mouseOffline }
            case .unknownProductID(let pid):
                status = .unsupported(String(format: "Unknown Keychron mouse (PID 0x%04X).", pid))
            case .unsupported(let model):
                status = .unsupported("The \(model.displayName) uses a newer protocol that this app doesn't support yet.")
            }
        } catch {
            if link == .receiver, fallBackToBluetooth() { return }
            status = .failed(error.localizedDescription)
        }
    }

    private func refreshBattery() async {
        guard status == .ready, let driver else { return }
        if let status = try? await driver.readBattery() { battery = status }
    }

    // MARK: Bluetooth

    private func fallBackToBluetooth() -> Bool {
        guard let model = DeviceDiscovery.bluetoothModel(in: transport.endpoints().map(\.info)) else { return false }
        enterBluetooth(model)
        return true
    }

    private func enterBluetooth(_ model: MouseModel) {
        if status == .bluetooth && self.model == model { return }
        self.model = model
        link = .bluetooth
        info = DeviceInfo()
        battery = nil
        lastKnown = cache.snapshot(for: model)
        status = .bluetooth
        bluetooth.stop()
        bluetooth.start()
    }

    // MARK: Writing

    /// Writes a change to the mouse. Returns false (and sets `lastError`) on failure.
    @discardableResult
    func apply(_ change: SettingChange) async -> Bool {
        guard let driver else { return false }
        busy = true
        defer { busy = false }
        do {
            try await driver.apply(change)
            saveSnapshot()
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func applyDPI() {
        let change = SettingChange.dpi(values: settings.dpiValues, stage: settings.dpiStage)
        Task { await apply(change) }
    }

    func applyPollingRate() {
        let change = SettingChange.pollingRate(settings.pollingRate)
        Task { await apply(change) }
    }

    func applySensor() {
        let change = SettingChange.sensor(settings.sensor)
        Task { await apply(change) }
    }

    func applyDebounce() {
        let change = SettingChange.debounce(settings.debounceMs)
        Task { await apply(change) }
    }

    /// Sends the part of the lighting that `change` touches and remembers the values locally.
    func applyLighting(_ change: SettingChange) {
        if let model { cache.saveLighting(lighting, for: model) }
        Task { await apply(change) }
    }

    func assign(_ action: ButtonAction, to slot: ButtonSlot) {
        Task {
            if await apply(.button(index: slot.index, action: action)) {
                buttons[slot.index] = action
                saveSnapshot()
            }
        }
    }

    func resetAllButtons() {
        Task {
            guard await apply(.resetButtons), let driver else { return }
            try? await Task.sleep(nanoseconds: 300_000_000)
            if let fresh = try? await driver.readButtons() {
                buttons = fresh
                saveSnapshot()
            }
        }
    }

    func factoryReset() {
        Task {
            guard await apply(.factoryReset) else { return }
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await load()
        }
    }

    // MARK: Persistence

    private func saveSnapshot() {
        guard let model, status == .ready else { return }
        var names: [String: String] = [:]
        for slot in model.buttons {
            let action = buttons[slot.index] ?? .factoryDefault
            names[slot.name] = action == .factoryDefault ? "Default (\(slot.factory.title))" : action.title
        }
        cache.saveSnapshot(StoredSnapshot(settings: settings,
                                          lightEffect: model.hasLighting ? lighting.effect.title : nil,
                                          buttons: names, date: Date()), for: model)
    }
}
