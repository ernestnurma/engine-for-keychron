import SwiftUI

@main
struct EngineForKeychronApp: App {
    @StateObject private var store = MouseStore()

    var body: some Scene {
        WindowGroup("Engine for Keychron") {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 640, idealWidth: 720, minHeight: 560, idealHeight: 640)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(after: .toolbar) {
                Button("Reload from Mouse") { store.reload() }.keyboardShortcut("r")
            }
        }
    }
}
