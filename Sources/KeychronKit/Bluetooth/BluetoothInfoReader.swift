import Foundation
import CoreBluetooth

/// Reads what a Bluetooth-connected M-series mouse exposes over GATT: the standard
/// Device Information (model, firmware) and Battery services. The only vendor service
/// is Telink's firmware-update (OTA) endpoint, so settings cannot be changed over Bluetooth.
public final class BluetoothInfoReader: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    public struct Info: Equatable, Sendable {
        public var model = ""
        public var firmware = ""
        public var battery: Int?
    }

    /// Called on the main queue whenever a value arrives.
    public var onUpdate: ((Info) -> Void)?
    public private(set) var info = Info()

    public override init() { super.init() }

    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?

    private static let deviceInfo = CBUUID(string: "180A")
    private static let batteryService = CBUUID(string: "180F")
    private static let modelChar = CBUUID(string: "2A24")
    private static let firmwareChar = CBUUID(string: "2A26")
    private static let batteryChar = CBUUID(string: "2A19")

    public func start() {
        if central == nil { central = CBCentralManager(delegate: self, queue: .main) }
        else { attach() }
    }

    public func stop() {
        if let p = peripheral { central?.cancelPeripheralConnection(p) }
        peripheral = nil
        info = Info()
    }

    public func centralManagerDidUpdateState(_ c: CBCentralManager) {
        if c.state == .poweredOn { attach() }
    }

    private func attach() {
        guard let c = central, c.state == .poweredOn, peripheral == nil else { return }
        let found = c.retrieveConnectedPeripherals(withServices: [Self.deviceInfo, Self.batteryService])
        guard let p = found.first(where: { ($0.name ?? "").localizedCaseInsensitiveContains("Keychron M") }) else { return }
        peripheral = p
        p.delegate = self
        c.connect(p)   // the link already exists (HID); this just lets us use GATT
    }

    public func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) {
        p.discoverServices([Self.deviceInfo, Self.batteryService])
    }

    public func centralManager(_ c: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        if p == peripheral { peripheral = nil }
    }

    public func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        for s in p.services ?? [] {
            p.discoverCharacteristics([Self.modelChar, Self.firmwareChar, Self.batteryChar], for: s)
        }
    }

    public func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor s: CBService, error: Error?) {
        for ch in s.characteristics ?? [] {
            p.readValue(for: ch)
            if ch.uuid == Self.batteryChar && ch.properties.contains(.notify) { p.setNotifyValue(true, for: ch) }
        }
    }

    public func peripheral(_ p: CBPeripheral, didUpdateValueFor ch: CBCharacteristic, error: Error?) {
        guard let d = ch.value, !d.isEmpty else { return }
        switch ch.uuid {
        case Self.modelChar: info.model = String(decoding: d, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        case Self.firmwareChar: info.firmware = String(decoding: d, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        case Self.batteryChar: info.battery = Int(d[0])
        default: return
        }
        onUpdate?(info)
    }
}
