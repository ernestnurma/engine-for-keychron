import Foundation
import KeychronKit

/// Settings last read over the receiver or cable, shown while the mouse is on Bluetooth.
struct StoredSnapshot: Codable, Equatable {
    var settings: MouseSettings
    var lightEffect: String?
    var buttons: [String: String]      // button name -> assignment title
    var date: Date
}

/// Local persistence for things the mouse can't report back.
struct SettingsCache {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // Brightness, speed and colour are write-only on these mice, so remember what was set.
    func lighting(for model: MouseModel) -> LightingSettings {
        decode(LightingSettings.self, key: "lighting.\(model.typeID)") ?? LightingSettings()
    }

    func saveLighting(_ lighting: LightingSettings, for model: MouseModel) {
        encode(lighting, key: "lighting.\(model.typeID)")
    }

    func snapshot(for model: MouseModel) -> StoredSnapshot? {
        decode(StoredSnapshot.self, key: "snapshot.\(model.typeID)")
    }

    func saveSnapshot(_ snapshot: StoredSnapshot, for model: MouseModel) {
        encode(snapshot, key: "snapshot.\(model.typeID)")
    }

    private func decode<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func encode<T: Encodable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) }
    }
}
