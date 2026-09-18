import Foundation

/// A single change to write to the mouse. Every write the app makes goes through one of these,
/// so a new feature means one new case here and one encoder in each driver.
public enum SettingChange: Equatable, Sendable {
    case dpi(values: [Int], stage: Int)
    case pollingRate(PollingRate)
    case sensor(SensorSettings)
    case debounce(Int)
    /// Switches effect and re-sends the parameters that effect uses.
    case lighting(LightingSettings)
    case lightBrightness(LightEffect, Int)
    case lightSpeed(LightEffect, Int)
    case lightColor(LightEffect, LightColor)
    case button(index: UInt8, action: ButtonAction)
    case resetButtons
    case factoryReset
}

/// Everything readable from a connected mouse.
public struct DeviceSnapshot: Equatable, Sendable {
    public var info: DeviceInfo
    public var battery: BatteryStatus?
    public var settings: MouseSettings
    /// Nil when the model has no lighting.
    public var lightEffect: LightEffect?
    public var buttons: [UInt8: ButtonAction]
}

/// Talks to one connected mouse using one protocol family.
/// Implementations do their I/O off the calling thread and are safe to call from the main actor.
public protocol MouseDriver: AnyObject {
    var model: MouseModel { get }
    var link: LinkKind { get }

    func readDeviceInfo() async throws -> DeviceInfo
    func readBattery() async throws -> BatteryStatus?
    func readSettings() async throws -> MouseSettings
    func readLightEffect() async throws -> LightEffect?
    func readButtons() async throws -> [UInt8: ButtonAction]
    func apply(_ change: SettingChange) async throws
}

public extension MouseDriver {
    func readAll() async throws -> DeviceSnapshot {
        let info = try await readDeviceInfo()
        let battery = try? await readBattery()
        let settings = try await readSettings()
        let effect = model.hasLighting ? try await readLightEffect() : nil
        let buttons = try await readButtons()
        return DeviceSnapshot(info: info, battery: battery ?? nil, settings: settings,
                              lightEffect: effect, buttons: buttons)
    }
}

/// Outcome of trying to reach a mouse through a configuration interface.
public enum DriverConnection {
    case connected(MouseDriver)
    /// A receiver is present but no mouse is linked to it (off, asleep, or on Bluetooth).
    case mouseNotLinked
    case unknownProductID(Int)
    /// Known model whose protocol family has no driver yet.
    case unsupported(MouseModel)
}
