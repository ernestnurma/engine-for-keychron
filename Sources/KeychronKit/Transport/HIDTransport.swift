import Foundation
import IOKit.hid

/// Plain description of a HID interface, independent of IOKit so discovery logic can be unit-tested.
public struct EndpointInfo: Hashable, Sendable {
    public var productID: Int
    public var product: String
    public var usagePage: Int
    public var transport: String
    public var locationID: Int

    public init(productID: Int, product: String, usagePage: Int, transport: String, locationID: Int = 0) {
        self.productID = productID
        self.product = product
        self.usagePage = usagePage
        self.transport = transport
        self.locationID = locationID
    }

    public var isBluetooth: Bool { transport.localizedCaseInsensitiveContains("Bluetooth") }
}

/// A Keychron HID interface currently attached to the Mac.
public struct HIDEndpoint: Hashable {
    public let info: EndpointInfo
    fileprivate let device: IOHIDDevice

    public static func == (a: HIDEndpoint, b: HIDEndpoint) -> Bool { a.device === b.device }
    public func hash(into h: inout Hasher) { h.combine(ObjectIdentifier(device)) }
}

/// Owns an IOHIDManager on a private run-loop thread and performs synchronous
/// request/response transactions on a serial queue.
///
/// Over the 2.4 GHz receiver, the dongle acknowledges every feature report with an input
/// report `54 E4 xx` (00 = accepted, 01 = reply ready), which `transact` waits for.
public final class HIDTransport: FeatureReportChannel {
    public static let classicUsagePage = 0x8C
    public static let nordicUsagePage = 0xFF0A

    /// Called on the main queue when a matching device is attached or removed.
    public var onDevicesChanged: (() -> Void)?

    private var manager: IOHIDManager!
    private var runLoop: CFRunLoop?
    private let ready = DispatchSemaphore(value: 0)
    private let ioQueue = DispatchQueue(label: "engineforkeychron.hid.io")

