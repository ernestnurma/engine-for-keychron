import Foundation

/// Decides which attached interface to use. Pure logic over `EndpointInfo`, so it's unit-testable.
public enum DeviceDiscovery {
    public enum Result<Endpoint> {
        case nothing
        /// A configuration interface to open: the mouse over a cable, or a receiver.
        case configurable(Endpoint, LinkKind)
        /// Only a Bluetooth mouse: recognisable, but it has no configuration channel.
        case bluetooth(MouseModel)
        /// Something we recognise but can't configure (e.g. a 4K receiver).
        case unsupported(String)
    }

    public static func classify<E>(_ endpoints: [E], info: (E) -> EndpointInfo) -> Result<E> {
        let classic = endpoints.filter { info($0).usagePage == HIDTransport.classicUsagePage && !info($0).isBluetooth }
        // Prefer an interface we can identify: a known receiver or a known mouse.
        let preferred = classic.first { ep in
            let pid = info(ep).productID
            return ModelCatalog.receivers[pid] == .classic || ModelCatalog.model(forProductID: pid) != nil
        }
        if let ep = preferred ?? classic.first {
            let link: LinkKind = ModelCatalog.receivers[info(ep).productID] != nil ? .receiver : .wired
            return .configurable(ep, link)
        }
        if let model = bluetoothModel(in: endpoints.map(info)) {
            return .bluetooth(model)
        }
        if let nordic = endpoints.first(where: { info($0).usagePage == HIDTransport.nordicUsagePage }) {
            let name = ModelCatalog.model(forProductID: info(nordic).productID)?.displayName ?? "Keychron 4K receiver"
            return .unsupported("Found a \(name). The 4K models use a different protocol that this app doesn't support yet.")
        }
        return .nothing
    }

    /// The Bluetooth-connected Keychron mouse among the endpoints, if any.
    public static func bluetoothModel(in infos: [EndpointInfo]) -> MouseModel? {
        for info in infos where info.isBluetooth {
            if let m = ModelCatalog.model(forProductID: info.productID) ?? ModelCatalog.model(forProductName: info.product) {
                return m
            }
        }
        return nil
    }

    public static func isBluetoothPresent(in infos: [EndpointInfo]) -> Bool {
        bluetoothModel(in: infos) != nil
    }
}
