import SwiftUI
import KeychronKit

struct HeaderView: View {
    @EnvironmentObject var store: MouseStore

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "computermouse.fill")
                .font(.system(size: 30))
                .foregroundStyle(.tint)
                .frame(width: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(store.model?.displayName ?? "No mouse")
                    .font(.title2.weight(.semibold))
                HStack(spacing: 8) {
                    if store.model != nil {
                        Label(store.link.title, systemImage: store.link.symbol)
                        if !store.info.mouseFirmware.isEmpty { Text("Firmware \(store.info.mouseFirmware)") }
                        if !store.info.receiverFirmware.isEmpty { Text("Receiver \(store.info.receiverFirmware)") }
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if store.busy { ProgressView().controlSize(.small) }
            if let battery = store.battery {
                Label("\(battery.percent)%", systemImage: battery.symbolName)
                    .font(.callout.monospacedDigit())
                    .help(battery.charging ? "Charging" : "Battery")
            }
            Button { store.reload() } label: { Image(systemName: "arrow.clockwise") }
                .help("Reload settings from the mouse (⌘R)")
                .disabled(store.status == .loading || store.status == .bluetooth)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}