    private var openDevice: IOHIDDevice?
    private var viaReceiver = false
    private let inputBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)

    // Receiver acknowledgements, written on the HID thread and read on ioQueue.
    private let eventLock = NSCondition()
    private var events: [UInt8] = []

    public init() {
        let thread = Thread { [weak self] in self?.runHIDThread() }
        thread.name = "engineforkeychron.hid.runloop"
        thread.start()
        ready.wait()
    }

    deinit { inputBuffer.deallocate() }

    // MARK: Discovery

    /// All matching Keychron interfaces currently attached: classic and Nordic configuration
    /// interfaces, plus Bluetooth mice (which have no configuration interface).
    public func endpoints() -> [HIDEndpoint] {
        guard let set = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else { return [] }
        return set.compactMap { dev in
            func int(_ key: String) -> Int { (IOHIDDeviceGetProperty(dev, key as CFString) as? NSNumber)?.intValue ?? 0 }
            func string(_ key: String) -> String { IOHIDDeviceGetProperty(dev, key as CFString) as? String ?? "" }
            let page = int(kIOHIDPrimaryUsagePageKey)
            if page == Self.classicUsagePage && int(kIOHIDPrimaryUsageKey) != 1 { return nil }
            let info = EndpointInfo(productID: int(kIOHIDProductIDKey),
                                    product: string(kIOHIDProductKey).trimmingCharacters(in: .whitespaces),
                                    usagePage: page,
                                    transport: string(kIOHIDTransportKey),
                                    locationID: int(kIOHIDLocationIDKey))
            return HIDEndpoint(info: info, device: dev)
        }
        .sorted { $0.info.locationID < $1.info.locationID }
    }

    // MARK: Opening

    /// Opens the endpoint for `transact`. `viaReceiver` enables the 2.4 GHz acknowledgement handshake.
    public func open(_ endpoint: HIDEndpoint, viaReceiver: Bool) throws {
        try ioQueue.sync {
            if let current = openDevice, current !== endpoint.device { closeLocked() }
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
            self.viaReceiver = viaReceiver
        }
    }

    public func close() {
        ioQueue.sync { closeLocked() }
    }

    private func closeLocked() {
        if let dev = openDevice {
            if let runLoop { IOHIDDeviceUnscheduleFromRunLoop(dev, runLoop, CFRunLoopMode.defaultMode.rawValue) }
            IOHIDDeviceClose(dev, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        openDevice = nil
    }

    // MARK: FeatureReportChannel

    @discardableResult
    public func transact(_ request: FeatureRequest) throws -> [UInt8] {
        try ioQueue.sync {
            var attempt = 0
            while true {
                do {
                    return try transactOnce(request)
                } catch HIDError.unexpectedReply where attempt < 2 {
                    attempt += 1
                    usleep(100_000)
                } catch HIDError.timeout where attempt < 1 {
                    attempt += 1
                }
            }
        }
    }

    private func transactOnce(_ request: FeatureRequest) throws -> [UInt8] {
        guard let dev = openDevice else { throw HIDError.notOpen }
        let packet = request.padded
        let reportID = CFIndex(packet[0])

        eventLock.lock(); events.removeAll(); eventLock.unlock()

        var r = IOHIDDeviceSetReport(dev, kIOHIDReportTypeFeature, reportID, packet, packet.count)
        if r != kIOReturnSuccess {
            usleep(50_000)
            r = IOHIDDeviceSetReport(dev, kIOHIDReportTypeFeature, reportID, packet, packet.count)
            guard r == kIOReturnSuccess else { throw HIDError.setFailed(r) }
        }

        if viaReceiver {
            switch request.reply {
            case .relayed:
                guard waitForEvent(0x01, timeout: 2.5) else { throw HIDError.timeout }
            case .immediate:
                _ = waitForEvent(0x00, timeout: 0.6)
                if !sawEvent(0x01) { _ = waitForEvent(0x01, timeout: 0.15) }
            case .none:
                // The dongle acks with 00 once it has queued the command.
                guard waitForEvent(0x00, timeout: 2.0) else { throw HIDError.timeout }
            }
        }

        guard request.reply != .none else { return [] }

        var lastError: IOReturn = kIOReturnSuccess
        for _ in 0..<10 {
            var length = CFIndex(request.length)
            var buffer = [UInt8](repeating: 0, count: request.length)
            buffer[0] = packet[0]
            lastError = IOHIDDeviceGetReport(dev, kIOHIDReportTypeFeature, reportID, &buffer, &length)
            if lastError == kIOReturnSuccess && length > 1 {
                let reply = Array(buffer[0..<length])
                // A stale buffer from an earlier command means the answer is not in yet.
                guard reply[0] == packet[0] && reply[1] == packet[1] else { throw HIDError.unexpectedReply }
                return reply
            }
            usleep(10_000)
        }
        throw HIDError.getFailed(lastError)
    }

    // MARK: Run loop and receiver events

    private func runHIDThread() {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let vendor = ModelCatalog.vendorID
        let matches: [[String: Any]] = [
            [kIOHIDVendorIDKey: vendor, kIOHIDPrimaryUsagePageKey: Self.classicUsagePage],
            [kIOHIDVendorIDKey: vendor, kIOHIDPrimaryUsagePageKey: Self.nordicUsagePage],
            // Over Bluetooth the mouse is a plain HID mouse; match it so it can be recognised.
            [kIOHIDVendorIDKey: vendor, kIOHIDTransportKey: "Bluetooth Low Energy"],
            [kIOHIDVendorIDKey: vendor, kIOHIDTransportKey: "Bluetooth"],
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

    private func handleInput(_ report: UnsafeMutablePointer<UInt8>, _ length: CFIndex) {
        guard length >= 3, report[0] == 0x54, report[1] == 0xE4 else { return }
        eventLock.lock()
        events.append(report[2])
        eventLock.broadcast()
        eventLock.unlock()
    }

    private func waitForEvent(_ wanted: UInt8, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        eventLock.lock()
        defer { eventLock.unlock() }
        while !events.contains(wanted) {
            if !eventLock.wait(until: deadline) { return events.contains(wanted) }
        }
        return true
    }

    private func sawEvent(_ event: UInt8) -> Bool {
        eventLock.lock(); defer { eventLock.unlock() }
        return events.contains(event)
    }
}
