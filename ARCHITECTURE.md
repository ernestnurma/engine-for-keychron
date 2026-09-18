# Architecture

Engine for Keychron is a Swift package with three products and one test target:

```
Sources/
├── KeychronKit/                 Library: device access and protocol logic (no UI)
│   ├── Catalog/                 MouseModel, ModelCatalog: every known mouse and receiver
│   ├── Domain/                  Protocol-independent types: settings, button actions, lighting, key codes
│   ├── Transport/               FeatureReportChannel protocol, HIDTransport (IOKit), EndpointInfo
│   ├── Discovery/               DeviceDiscovery: picks which attached interface to use (pure logic)
│   ├── Driver/                  MouseDriver protocol, SettingChange, DeviceSnapshot, DriverConnection
│   ├── Protocol/Classic/        ClassicDriver + command builders, parsers, button codec
│   └── Bluetooth/               BluetoothInfoReader: battery/firmware over GATT (read-only)
├── EngineForKeychron/           SwiftUI app
│   ├── App/                     @main entry point
│   ├── Store/                   MouseStore (app state), SettingsCache (UserDefaults)
│   └── Views/                   One file per screen, plus ViewSupport presentation helpers
└── engine-cli/                  Hardware diagnostics: `engine-cli info`, `engine-cli write-test`
Tests/KeychronKitTests/          Unit tests with packets and replies captured from a real M3
```

## Layers

```
Views ──► MouseStore ──► MouseDriver (ClassicDriver) ──► FeatureReportChannel (HIDTransport) ──► IOKit
             │                 │
             │                 └── ClassicCommands / ClassicParsers / ClassicButtonCodec (pure)
             ├── DeviceDiscovery (pure)
             ├── BluetoothInfoReader
             └── SettingsCache
```

- **Views** read `MouseStore` and call its `apply…` methods. They never see bytes.
- **MouseStore** (`@MainActor`) handles the connection lifecycle: it finds the device, connects a driver, loads a
  `DeviceSnapshot`, falls back to Bluetooth mode, and persists what the mouse can't report.
- **MouseDriver** is the only interface to a mouse. Reads return domain types; every write is a `SettingChange`.
  Drivers do their blocking I/O on a background queue.
- **ClassicDriver** turns changes into `FeatureRequest`s using pure builders (`ClassicCommands`) and decodes replies
  with pure parsers (`ClassicParsers`), so the byte-level behaviour is unit-tested without hardware.
- **FeatureReportChannel** is a single method, `transact(FeatureRequest) -> [UInt8]`. `HIDTransport` implements it
  with IOKit, including the 2.4 GHz receiver's acknowledgement handshake; tests use `MockChannel`.

Rules that keep this maintainable:
- `KeychronKit` must not import SwiftUI or AppKit. Presentation helpers (titles for links, battery icons, colour
  conversion) live in `EngineForKeychron/Views/ViewSupport.swift`.
- Protocol bytes appear only under `Protocol/<Family>/`. Domain types describe *what*, not *how*.
- Anything a new protocol could encode differently goes through a codec in the protocol folder (see `ClassicButtonCodec`).

## Common changes

### Add a mouse model that uses an existing protocol
1. Add a `MouseModel` entry to `ModelCatalog.all` with its product IDs, protocol family, lighting support and
   button slots (the key indices come from the original app's `Keychron-*.xml` device files).
2. If it ships with a new receiver, add the receiver's product ID to `ModelCatalog.receivers`.
3. Add a lookup case to `DeviceDiscoveryTests.testCatalogLookups`.

### Add a new setting
1. Add the value to the domain type (`MouseSettings`, `LightingSettings`, …) and a case to `SettingChange`.
2. In `ClassicCommands`, add a builder; in `ClassicParsers`, decode it; in `ClassicDriver.requests(for:)`, map the change.
3. Add byte-exact tests in `ClassicCommandsTests` / `ClassicParsersTests`, using bytes captured from a real device.
4. Add an `apply…` helper to `MouseStore` if the UI needs one, and a control in the relevant view.

### Add a protocol family (e.g. the 4K / Nordic mice)
1. Create `Protocol/Nordic/` with its own commands, parsers and a `NordicDriver: MouseDriver`, plus a static
   `connect(channel:productID:link:) -> DriverConnection` like `ClassicDriver`.
2. Mark its models `family: .nordic` in the catalog (already done for the known 4K models).
3. In `DeviceDiscovery.classify`, return `.configurable` for its interfaces (usage page `0xFF0A`) instead of
   `.unsupported`, and in `MouseStore.load()` pick the driver by family.
4. Views need no changes unless the new mice have new capabilities.

## Testing

```sh
swift test                                   # unit tests, no hardware needed
swift build && "$(swift build --show-bin-path)/engine-cli" info          # read a connected mouse
"$(swift build --show-bin-path)/engine-cli" write-test                    # change, verify, restore
```

Quit the original Keychron Engine before using `engine-cli` or the app; it holds the device exclusively.
