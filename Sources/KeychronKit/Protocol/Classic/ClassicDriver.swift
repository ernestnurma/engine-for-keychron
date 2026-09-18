import Foundation

/// `MouseDriver` for the classic M-series protocol (M1, M2, M3, M6, M7 and their minis).
public final class ClassicDriver: MouseDriver {
    public let model: MouseModel
    public let link: LinkKind
    private let channel: FeatureReportChannel

    init(model: MouseModel, link: LinkKind, channel: FeatureReportChannel) {
        self.model = model
        self.link = link
        self.channel = channel
    }

    /// Identifies the mouse behind an open classic configuration interface.
    /// - Parameters:
    ///   - productID: the interface's product ID (the mouse itself over a cable, or a receiver).
    ///   - link: `.receiver` when `productID` is a 2.4 GHz receiver.
    public static func connect(channel: FeatureReportChannel, productID: Int, link: LinkKind) async throws -> DriverConnection {
        var mousePID = productID
        if link == .receiver {
            let paired = try await perform { try channel.transact(ClassicCommands.connectedMouse) }
            let info = try await perform { try channel.transact(ClassicCommands.deviceInfo) }
            guard let pid = ClassicParsers.pairedProductID(paired), ClassicParsers.isLinked(info) else {
                return .mouseNotLinked
            }
            mousePID = pid
        }
        guard let model = ModelCatalog.model(forProductID: mousePID) else { return .unknownProductID(mousePID) }
        guard model.family == .classic else { return .unsupported(model) }
        return .connected(ClassicDriver(model: model, link: link, channel: channel))
    }

    // MARK: Reads

    public func readDeviceInfo() async throws -> DeviceInfo {
        var info = DeviceInfo()
        info.mouseFirmware = ClassicParsers.firmware(try await send(ClassicCommands.mouseFirmware))
        if link == .receiver {
            info.receiverFirmware = ClassicParsers.firmware(try await send(ClassicCommands.receiverFirmware))
        }
        return info
    }

    public func readBattery() async throws -> BatteryStatus? {
        let r = try await send(ClassicCommands.deviceInfo)
        if link == .receiver && !ClassicParsers.isLinked(r) { return nil }
        return ClassicParsers.battery(r)
    }

    public func readSettings() async throws -> MouseSettings {
        var s = MouseSettings()
        ClassicParsers.profile(try await send(ClassicCommands.profileData), link: link, into: &s)
        // The polling rate lives in the receiver's snapshot, not in the mouse profile.
        s.pollingRate = ClassicParsers.pollingRate(try await send(ClassicCommands.settingsSnapshot), link: link) ?? .hz1000
        return s
    }

    public func readLightEffect() async throws -> LightEffect? {
        guard model.hasLighting else { return nil }
        return ClassicParsers.lightEffect(try await send(ClassicCommands.lightingInfo))
    }

    public func readButtons() async throws -> [UInt8: ButtonAction] {
        let types = try await send(ClassicCommands.buttonTypes)
        var result: [UInt8: ButtonAction] = [:]
        for slot in model.buttons {
            switch ClassicParsers.buttonType(types, index: slot.index) {
            case 0:
                result[slot.index] = .factoryDefault
            case 4:
                // Macro data is read with a different command; show it as "set elsewhere".
                result[slot.index] = .unsupported(type: 4, data: [])
            default:
                let reply = try await send(ClassicCommands.buttonData(slot.index))
                result[slot.index] = ClassicParsers.button(reply) ?? .factoryDefault
            }
        }
        return result
    }

    // MARK: Writes

    public func apply(_ change: SettingChange) async throws {
        for request in Self.requests(for: change) {
            try await send(request)
        }
    }

    /// The packets that implement a change, in order. Pure, so it's unit-tested byte for byte.
    public static func requests(for change: SettingChange) -> [FeatureRequest] {
        switch change {
        case .dpi(let values, let stage):
            return [ClassicCommands.dpi(values: values, stage: stage)]
        case .pollingRate(let rate):
            return [ClassicCommands.pollingRate(rate)]
        case .sensor(let sensor):
            return [ClassicCommands.sensor(sensor)]
        case .debounce(let ms):
            return [ClassicCommands.debounce(ms)]
        case .lighting(let l):
            var out = [ClassicCommands.lightEffect(l.effect)]
            guard l.effect != .off else { return out }
            out.append(ClassicCommands.lightBrightness(l.effect, l.brightness))
            if l.effect.hasSpeed { out.append(ClassicCommands.lightSpeed(l.effect, l.speed)) }
            if l.effect.hasColor { out.append(ClassicCommands.lightColor(l.effect, l.color)) }
            return out
        case .lightBrightness(let e, let v):
            return e == .off ? [] : [ClassicCommands.lightBrightness(e, v)]
        case .lightSpeed(let e, let v):
            return e.hasSpeed ? [ClassicCommands.lightSpeed(e, v)] : []
        case .lightColor(let e, let c):
            return e.hasColor ? [ClassicCommands.lightColor(e, c)] : []
        case .button(let index, let action):
            return [ClassicCommands.setButton(index, action)]
        case .resetButtons:
            return [ClassicCommands.resetAllButtons]
        case .factoryReset:
            return [ClassicCommands.factoryReset]
        }
    }

    // MARK: I/O

    @discardableResult
    private func send(_ request: FeatureRequest) async throws -> [UInt8] {
        let channel = self.channel
        return try await Self.perform { try channel.transact(request) }
    }

    /// Runs blocking HID I/O on a background queue.
    private static func perform<T>(_ work: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(with: Result { try work() })
            }
        }
    }
}
