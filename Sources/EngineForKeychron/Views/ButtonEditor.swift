import SwiftUI
import KeychronKit

/// Sheet for choosing what one button does.
struct ButtonEditor: View {
    @EnvironmentObject var store: MouseStore
    @Environment(\.dismiss) private var dismiss
    let slot: ButtonSlot
    let current: ButtonAction

    enum Category: String, CaseIterable, Identifiable {
        case factoryDefault = "Default", mouse = "Mouse", keyboard = "Keyboard key", media = "Media"
        case shortcut = "macOS shortcut", dpi = "DPI", lighting = "Lighting", disabled = "Disabled"
        var id: String { rawValue }
    }

    @State private var category: Category = .factoryDefault
    @State private var mouseFunction: MouseFunction = .left
    @State private var mediaFunction: MediaFunction = .playPause
    @State private var shortcutFunction: ShortcutFunction = .copy
    @State private var dpiFunction: DPIFunction = .cycle
    @State private var lightingFunction: LightingFunction = .effect
    @State private var key: UInt8 = 0x04
    @State private var modifiers: Modifiers = []

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(slot.name).font(.title3.weight(.semibold))
            Form {
                Picker("Function", selection: $category) {
                    ForEach(categories) { Text($0.rawValue).tag($0) }
                }
                details
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .frame(height: 210)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Assign") { store.assign(action, to: slot); dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(category == .keyboard && key == 0 && modifiers.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 440)
        .onAppear { load(current) }
    }

    @ViewBuilder
    private var details: some View {
        switch category {
        case .factoryDefault:
            LabeledContent("Factory function", value: slot.factory.title)
        case .mouse:
            Picker("Action", selection: $mouseFunction) { ForEach(MouseFunction.allCases) { Text($0.title).tag($0) } }
        case .keyboard:
            HStack {
                modifierToggle("⌃", .control, help: "Control")
                modifierToggle("⌥", .option, help: "Option")
                modifierToggle("⇧", .shift, help: "Shift")
                modifierToggle("⌘", .command, help: "Command")
            }
            .toggleStyle(.button)
            Picker("Key", selection: $key) {
                Text("None (modifiers only)").tag(UInt8(0))
                ForEach(KeyCodes.all) { Text($0.name).tag($0.code) }
            }
        case .media:
            Picker("Action", selection: $mediaFunction) { ForEach(MediaFunction.allCases) { Text($0.title).tag($0) } }
        case .shortcut:
            Picker("Action", selection: $shortcutFunction) { ForEach(ShortcutFunction.allCases) { Text($0.title).tag($0) } }
        case .dpi:
            Picker("Action", selection: $dpiFunction) { ForEach(DPIFunction.allCases) { Text($0.title).tag($0) } }
        case .lighting:
            Picker("Action", selection: $lightingFunction) { ForEach(LightingFunction.allCases) { Text($0.title).tag($0) } }
        case .disabled:
            Text("The button will do nothing.").foregroundStyle(.secondary)
        }
    }

    private func modifierToggle(_ symbol: String, _ modifier: Modifiers, help: String) -> some View {
        Toggle(symbol, isOn: Binding(
            get: { modifiers.contains(modifier) },
            set: { if $0 { modifiers.insert(modifier) } else { modifiers.remove(modifier) } }))
            .help(help)
    }

    private var categories: [Category] {
        Category.allCases.filter { $0 != .lighting || store.model?.hasLighting == true }
    }

    private var action: ButtonAction {
        switch category {
        case .factoryDefault: return .factoryDefault
        case .mouse: return .mouse(mouseFunction)
        case .keyboard: return .keyboard(modifiers: modifiers.rawValue, key: key)
        case .media: return .media(mediaFunction)
        case .shortcut: return .shortcut(shortcutFunction)
        case .dpi: return .dpi(dpiFunction)
        case .lighting: return .lighting(lightingFunction)
        case .disabled: return .disabled
        }
    }

    private func load(_ action: ButtonAction) {
        switch action {
        case .factoryDefault, .unsupported: category = .factoryDefault
        case .mouse(let f): category = .mouse; mouseFunction = f
        case .keyboard(let m, let k): category = .keyboard; modifiers = Modifiers(rawValue: m); key = k
        case .media(let f): category = .media; mediaFunction = f
        case .shortcut(let f): category = .shortcut; shortcutFunction = f
        case .dpi(let f): category = .dpi; dpiFunction = f
        case .lighting(let f): category = .lighting; lightingFunction = f
        case .disabled: category = .disabled
        }
    }
}
