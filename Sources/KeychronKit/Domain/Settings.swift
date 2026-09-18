import Foundation

/// How the configuration interface is reached.
public enum LinkKind: String, Codable, Sendable {
    case wired
    case receiver
    /// Recognised only: the mouse has no configuration channel over Bluetooth.
    case bluetooth
}

public enum PollingRate: Int, CaseIterable, Identifiable, Codable, Sendable {
    case hz125 = 0, hz500 = 1, hz1000 = 2
    public var id: Int { rawValue }
    public var title: String { ["125 Hz", "500 Hz", "1000 Hz"][rawValue] }
}

public struct SensorSettings: Equatable, Codable, Sendable {
    public var highLiftOff: Bool       // false = 1 mm, true = 2 mm
    public var rippleControl: Bool
    public var angleSnapping: Bool
    public var motionSync: Bool
    public var reverseScroll: Bool

    public init(highLiftOff: Bool = false, rippleControl: Bool = false, angleSnapping: Bool = false,
                motionSync: Bool = false, reverseScroll: Bool = false) {
        self.highLiftOff = highLiftOff
        self.rippleControl = rippleControl
        self.angleSnapping = angleSnapping
        self.motionSync = motionSync
        self.reverseScroll = reverseScroll
    }
}

/// Settings stored in the mouse (plus the polling rate, which the receiver holds).
public struct MouseSettings: Equatable, Codable, Sendable {
    public static let dpiRange = 100...26_000
    public static let dpiStep = 100
    public static let debounceRange = 0...20
    public static let defaultDPIValues = [400, 800, 1600, 3200, 5000]

    public var profile = 0
    public var dpiValues = MouseSettings.defaultDPIValues
    public var dpiStage = 0
    public var pollingRate: PollingRate = .hz1000
    public var sensor = SensorSettings()
    public var debounceMs = 8

    public init() {}

    /// Rounds and clamps a DPI value to what the sensor accepts.
    public static func normalizedDPI(_ value: Int) -> Int {
        let clamped = min(dpiRange.upperBound, max(dpiRange.lowerBound, value))
        return Int((Double(clamped) / Double(dpiStep)).rounded()) * dpiStep
    }
}

public struct DeviceInfo: Equatable, Sendable {
    public var mouseFirmware = ""
    public var receiverFirmware = ""
    public init() {}
}

public struct BatteryStatus: Equatable, Sendable {
    public var percent: Int
    public var charging: Bool
    public init(percent: Int, charging: Bool) {
        self.percent = percent
        self.charging = charging
    }
}
