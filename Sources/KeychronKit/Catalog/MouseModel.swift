import Foundation

/// The firmware protocol a mouse speaks. Each family has its own `MouseDriver`.
public enum ProtocolFamily: String, Sendable {
    /// M1/M2/M3/M6/M7 generation: vendor HID interface on usage page 0x8C. Implemented by `ClassicDriver`.
    case classic
    /// 4K generation: vendor HID interface on usage page 0xFF0A. Not implemented yet.
    case nordic
}

/// A physical button. `index` is the firmware key index used by the button commands.
public struct ButtonSlot: Identifiable, Hashable, Sendable {
    public let index: UInt8
    public let name: String
    public let factory: ButtonAction
    public var id: UInt8 { index }

    public init(index: UInt8, name: String, factory: ButtonAction) {
        self.index = index
        self.name = name
        self.factory = factory
    }
}

public struct MouseModel: Hashable, Sendable {
    public let name: String
    /// Keychron's internal device type (from the original app's device table).
    public let typeID: Int
    /// Product IDs the mouse itself reports (USB cable / Bluetooth).
    public let productIDs: [Int]
    public let family: ProtocolFamily
    public let hasLighting: Bool
    public let buttons: [ButtonSlot]

    public var displayName: String { "Keychron \(name)" }

    public init(name: String, typeID: Int, productIDs: [Int], family: ProtocolFamily,
                hasLighting: Bool = false, buttons: [ButtonSlot] = []) {
        self.name = name
        self.typeID = typeID
        self.productIDs = productIDs
        self.family = family
        self.hasLighting = hasLighting
        self.buttons = buttons
    }

    public static func == (a: MouseModel, b: MouseModel) -> Bool { a.typeID == b.typeID }
    public func hash(into h: inout Hasher) { h.combine(typeID) }
}
