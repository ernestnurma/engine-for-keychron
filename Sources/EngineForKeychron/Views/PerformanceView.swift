import SwiftUI
import KeychronKit

struct PerformanceView: View {
    @EnvironmentObject var store: MouseStore

    var body: some View {
        Form {
            Section("Polling rate") {
                Picker("Report rate", selection: Binding(
                    get: { store.settings.pollingRate },
                    set: { store.settings.pollingRate = $0; store.applyPollingRate() })) {
                    ForEach(PollingRate.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            Section("Sensor") {
                Picker("Lift-off distance", selection: sensorBinding(\.highLiftOff)) {
                    Text("Low (1 mm)").tag(false)
                    Text("High (2 mm)").tag(true)
                }
                .pickerStyle(.segmented)
                Toggle("Ripple control", isOn: sensorBinding(\.rippleControl))
                    .help("Smooths sensor jitter at high DPI (above about 9000).")
                Toggle("Angle snapping", isOn: sensorBinding(\.angleSnapping))
                    .help("Straightens slightly angled movements into straight lines.")
                Toggle("Motion sync", isOn: sensorBinding(\.motionSync))
                    .help("Aligns sensor reads with the polling interval for more consistent tracking.")
            }
            Section("Scrolling") {
                Picker("Scroll direction", selection: sensorBinding(\.reverseScroll)) {
                    Text("Standard").tag(false)
                    Text("Reversed").tag(true)
                }
                .pickerStyle(.segmented)
            }
            Section {
                Stepper(value: Binding(
                    get: { store.settings.debounceMs },
                    set: { store.settings.debounceMs = $0; store.applyDebounce() }),
                        in: MouseSettings.debounceRange) {
                    HStack {
                        Text("Button debounce time")
                        Spacer()
                        Text("\(store.settings.debounceMs) ms").monospacedDigit().foregroundStyle(.secondary)
                    }
                }
            } footer: {
                Text("Raise this if a button registers accidental double clicks.").foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func sensorBinding(_ keyPath: WritableKeyPath<SensorSettings, Bool>) -> Binding<Bool> {
        Binding(get: { store.settings.sensor[keyPath: keyPath] },
                set: { store.settings.sensor[keyPath: keyPath] = $0; store.applySensor() })
    }
}
