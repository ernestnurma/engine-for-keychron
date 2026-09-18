import XCTest
@testable import KeychronKit

final class ClassicParsersTests: XCTestCase {
    func testFirmware() {
        XCTAssertEqual(ClassicParsers.firmware(Captured.mouseFirmware), "1.2.2r")
        XCTAssertEqual(ClassicParsers.firmware(Captured.receiverFirmware), "c.3.0")
        XCTAssertEqual(ClassicParsers.firmware([0x51]), "")
    }

    func testPairedMouseAndLinkState() {
        XCTAssertEqual(ClassicParsers.pairedProductID(Captured.connectedMouse), 0xD033)
        XCTAssertNil(ClassicParsers.pairedProductID(hex("51 03 00 00 00 00 00")))
        XCTAssertTrue(ClassicParsers.isLinked(Captured.deviceInfoLinked))
        XCTAssertFalse(ClassicParsers.isLinked(Captured.deviceInfoOnBluetooth))
    }

    func testBattery() {
        XCTAssertEqual(ClassicParsers.battery(Captured.deviceInfoLinked), BatteryStatus(percent: 87, charging: false))
    }

    func testProfile() {
        var s = MouseSettings()
        ClassicParsers.profile(Captured.profile, link: .receiver, into: &s)
        XCTAssertEqual(s.profile, 0)
        XCTAssertEqual(s.dpiStage, 4)
        XCTAssertEqual(s.dpiValues, [400, 800, 1600, 3200, 5000])
        XCTAssertEqual(s.debounceMs, 8)
        XCTAssertEqual(s.sensor, SensorSettings(highLiftOff: false, rippleControl: true, angleSnapping: false,
                                                motionSync: true, reverseScroll: false))

        ClassicParsers.profile(Captured.profileReversedScroll, link: .receiver, into: &s)
        XCTAssertTrue(s.sensor.reverseScroll)
    }

    func testProfileIgnoresShortReply() {
        var s = MouseSettings()
        s.debounceMs = 3
        ClassicParsers.profile([0x52, 0x67], link: .receiver, into: &s)
        XCTAssertEqual(s.debounceMs, 3)
    }

    func testPollingRate() {
        XCTAssertEqual(ClassicParsers.pollingRate(Captured.snapshot1000Hz, link: .receiver), .hz1000)
        XCTAssertEqual(ClassicParsers.pollingRate(Captured.snapshot500Hz, link: .receiver), .hz500)
    }

    func testLightingAndButtons() {
        XCTAssertEqual(ClassicParsers.lightEffect(Captured.lightingOff), .off)
        XCTAssertEqual(ClassicParsers.buttonType(Captured.buttonTypesBackRemapped, index: 4), 1)
        XCTAssertEqual(ClassicParsers.buttonType(Captured.buttonTypesBackRemapped, index: 3), 0)
        XCTAssertEqual(ClassicParsers.button(Captured.buttonBackAsForward), .mouse(.forward))
    }
}
