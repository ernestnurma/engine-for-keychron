import XCTest
@testable import KeychronKit

/// Every expected packet here was sent to a real M3 and confirmed to work.
final class ClassicCommandsTests: XCTestCase {
    func testDPI() {
        let r = ClassicCommands.dpi(values: [400, 800, 1600, 3200, 5000], stage: 4)
        XCTAssertEqual(r.bytes, hex("51 40 04 04 04 90 01 20 03 40 06 80 0c 88 13 05"))
        XCTAssertEqual(r.length, 21)
        XCTAssertEqual(r.reply, .none)
        XCTAssertEqual(r.padded.count, 21)
    }

    func testPollingRate() {
        XCTAssertEqual(ClassicCommands.pollingRate(.hz1000).bytes, hex("51 41 02 02 02 7d 00 f4 01 e8 03"))
        XCTAssertEqual(ClassicCommands.pollingRate(.hz500).bytes, hex("51 41 01 01 01 7d 00 f4 01 e8 03"))
    }

    func testSensor() {
        let s = SensorSettings(highLiftOff: false, rippleControl: true, angleSnapping: false,
                               motionSync: true, reverseScroll: false)
        XCTAssertEqual(ClassicCommands.sensor(s).bytes, hex("51 42 01 01 02 01 00 01"))
        var reversed = s
        reversed.reverseScroll = true
        XCTAssertEqual(ClassicCommands.sensor(reversed).bytes, hex("51 42 01 01 02 01 00 02"))
    }

    func testDebounceIsClamped() {
        XCTAssertEqual(ClassicCommands.debounce(8).bytes, hex("51 43 08"))
        XCTAssertEqual(ClassicCommands.debounce(99).bytes, hex("51 43 14"))
        XCTAssertEqual(ClassicCommands.debounce(-1).bytes, hex("51 43 00"))
    }

    func testLighting() {
        XCTAssertEqual(ClassicCommands.lightEffect(.staticColor).bytes, hex("51 22 01 01"))
        XCTAssertEqual(ClassicCommands.lightBrightness(.staticColor, 255).bytes, hex("51 23 01 01 ff"))
        XCTAssertEqual(ClassicCommands.lightSpeed(.breathing, 128).bytes, hex("51 27 01 02 80"))
        XCTAssertEqual(ClassicCommands.lightColor(.staticColor, LightColor(red: 255, green: 0, blue: 0)).bytes,
                       hex("51 28 01 01 ff 00 00"))
    }

    func testSetButton() {
        let r = ClassicCommands.setButton(4, .mouse(.forward))
        XCTAssertEqual(Array(r.bytes.prefix(6)), hex("52 52 04 00 01 08"))
        XCTAssertEqual(r.length, 65)
        XCTAssertEqual(ClassicCommands.setButton(4, .factoryDefault).bytes, hex("52 52 04 00") + Array(repeating: 0, count: 10))
    }

    func testResetsAre64Bytes() {
        XCTAssertEqual(ClassicCommands.resetAllButtons.bytes, hex("51 0b 01 01"))
        XCTAssertEqual(ClassicCommands.resetAllButtons.length, 64)
        XCTAssertEqual(ClassicCommands.factoryReset.bytes, hex("51 0b aa"))
    }

    func testReadsOverTheAirAreRelayed() {
        XCTAssertEqual(ClassicCommands.profileData.reply, .relayed)
        XCTAssertEqual(ClassicCommands.buttonTypes.reply, .relayed)
        XCTAssertEqual(ClassicCommands.lightingInfo.reply, .relayed)
        XCTAssertEqual(ClassicCommands.settingsSnapshot.reply, .immediate)
    }
}
