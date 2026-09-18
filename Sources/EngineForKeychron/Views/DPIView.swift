import SwiftUI
import KeychronKit

struct DPIView: View {
    @EnvironmentObject var store: MouseStore

    var body: some View {
        Form {
            Section {
                ForEach(store.settings.dpiValues.indices, id: \.self) { index in
                    DPIStageRow(index: index)
                }
            } header: {
                Text("DPI stages")
            } footer: {
                Text("Pick the active stage with the radio button. The DPI button on the mouse cycles through these stages. Range 100–26 000 in steps of 100.")
                    .foregroundStyle(.secondary)
            }
            Section {
                HStack {
                    Spacer()
                    Button("Restore Default Stages") {
                        store.settings.dpiValues = MouseSettings.defaultDPIValues
                        store.settings.dpiStage = 2
                        store.applyDPI()
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct DPIStageRow: View {
    @EnvironmentObject var store: MouseStore
    let index: Int
    @State private var value: Double = 800

    private var isActive: Bool { store.settings.dpiStage == index }

    var body: some View {
        HStack(spacing: 12) {
            Button {
                store.settings.dpiStage = index
                store.applyDPI()
            } label: {
                Image(systemName: isActive ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isActive ? Color.accentColor : .secondary)
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .help("Make this the active stage")
            Text("Stage \(index + 1)").frame(width: 60, alignment: .leading)
            Slider(value: $value,
                   in: Double(MouseSettings.dpiRange.lowerBound)...Double(MouseSettings.dpiRange.upperBound),
                   step: Double(MouseSettings.dpiStep)) { editing in
                if !editing { commit() }
            }
            TextField("", value: Binding(get: { Int(value) }, set: { value = Double($0) }), format: .number.grouping(.never))
                .frame(width: 70)
                .multilineTextAlignment(.trailing)
                .onSubmit { commit() }
            Text("DPI").foregroundStyle(.secondary)
        }
        .onAppear { value = Double(store.settings.dpiValues[safe: index] ?? 800) }
        .onChange(of: store.settings.dpiValues) { values in value = Double(values[safe: index] ?? 800) }
    }

    private func commit() {
        let dpi = MouseSettings.normalizedDPI(Int(value))
        value = Double(dpi)
        guard store.settings.dpiValues[safe: index] != dpi else { return }
        store.settings.dpiValues[index] = dpi
        store.applyDPI()
    }
}
