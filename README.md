# Engine for Keychron

A native **Apple Silicon** macOS app for configuring Keychron M-series mice. It replaces the Intel-only
Keychron Engine 1.0.10, which relies on Rosetta 2 and will stop working once Rosetta is removed from macOS.

> **Unofficial.** Not affiliated with, endorsed by, or supported by Keychron. The protocol was worked out by studying how
> the original app talks to the mouse. Use it at your own risk.

## Features

- **DPI:** five stages (100–26 000 in steps of 100) and the active stage
- **Performance:** polling rate (125 / 500 / 1000 Hz), lift-off distance, ripple control, angle snapping, motion sync,
  scroll direction, button debounce (0–20 ms)
- **Button remapping:** mouse actions, keyboard keys with modifiers, media keys, macOS shortcuts (Mission Control,
  screenshot, copy/paste…), DPI cycle/+/−, lighting control, or disabled
- **RGB lighting** (M1, M3): effect, brightness, speed, colour
- **Device info:** battery, mouse and receiver firmware versions, reset buttons, factory reset
- **Bluetooth mode:** shows model, firmware, battery and the settings stored in the mouse (read-only; see below)

Settings are saved in the mouse, so they keep working on any computer and in every connection mode.

## Supported mice

| Model | USB cable | 2.4 GHz receiver | Bluetooth |
|---|---|---|---|
| M1, M2, M2 mini, M3, M3 mini, M6, M7 | ✅ configure | ✅ configure | ℹ️ info only |
| M2 4K, M3 4K, M3 mini 4K, M6 4K, M4 | detected, not supported | detected, not supported | — |

Tested on a Keychron M3 (firmware 1.2.2r) with the 2.4 GHz receiver and over Bluetooth. The 4K models use a different
protocol that isn't implemented yet.

**Why Bluetooth is read-only:** over Bluetooth the mouse exposes only standard pointer/keyboard/media input plus the Device
Information and Battery services. It has no configuration channel, so neither this app nor the original Keychron Engine can
change settings over Bluetooth. Switch the mouse to 2.4 GHz or connect the cable to change settings; they stay active when
you switch back to Bluetooth.

## Installation

Requirements: a Mac with Apple Silicon running macOS 13 Ventura or later.

1. Download `EngineForKeychron-<version>.dmg` from the [Releases](../../releases) page.
2. Open the DMG and drag **Engine for Keychron** into **Applications**.
3. The app is not notarized by Apple, so macOS blocks the first launch. Allow it once:
   - Open the app, click **Done** on the warning, then go to **System Settings → Privacy & Security** and click
     **Open Anyway** next to "Engine for Keychron", **or**
   - run `xattr -dr com.apple.quarantine "/Applications/Engine for Keychron.app"` in Terminal.
4. Plug in the 2.4 GHz receiver (or the USB cable) and launch the app. If macOS asks for **Bluetooth** access, allow it.
   The app uses it only to read battery level and firmware in Bluetooth mode.

### If you have the original Keychron Engine installed

The original app takes exclusive control of the mouse, so this app can't connect to it while it's running. Quit
Keychron Engine first. It also starts at login through a login item; to stop that, run:

```sh
sudo launchctl bootout gui/$(id -u) /Library/LaunchAgents/com.pkg.KeychronEngine.plist 2>/dev/null
sudo rm /Library/LaunchAgents/com.pkg.KeychronEngine.plist
```

You can delete `/Applications/Keychron Engine.app` afterwards if you no longer need it.

## Building from source

Requires Xcode 15 or later (or the Swift 5.9+ command-line toolchain).

```sh
git clone <this repo>
cd engine-for-keychron
./Scripts/build.sh      # -> dist/Engine for Keychron.app and dist/EngineForKeychron-1.0.0.dmg (arm64, ad-hoc signed)
```

For development, `swift build` compiles the code; run the app through `build.sh` so it has its Info.plist (needed for the Bluetooth permission prompt).

Self-test against a connected mouse (no window):

```sh
"dist/Engine for Keychron.app/Contents/MacOS/EngineForKeychron" --selftest           # read-only dump of all settings
"dist/Engine for Keychron.app/Contents/MacOS/EngineForKeychron" --selftest --write   # change a few settings, verify, restore
```

