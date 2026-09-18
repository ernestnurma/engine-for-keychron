import Foundation

// MARK: - Models

/// Physical button slot on a mouse. `index` is the firmware key index used by
/// commands 0x52 0x52 / 0x52 0x61 / 0x52 0x62.
struct ButtonSlot: Identifiable, Hashable {
    let index: UInt8
    let name: String
    let factory: ButtonAction
    var id: UInt8 { index }
}

struct MouseModel: Hashable {
    let name: String
    let typeID: Int
    let pids: [Int]          // own PIDs (USB cable / Bluetooth)
    let hasLighting: Bool
    let buttons: [ButtonSlot]
    /// Mice that use the newer Nordic-based protocol (4K models). Detected but not configurable.
    var usesNordicProtocol: Bool { typeID > 200 }

    static func == (a: MouseModel, b: MouseModel) -> Bool { a.typeID == b.typeID }
    func hash(into h: inout Hasher) { h.combine(typeID) }
}

enum Models {
    /// 2.4 GHz receivers for the classic M-series (config interface 0x8C).
    static let receiverPIDs: Set<Int> = [0xD030, 0xD031]
    /// 2.4 GHz receivers for the 4K / Nordic M-series (config interface 0xFF0A).
    static let nordicReceiverPIDs: Set<Int> = [0xD038, 0xD043]

    private static let leftB  = ButtonSlot(index: 0,  name: "Left button",       factory: .mouse(.left))
    private static let midB   = ButtonSlot(index: 1,  name: "Wheel button",      factory: .mouse(.middle))
    private static let rightB = ButtonSlot(index: 2,  name: "Right button",      factory: .mouse(.right))
    private static let fwdB   = ButtonSlot(index: 3,  name: "Front side button", factory: .mouse(.forward))
    private static let backB  = ButtonSlot(index: 4,  name: "Rear side button",  factory: .mouse(.back))
    private static let wUp    = ButtonSlot(index: 14, name: "Wheel up",          factory: .mouse(.scrollUp))
    private static let wDown  = ButtonSlot(index: 13, name: "Wheel down",        factory: .mouse(.scrollDown))
    private static let basic  = [leftB, rightB, midB, fwdB, backB, wUp, wDown]

    static let all: [MouseModel] = [
        MouseModel(name: "M3", typeID: 101, pids: [0xD032, 0xD033], hasLighting: true,
                   buttons: basic + [ButtonSlot(index: 7, name: "Top button", factory: .lighting(.effect))]),
        MouseModel(name: "M1", typeID: 102, pids: [0xD035], hasLighting: true,
                   buttons: basic + [ButtonSlot(index: 5, name: "Extra front button", factory: .mouse(.forward)),
                                     ButtonSlot(index: 6, name: "Extra rear button", factory: .mouse(.back))]),
        MouseModel(name: "M3 mini", typeID: 103, pids: [0xD036], hasLighting: false, buttons: basic),
        MouseModel(name: "M2", typeID: 105, pids: [0xD03B], hasLighting: false, buttons: basic),
        MouseModel(name: "M3 mini", typeID: 106, pids: [0xD03E], hasLighting: false, buttons: basic),
        MouseModel(name: "M2 mini", typeID: 122, pids: [0xD03D], hasLighting: false, buttons: basic),
        MouseModel(name: "M6", typeID: 160, pids: [0xD03F], hasLighting: false,
                   buttons: basic + [ButtonSlot(index: 8, name: "Wheel tilt left", factory: .mouse(.scrollLeft)),
                                     ButtonSlot(index: 9, name: "Wheel tilt right", factory: .mouse(.scrollRight)),
                                     ButtonSlot(index: 10, name: "Thumb wheel up", factory: .mouse(.scrollLeft)),
                                     ButtonSlot(index: 11, name: "Thumb wheel down", factory: .mouse(.scrollRight))]),
        MouseModel(name: "M7", typeID: 170, pids: [0xD044], hasLighting: false,
                   buttons: basic + [ButtonSlot(index: 7, name: "Side key", factory: .keyboard(modifiers: 0, key: 0x41))]),
        // 4K models (Nordic protocol): recognised only.
        MouseModel(name: "M3 mini 4K", typeID: 201, pids: [0xD037], hasLighting: false, buttons: []),
        MouseModel(name: "M3 4K", typeID: 202, pids: [0xD03C], hasLighting: false, buttons: []),
        MouseModel(name: "M3 mini 4K", typeID: 203, pids: [0xD041], hasLighting: false, buttons: []),
        MouseModel(name: "M2 4K", typeID: 205, pids: [0xD045], hasLighting: false, buttons: []),
        MouseModel(name: "M6 4K", typeID: 206, pids: [0xD046], hasLighting: false, buttons: []),
        MouseModel(name: "M4", typeID: 231, pids: [0xD040], hasLighting: false, buttons: []),
    ]

