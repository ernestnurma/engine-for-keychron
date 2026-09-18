import SwiftUI
import KeychronKit

struct LightingView: View {
    @EnvironmentObject var store: MouseStore
    @State private var colorTask: Task<Void, Never>?

    private var effect: LightEffect { store.lighting.effect }

    var body: some View {
        Form {
            Section("Effect") {
                Picker("Effect", selection: Binding(
                    get: { effect },
                    set: { store.lighting.effect = $0; store.applyLighting(.lighting(store.lighting)) })) {
                    ForEach(LightEffect.allCases) { Text($0.title).tag($0) }
                }
            }
            if effect != .off {
                Section {
                    LabeledContent("Brightness") {
                        Slider(value: level(\.brightness), in: 0...255) { editing in
                            if !editing { store.applyLighting(.lightBrightness(effect, store.lighting.brightness)) }
                        }
                    }
                    if effect.hasSpeed {
                        LabeledContent("Speed") {
                            Slider(value: level(\.speed), in: 0...255) { editing in
                                if !editing { store.applyLighting(.lightSpeed(effect, store.lighting.speed)) }
                            }
                        }
                    }
                    if effect.hasColor {
                        ColorPicker("Colour", selection: Binding(
                            get: { Color(store.lighting.color) },
                            set: { store.lighting.color = LightColor($0); sendColorSoon() }), supportsOpacity: false)
                    }
                } footer: {
                    Text("The mouse can report the active effect but not its brightness, speed or colour, so these show the last values set from this Mac.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    /// Sliders work in Double; lighting levels are stored as 0…255 integers.
    private func level(_ keyPath: WritableKeyPath<LightingSettings, Int>) -> Binding<Double> {
        Binding(get: { Double(store.lighting[keyPath: keyPath]) },
                set: { store.lighting[keyPath: keyPath] = Int($0.rounded()) })
    }

    /// The colour panel reports every drag step; send only once it settles.
    private func sendColorSoon() {
        colorTask?.cancel()
        colorTask = Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            store.applyLighting(.lightColor(effect, store.lighting.color))
        }
    }
}
