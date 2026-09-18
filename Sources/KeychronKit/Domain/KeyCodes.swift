import Foundation

/// USB HID keyboard usages (page 0x07) offered for "Keyboard key" assignments.
public enum KeyCodes {
    public struct Key: Identifiable, Hashable {
        public let code: UInt8
        public let name: String
        public var id: UInt8 { code }
    }

    public static let all: [Key] = {
        var keys: [Key] = []
        for (i, c) in "ABCDEFGHIJKLMNOPQRSTUVWXYZ".enumerated() { keys.append(Key(code: UInt8(0x04 + i), name: String(c))) }
        for (i, c) in "1234567890".enumerated() { keys.append(Key(code: UInt8(0x1E + i), name: String(c))) }
        keys += [
            Key(code: 0x28, name: "Return"), Key(code: 0x29, name: "Escape"), Key(code: 0x2A, name: "Delete (Backspace)"),
            Key(code: 0x2B, name: "Tab"), Key(code: 0x2C, name: "Space"), Key(code: 0x2D, name: "-"),
            Key(code: 0x2E, name: "="), Key(code: 0x2F, name: "["), Key(code: 0x30, name: "]"),
            Key(code: 0x31, name: "\\"), Key(code: 0x33, name: ";"), Key(code: 0x34, name: "'"),
            Key(code: 0x35, name: "`"), Key(code: 0x36, name: ","), Key(code: 0x37, name: "."),
            Key(code: 0x38, name: "/"), Key(code: 0x39, name: "Caps Lock"),
        ]
        for i in 0..<12 { keys.append(Key(code: UInt8(0x3A + i), name: "F\(i + 1)")) }
        keys += [
            Key(code: 0x46, name: "Print Screen"), Key(code: 0x47, name: "Scroll Lock"), Key(code: 0x48, name: "Pause"),
            Key(code: 0x49, name: "Insert"), Key(code: 0x4A, name: "Home"), Key(code: 0x4B, name: "Page Up"),
            Key(code: 0x4C, name: "Forward Delete"), Key(code: 0x4D, name: "End"), Key(code: 0x4E, name: "Page Down"),
            Key(code: 0x4F, name: "→"), Key(code: 0x50, name: "←"), Key(code: 0x51, name: "↓"), Key(code: 0x52, name: "↑"),
        ]
        for i in 0..<12 { keys.append(Key(code: UInt8(0x68 + i), name: "F\(i + 13)")) }
        return keys
    }()

    public static func name(for code: UInt8) -> String {
        all.first { $0.code == code }?.name ?? String(format: "Key 0x%02X", code)
    }
}
