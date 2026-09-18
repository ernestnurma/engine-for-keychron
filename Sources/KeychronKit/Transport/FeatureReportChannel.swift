import Foundation

/// How a request is answered.
public enum ReplyMode: Sendable {
    /// Write-only command. Over a receiver, wait for its `54 E4 00` acknowledgement.
    case none
    /// The device answers straight away (read with GET_FEATURE after the SET).
    case immediate
    /// Over a receiver, the answer is fetched from the mouse over the air and announced with `54 E4 01`.
    /// Over a cable this behaves like `.immediate`.
    case relayed
}

/// One feature-report exchange. `bytes[0]` is the report ID; the packet is zero-padded to `length`.
public struct FeatureRequest: Equatable, Sendable {
    public var bytes: [UInt8]
    public var length: Int
    public var reply: ReplyMode

    public init(_ bytes: [UInt8], length: Int, reply: ReplyMode) {
        self.bytes = bytes
        self.length = length
        self.reply = reply
    }

    /// The exact bytes sent to the device.
    public var padded: [UInt8] { bytes + [UInt8](repeating: 0, count: max(0, length - bytes.count)) }
}

/// A synchronous request/response channel to one device. Implementations must be thread-safe.
/// `HIDTransport` is the real one; tests use a mock.
public protocol FeatureReportChannel: AnyObject {
    /// Sends the request and returns the reply (empty for `.none`).
    @discardableResult
    func transact(_ request: FeatureRequest) throws -> [UInt8]
}

public enum HIDError: LocalizedError, Equatable {
    case notOpen
    case exclusiveAccess
    case openFailed(Int32)
    case setFailed(Int32)
    case getFailed(Int32)
    case timeout
    case unexpectedReply

    public var errorDescription: String? {
        func hex(_ r: Int32) -> String { "0x" + String(UInt32(bitPattern: r), radix: 16) }
        switch self {
        case .notOpen: return "The mouse is not connected."
        case .exclusiveAccess:
            return "Another app is using the mouse. Quit the original Keychron Engine (including its login item) and try again."
        case .openFailed(let r): return "Could not open the mouse (IOKit error \(hex(r)))."
        case .setFailed(let r): return "Sending a command failed (IOKit error \(hex(r)))."
        case .getFailed(let r): return "Reading from the mouse failed (IOKit error \(hex(r)))."
        case .timeout: return "The mouse did not answer. Move it to wake it up and try again."
        case .unexpectedReply: return "The mouse sent an unexpected reply."
        }
    }
}
