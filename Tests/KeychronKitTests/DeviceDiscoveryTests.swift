import XCTest
@testable import KeychronKit

final class DeviceDiscoveryTests: XCTestCase {
    private let receiver = EndpointInfo(productID: 0xD031, product: "Keychron Link", usagePage: 0x8C, transport: "USB")
    private let cable = EndpointInfo(productID: 0xD033, product: "Keychron M3", usagePage: 0x8C, transport: "USB")
    private let bluetooth = EndpointInfo(productID: 0xD033, product: "Keychron M3", usagePage: 0x01, transport: "Bluetooth Low Energy")
    private let nordicReceiver = EndpointInfo(productID: 0xD038, product: "Keychron Link", usagePage: 0xFF0A, transport: "USB")

    private func classify(_ infos: [EndpointInfo]) -> DeviceDiscovery.Result<EndpointInfo> {
        DeviceDiscovery.classify(infos) { $0 }
    }

    func testNothing() {
        guard case .nothing = classify([]) else { return XCTFail() }
    }

    func testReceiver() {
        guard case .configurable(let ep, let link) = classify([receiver]) else { return XCTFail() }
        XCTAssertEqual(ep, receiver)
        XCTAssertEqual(link, .receiver)
    }

    func testCable() {
        guard case .configurable(_, let link) = classify([cable]) else { return XCTFail() }
        XCTAssertEqual(link, .wired)
    }

    func testReceiverWinsOverBluetooth() {
        // The store falls back to Bluetooth if the receiver reports the mouse isn't linked.
        guard case .configurable = classify([bluetooth, receiver]) else { return XCTFail() }
    }

    func testBluetoothOnly() {
        guard case .bluetooth(let model) = classify([bluetooth]) else { return XCTFail() }
        XCTAssertEqual(model.name, "M3")
    }

    func testNordicIsUnsupported() {
        guard case .unsupported = classify([nordicReceiver]) else { return XCTFail() }
    }

    func testCatalogLookups() {
        XCTAssertEqual(ModelCatalog.model(forProductName: "Keychron M3")?.typeID, 101)
        XCTAssertEqual(ModelCatalog.model(forProductID: 0xD035)?.name, "M1")
        XCTAssertEqual(MouseSettings.normalizedDPI(1649), 1600)
        XCTAssertEqual(MouseSettings.normalizedDPI(99_999), 26_000)
    }
}
