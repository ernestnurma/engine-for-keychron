import Foundation
@testable import KeychronKit

/// Parses "51 07 00 24" style hex into bytes.
func hex(_ s: String) -> [UInt8] {
    s.split(separator: " ").map { UInt8($0, radix: 16)! }
}

/// Replies captured from a Keychron M3 (firmware 1.2.2r) on the 2.4 GHz receiver (firmware c.3.0).
enum Captured {
    static let connectedMouse = hex("51 03 01 34 34 33 d0 01")
    static let mouseFirmware = hex("51 04 07 31 2e 32 2e 32 72")
    static let receiverFirmware = hex("51 04 06 63 2e 33 2e 30 00")
    static let deviceInfoLinked = hex("51 06 01 00 34 34 33 d0 22 01 09 57 00")
    static let deviceInfoOnBluetooth = hex("51 06 01 00 34 34 33 d0 22 01 01 53 00")
    static let snapshot1000Hz = hex("51 07 00 24 24 24 90 01 20 03 40 06 80 0c 88 13 35 00 08 00 00")
    static let snapshot500Hz = hex("51 07 00 14 14 14 90 01 20 03 40 06 80 0c 88 13 35 00 08 00 00")
    static let profile = hex("52 67 00 44 44 44 90 01 20 03 40 06 80 0c 88 13 05 35 08 00 00")
    static let profileReversedScroll = hex("52 67 00 44 44 44 90 01 20 03 40 06 80 0c 88 13 05 75 08 00 00")
    static let lightingOff = hex("51 12 01 06 00 ff ff cf cf cd cd cf cd")
    static let buttonTypesAllDefault = hex("52 61 00") + [UInt8](repeating: 0, count: 20)
    static let buttonTypesBackRemapped = hex("52 61 00 00 00 00 01") + [UInt8](repeating: 0, count: 16)
    static let buttonBackAsForward = hex("52 62 04 00 01 08 00 00 00 00 00 00")
}

/// In-memory `FeatureReportChannel`: answers requests from a table and records what was sent.
final class MockChannel: FeatureReportChannel {
    private(set) var sent: [FeatureRequest] = []
    /// Replies keyed by the request's leading bytes (longest match wins).
    var replies: [[UInt8]: [UInt8]] = [:]

    func transact(_ request: FeatureRequest) throws -> [UInt8] {
        sent.append(request)
        guard request.reply != .none else { return [] }
        let match = replies.keys
            .filter { request.bytes.starts(with: $0) }
            .max { $0.count < $1.count }
        guard let key = match else { throw HIDError.timeout }
        return replies[key]!
    }

    static func m3OnReceiver() -> MockChannel {
        let c = MockChannel()
        c.replies = [
            [0x51, 0x03]: Captured.connectedMouse,
            [0x51, 0x04, 0x00]: Captured.mouseFirmware,
            [0x51, 0x04, 0xAA]: Captured.receiverFirmware,
            [0x51, 0x06]: Captured.deviceInfoLinked,
            [0x51, 0x07]: Captured.snapshot1000Hz,
            [0x51, 0x12]: Captured.lightingOff,
            [0x52, 0x67]: Captured.profile,
            [0x52, 0x61]: Captured.buttonTypesAllDefault,
        ]
        return c
    }
}
