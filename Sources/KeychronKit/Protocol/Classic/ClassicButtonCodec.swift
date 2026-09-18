import Foundation

/// Encodes `ButtonAction` as the classic protocol's 10-byte function block.
/// `b0` is the function type: 1 mouse, 2 keyboard, 3 media, 4 macro, 5 DPI, 6 lighting,
/// 7 rapid fire, 8 shortcut, 9 disabled; all zero means factory default.
public enum ClassicButtonCodec {
    public static let blockLength = 10

    public static func encode(_ action: ButtonAction) -> [UInt8] {
        var b = [UInt8](repeating: 0, count: blockLength)
        func put(_ bytes: [UInt8]) { for (i, v) in bytes.prefix(blockLength - 1).enumerated() { b[1 + i] = v } }
        switch action {
        case .factoryDefault: break
        case .mouse(let f): b[0] = 1; put(payload(f))
        case .keyboard(let m, let k): b[0] = 2; put([m, k])
        case .media(let f): b[0] = 3; b[1] = usage(f)
        case .dpi(let f): b[0] = 5; b[1] = code(f)
        case .lighting(let f): b[0] = 6; b[1] = UInt8(f.rawValue)
        case .shortcut(let f): b[0] = 8; put(payload(f))
        case .disabled: b[0] = 9
        case .unsupported(let t, let data): b[0] = t; put(data)
        }
        return b
    }

    /// Decodes a function block read back with `52 62` (`type` plus `b1…b6`).
    public static func decode(type: UInt8, data d: [UInt8]) -> ButtonAction {
        func at(_ i: Int) -> UInt8 { i < d.count ? d[i] : 0 }
        switch type {
        case 0:
            return .factoryDefault
        case 1:
            if let f = MouseFunction.allCases.first(where: { payload($0) == [at(0), at(1), at(2)] }) { return .mouse(f) }
        case 2:
            return .keyboard(modifiers: at(0), key: at(1))
        case 3:
            if let f = MediaFunction.allCases.first(where: { usage($0) == at(0) }) { return .media(f) }
        case 5:
            if let f = DPIFunction.allCases.first(where: { code($0) == at(0) }) { return .dpi(f) }
        case 6:
            if let f = LightingFunction(rawValue: Int(at(0))) { return .lighting(f) }
        case 8:
            if let f = ShortcutFunction.allCases.first(where: {
                let p = payload($0)
                return d.starts(with: p) && d.dropFirst(p.count).allSatisfy { $0 == 0 }
            }) { return .shortcut(f) }
        case 9:
            return .disabled
        default:
            break
        }
        return .unsupported(type: type, data: d)
    }

    // MARK: Tables (from the original app's encoder)

    /// b1…b3: button bitmask, vertical wheel, horizontal wheel.
    static func payload(_ f: MouseFunction) -> [UInt8] {
        switch f {
        case .left: return [0x01, 0, 0]
        case .right: return [0x02, 0, 0]
        case .middle: return [0x04, 0, 0]
        case .forward: return [0x08, 0, 0]
        case .back: return [0x10, 0, 0]
        case .doubleClick: return [0x80, 0, 0]
        case .scrollUp: return [0, 0x02, 0]
        case .scrollDown: return [0, 0xFE, 0]
        case .scrollLeft: return [0, 0, 0xFE]
        case .scrollRight: return [0, 0, 0x02]
        }
    }

    /// Consumer-page usage.
    static func usage(_ f: MediaFunction) -> UInt8 {
        switch f {
        case .volumeUp: return 0xE9
        case .volumeDown: return 0xEA
        case .mute: return 0xE2
        case .playPause: return 0xCD
        case .previous: return 0xB6
        case .next: return 0xB5
        }
    }

    static func code(_ f: DPIFunction) -> UInt8 {
        switch f {
        case .cycle: return 1
        case .up: return 2
        case .down: return 3
        }
    }

    /// b1 = usage page (0x0C consumer, 0x07 keyboard), then usage or modifier + key.
    static func payload(_ f: ShortcutFunction) -> [UInt8] {
        switch f {
        case .brightnessUp: return [0x0C, 0x6F, 0x00]
        case .brightnessDown: return [0x0C, 0x70, 0x00]
        case .refresh: return [0x07, 0x00, 0x3E]
        case .appSwitcher: return [0x07, 0x08, 0x2B, 0x00, 0x00, 0x01]
        case .copy: return [0x07, 0x08, 0x06]
        case .paste: return [0x07, 0x08, 0x19]
        case .cut: return [0x07, 0x08, 0x1B]
        case .showDesktop: return [0x07, 0x00, 0x44]
        case .missionControl: return [0x07, 0x01, 0x52]
        case .screenshot: return [0x07, 0x0A, 0x21]
        case .dock: return [0x07, 0x0C, 0x07]
        case .pageUp: return [0x07, 0x00, 0x4B]
        case .pageDown: return [0x07, 0x00, 0x4E]
        }
    }
}
