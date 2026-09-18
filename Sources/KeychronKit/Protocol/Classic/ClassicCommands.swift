import Foundation

/// Packet builders for the classic M-series protocol (vendor interface, usage page 0x8C).
///
/// Report 0x51 is 21 bytes, report 0x52 is 65 bytes, and the 0x51 0x0B resets are sent as 64 bytes.
/// Every builder returns a complete `FeatureRequest`, so callers never deal with lengths or reply modes.
/// See README → "Protocol notes" for the full reference.
public enum ClassicCommands {
    static let shortLength = 21
    static let longLength = 65
    static let resetLength = 64

    private static func short(_ bytes: [UInt8], _ reply: ReplyMode) -> FeatureRequest {
        FeatureRequest(bytes, length: shortLength, reply: reply)
    }
    private static func long(_ bytes: [UInt8], _ reply: ReplyMode) -> FeatureRequest {
        FeatureRequest(bytes, length: longLength, reply: reply)
    }

    // MARK: Reads

    /// Receiver only: VID/PID of the mouse paired with it (cached; check `deviceInfo` for the link state).
    public static let connectedMouse = short([0x51, 0x03], .immediate)
    public static let mouseFirmware = short([0x51, 0x04, 0x00], .immediate)
    public static let receiverFirmware = short([0x51, 0x04, 0xAA], .immediate)
    /// Link state, battery and charging.
    public static let deviceInfo = short([0x51, 0x06], .immediate)
    /// Snapshot held by the receiver; authoritative only for the polling rate.
    public static let settingsSnapshot = short([0x51, 0x07], .immediate)
    public static let lightingInfo = short([0x51, 0x12], .relayed)
    /// Live DPI, sensor and debounce settings stored in the mouse.
    public static let profileData = long([0x52, 0x67], .relayed)
    public static let buttonTypes = long([0x52, 0x61], .relayed)
    public static func buttonData(_ index: UInt8) -> FeatureRequest { long([0x52, 0x62, index], .relayed) }

    // MARK: Writes

    public static func dpi(values: [Int], stage: Int) -> FeatureRequest {
        let s = UInt8(stage)
        var p: [UInt8] = [0x51, 0x40, s, s, s]
        for v in values.prefix(5) { p += [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF)] }
        p.append(UInt8(min(values.count, 5)))
        return short(p, .none)
    }

    public static func pollingRate(_ rate: PollingRate) -> FeatureRequest {
        let i = UInt8(rate.rawValue)
        // Followed by the rate table (125, 500, 1000 as little-endian words), as the original app sends it.
        return short([0x51, 0x41, i, i, i, 0x7D, 0x00, 0xF4, 0x01, 0xE8, 0x03], .none)
    }

    public static func sensor(_ s: SensorSettings) -> FeatureRequest {
        func flag(_ on: Bool) -> UInt8 { on ? 1 : 2 }
        return short([0x51, 0x42, s.highLiftOff ? 2 : 1, flag(s.rippleControl), flag(s.angleSnapping),
                      flag(s.motionSync), 0x00, s.reverseScroll ? 2 : 1], .none)
    }

    public static func debounce(_ ms: Int) -> FeatureRequest {
        let clamped = min(MouseSettings.debounceRange.upperBound, max(MouseSettings.debounceRange.lowerBound, ms))
        return short([0x51, 0x43, UInt8(clamped)], .none)
    }

    public static func lightEffect(_ e: LightEffect) -> FeatureRequest {
        short([0x51, 0x22, 0x01, UInt8(e.rawValue)], .none)
    }
    public static func lightBrightness(_ e: LightEffect, _ value: Int) -> FeatureRequest {
        short([0x51, 0x23, 0x01, UInt8(e.rawValue), byte(value)], .none)
    }
    public static func lightSpeed(_ e: LightEffect, _ value: Int) -> FeatureRequest {
        short([0x51, 0x27, 0x01, UInt8(e.rawValue), byte(value)], .none)
    }
    public static func lightColor(_ e: LightEffect, _ c: LightColor) -> FeatureRequest {
        short([0x51, 0x28, 0x01, UInt8(e.rawValue), c.red, c.green, c.blue], .none)
    }

    /// Assigns a function to a button. The 10-byte function block starts at byte 4.
    public static func setButton(_ index: UInt8, _ action: ButtonAction) -> FeatureRequest {
        long([0x52, 0x52, index, 0x00] + ClassicButtonCodec.encode(action), .none)
    }

    public static let resetAllButtons = FeatureRequest([0x51, 0x0B, 0x01, 0x01], length: resetLength, reply: .none)
    public static let resetLighting = FeatureRequest([0x51, 0x0B, 0x01, 0x04], length: resetLength, reply: .none)
    public static let factoryReset = FeatureRequest([0x51, 0x0B, 0xAA], length: resetLength, reply: .none)

    private static func byte(_ v: Int) -> UInt8 { UInt8(min(255, max(0, v))) }
}
