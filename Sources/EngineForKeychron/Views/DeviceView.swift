import SwiftUI
import KeychronKit

struct DeviceView: View {
    @EnvironmentObject var store: MouseStore
    @State private var confirmFactoryReset = false

    var body: some View {
        Form {
            Section("Information") {
                LabeledContent("Model", value: store.model?.displayName ?? "—")
                LabeledContent("Connection", value: store.link.title)
                LabeledContent("Mouse firmware", value: store.info.mouseFirmware.orDash)
                if store.link == .receiver {
                    LabeledContent("Receiver firmware", value: store.info.receiverFirmware.orDash)
                }
                LabeledContent("Battery", value: store.battery.map { "\($0.percent)%" + ($0.charging ? " (charging)" : "") } ?? "—")
                LabeledContent("Onboard profile", value: "\(store.settings.profile + 1)")
            }
            Section {
                HStack {
                    Spacer()
                    Button("Restore Factory Settings…", role: .destructive) { confirmFactoryReset = true }
                }
            } footer: {
                Text("Resets DPI, polling rate, sensor options, buttons and lighting stored in the mouse.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Restore the mouse to factory settings?", isPresented: $confirmFactoryReset) {
            Button("Restore Factory Settings", role: .destructive) { store.factoryReset() }
        } message: {
            Text("All settings stored in the mouse will be erased.")
        }
    }
}