### Project layout

| File | Purpose |
|---|---|
| `Sources/EngineForKeychron/HIDTransport.swift` | IOKit HID access, receiver handshake, request/response |
| `Sources/EngineForKeychron/Protocol.swift` | Model table, command builders and parsers, button-function encoding |
| `Sources/EngineForKeychron/MouseController.swift` | Device discovery, loading and applying settings |
| `Sources/EngineForKeychron/BluetoothInfo.swift` | CoreBluetooth battery/firmware reader for Bluetooth mode |
| `Sources/EngineForKeychron/Views.swift`, `Main.swift` | SwiftUI interface and the `--selftest` entry point |
| `Scripts/build.sh`, `Scripts/make_icon.swift` | App bundle, icon and DMG packaging |

## Protocol notes

All commands are HID **feature reports** on the vendor interface (usage page `0x8C`, usage 1). Report `0x51` is 21 bytes,
report `0x52` is 65 bytes, and the `0x51 0x0B` resets are sent as 64 bytes.

Over the receiver, every write is acknowledged with input report `54 E4 00`. When the receiver has to fetch a reply from
the mouse, it announces it with `54 E4 01`, and the reply must be read (GET_FEATURE) only after that. Over the cable: SET,
then GET directly.

| Request | Meaning |
|---|---|
| `51 03` | receiver → connected mouse: `[3..4]` VID, `[5..6]` PID (cached, see `51 06`) |
| `51 04 00` / `51 04 AA` | firmware of mouse / receiver: `[2]` length, `[3..]` ASCII |
| `51 06` | `[10]&7` work mode, `[10]&0x08` mouse linked to receiver, `[11]` battery %, `[12]` charging |
| `51 07` | snapshot cached by the receiver: `[3+slot]` = DPI stage (low nibble) \| rate index << 4; slot 0 USB, 1 2.4 GHz |
| `51 12` (async) | lighting: `[3]` effect count, `[4]` current effect |
| `52 67` (async) | live profile: `[2]` profile, `[3+slot]` stage, `[6..15]` 5× DPI LE16, `[16]` count, `[17]` sensor flags, `[18]` debounce |
| `52 61` (async) | per-button function type at `[2+index]` (0 = default) |
| `52 62 i` (async) | button `i`: `[4]` type, `[5..10]` data |
| `51 40 s s s d0 … d4 05` | DPI stage + 5 values (LE16) |
| `51 41 r r r 7D 00 F4 01 E8 03` | polling rate index 0/1/2 = 125/500/1000 Hz |
| `51 42 lift ripple angle motion 00 scroll` | lift 1=1 mm 2=2 mm; features 1=on 2=off; scroll 1=standard 2=reversed |
| `51 43 ms` | debounce 0–20 ms |
| `51 22 01 e` / `51 23 01 e v` / `51 27 01 e v` / `51 28 01 e r g b` | light effect / brightness / speed / colour |
| `52 52 i 00 b0 … b9` | assign button `i`; `b0` type (1 mouse, 2 key, 3 media, 5 DPI, 6 light, 8 shortcut, 9 disabled); all zero = default |
| `51 0B 01 01` / `51 0B 01 04` / `51 0B AA` | reset buttons / reset lighting / factory reset |

Sensor flag byte (`52 67 [17]`): bit 0 set = 1 mm lift-off, `0x04` ripple, `0x08` angle snap, `0x10` motion sync,
`0x40` reversed scroll. The polling rate is held by the receiver (read it from `51 07`); DPI, sensor, debounce and button
settings live in the mouse (read them from `52 67` / `52 6x`).

Bluetooth: the BLE HID descriptor has only input reports (mouse, keyboard, consumer). GATT offers Device Information
(`180A`), Battery (`180F`) and Telink's firmware-update (OTA) service (`00010203-0405-0607-0809-0A0B0C0D1912`), which this
app never writes to.

## Not implemented

Macros, rapid fire, switching between onboard profiles, and the 4K (Nordic-based) models.

## Trademarks

Keychron is a trademark of its owner. This project is independent and uses the name only to describe which devices it
works with. It contains no code or assets from the original application.
