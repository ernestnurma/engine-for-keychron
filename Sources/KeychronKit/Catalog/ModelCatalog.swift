import Foundation

/// Every known mouse and receiver. Source: the device tables embedded in Keychron Engine 1.0.10.
/// To support a new model, add an entry here (and a driver if it uses a new protocol family).
public enum ModelCatalog {
    public static let vendorID = 0x3434

    /// 2.4 GHz receivers, keyed by product ID.
    public static let receivers: [Int: ProtocolFamily] = [
        0xD030: .classic,   // Type-A receiver
        0xD031: .classic,   // Type-C receiver ("Keychron Link")
        0xD038: .nordic,    // 4K Type-C receiver
        0xD043: .nordic,    // 4K Type-A receiver
    ]

    public static func model(forProductID pid: Int) -> MouseModel? {
        all.first { $0.productIDs.contains(pid) }
    }

    /// Bluetooth devices can also be matched by their advertised name, e.g. "Keychron M3".
    public static func model(forProductName name: String) -> MouseModel? {
        all.first { name.trimmingCharacters(in: .whitespaces).hasSuffix(" " + $0.name) }
    }

    public static let all: [MouseModel] = [
        MouseModel(name: "M3", typeID: 101, productIDs: [0xD032, 0xD033], family: .classic, hasLighting: true,
                   buttons: Buttons.standard + [ButtonSlot(index: 7, name: "Top button", factory: .lighting(.effect))]),
        MouseModel(name: "M1", typeID: 102, productIDs: [0xD035], family: .classic, hasLighting: true,
                   buttons: Buttons.standard + [
                       ButtonSlot(index: 5, name: "Extra front button", factory: .mouse(.forward)),
                       ButtonSlot(index: 6, name: "Extra rear button", factory: .mouse(.back)),
                   ]),
        MouseModel(name: "M3 mini", typeID: 103, productIDs: [0xD036], family: .classic, buttons: Buttons.standard),
        MouseModel(name: "M2", typeID: 105, productIDs: [0xD03B], family: .classic, buttons: Buttons.standard),
        MouseModel(name: "M3 mini", typeID: 106, productIDs: [0xD03E], family: .classic, buttons: Buttons.standard),
        MouseModel(name: "M2 mini", typeID: 122, productIDs: [0xD03D], family: .classic, buttons: Buttons.standard),
        MouseModel(name: "M6", typeID: 160, productIDs: [0xD03F], family: .classic,
                   buttons: Buttons.standard + [
                       ButtonSlot(index: 8, name: "Wheel tilt left", factory: .mouse(.scrollLeft)),
                       ButtonSlot(index: 9, name: "Wheel tilt right", factory: .mouse(.scrollRight)),
                       ButtonSlot(index: 10, name: "Thumb wheel up", factory: .mouse(.scrollLeft)),
                       ButtonSlot(index: 11, name: "Thumb wheel down", factory: .mouse(.scrollRight)),
                   ]),
        MouseModel(name: "M7", typeID: 170, productIDs: [0xD044], family: .classic,
                   buttons: Buttons.standard + [
                       ButtonSlot(index: 7, name: "Side key", factory: .keyboard(modifiers: 0, key: 0x41)),
                   ]),
        // 4K generation: recognised only until a Nordic driver exists.
        MouseModel(name: "M3 mini 4K", typeID: 201, productIDs: [0xD037], family: .nordic),
        MouseModel(name: "M3 4K", typeID: 202, productIDs: [0xD03C], family: .nordic),
        MouseModel(name: "M3 mini 4K", typeID: 203, productIDs: [0xD041], family: .nordic),
        MouseModel(name: "M2 4K", typeID: 205, productIDs: [0xD045], family: .nordic),
        MouseModel(name: "M6 4K", typeID: 206, productIDs: [0xD046], family: .nordic),
        MouseModel(name: "M4", typeID: 231, productIDs: [0xD040], family: .nordic),
    ]

    private enum Buttons {
        static let standard = [
            ButtonSlot(index: 0, name: "Left button", factory: .mouse(.left)),
            ButtonSlot(index: 2, name: "Right button", factory: .mouse(.right)),
            ButtonSlot(index: 1, name: "Wheel button", factory: .mouse(.middle)),
            ButtonSlot(index: 3, name: "Front side button", factory: .mouse(.forward)),
            ButtonSlot(index: 4, name: "Rear side button", factory: .mouse(.back)),
            ButtonSlot(index: 14, name: "Wheel up", factory: .mouse(.scrollUp)),
            ButtonSlot(index: 13, name: "Wheel down", factory: .mouse(.scrollDown)),
        ]
    }
}
