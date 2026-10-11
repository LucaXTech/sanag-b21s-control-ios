# Roadmap / verification status

## Present in 0.4.4

- [x] Independent CoreBluetooth manager, service discovery, RX notifications.
- [x] Select and query firmware EQ presets 0–5.
- [x] Local preference persistence and reconnect strategy.
- [x] Shortcuts App Intent for requesting the stored EQ preset.
- [x] Responsive minimal SwiftUI home and iOS icon.
- [x] Developer protocol reference and local logs.
- [x] Experimental B21S battery read (`0x33`).

## Before first stable release

- [ ] Compile on macOS Xcode 26+; CI run green.
- [ ] Validate 0.4.4 design on an iPhone and test in light and dark mode.
- [ ] Confirm battery reading with iOS battery display across several charge levels.
- [ ] Test EQ restore with foreground app, background app, and locked iPhone.
- [ ] Test Shortcuts trigger at cold BLE connection and after app force-quit.
- [ ] Fix/modernize Swift 6 isolation warnings before switching to Swift 6 language mode.
- [ ] Add protocol parser unit tests and mock BLE transport for CI.
- [ ] Check VoiceOver, Dynamic Type, translations and reduce-transparency accessibility options.

## Future improvements

- [ ] More accurate error reporting and diagnostics without showing technical data on Home.
- [ ] Show timestamps of BLE state/battery readings in advanced diagnostics.
- [ ] Robust timeouts and deduplicated restore requests when background reconnect and App Intent happen concurrently.
- [ ] Validate other headset firmware versions **before** expanding supported devices.

*No promise of unsupported EQ profiles or firmware update functionality.*
