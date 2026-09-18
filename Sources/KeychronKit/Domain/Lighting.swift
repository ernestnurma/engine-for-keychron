import Foundation

public enum LightEffect: Int, CaseIterable, Identifiable, Codable, Sendable {
    case off = 0, staticColor = 1, breathing = 2, spectrum = 3, flow = 4, marquee = 5, neon = 6
    public var id: Int { rawValue }
    public var title: String {
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
    public var hasSpeed: Bool { [.breathing, .spectrum, .flow, .marquee, .neon].contains(self) }
    public var hasColor: Bool { [.staticColor, .breathing, .marquee].contains(self) }
}

public struct LightColor: Equatable, Codable, Sendable {
    public var red: UInt8
    public var green: UInt8
    public var blue: UInt8
    public init(red: UInt8, green: UInt8, blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }
    public static let white = LightColor(red: 255, green: 255, blue: 255)
}

public struct LightingSettings: Equatable, Codable, Sendable {
    public static let range = 0...255

    public var effect: LightEffect = .off
    public var brightness = 255
    public var speed = 128
    public var color = LightColor.white

    public init() {}
}
