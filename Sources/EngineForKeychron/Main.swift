import Foundation
import SwiftUI

@main
enum Entry {
    static func main() {
        if CommandLine.arguments.contains("--selftest") {
            SelfTest.run()
        } else {
            EngineForKeychronApp.main()
        }
    }
}

/// `EngineForKeychron --selftest` loads everything the UI shows through the same
/// controller and prints it, without changing any setting on the mouse.
@MainActor
enum SelfTest {
    static func run() {
        let mouse = MouseController()
        Task { @MainActor in
            let deadline = Date().addingTimeInterval(20)
            while Date() < deadline {
                switch mouse.status {
                case .searching, .loading: try? await Task.sleep(nanoseconds: 200_000_000); continue
                default: break
                }
                break
            }
            report(mouse)
            if mouse.status == .bluetooth {
                try? await Task.sleep(nanoseconds: 4_000_000_000)   // let GATT reads arrive
                print("bluetooth: firmware \(mouse.mouseFirmware)  battery \(mouse.battery.map { "\($0)%" } ?? "n/a")")
                print("last known settings:", mouse.lastKnown.map { "\($0.settings.dpiValues) @ \($0.date)" } ?? "none")
                exit(0)
            }
            guard mouse.status == .ready else { exit(1) }
            if CommandLine.arguments.contains("--write") { await writeTest(mouse) }
            exit(0)
        }
        RunLoop.main.run()
    }

    /// Changes a few settings through the app's encoders, verifies them on the mouse and restores them.
    static func writeTest(_ m: MouseController) async {
        let original = m.settings
        guard let model = m.model, let back = model.buttons.first(where: { $0.index == 4 }) else { return }
        var ok = true
        func check(_ what: String, _ cond: Bool) { print(cond ? "PASS" : "FAIL", what); ok = ok && cond }

        var s = original
        s.dpiValues[0] = original.dpiValues[0] == 500 ? 600 : 500
        s.debounceMs = original.debounceMs == 9 ? 10 : 9
        s.sensor.angleSnapping.toggle()
        _ = await m.send(Cmd.dpi(values: s.dpiValues, stage: s.dpiStage))
        _ = await m.send(Cmd.debounce(s.debounceMs))
        _ = await m.send(Cmd.sensor(s.sensor))
        _ = await m.send(Cmd.setButton(back.index, .mouse(.forward)), length: Cmd.long)
        try? await Task.sleep(nanoseconds: 800_000_000)
        await m.load()
        check("DPI stage 1 = \(s.dpiValues[0])", m.settings.dpiValues == s.dpiValues)
        check("debounce = \(s.debounceMs)", m.settings.debounceMs == s.debounceMs)
        check("angle snapping toggled", m.settings.sensor == s.sensor)
        check("rear side button = Forward", m.buttons[back.index] == .mouse(.forward))

        _ = await m.send(Cmd.dpi(values: original.dpiValues, stage: original.dpiStage))
        _ = await m.send(Cmd.debounce(original.debounceMs))
        _ = await m.send(Cmd.sensor(original.sensor))
        _ = await m.send(Cmd.setButton(back.index, .factoryDefault), length: Cmd.long)
        try? await Task.sleep(nanoseconds: 800_000_000)
        await m.load()
        check("restored DPI/debounce/sensor", m.settings.dpiValues == original.dpiValues &&
              m.settings.debounceMs == original.debounceMs && m.settings.sensor == original.sensor)
        check("restored rear side button", m.buttons[back.index] == .factoryDefault)
        print(ok ? "write test passed" : "write test FAILED")
    }

    static func report(_ m: MouseController) {
        print("status:", m.status)
        guard let model = m.model else { return }
        print("model: Keychron \(model.name) (type \(model.typeID))  link: \(m.link)")
        print("firmware: mouse \(m.mouseFirmware)  receiver \(m.receiverFirmware)")
        print("battery:", m.battery.map { "\($0)%" } ?? "n/a", m.charging ? "(charging)" : "")
        if m.status == .bluetooth { return }
        let s = m.settings
        print("profile: \(s.profile + 1)")
        print("dpi: \(s.dpiValues)  active stage: \(s.dpiStage + 1)")
        print("polling: \(s.pollingRate.title)  debounce: \(s.debounceMs) ms")
        print("sensor: \(s.sensor)")
        if model.hasLighting { print("lighting effect: \(m.lighting.effect.title)") }
        for slot in model.buttons {
            print("button \(slot.name): \(m.buttons[slot.index]?.title ?? "?")")
        }
    }
}
