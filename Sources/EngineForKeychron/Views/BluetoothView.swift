import SwiftUI
import KeychronKit

/// Shown while the mouse is on Bluetooth, which has no configuration channel.
struct BluetoothView: View {
    @EnvironmentObject var store: MouseStore

    var body: some View {
        Form {
            Section {
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Settings can't be changed over Bluetooth").font(.headline)
                        Text("In Bluetooth mode the mouse only acts as a standard mouse. It has no configuration channel, and the original Keychron app couldn't change settings over Bluetooth either. Everything is stored in the mouse, so changes made over the 2.4 GHz receiver or USB cable stay active in Bluetooth mode. To change settings, switch the mouse to 2.4 GHz or plug in the cable.")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } icon: {
                    Image(systemName: "info.circle").foregroundStyle(.tint)
                }
            }
            Section("Mouse") {
                LabeledContent("Model", value: store.model?.displayName ?? "—")
                LabeledContent("Firmware", value: store.info.mouseFirmware.orDash)
                LabeledContent("Battery", value: store.battery.map { "\($0.percent)%" } ?? "—")
            }
            if let snapshot = store.lastKnown {
                lastKnownSection(snapshot)
            }
        }
        .formStyle(.grouped)
        .padding(16)
    }

    private func lastKnownSection(_ snapshot: StoredSnapshot) -> some View {
        let s = snapshot.settings
        return Section {
            LabeledContent("DPI stages", value: s.dpiValues.map(String.init).joined(separator: " · "))
            LabeledContent("Active stage", value: "\(s.dpiStage + 1) (\(s.dpiValues[safe: s.dpiStage] ?? 0) DPI)")
            LabeledContent("Lift-off distance", value: s.sensor.highLiftOff ? "High (2 mm)" : "Low (1 mm)")
            LabeledContent("Ripple control", value: s.sensor.rippleControl.onOff)
            LabeledContent("Angle snapping", value: s.sensor.angleSnapping.onOff)
            LabeledContent("Motion sync", value: s.sensor.motionSync.onOff)
            LabeledContent("Scroll direction", value: s.sensor.reverseScroll ? "Reversed" : "Standard")
            LabeledContent("Debounce", value: "\(s.debounceMs) ms")
            if let effect = snapshot.lightEffect { LabeledContent("Lighting", value: effect) }
            ForEach(store.model?.buttons ?? []) { slot in
                LabeledContent(slot.name, value: snapshot.buttons[slot.name] ?? "—")
            }
        } header: {
            Text("Settings stored in the mouse")
        } footer: {
            Text("As last read over the receiver or cable on \(snapshot.date.formatted(date: .abbreviated, time: .shortened)). The DPI button on the mouse may have changed the active stage since then.")
                .foregroundStyle(.secondary)
        }
    }
}
