import SwiftUI
import KeychronKit

struct ButtonsView: View {
    @EnvironmentObject var store: MouseStore
    @AppStorage("allowLeftButton") private var allowLeft = false
    @State private var editing: ButtonSlot?
    @State private var confirmReset = false

    var body: some View {
        Form {
            Section {
                ForEach(store.model?.buttons ?? []) { slot in
                    HStack {
                        Text(slot.name)
                        Spacer()
                        let action = store.buttons[slot.index] ?? .factoryDefault
                        Text(action == .factoryDefault ? "Default (\(slot.factory.title))" : action.title)
                            .foregroundStyle(action == .factoryDefault ? .secondary : .primary)
                        Button("Change…") { editing = slot }
                            .disabled(slot.index == 0 && !allowLeft)
                    }
                }
            } header: {
                Text("Button assignments")
            } footer: {
                Text("Changes are saved in the mouse itself, so they work on any computer.").foregroundStyle(.secondary)
            }
            Section {
                Toggle("Allow changing the left button", isOn: $allowLeft)
                HStack {
                    Spacer()
                    Button("Reset All Buttons…", role: .destructive) { confirmReset = true }
                }
            }
        }
        .formStyle(.grouped)
        .sheet(item: $editing) { slot in
            ButtonEditor(slot: slot, current: store.buttons[slot.index] ?? .factoryDefault)
                .environmentObject(store)
        }
        .confirmationDialog("Reset every button to its factory function?", isPresented: $confirmReset) {
            Button("Reset All Buttons", role: .destructive) { store.resetAllButtons() }
        }
    }
}
