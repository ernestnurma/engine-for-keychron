import XCTest
@testable import KeychronKit

final class ClassicDriverTests: XCTestCase {
    private func connectedM3(_ channel: MockChannel) async throws -> MouseDriver {
        guard case .connected(let driver) = try await ClassicDriver.connect(channel: channel, productID: 0xD031, link: .receiver) else {
            XCTFail("expected a connected driver")
            throw HIDError.notOpen
        }
        return driver
    }

    func testConnectIdentifiesMouseBehindReceiver() async throws {
        let driver = try await connectedM3(.m3OnReceiver())
        XCTAssertEqual(driver.model.name, "M3")
        XCTAssertEqual(driver.link, .receiver)
    }

    func testConnectReportsMouseOnBluetooth() async throws {
        let channel = MockChannel.m3OnReceiver()
        channel.replies[[0x51, 0x06]] = Captured.deviceInfoOnBluetooth
        guard case .mouseNotLinked = try await ClassicDriver.connect(channel: channel, productID: 0xD031, link: .receiver) else {
            return XCTFail("expected mouseNotLinked")
        }
    }

    func testConnectRejectsNordicModel() async throws {
        let result = try await ClassicDriver.connect(channel: MockChannel(), productID: 0xD040, link: .wired)
        guard case .unsupported(let model) = result else { return XCTFail("expected unsupported") }
        XCTAssertEqual(model.name, "M4")
    }

    func testReadAll() async throws {
        let snapshot = try await connectedM3(.m3OnReceiver()).readAll()
        XCTAssertEqual(snapshot.info.mouseFirmware, "1.2.2r")
        XCTAssertEqual(snapshot.info.receiverFirmware, "c.3.0")
        XCTAssertEqual(snapshot.battery?.percent, 87)
        XCTAssertEqual(snapshot.settings.dpiValues, [400, 800, 1600, 3200, 5000])
        XCTAssertEqual(snapshot.settings.pollingRate, .hz1000)
        XCTAssertEqual(snapshot.lightEffect, .off)
        XCTAssertEqual(snapshot.buttons.count, 8)
        XCTAssertTrue(snapshot.buttons.values.allSatisfy { $0 == .factoryDefault })
    }

    func testReadButtonsFetchesDetailsOnlyForRemappedButtons() async throws {
        let channel = MockChannel.m3OnReceiver()
        channel.replies[[0x52, 0x61]] = Captured.buttonTypesBackRemapped
        channel.replies[[0x52, 0x62, 0x04]] = Captured.buttonBackAsForward
        let buttons = try await connectedM3(channel).readButtons()
        XCTAssertEqual(buttons[4], .mouse(.forward))
        XCTAssertEqual(buttons[3], .factoryDefault)
        XCTAssertEqual(channel.sent.filter { $0.bytes.starts(with: [0x52, 0x62]) }.count, 1)
    }

    func testApplyLightingSendsOnlyRelevantParameters() {
        var l = LightingSettings()
        l.effect = .spectrum   // has speed, no colour
        let sent = ClassicDriver.requests(for: .lighting(l)).map { $0.bytes[1] }
        XCTAssertEqual(sent, [0x22, 0x23, 0x27])

        l.effect = .off
        XCTAssertEqual(ClassicDriver.requests(for: .lighting(l)).map { $0.bytes[1] }, [0x22])
        XCTAssertTrue(ClassicDriver.requests(for: .lightColor(.spectrum, .white)).isEmpty)
    }

    func testApplyWritesThroughChannel() async throws {
        let channel = MockChannel.m3OnReceiver()
        let driver = try await connectedM3(channel)
        try await driver.apply(.debounce(9))
        XCTAssertEqual(channel.sent.last?.bytes, hex("51 43 09"))
    }
}
