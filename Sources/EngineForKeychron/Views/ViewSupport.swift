import SwiftUI
import AppKit
import KeychronKit

// Presentation helpers for KeychronKit types. Kept in the app so the library stays UI-free.

extension LinkKind {
    var title: String {
        switch self {
        case .wired: return "USB cable"
        case .receiver: return "2.4 GHz receiver"
        case .bluetooth: return "Bluetooth"
        }
    }

    var symbol: String {
        switch self {
        case .wired: return "cable.connector"
        case .receiver: return "antenna.radiowaves.left.and.right"
        case .bluetooth: return "wave.3.right"
        }
    }
}

extension BatteryStatus {
    var symbolName: String {
        if charging { return "battery.100.bolt" }
        switch percent {
        case ..<13: return "battery.0"
        case ..<38: return "battery.25"
        case ..<63: return "battery.50"
        case ..<88: return "battery.75"
        default: return "battery.100"
        }
    }
}

extension Color {
    init(_ rgb: LightColor) {
        self.init(.sRGB, red: Double(rgb.red) / 255, green: Double(rgb.green) / 255, blue: Double(rgb.blue) / 255)
    }
}

extension LightColor {
    init(_ color: Color) {
        let c = NSColor(color).usingColorSpace(.sRGB) ?? .white
        func byte(_ v: CGFloat) -> UInt8 { UInt8(max(0, min(255, (v * 255).rounded()))) }
        self.init(red: byte(c.redComponent), green: byte(c.greenComponent), blue: byte(c.blueComponent))
    }
}

extension String {
    var orDash: String { isEmpty ? "—" : self }
}

extension Bool {
    var onOff: String { self ? "On" : "Off" }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
