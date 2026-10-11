# Privacy — Sanag Control

This independent iOS application is designed to communicate **locally** with compatible Sanag B21S headphones via Apple's CoreBluetooth framework.

## Data used by the app

- Bluetooth peripheral identifiers and connection state, for reconnecting to the user's device.
- The selected EQ preset and user preferences, saved in **UserDefaults** on the iPhone.
- A short local diagnostic history (up to 50 entries) containing connection events, timestamps and device information. Users can clear the event log from Settings.
- A battery reading from the headphones, when the BLE protocol provides one.

## Data sharing

The current 0.4.4 code does not include an analytics SDK, an account system, advertising tracking, or an app-operated network endpoint. **The developer does not collect or upload the app's diagnostic records.** Apple's operating system and an installed Shortcuts automation may process their own system events under Apple's policies.

If a user chooses to **copy** diagnostic logs and share them in a GitHub issue, the logs may contain device names, BLE identifiers and timestamps; users should review/redact these before posting.

## Permissions

The app requests Bluetooth permission to discover and control the B21S. It declares `bluetooth-central` background mode, subject to iOS scheduling and authorization.

## Contact

Questions or deletion concerns: open an issue at [LucaXTech/sanag-b21s-control-ios](https://github.com/LucaXTech/sanag-b21s-control-ios/issues). No remote deletion is needed for data that never left your device. Uninstalling the app removes its local data under normal iOS behavior.

**Last revised:** 2026-10-09. Update this statement if network collection, telemetry or other new data practices are introduced.