    static func model(forPID pid: Int) -> MouseModel? { all.first { $0.pids.contains(pid) } }
}

// MARK: - Button actions (10-byte function block used by 0x52 0x52)

enum MouseFunction: Int, CaseIterable, Identifiable {
    case left = 1, middle = 2, right = 3, doubleClick = 4, forward = 5, back = 6
    case scrollUp = 7, scrollDown = 8, scrollLeft = 9, scrollRight = 10
    var id: Int { rawValue }
    var title: String {
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
    /// b1..b3 of the function block.
    var payload: [UInt8] {
        switch self {
        case .left: return [0x01, 0, 0]
        case .middle: return [0x04, 0, 0]
        case .right: return [0x02, 0, 0]
        case .doubleClick: return [0x80, 0, 0]
        case .forward: return [0x08, 0, 0]
        case .back: return [0x10, 0, 0]
        case .scrollUp: return [0, 0x02, 0]
        case .scrollDown: return [0, 0xFE, 0]
        case .scrollLeft: return [0, 0, 0xFE]
        case .scrollRight: return [0, 0, 0x02]
        }
    }
}

enum MediaFunction: Int, CaseIterable, Identifiable {
    case volumeUp = 6, volumeDown = 7, mute = 8, playPause = 2, previous = 4, next = 5
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .volumeUp: return "Volume up"
        case .volumeDown: return "Volume down"
        case .mute: return "Mute"
        case .playPause: return "Play / Pause"
        case .previous: return "Previous track"
        case .next: return "Next track"
        }
    }
    var usage: UInt8 {
        switch self {
        case .volumeUp: return 0xE9
        case .volumeDown: return 0xEA
        case .mute: return 0xE2
        case .playPause: return 0xCD
        case .previous: return 0xB6
        case .next: return 0xB5
        }
    }
}

enum DPIFunction: Int, CaseIterable, Identifiable {
    case cycle = 3, up = 1, down = 2
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .cycle: return "DPI cycle"
        case .up: return "DPI +"
        case .down: return "DPI −"
        }
    }
    var code: UInt8 {
        switch self {
        case .up: return 2
        case .down: return 3
        case .cycle: return 1
        }
    }
}

enum LightingFunction: Int, CaseIterable, Identifiable {
    case effect = 1, speed = 2, color = 3, brighter = 4, dimmer = 5
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .effect: return "Next light effect"
        case .speed: return "Next light speed"
        case .color: return "Next light colour"
        case .brighter: return "Light brightness +"
        case .dimmer: return "Light brightness −"
        }
    }
}

