import XCTest
@testable import KeychronKit

final class ClassicButtonCodecTests: XCTestCase {
    /// Every action the UI can assign must decode back to itself from what the mouse returns
    /// (`52 62` reports the type plus the first six data bytes).
    func testEveryEditableActionRoundTrips() {
        var actions: [ButtonAction] = [.factoryDefault, .disabled,
                                       .keyboard(modifiers: Modifiers.command.rawValue, key: 0x04),
                                       .keyboard(modifiers: Modifiers([.control, .shift]).rawValue, key: 0)]
        actions += MouseFunction.allCases.map { .mouse($0) }
        actions += MediaFunction.allCases.map { .media($0) }
        actions += DPIFunction.allCases.map { .dpi($0) }
        actions += LightingFunction.allCases.map { .lighting($0) }
        actions += ShortcutFunction.allCases.map { .shortcut($0) }

        for action in actions {
            let block = ClassicButtonCodec.encode(action)
            XCTAssertEqual(block.count, ClassicButtonCodec.blockLength)
            let decoded = ClassicButtonCodec.decode(type: block[0], data: Array(block[1...6]))
            XCTAssertEqual(decoded, action, "\(action.title)")
        }
    }

    func testKnownEncodings() {
        XCTAssertEqual(ClassicButtonCodec.encode(.mouse(.forward)).prefix(2), [0x01, 0x08])
        XCTAssertEqual(ClassicButtonCodec.encode(.media(.playPause)).prefix(2), [0x03, 0xCD])
        XCTAssertEqual(ClassicButtonCodec.encode(.dpi(.cycle)).prefix(2), [0x05, 0x01])
        XCTAssertEqual(ClassicButtonCodec.encode(.shortcut(.screenshot)).prefix(4), [0x08, 0x07, 0x0A, 0x21])
        XCTAssertEqual(ClassicButtonCodec.encode(.keyboard(modifiers: 0x08, key: 0x04)).prefix(3), [0x02, 0x08, 0x04])
        XCTAssertEqual(ClassicButtonCodec.encode(.disabled).first, 0x09)
    }

    func testUnknownTypeIsPreserved() {
        let decoded = ClassicButtonCodec.decode(type: 7, data: [1, 2, 3, 4, 5, 6])
        XCTAssertEqual(decoded, .unsupported(type: 7, data: [1, 2, 3, 4, 5, 6]))
        XCTAssertEqual(Array(ClassicButtonCodec.encode(decoded).prefix(7)), [7, 1, 2, 3, 4, 5, 6])
    }
}
