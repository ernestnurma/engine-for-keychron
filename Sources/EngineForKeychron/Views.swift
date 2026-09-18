import SwiftUI


struct EngineForKeychronApp: App {
    @StateObject private var mouse = MouseController()

    var body: some Scene {
        WindowGroup("Engine for Keychron") {
            ContentView()
                .environmentObject(mouse)
                .frame(minWidth: 640, idealWidth: 720, minHeight: 560, idealHeight: 640)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(after: .toolbar) {
                Button("Reload from Mouse") { mouse.reload() }.keyboardShortcut("r")
            }
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var mouse: MouseController

    var body: some View {
        VStack(spacing: 0) {
            HeaderView()
            Divider()
            switch mouse.status {
            case .ready:
                SettingsTabs()
            case .bluetooth:
                BluetoothView()
            case .searching:
                Placeholder(symbol: "computermouse", title: "Looking for a Keychron mouse…",
                            message: "Plug in the 2.4 GHz receiver or connect the mouse with its USB cable.")
            case .loading:
                Placeholder(symbol: "arrow.triangle.2.circlepath", title: "Reading settings…", message: nil, spinner: true)
            case .mouseOffline:
                Placeholder(symbol: "moon.zzz", title: "The receiver can't reach the mouse",
                            message: "Turn the mouse on (2.4 GHz mode) or move it to wake it up.",
                            action: ("Try Again", { mouse.reload() }))
            case .unsupported(let msg):
                Placeholder(symbol: "exclamationmark.triangle", title: "Not supported", message: msg)
            case .failed(let msg):
                Placeholder(symbol: "xmark.octagon", title: "Couldn't talk to the mouse", message: msg,
                            action: ("Try Again", { mouse.reload() }))
            }
        }
        .alert("Couldn't apply the change", isPresented: Binding(
            get: { mouse.lastError != nil }, set: { if !$0 { mouse.lastError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(mouse.lastError ?? "")
        }
    }
}

struct Placeholder: View {
    let symbol: String
    let title: String
    let message: String?
    var spinner = false
    var action: (String, () -> Void)? = nil

    var body: some View {
        VStack(spacing: 14) {
            if spinner { ProgressView().controlSize(.large) }
            else { Image(systemName: symbol).font(.system(size: 44, weight: .light)).foregroundStyle(.secondary) }
            Text(title).font(.title3.weight(.semibold))
            if let message { Text(message).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 420) }
            if let action { Button(action.0, action: action.1).controlSize(.large) }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct HeaderView: View {
    @EnvironmentObject var mouse: MouseController

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "computermouse.fill")
                .font(.system(size: 30))
                .foregroundStyle(.tint)
                .frame(width: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(mouse.model.map { "Keychron \($0.name)" } ?? "No mouse")
                    .font(.title2.weight(.semibold))
                HStack(spacing: 8) {
                    if mouse.model != nil {
                        Label(mouse.link.title, systemImage: mouse.link.symbol)
                        if !mouse.mouseFirmware.isEmpty { Text("Firmware \(mouse.mouseFirmware)") }
                        if !mouse.receiverFirmware.isEmpty { Text("Receiver \(mouse.receiverFirmware)") }
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if mouse.busy { ProgressView().controlSize(.small) }
            if let b = mouse.battery {
                Label("\(b)%", systemImage: batterySymbol(b))
                    .font(.callout.monospacedDigit())
                    .help(mouse.charging ? "Charging" : "Battery")
            }
            Button { mouse.reload() } label: { Image(systemName: "arrow.clockwise") }
                .help("Reload settings from the mouse (⌘R)")
                .disabled(mouse.status == .loading)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private func batterySymbol(_ b: Int) -> String {
        if mouse.charging { return "battery.100.bolt" }
        switch b {
        case ..<13: return "battery.0"
        case ..<38: return "battery.25"
        case ..<63: return "battery.50"
        case ..<88: return "battery.75"
        default: return "battery.100"
        }
    }
}

struct SettingsTabs: View {
    @EnvironmentObject var mouse: MouseController

    var body: some View {
        TabView {
            DPIView().tabItem { Text("DPI") }
            PerformanceView().tabItem { Text("Performance") }
            ButtonsView().tabItem { Text("Buttons") }
            if mouse.model?.hasLighting == true {
                LightingView().tabItem { Text("Lighting") }
            }
            DeviceView().tabItem { Text("Device") }
        }
        .padding(16)
    }
}

// MARK: - DPI

struct DPIView: View {
    @EnvironmentObject var mouse: MouseController
    @State private var editing: [Int] = []

    var body: some View {
        Form {
            Section {
                ForEach(mouse.settings.dpiValues.indices, id: \.self) { i in
                    DPIRow(index: i)
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
                        mouse.settings.dpiValues = [400, 800, 1600, 3200, 5000]
                        mouse.settings.dpiStage = 2
                        mouse.applyDPI()
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct DPIRow: View {
    @EnvironmentObject var mouse: MouseController
    let index: Int
    @State private var value: Double = 800

    var body: some View {
        HStack(spacing: 12) {
            Button {
                mouse.settings.dpiStage = index
                mouse.applyDPI()
            } label: {
                Image(systemName: mouse.settings.dpiStage == index ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(mouse.settings.dpiStage == index ? Color.accentColor : .secondary)
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .help("Make this the active stage")
            Text("Stage \(index + 1)").frame(width: 60, alignment: .leading)
            Slider(value: $value, in: 100...26000, step: 100) { editing in
                if !editing { commit() }
            }
            TextField("", value: Binding(get: { Int(value) }, set: { value = Double($0) }), format: .number.grouping(.never))
                .frame(width: 70)
                .multilineTextAlignment(.trailing)
                .onSubmit { commit() }
            Text("DPI").foregroundStyle(.secondary)
        }
        .onAppear { value = Double(mouse.settings.dpiValues[safe: index] ?? 800) }
        .onChange(of: mouse.settings.dpiValues) { v in value = Double(v[safe: index] ?? 800) }
    }

    private func commit() {
        let v = Int((min(26000, max(100, value)) / 100).rounded()) * 100
        value = Double(v)
        guard mouse.settings.dpiValues[safe: index] != v else { return }
        mouse.settings.dpiValues[index] = v
        mouse.applyDPI()
    }
}

// MARK: - Performance

struct PerformanceView: View {
    @EnvironmentObject var mouse: MouseController

    var body: some View {
        Form {
            Section("Polling rate") {
                Picker("Report rate", selection: Binding(
                    get: { mouse.settings.pollingRate },
                    set: { mouse.settings.pollingRate = $0; mouse.applyPollingRate() })) {
                    ForEach(PollingRate.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            Section {
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
            } header: {
                Text("Sensor")
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
                    get: { mouse.settings.debounceMs },
                    set: { mouse.settings.debounceMs = $0; mouse.applyDebounce() }), in: 0...20) {
                    HStack {
                        Text("Button debounce time")
                        Spacer()
                        Text("\(mouse.settings.debounceMs) ms").monospacedDigit().foregroundStyle(.secondary)
                    }
                }
            } footer: {
                Text("Raise this if a button registers accidental double clicks.").foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func sensorBinding(_ kp: WritableKeyPath<SensorSettings, Bool>) -> Binding<Bool> {
        Binding(get: { mouse.settings.sensor[keyPath: kp] },
                set: { mouse.settings.sensor[keyPath: kp] = $0; mouse.applySensor() })
    }
}

// MARK: - Buttons

struct ButtonsView: View {
    @EnvironmentObject var mouse: MouseController
    @State private var editing: ButtonSlot?
    @State private var confirmReset = false

    var body: some View {
        Form {
            Section {
                ForEach(mouse.model?.buttons ?? []) { slot in
                    HStack {
                        Text(slot.name)
                        Spacer()
                        let action = mouse.buttons[slot.index] ?? .factoryDefault
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
            ButtonEditor(slot: slot, current: mouse.buttons[slot.index] ?? .factoryDefault)
                .environmentObject(mouse)
        }
        .confirmationDialog("Reset every button to its factory function?", isPresented: $confirmReset) {
            Button("Reset All Buttons", role: .destructive) { mouse.resetAllButtons() }
        }
    }

    @AppStorage("allowLeftButton") private var allowLeft = false
}

struct ButtonEditor: View {
    @EnvironmentObject var mouse: MouseController
    @Environment(\.dismiss) private var dismiss
    let slot: ButtonSlot
    let current: ButtonAction

    enum Category: String, CaseIterable, Identifiable {
        case def = "Default", mouse = "Mouse", keyboard = "Keyboard key", media = "Media"
        case shortcut = "macOS shortcut", dpi = "DPI", lighting = "Lighting", disabled = "Disabled"
        var id: String { rawValue }
    }

    @State private var category: Category = .def
    @State private var mouseFn: MouseFunction = .left
    @State private var mediaFn: MediaFunction = .playPause
    @State private var shortcutFn: ShortcutFunction = .copy
    @State private var dpiFn: DPIFunction = .cycle
    @State private var lightFn: LightingFunction = .effect
    @State private var key: UInt8 = 0x04
    @State private var ctrl = false
    @State private var shift = false
    @State private var opt = false
    @State private var cmd = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(slot.name).font(.title3.weight(.semibold))
            Form {
                Picker("Function", selection: $category) {
                    ForEach(categories) { Text($0.rawValue).tag($0) }
                }
                switch category {
                case .def:
                    LabeledContent("Factory function", value: slot.factory.title)
                case .mouse:
                    Picker("Action", selection: $mouseFn) { ForEach(MouseFunction.allCases) { Text($0.title).tag($0) } }
                case .keyboard:
                    HStack {
                        Toggle("⌃", isOn: $ctrl).help("Control")
                        Toggle("⌥", isOn: $opt).help("Option")
                        Toggle("⇧", isOn: $shift).help("Shift")
                        Toggle("⌘", isOn: $cmd).help("Command")
                    }
                    .toggleStyle(.button)
                    Picker("Key", selection: $key) {
                        Text("None (modifiers only)").tag(UInt8(0))
                        ForEach(KeyCodes.all) { Text($0.name).tag($0.code) }
                    }
                case .media:
                    Picker("Action", selection: $mediaFn) { ForEach(MediaFunction.allCases) { Text($0.title).tag($0) } }
                case .shortcut:
                    Picker("Action", selection: $shortcutFn) { ForEach(ShortcutFunction.allCases) { Text($0.title).tag($0) } }
                case .dpi:
                    Picker("Action", selection: $dpiFn) { ForEach(DPIFunction.allCases) { Text($0.title).tag($0) } }
                case .lighting:
                    Picker("Action", selection: $lightFn) { ForEach(LightingFunction.allCases) { Text($0.title).tag($0) } }
                case .disabled:
                    Text("The button will do nothing.").foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .frame(height: 210)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Assign") { mouse.assign(action, to: slot); dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(category == .keyboard && key == 0 && modifiers == 0)
            }
        }
        .padding(20)
        .frame(width: 440)
        .onAppear(perform: load)
    }

    private var categories: [Category] {
        Category.allCases.filter { $0 != .lighting || mouse.model?.hasLighting == true }
    }

    private var modifiers: UInt8 {
        var m: Modifiers = []
        if ctrl { m.insert(.control) }
        if shift { m.insert(.shift) }
        if opt { m.insert(.option) }
        if cmd { m.insert(.command) }
        return m.rawValue
    }

    private var action: ButtonAction {
        switch category {
        case .def: return .factoryDefault
        case .mouse: return .mouse(mouseFn)
        case .keyboard: return .keyboard(modifiers: modifiers, key: key)
        case .media: return .media(mediaFn)
        case .shortcut: return .shortcut(shortcutFn)
        case .dpi: return .dpi(dpiFn)
        case .lighting: return .lighting(lightFn)
        case .disabled: return .disabled
        }
    }

    private func load() {
        switch current {
        case .factoryDefault, .unsupported: category = .def
        case .mouse(let f): category = .mouse; mouseFn = f
        case .keyboard(let m, let k):
            category = .keyboard; key = k
            let mods = Modifiers(rawValue: m)
            ctrl = mods.contains(.control); shift = mods.contains(.shift)
            opt = mods.contains(.option); cmd = mods.contains(.command)
        case .media(let f): category = .media; mediaFn = f
        case .shortcut(let f): category = .shortcut; shortcutFn = f
        case .dpi(let f): category = .dpi; dpiFn = f
        case .lighting(let f): category = .lighting; lightFn = f
        case .disabled: category = .disabled
        }
    }
}

// MARK: - Lighting

struct LightingView: View {
    @EnvironmentObject var mouse: MouseController

    var body: some View {
        Form {
            Section("Effect") {
                Picker("Effect", selection: Binding(
                    get: { mouse.lighting.effect },
                    set: { mouse.lighting.effect = $0; mouse.applyLightEffect() })) {
                    ForEach(LightEffect.allCases) { Text($0.title).tag($0) }
                }
            }
            if mouse.lighting.effect != .off {
                Section {
                    LabeledContent("Brightness") {
                        Slider(value: $mouse.lighting.brightness, in: 0...255) { if !$0 { mouse.applyLightBrightness() } }
                    }
                    if mouse.lighting.effect.hasSpeed {
                        LabeledContent("Speed") {
                            Slider(value: $mouse.lighting.speed, in: 0...255) { if !$0 { mouse.applyLightSpeed() } }
                        }
                    }
                    if mouse.lighting.effect.hasColor {
                        ColorPicker("Colour", selection: Binding(
                            get: { mouse.lighting.color },
                            set: { mouse.lighting.color = $0; debounceColor() }), supportsOpacity: false)
                    }
                } footer: {
                    Text("The mouse can report the active effect but not its brightness, speed or colour, so these show the last values set from this Mac.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    @State private var colorTask: Task<Void, Never>?
    private func debounceColor() {
        colorTask?.cancel()
        colorTask = Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            mouse.applyLightColor()
        }
    }
}

// MARK: - Device

struct DeviceView: View {
    @EnvironmentObject var mouse: MouseController
    @State private var confirmFactory = false

    var body: some View {
        Form {
            Section("Information") {
                LabeledContent("Model", value: mouse.model.map { "Keychron \($0.name)" } ?? "—")
                LabeledContent("Connection", value: mouse.link.title)
                LabeledContent("Mouse firmware", value: mouse.mouseFirmware.isEmpty ? "—" : mouse.mouseFirmware)
                if mouse.link == .receiver {
                    LabeledContent("Receiver firmware", value: mouse.receiverFirmware.isEmpty ? "—" : mouse.receiverFirmware)
                }
                LabeledContent("Battery", value: mouse.battery.map { "\($0)%" + (mouse.charging ? " (charging)" : "") } ?? "—")
                LabeledContent("Onboard profile", value: "\(mouse.settings.profile + 1)")
            }
            Section {
                HStack {
                    Spacer()
                    Button("Restore Factory Settings…", role: .destructive) { confirmFactory = true }
                }
            } footer: {
                Text("Resets DPI, polling rate, sensor options, buttons and lighting stored in the mouse.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Restore the mouse to factory settings?", isPresented: $confirmFactory) {
            Button("Restore Factory Settings", role: .destructive) { mouse.factoryReset() }
        } message: {
            Text("All settings stored in the mouse will be erased.")
        }
    }
}

extension LinkKind {
    var title: String {
        switch self {
        case .wired: return "USB cable"
        case .receiver: return "2.4 GHz receiver"
        case .bluetooth: return "Bluetooth"
        }
    }
    var symbol: String {
        switch self {
        case .wired: return "cable.connector"
        case .receiver: return "antenna.radiowaves.left.and.right"
        case .bluetooth: return "wave.3.right"
        }
    }
}

// MARK: - Bluetooth

struct BluetoothView: View {
    @EnvironmentObject var mouse: MouseController

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
                LabeledContent("Model", value: mouse.model.map { "Keychron \($0.name)" } ?? "—")
                LabeledContent("Firmware", value: mouse.mouseFirmware.isEmpty ? "—" : mouse.mouseFirmware)
                LabeledContent("Battery", value: mouse.battery.map { "\($0)%" } ?? "—")
            }
            if let snap = mouse.lastKnown {
                Section {
                    let s = snap.settings
                    LabeledContent("DPI stages", value: s.dpiValues.map(String.init).joined(separator: " · "))
                    LabeledContent("Active stage", value: "\(s.dpiStage + 1) (\(s.dpiValues[safe: s.dpiStage] ?? 0) DPI)")
                    LabeledContent("Lift-off distance", value: s.sensor.highLiftOff ? "High (2 mm)" : "Low (1 mm)")
                    LabeledContent("Ripple control", value: s.sensor.rippleControl ? "On" : "Off")
                    LabeledContent("Angle snapping", value: s.sensor.angleSnapping ? "On" : "Off")
                    LabeledContent("Motion sync", value: s.sensor.motionSync ? "On" : "Off")
                    LabeledContent("Scroll direction", value: s.sensor.reverseScroll ? "Reversed" : "Standard")
                    LabeledContent("Debounce", value: "\(s.debounceMs) ms")
                    if let e = snap.lightEffect { LabeledContent("Lighting", value: e) }
                    ForEach(mouse.model?.buttons ?? []) { slot in
                        LabeledContent(slot.name, value: snap.buttons[slot.name] ?? "—")
                    }
                } header: {
                    Text("Settings stored in the mouse")
                } footer: {
                    Text("As last read over the receiver or cable on \(snap.date.formatted(date: .abbreviated, time: .shortened)). The DPI button on the mouse may have changed the active stage since then.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding(16)
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
