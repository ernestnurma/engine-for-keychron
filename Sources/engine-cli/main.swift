import Foundation
import KeychronKit

// Hardware diagnostics for a connected mouse.
//
//   engine-cli info         read and print everything (changes nothing)
//   engine-cli write-test   change a few settings, verify them on the mouse, then restore them

let usage = """
usage: engine-cli <command>

commands:
  info         print model, firmware, battery, settings and button assignments
  write-test   change DPI, debounce, a sensor option and a button; verify; restore
"""

let transport = HIDTransport()

func fail(_ message: String) -> Never {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    exit(1)
}

func connect() async throws -> MouseDriver {
    // Give IOKit a moment to report attached devices.
    try await Task.sleep(nanoseconds: 300_000_000)
    let endpoints = transport.endpoints()
    switch DeviceDiscovery.classify(endpoints, info: \.info) {
    case .nothing:
        fail("No Keychron mouse or receiver found.")
    case .bluetooth(let model):
        fail("\(model.displayName) is connected over Bluetooth, which has no configuration channel.")
    case .unsupported(let message):
        fail(message)
    case .configurable(let endpoint, let link):
        try transport.open(endpoint, viaReceiver: link == .receiver)
        switch try await ClassicDriver.connect(channel: transport, productID: endpoint.info.productID, link: link) {
        case .connected(let driver): return driver
        case .mouseNotLinked: fail("The receiver can't reach the mouse (off, asleep, or on Bluetooth).")
        case .unknownProductID(let pid): fail(String(format: "Unknown Keychron mouse (PID 0x%04X).", pid))
        case .unsupported(let model): fail("\(model.displayName) uses a protocol this app doesn't support yet.")
        }
    }
}

func printSnapshot(_ driver: MouseDriver, _ s: DeviceSnapshot) {
    print("model:    \(driver.model.displayName) (type \(driver.model.typeID)) via \(driver.link.rawValue)")
    print("firmware: mouse \(s.info.mouseFirmware)" + (s.info.receiverFirmware.isEmpty ? "" : ", receiver \(s.info.receiverFirmware)"))
    print("battery:  " + (s.battery.map { "\($0.percent)%" + ($0.charging ? " (charging)" : "") } ?? "n/a"))
    let st = s.settings
    print("profile:  \(st.profile + 1)")
    print("dpi:      \(st.dpiValues.map(String.init).joined(separator: " / ")), active stage \(st.dpiStage + 1)")
    print("polling:  \(st.pollingRate.title), debounce \(st.debounceMs) ms")
    print("sensor:   lift-off \(st.sensor.highLiftOff ? "2 mm" : "1 mm"), ripple \(st.sensor.rippleControl), "
          + "angle snap \(st.sensor.angleSnapping), motion sync \(st.sensor.motionSync), "
          + "reverse scroll \(st.sensor.reverseScroll)")
    if let e = s.lightEffect { print("lighting: \(e.title)") }
    for slot in driver.model.buttons {
        print("button:   \(slot.name) = \(s.buttons[slot.index]?.title ?? "?")")
    }
}

func writeTest(_ driver: MouseDriver) async throws -> Bool {
    let original = try await driver.readAll()
    guard let slot = driver.model.buttons.first(where: { $0.index == 4 }) else { return false }
    var ok = true
    func check(_ what: String, _ condition: Bool) {
        print(condition ? "PASS" : "FAIL", what)
        ok = ok && condition
    }
    func settle() async throws { try await Task.sleep(nanoseconds: 800_000_000) }

    var changed = original.settings
    changed.dpiValues[0] = original.settings.dpiValues[0] == 500 ? 600 : 500
    changed.debounceMs = original.settings.debounceMs == 9 ? 10 : 9
    changed.sensor.angleSnapping.toggle()
    try await driver.apply(.dpi(values: changed.dpiValues, stage: changed.dpiStage))
    try await driver.apply(.debounce(changed.debounceMs))
    try await driver.apply(.sensor(changed.sensor))
    try await driver.apply(.button(index: slot.index, action: .mouse(.forward)))
    try await settle()

    let after = try await driver.readAll()
    check("DPI stage 1 = \(changed.dpiValues[0])", after.settings.dpiValues == changed.dpiValues)
    check("debounce = \(changed.debounceMs) ms", after.settings.debounceMs == changed.debounceMs)
    check("angle snapping toggled", after.settings.sensor == changed.sensor)
    check("\(slot.name) = Forward", after.buttons[slot.index] == .mouse(.forward))

    let o = original.settings
    try await driver.apply(.dpi(values: o.dpiValues, stage: o.dpiStage))
    try await driver.apply(.debounce(o.debounceMs))
    try await driver.apply(.sensor(o.sensor))
    try await driver.apply(.button(index: slot.index, action: original.buttons[slot.index] ?? .factoryDefault))
    try await settle()

    let restored = try await driver.readAll()
    check("settings restored", restored.settings.dpiValues == o.dpiValues
          && restored.settings.debounceMs == o.debounceMs && restored.settings.sensor == o.sensor)
    check("\(slot.name) restored", restored.buttons[slot.index] == original.buttons[slot.index])
    return ok
}

let command = CommandLine.arguments.dropFirst().first ?? ""
guard ["info", "write-test"].contains(command) else { print(usage); exit(command.isEmpty ? 0 : 2) }

Task {
    do {
        let driver = try await connect()
        switch command {
        case "info":
            printSnapshot(driver, try await driver.readAll())
            exit(0)
        default:
            let passed = try await writeTest(driver)
            print(passed ? "write test passed" : "write test FAILED")
            exit(passed ? 0 : 1)
        }
    } catch {
        fail("error: \(error.localizedDescription)")
    }
}
RunLoop.main.run()
