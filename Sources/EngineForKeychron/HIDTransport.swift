import Foundation
import IOKit.hid

/// How the mouse is attached. Over the 2.4 GHz receiver the dongle acknowledges
/// every feature report with an input report `54 E4 xx` (00 = accepted,
/// 01 = reply ready), which the transport waits for before reading back.
enum LinkKind: Equatable {
    case wired
    case receiver
    case bluetooth   // recognised only; no configuration channel
}

enum HIDError: LocalizedError {
    case notOpen
    case exclusiveAccess
    case openFailed(IOReturn)
    case setFailed(IOReturn)
    case getFailed(IOReturn)
    case timeout
    case unexpectedReply

    var errorDescription: String? {
        switch self {
        case .notOpen: return "The mouse is not connected."
        case .exclusiveAccess:
            return "Another app is using the mouse. Quit the original Keychron Engine (including its menu-bar/login item) and try again."
        case .openFailed(let r): return "Could not open the mouse (IOKit error 0x\(String(UInt32(bitPattern: r), radix: 16)))."
        case .setFailed(let r): return "Sending a command failed (IOKit error 0x\(String(UInt32(bitPattern: r), radix: 16)))."
        case .getFailed(let r): return "Reading from the mouse failed (IOKit error 0x\(String(UInt32(bitPattern: r), radix: 16)))."
        case .timeout: return "The mouse did not answer. Move it to wake it up and try again."
        case .unexpectedReply: return "The mouse sent an unexpected reply."
        }
    }
}

/// A Keychron configuration interface (usage page 0x8C, usage 1) found on the system.
struct HIDEndpoint: Hashable {
    let productID: Int
    let product: String
    let locationID: Int
    let usagePage: Int
    let transportName: String
    fileprivate let device: IOHIDDevice

    var isBluetooth: Bool { transportName.localizedCaseInsensitiveContains("Bluetooth") }

    static func == (a: HIDEndpoint, b: HIDEndpoint) -> Bool { a.device === b.device }
    func hash(into h: inout Hasher) { h.combine(ObjectIdentifier(device)) }
}

/// Owns an IOHIDManager on a private run-loop thread and performs synchronous
/// request/response transactions on a serial queue.
final class HIDTransport {
    static let vendorID = 0x3434
    static let configUsagePage = 0x8C
    static let nordicUsagePage = 0xFF0A

    var onDevicesChanged: (() -> Void)?

    private var manager: IOHIDManager!
    private var runLoop: CFRunLoop?
    private let ready = DispatchSemaphore(value: 0)
    private let ioQueue = DispatchQueue(label: "engineforkeychron.hid.io")

