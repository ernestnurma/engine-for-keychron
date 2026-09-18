import Foundation

/// Reply decoders for the classic protocol. All functions tolerate short or malformed replies.
public enum ClassicParsers {
    /// Byte offset of the per-link byte: USB cable uses slot 0, the 2.4 GHz receiver slot 1.
    public static func slot(for link: LinkKind) -> Int { link == .wired ? 0 : 1 }

    /// `51 04`: `[2]` length, `[3…]` ASCII.
    public static func firmware(_ r: [UInt8]) -> String {
        guard r.count > 3 else { return "" }
        let n = min(Int(r[2]), r.count - 3)
        return String(bytes: r[3..<(3 + n)].filter { $0 >= 0x20 && $0 < 0x7F }, encoding: .ascii) ?? ""
    }

    /// `51 03`: product ID of the mouse paired with the receiver, nil if none.
    public static func pairedProductID(_ r: [UInt8]) -> Int? {
        guard r.count > 6 else { return nil }
        let vid = Int(r[3]) | Int(r[4]) << 8
        let pid = Int(r[5]) | Int(r[6]) << 8
        return vid == 0 && pid == 0 ? nil : pid
    }

    /// `51 06`: `[10]` bit 3 is set while the mouse is linked to the receiver.
    /// The receiver keeps reporting the last PID after the mouse switches to Bluetooth, so check this.
    public static func isLinked(_ r: [UInt8]) -> Bool {
        r.count > 10 && r[10] & 0x08 != 0
    }

    /// `51 06`: `[11]` battery percent, `[12]` charging.
    public static func battery(_ r: [UInt8]) -> BatteryStatus? {
        guard r.count > 12, r[11] <= 100 else { return nil }
        return BatteryStatus(percent: Int(r[11]), charging: r[12] != 0)
    }

    /// `52 67`: `[2]` profile, `[3+slot]` DPI stage (low nibble), `[6…15]` five DPI values (LE16),
    /// `[16]` stage count, `[17]` sensor flags, `[18]` debounce. Leaves `pollingRate` untouched.
    public static func profile(_ r: [UInt8], link: LinkKind, into s: inout MouseSettings) {
        guard r.count >= 19 else { return }
        s.profile = Int(r[2])
        s.dpiStage = Int(r[3 + slot(for: link)] & 0x0F)
        let count = max(1, min(5, r[16] == 0 ? 5 : Int(r[16])))
        s.dpiValues = (0..<count).map { Int(r[6 + 2 * $0]) | Int(r[7 + 2 * $0]) << 8 }
        let f = r[17]
        s.sensor = SensorSettings(highLiftOff: f & 0x01 == 0,
                                  rippleControl: f & 0x04 != 0,
                                  angleSnapping: f & 0x08 != 0,
                                  motionSync: f & 0x10 != 0,
                                  reverseScroll: f & 0x40 != 0)
        s.debounceMs = Int(r[18])
    }

    /// `51 07`: polling rate index in the high nibble of `[3+slot]`.
    public static func pollingRate(_ r: [UInt8], link: LinkKind) -> PollingRate? {
        let i = 3 + slot(for: link)
        guard r.count > i else { return nil }
        return PollingRate(rawValue: Int((r[i] >> 4) & 0x07))
    }

    /// `51 12`: `[4]` current light effect.
    public static func lightEffect(_ r: [UInt8]) -> LightEffect? {
        r.count > 4 ? LightEffect(rawValue: Int(r[4])) : nil
    }

    /// `52 61`: function type of button `index` (0 = factory default).
    public static func buttonType(_ r: [UInt8], index: UInt8) -> UInt8 {
        let i = 2 + Int(index)
        return i < r.count ? r[i] : 0
    }

    /// `52 62 i`: `[4]` type, `[5…10]` function data.
    public static func button(_ r: [UInt8]) -> ButtonAction? {
        guard r.count > 10 else { return nil }
        return ClassicButtonCodec.decode(type: r[4], data: Array(r[5...10]))
    }
}
