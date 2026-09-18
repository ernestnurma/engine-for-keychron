import SwiftUI
import KeychronKit

/// Root view: header plus whatever the connection status calls for.
struct ContentView: View {
    @EnvironmentObject var store: MouseStore

    var body: some View {
        VStack(spacing: 0) {
            HeaderView()
            Divider()
            switch store.status {
            case .ready:
                SettingsTabs()
            case .bluetooth:
                BluetoothView()
            case .searching:
                StatusPlaceholder(symbol: "computermouse", title: "Looking for a Keychron mouse…",
                                  message: "Plug in the 2.4 GHz receiver or connect the mouse with its USB cable.")
            case .loading:
                StatusPlaceholder(symbol: "arrow.triangle.2.circlepath", title: "Reading settings…", message: nil, spinner: true)
            case .mouseOffline:
                StatusPlaceholder(symbol: "moon.zzz", title: "The receiver can't reach the mouse",
                                  message: "Turn the mouse on (2.4 GHz mode) or move it to wake it up.",
                                  action: ("Try Again", { store.reload() }))
            case .unsupported(let message):
                StatusPlaceholder(symbol: "exclamationmark.triangle", title: "Not supported", message: message)
            case .failed(let message):
                StatusPlaceholder(symbol: "xmark.octagon", title: "Couldn't talk to the mouse", message: message,
                                  action: ("Try Again", { store.reload() }))
            }
        }
        .alert("Couldn't apply the change", isPresented: Binding(
            get: { store.lastError != nil }, set: { if !$0 { store.lastError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.lastError ?? "")
        }
    }
}

struct SettingsTabs: View {
    @EnvironmentObject var store: MouseStore

    var body: some View {
        TabView {
            DPIView().tabItem { Text("DPI") }
            PerformanceView().tabItem { Text("Performance") }
            ButtonsView().tabItem { Text("Buttons") }
            if store.model?.hasLighting == true {
                LightingView().tabItem { Text("Lighting") }
            }
            DeviceView().tabItem { Text("Device") }
        }
        .padding(16)
    }
}

struct StatusPlaceholder: View {
    let symbol: String
    let title: String
    let message: String?
    var spinner = false
    var action: (String, () -> Void)? = nil

    var body: some View {
        VStack(spacing: 14) {
            if spinner {
                ProgressView().controlSize(.large)
            } else {
                Image(systemName: symbol).font(.system(size: 44, weight: .light)).foregroundStyle(.secondary)
            }
            Text(title).font(.title3.weight(.semibold))
            if let message {
                Text(message).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 420)
            }
            if let action {
                Button(action.0, action: action.1).controlSize(.large)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