    private var openDevice: IOHIDDevice?
    private var link: LinkKind = .wired
    private let inputBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)

    // Receiver acknowledgements, written on the HID thread and read on ioQueue.
    private let evtLock = NSCondition()
    private var events: [UInt8] = []

    init() {
        let thread = Thread { [weak self] in self?.runHIDThread() }
        thread.name = "engineforkeychron.hid.runloop"
        thread.start()
        ready.wait()
    }

    private func runHIDThread() {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matches: [[String: Any]] = [
            [kIOHIDVendorIDKey: Self.vendorID, kIOHIDPrimaryUsagePageKey: Self.configUsagePage],
            [kIOHIDVendorIDKey: Self.vendorID, kIOHIDPrimaryUsagePageKey: Self.nordicUsagePage],
            // Over Bluetooth the mouse is a plain HID mouse (no config interface); match it to recognise it.
            [kIOHIDVendorIDKey: Self.vendorID, kIOHIDTransportKey: "Bluetooth Low Energy"],
            [kIOHIDVendorIDKey: Self.vendorID, kIOHIDTransportKey: "Bluetooth"],
        ]
        IOHIDManagerSetDeviceMatchingMultiple(manager, matches as CFArray)
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { ctx, _, _, _ in
            guard let ctx else { return }
            let me = Unmanaged<HIDTransport>.fromOpaque(ctx).takeUnretainedValue()
            DispatchQueue.main.async { me.onDevicesChanged?() }
        }, ctx)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { ctx, _, _, device in
            guard let ctx else { return }
            let me = Unmanaged<HIDTransport>.fromOpaque(ctx).takeUnretainedValue()
            me.deviceRemoved(device)
            DispatchQueue.main.async { me.onDevicesChanged?() }
        }, ctx)
        runLoop = CFRunLoopGetCurrent()
        IOHIDManagerScheduleWithRunLoop(manager, runLoop!, CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        ready.signal()
        CFRunLoopRun()
    }

    private func deviceRemoved(_ device: IOHIDDevice) {
        ioQueue.async { [weak self] in
            guard let self, self.openDevice === device else { return }
            self.openDevice = nil
        }
    }

    /// All matching configuration endpoints currently attached.
    func endpoints() -> [HIDEndpoint] {
        guard let set = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else { return [] }
        return set.compactMap { dev in
            func int(_ key: String) -> Int { (IOHIDDeviceGetProperty(dev, key as CFString) as? NSNumber)?.intValue ?? 0 }
            let page = int(kIOHIDPrimaryUsagePageKey)
            let usage = int(kIOHIDPrimaryUsageKey)
            if page == Self.configUsagePage && usage != 1 { return nil }
            let product = (IOHIDDeviceGetProperty(dev, kIOHIDProductKey as CFString) as? String ?? "")
                .trimmingCharacters(in: .whitespaces)
            let transport = IOHIDDeviceGetProperty(dev, kIOHIDTransportKey as CFString) as? String ?? ""
            return HIDEndpoint(productID: int(kIOHIDProductIDKey), product: product,
                               locationID: int(kIOHIDLocationIDKey), usagePage: page,
                               transportName: transport, device: dev)
        }
        .sorted { $0.locationID < $1.locationID }
    }

    func open(_ endpoint: HIDEndpoint, link: LinkKind) throws {
        try ioQueue.sync {
            if let current = openDevice, current !== endpoint.device {
                IOHIDDeviceClose(current, IOOptionBits(kIOHIDOptionsTypeNone))
                openDevice = nil
            }
            if openDevice == nil {
                let r = IOHIDDeviceOpen(endpoint.device, IOOptionBits(kIOHIDOptionsTypeNone))
                if r == IOReturn(bitPattern: 0xE000_02C5) { throw HIDError.exclusiveAccess }
                guard r == kIOReturnSuccess else { throw HIDError.openFailed(r) }
                let ctx = Unmanaged.passUnretained(self).toOpaque()
                IOHIDDeviceRegisterInputReportCallback(endpoint.device, inputBuffer, 64, { ctx, _, _, _, _, report, length in
                    guard let ctx else { return }
                    Unmanaged<HIDTransport>.fromOpaque(ctx).takeUnretainedValue().handleInput(report, length)
                }, ctx)
                if let runLoop {
                    IOHIDDeviceScheduleWithRunLoop(endpoint.device, runLoop, CFRunLoopMode.defaultMode.rawValue)
                    CFRunLoopWakeUp(runLoop)
                }
                openDevice = endpoint.device
            }
            self.link = link
        }
    }

    func close() {
        ioQueue.sync {
            if let dev = openDevice {
                if let runLoop { IOHIDDeviceUnscheduleFromRunLoop(dev, runLoop, CFRunLoopMode.defaultMode.rawValue) }
                IOHIDDeviceClose(dev, IOOptionBits(kIOHIDOptionsTypeNone))
            }
            openDevice = nil
        }
    }

    private func handleInput(_ report: UnsafeMutablePointer<UInt8>, _ length: CFIndex) {
        guard length >= 3, report[0] == 0x54, report[1] == 0xE4 else { return }
        evtLock.lock()
        events.append(report[2])
        evtLock.broadcast()
        evtLock.unlock()
    }

    /// Wait until the receiver posts `wanted`; returns every event seen.
    private func waitForEvent(_ wanted: UInt8, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        evtLock.lock()
        defer { evtLock.unlock() }
        while !events.contains(wanted) {
            if !evtLock.wait(until: deadline) { return events.contains(wanted) }
        }
        return true
    }

    private func sawEvent(_ e: UInt8) -> Bool {
        evtLock.lock(); defer { evtLock.unlock() }
        return events.contains(e)
    }

    /// Send a feature report (first byte = report ID) and optionally read the reply.
    /// `asyncReply` marks requests whose answer the receiver fetches from the mouse
    /// over the air and announces with `54 E4 01`.
    @discardableResult
    func transact(_ request: [UInt8], length: Int, expectReply: Bool, asyncReply: Bool = false) throws -> [UInt8] {
        try ioQueue.sync {
            var attempt = 0
            while true {
                do {
                    return try transactOnce(request, length: length, expectReply: expectReply, asyncReply: asyncReply)
                } catch HIDError.unexpectedReply where attempt < 2 {
                    attempt += 1
                    usleep(100_000)
                } catch HIDError.timeout where attempt < 1 {
                    attempt += 1
                }
            }
        }
    }

    private func transactOnce(_ request: [UInt8], length: Int, expectReply: Bool, asyncReply: Bool) throws -> [UInt8] {
        do {
            guard let dev = openDevice else { throw HIDError.notOpen }
            var buf = request + [UInt8](repeating: 0, count: max(0, length - request.count))
            let reportID = CFIndex(buf[0])

            evtLock.lock(); events.removeAll(); evtLock.unlock()

            var r = IOHIDDeviceSetReport(dev, kIOHIDReportTypeFeature, reportID, buf, buf.count)
            if r != kIOReturnSuccess {
                usleep(50_000)
                r = IOHIDDeviceSetReport(dev, kIOHIDReportTypeFeature, reportID, buf, buf.count)
                guard r == kIOReturnSuccess else { throw HIDError.setFailed(r) }
            }

            if link == .receiver {
                if expectReply && asyncReply {
                    guard waitForEvent(0x01, timeout: 2.5) else { throw HIDError.timeout }
                } else if expectReply {
                    _ = waitForEvent(0x00, timeout: 0.6)
                    if !sawEvent(0x01) { _ = waitForEvent(0x01, timeout: 0.15) }
                } else {
                    // Writes: the dongle acks with 00 once it has queued the command.
                    guard waitForEvent(0x00, timeout: 2.0) else { throw HIDError.timeout }
                }
            }

            guard expectReply else { return [] }

            var lastErr: IOReturn = kIOReturnSuccess
            for _ in 0..<10 {
                var len = CFIndex(length)
                buf = [UInt8](repeating: 0, count: length)
                buf[0] = request[0]
                lastErr = IOHIDDeviceGetReport(dev, kIOHIDReportTypeFeature, reportID, &buf, &len)
                if lastErr == kIOReturnSuccess && len > 1 {
                    let reply = Array(buf[0..<len])
                    // A stale buffer from an earlier command means the answer is not in yet.
                    guard reply[0] == request[0] && reply[1] == request[1] else { throw HIDError.unexpectedReply }
                    return reply
                }
                usleep(10_000)
            }
            throw HIDError.getFailed(lastErr)
        }
    }
}