enum ShortcutFunction: Int, CaseIterable, Identifiable {
    case copy = 9, paste = 10, cut = 11, screenshot = 14, missionControl = 16, showDesktop = 12
    case dock = 15, brightnessUp = 1, brightnessDown = 2, refresh = 7, appSwitcher = 8, pageUp = 17, pageDown = 18
    var id: Int { rawValue }
    var title: String {
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
    /// b1..b6 of the function block (b1 = usage page: 0x0C consumer, 0x07 keyboard).
    var payload: [UInt8] {
        switch self {
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

struct Modifiers: OptionSet, Hashable {
    let rawValue: UInt8
    static let control = Modifiers(rawValue: 0x01)
    static let shift = Modifiers(rawValue: 0x02)
    static let option = Modifiers(rawValue: 0x04)
    static let command = Modifiers(rawValue: 0x08)

    var symbols: String {
        var s = ""
        if contains(.control) { s += "⌃" }
        if contains(.option) { s += "⌥" }
        if contains(.shift) { s += "⇧" }
        if contains(.command) { s += "⌘" }
        return s
    }
}

enum ButtonAction: Hashable {
    case factoryDefault
    case mouse(MouseFunction)
    case keyboard(modifiers: UInt8, key: UInt8)
    case media(MediaFunction)
    case dpi(DPIFunction)
    case lighting(LightingFunction)
    case shortcut(ShortcutFunction)
    case disabled
    case unsupported(type: UInt8, data: [UInt8])   // macro / rapid-fire etc. set elsewhere

    var title: String {
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

    /// The 10-byte function block (b0 = function type).
    var functionBlock: [UInt8] {
        var b = [UInt8](repeating: 0, count: 10)
        func put(_ bytes: [UInt8]) { for (i, v) in bytes.enumerated() { b[1 + i] = v } }
        switch self {
        case .factoryDefault: break
        case .mouse(let f): b[0] = 1; put(f.payload)
        case .keyboard(let m, let k):
            b[0] = 2
            if k == 0 { b[1] = m } else { b[1] = m; b[2] = k }
        case .media(let f): b[0] = 3; b[1] = f.usage
        case .dpi(let f): b[0] = 5; b[1] = f.code
        case .lighting(let f): b[0] = 6; b[1] = UInt8(f.rawValue)
        case .shortcut(let f): b[0] = 8; put(f.payload)
        case .disabled: b[0] = 9
        case .unsupported(let t, let data): b[0] = t; put(Array(data.prefix(9)))
        }
        return b
    }

    /// Decode a function block read back with 0x52 0x62 (`type` + b1…b6).
    static func decode(type: UInt8, data d: [UInt8]) -> ButtonAction {
        func at(_ i: Int) -> UInt8 { i < d.count ? d[i] : 0 }
        switch type {
        case 0: return .factoryDefault
        case 1:
            if let f = MouseFunction.allCases.first(where: { $0.payload == [at(0), at(1), at(2)] }) { return .mouse(f) }
        case 2: return .keyboard(modifiers: at(0), key: at(1))
        case 3:
            if let f = MediaFunction.allCases.first(where: { $0.usage == at(0) }) { return .media(f) }
        case 5:
            if let f = DPIFunction.allCases.first(where: { $0.code == at(0) }) { return .dpi(f) }
        case 6:
            if let f = LightingFunction(rawValue: Int(at(0))) { return .lighting(f) }
        case 8:
            if let f = ShortcutFunction.allCases.first(where: { d.starts(with: $0.payload) &&
                d.dropFirst($0.payload.count).allSatisfy { $0 == 0 } }) { return .shortcut(f) }
        case 9: return .disabled
        default: break
        }
        return .unsupported(type: type, data: d)
    }
}

// MARK: - Lighting

enum LightEffect: Int, CaseIterable, Identifiable {
    case off = 0, staticColor = 1, breathing = 2, spectrum = 3, flow = 4, marquee = 5, neon = 6
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .off: return "Off"
        case .staticColor: return "Static"
        case .breathing: return "Breathing"
        case .spectrum: return "Spectrum cycle"
        case .flow: return "Rainbow flow"
        case .marquee: return "Marquee"
        case .neon: return "Neon"
        }
    }
    // From the original app's defaults (config_func bits: 0x02 speed, 0x10 colour).
    var hasSpeed: Bool { [.breathing, .spectrum, .flow, .marquee, .neon].contains(self) }
    var hasColor: Bool { [.staticColor, .breathing, .marquee].contains(self) }
}

// MARK: - Settings snapshot

enum PollingRate: Int, CaseIterable, Identifiable, Codable {
    case hz125 = 0, hz500 = 1, hz1000 = 2
    var id: Int { rawValue }
    var title: String { ["125 Hz", "500 Hz", "1000 Hz"][rawValue] }
}

struct SensorSettings: Equatable, Codable {
    var highLiftOff = false      // false = 1 mm, true = 2 mm
    var rippleControl = false
    var angleSnapping = false
    var motionSync = false
    var reverseScroll = false
}

struct MouseSettings: Equatable, Codable {
    var profile = 0
    var dpiValues: [Int] = [400, 800, 1600, 3200, 5000]
    var dpiStage = 0
    var pollingRate: PollingRate = .hz1000
    var sensor = SensorSettings()
    var debounceMs = 8
}

// MARK: - Commands

enum Cmd {
    static let short = 21   // report 0x51
    static let long = 65    // report 0x52
    static let reset = 64   // 0x51 0x0B

    // Reads
    static let firmwareVersion: [UInt8] = [0x51, 0x04]
    static let connectedMouse: [UInt8] = [0x51, 0x03]
    static let deviceInfo: [UInt8] = [0x51, 0x06]
    static let settingsSnapshot: [UInt8] = [0x51, 0x07]
    static let lightingInfo: [UInt8] = [0x51, 0x12]
    static let profileData: [UInt8] = [0x52, 0x67]
    static let buttonTypes: [UInt8] = [0x52, 0x61]
    static func buttonData(_ i: UInt8) -> [UInt8] { [0x52, 0x62, i] }

    // Writes
    static func dpi(values: [Int], stage: Int) -> [UInt8] {
        var p: [UInt8] = [0x51, 0x40, UInt8(stage), UInt8(stage), UInt8(stage)]
        for v in values.prefix(5) { p += [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF)] }
        p.append(UInt8(min(values.count, 5)))
        return p
    }
    static func pollingRate(_ r: PollingRate) -> [UInt8] {
        let i = UInt8(r.rawValue)
        return [0x51, 0x41, i, i, i, 0x7D, 0x00, 0xF4, 0x01, 0xE8, 0x03]
    }
    static func sensor(_ s: SensorSettings) -> [UInt8] {
        func flag(_ on: Bool) -> UInt8 { on ? 1 : 2 }
        return [0x51, 0x42, s.highLiftOff ? 2 : 1, flag(s.rippleControl), flag(s.angleSnapping),
                flag(s.motionSync), 0x00, s.reverseScroll ? 2 : 1]
    }
    static func debounce(_ ms: Int) -> [UInt8] { [0x51, 0x43, UInt8(max(0, min(20, ms)))] }
    static func lightEffect(_ e: LightEffect) -> [UInt8] { [0x51, 0x22, 0x01, UInt8(e.rawValue)] }
    static func lightBrightness(_ e: LightEffect, _ v: Int) -> [UInt8] { [0x51, 0x23, 0x01, UInt8(e.rawValue), UInt8(v)] }
    static func lightSpeed(_ e: LightEffect, _ v: Int) -> [UInt8] { [0x51, 0x27, 0x01, UInt8(e.rawValue), UInt8(v)] }
    static func lightColor(_ e: LightEffect, r: UInt8, g: UInt8, b: UInt8) -> [UInt8] { [0x51, 0x28, 0x01, UInt8(e.rawValue), r, g, b] }
    static func setButton(_ index: UInt8, _ action: ButtonAction) -> [UInt8] { [0x52, 0x52, index, 0x00] + action.functionBlock }
    static let resetAllButtons: [UInt8] = [0x51, 0x0B, 0x01, 0x01]
    static let resetLighting: [UInt8] = [0x51, 0x0B, 0x01, 0x04]
    static let factoryReset: [UInt8] = [0x51, 0x0B, 0xAA]
}

enum Parse {
    static func ascii(_ r: [UInt8]) -> String {
        guard r.count > 3 else { return "" }
        let n = min(Int(r[2]), r.count - 3)
        return String(bytes: r[3..<(3 + n)].filter { $0 >= 0x20 && $0 < 0x7F }, encoding: .ascii) ?? ""
    }

    /// 0x52 0x67: profile data stored in the mouse.
    ///  [2] profile, [3…5] per-link byte (low nibble DPI stage), [6…15] five DPI values,
    ///  [16] stage count, [17] sensor flags, [18] debounce.
    static func profile(_ r: [UInt8], slot: Int, into s: inout MouseSettings) {
        guard r.count >= 19 else { return }
        s.profile = Int(r[2])
        s.dpiStage = Int(r[3 + slot] & 0x0F)
        let count = max(1, min(5, Int(r[16]) == 0 ? 5 : Int(r[16])))
        s.dpiValues = (0..<count).map { Int(r[6 + 2 * $0]) | Int(r[7 + 2 * $0]) << 8 }
        let f = r[17]
        s.sensor = SensorSettings(highLiftOff: f & 0x01 == 0,
                                  rippleControl: f & 0x04 != 0,
                                  angleSnapping: f & 0x08 != 0,
                                  motionSync: f & 0x10 != 0,
                                  reverseScroll: f & 0x40 != 0)
        s.debounceMs = Int(r[18])
    }

    /// 0x51 0x07: settings snapshot (on the receiver this reflects the polling rate it uses).
    static func pollingRate(_ r: [UInt8], slot: Int) -> PollingRate? {
        guard r.count > 5 else { return nil }
        return PollingRate(rawValue: Int((r[3 + slot] >> 4) & 0x07))
    }
}
