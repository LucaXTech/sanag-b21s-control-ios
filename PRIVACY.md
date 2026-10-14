# Privacy — Sanag Control

This independent iOS application is designed to communicate **locally** with compatible Sanag B21S headphones via Apple's CoreBluetooth framework.

## Data used by the app

- Bluetooth peripheral identifiers and connection state, for reconnecting to the user's device.
- The selected EQ preset and user preferences, saved in **UserDefaults** on the iPhone.
- A short local diagnostic history (up to 50 entries) containing connection events, timestamps and device information. Users can clear the event log from Settings.
- A battery reading from the headphones, when the BLE protocol provides one.

## Data sharing

Version **0.4.4** does not upload or collect diagnostic records remotely.

A proposed **0.4.5** feature can automatically submit a small compatibility report **only after explicit first-run consent**. Reports contain the fixed compatible model name, observed GATT service and characteristic UUIDs, and app version. No CoreBluetooth identifier, MAC address, Bluetooth device name, phone information, account identifier, audio, raw packet, location, logs, or precise battery percentage is included. Declining leaves upload disabled. A persistent Settings toggle allows opting out at any time; a pending network request is cancelled when disabled. At most one successful report is uploaded in 30 days per installation, when iOS allows BLE activity. Reports are transmitted over HTTPS.

The HTTPS host necessarily processes the connecting IP address in transit. A separately maintained receiver is intended to store **only aggregate counters**, without IPs, user identifiers or individual events. The actual hosting provider's logs, retention policy and contact details must be disclosed before enabling this service. Because reports have no stable personal identifier, individual aggregate contributions cannot be isolated or withdrawn once recorded.

**No endpoint is configured in the source tree** (`DeviceReportURL` is empty). No sharing takes place until a trustworthy HTTPS receiver is deployed and configured. Operator-specific deployment instructions are not included in this public application repository.

Users can still choose to **copy** local diagnostic logs and share them manually in a GitHub issue. Logs may contain device names, BLE identifiers and timestamps and should be reviewed before posting.

## Permissions

The app requests Bluetooth permission to discover and control the B21S. It declares `bluetooth-central` background mode, subject to iOS scheduling and authorization.

## Contact

Questions or deletion concerns: open an issue at [LucaXTech/sanag-b21s-control-ios](https://github.com/LucaXTech/sanag-b21s-control-ios/issues). No remote deletion is needed for data that never left your device. Uninstalling the app removes its local data under normal iOS behavior.

**Last revised:** 2026-10-14. Update this statement if network collection, telemetry or other new data practices are introduced.
