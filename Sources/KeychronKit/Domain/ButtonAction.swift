import Foundation

// Protocol-independent description of what a button does. Byte encodings live in the
// protocol layer (see `ClassicButtonCodec`), so other protocol families can reuse these types.

public enum MouseFunction: Int, CaseIterable, Identifiable, Sendable {
    case left = 1, middle = 2, right = 3, doubleClick = 4, forward = 5, back = 6
    case scrollUp = 7, scrollDown = 8, scrollLeft = 9, scrollRight = 10
    public var id: Int { rawValue }
    public var title: String {
        switch self {
        case .left: return "Left click"
        case .right: return "Right click"
        case .middle: return "Middle click"
        case .forward: return "Forward"
        case .back: return "Back"
        case .doubleClick: return "Double click"
        case .scrollUp: return "Scroll up"
        case .scrollDown: return "Scroll down"
        case .scrollLeft: return "Scroll left"
        case .scrollRight: return "Scroll right"
        }
    }
}

public enum MediaFunction: Int, CaseIterable, Identifiable, Sendable {
    case volumeUp = 6, volumeDown = 7, mute = 8, playPause = 2, previous = 4, next = 5
    public var id: Int { rawValue }
    public var title: String {
        switch self {
        case .volumeUp: return "Volume up"
        case .volumeDown: return "Volume down"
        case .mute: return "Mute"
        case .playPause: return "Play / Pause"
        case .previous: return "Previous track"
        case .next: return "Next track"
        }
    }
}

public enum DPIFunction: Int, CaseIterable, Identifiable, Sendable {
    case cycle = 3, up = 1, down = 2
    public var id: Int { rawValue }
    public var title: String {
        switch self {
        case .cycle: return "DPI cycle"
        case .up: return "DPI +"
        case .down: return "DPI −"
        }
    }
}

public enum LightingFunction: Int, CaseIterable, Identifiable, Sendable {
    case effect = 1, speed = 2, color = 3, brighter = 4, dimmer = 5
    public var id: Int { rawValue }
    public var title: String {
        switch self {
        case .effect: return "Next light effect"
        case .speed: return "Next light speed"
        case .color: return "Next light colour"
        case .brighter: return "Light brightness +"
        case .dimmer: return "Light brightness −"
        }
    }
}

public enum ShortcutFunction: Int, CaseIterable, Identifiable, Sendable {
    case copy = 9, paste = 10, cut = 11, screenshot = 14, missionControl = 16, showDesktop = 12
    case dock = 15, brightnessUp = 1, brightnessDown = 2, refresh = 7, appSwitcher = 8, pageUp = 17, pageDown = 18
    public var id: Int { rawValue }
    public var title: String {
        switch self {
        case .copy: return "Copy (⌘C)"
        case .paste: return "Paste (⌘V)"
        case .cut: return "Cut (⌘X)"
        case .screenshot: return "Screenshot area (⇧⌘4)"
        case .missionControl: return "Mission Control (⌃↑)"
        case .showDesktop: return "Show Desktop (F11)"
        case .dock: return "Show/Hide Dock (⌥⌘D)"
        case .brightnessUp: return "Display brightness +"
        case .brightnessDown: return "Display brightness −"
        case .refresh: return "Refresh (F5)"
        case .appSwitcher: return "App switcher (⌘Tab)"
        case .pageUp: return "Page Up"
        case .pageDown: return "Page Down"
        }
    }
}

/// HID keyboard modifier bits.
public struct Modifiers: OptionSet, Hashable, Sendable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }

    public static let control = Modifiers(rawValue: 0x01)
    public static let shift = Modifiers(rawValue: 0x02)
    public static let option = Modifiers(rawValue: 0x04)
    public static let command = Modifiers(rawValue: 0x08)

    public var symbols: String {
        var s = ""
        if contains(.control) { s += "⌃" }
        if contains(.option) { s += "⌥" }
        if contains(.shift) { s += "⇧" }
        if contains(.command) { s += "⌘" }
        return s
    }
}

public enum ButtonAction: Hashable, Sendable {
    case factoryDefault
    case mouse(MouseFunction)
    /// `key` is a HID keyboard usage (0 = modifiers only).
    case keyboard(modifiers: UInt8, key: UInt8)
    case media(MediaFunction)
    case dpi(DPIFunction)
    case lighting(LightingFunction)
    case shortcut(ShortcutFunction)
    case disabled
    /// A function this app can't edit (macro, rapid fire…), kept verbatim so it round-trips.
    case unsupported(type: UInt8, data: [UInt8])

    public var title: String {
        switch self {
        case .factoryDefault: return "Default"
        case .mouse(let f): return f.title
        case .keyboard(let m, let k):
            let mods = Modifiers(rawValue: m).symbols
            return k == 0 ? (mods.isEmpty ? "Key" : mods) : mods + KeyCodes.name(for: k)
        case .media(let f): return f.title
        case .dpi(let f): return f.title
        case .lighting(let f): return f.title
        case .shortcut(let f): return f.title
        case .disabled: return "Disabled"
        case .unsupported(let t, _):
            switch t {
            case 4: return "Macro (set in another app)"
            case 7: return "Rapid fire (set in another app)"
            default: return "Custom (type \(t))"
            }
        }
    }
}
