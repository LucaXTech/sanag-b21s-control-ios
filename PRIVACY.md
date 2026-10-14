# Privacy — Sanag Control

This independent iOS application is designed to communicate **locally** with compatible Sanag B21S headphones via Apple's CoreBluetooth framework.

## Data used by the app

- Bluetooth peripheral identifiers and connection state, for reconnecting to the user's device.
- The selected EQ preset and user preferences, saved in **UserDefaults** on the iPhone.
- A short local diagnostic history (up to 50 entries) containing connection events, timestamps and device information. Users can clear the event log from Settings.
- A battery reading from the headphones, when the BLE protocol provides one.

## Anonymous-by-design contributions in the 0.5.0 development branch

The app uses **one Cloudflare Workers HTTPS endpoint and D1 aggregate database** for both types of contribution:

- **Automatic observations:** Only after explicit opt-in; the app may submit the selected supported model, app version, observed BLE service and characteristic UUIDs, and observation type. Successful observations are locally limited to approximately one per model every 30 days.
- **Manual support requests:** After a separate on-screen confirmation, the user can submit the headphone model they typed and, optionally, service and characteristic UUIDs obtained through read-only GATT discovery. This is available even when the headphones do not expose BLE and without a GitHub account. Manual requests do not silently enable automatic sharing; they are locally limited to approximately one per model every 30 days.

The contribution does **not** contain Bluetooth MAC addresses, CoreBluetooth identifiers, serial numbers, device-advertised names, location, audio, raw packets, local logs or account identifiers. Users must enter only an ordinary headphone brand/model, not personal information. Reports are stored as **aggregated counts** grouped by model, app version and available GATT metadata. Aggregate counts are retained until manually deleted or the service is retired; they cannot be withdrawn per user because they lack a user identifier.

The host necessarily processes the connecting IP address in transit, and the Worker uses it transiently for rate limiting. **IP addresses are not written to the application's D1 tables.** Cloudflare may separately process network metadata or logs under its own policies. The application operator must verify and publish the relevant provider disclosures before broadly enabling public reporting.

The app source deliberately omits the deployed receiver address and deployment credentials. Builds without a configured endpoint have reporting disabled.

## Data sharing

Version **0.4.4** does not upload or collect diagnostic records remotely.

A proposed **0.4.5** feature can automatically submit a small compatibility report **only after explicit first-run consent**. Reports contain the fixed compatible model name, observed GATT service and characteristic UUIDs, and app version. No CoreBluetooth identifier, MAC address, Bluetooth device name, phone information, account identifier, audio, raw packet, location, logs, or precise battery percentage is included. Declining leaves upload disabled. A persistent Settings toggle allows opting out at any time; a pending network request is cancelled when disabled. At most one successful report is uploaded in 30 days per installation, when iOS allows BLE activity. Reports are transmitted over HTTPS.

The older 0.4.5 B21S report protocol remains supported by the deployed receiver during migration. The 0.5.0 aggregate protocol must be deployed and tested before releasing the multi-brand beta.

**No endpoint is configured in the source tree** (`DeviceReportURL` is empty). No sharing takes place until a trustworthy HTTPS receiver is deployed and configured. Operator-specific deployment instructions are not included in this public application repository.

Users can still choose to **copy** local diagnostic logs and share them manually in a GitHub issue. Logs may contain device names, BLE identifiers and timestamps and should be reviewed before posting.

## Permissions

The app requests Bluetooth permission to discover and control the B21S. It declares `bluetooth-central` background mode, subject to iOS scheduling and authorization.

## Contact

Questions or deletion concerns: open an issue at [LucaXTech/sanag-b21s-control-ios](https://github.com/LucaXTech/sanag-b21s-control-ios/issues). No remote deletion is needed for data that never left your device. Uninstalling the app removes its local data under normal iOS behavior.

**Last revised:** 2026-10-14. Update this statement if network collection, telemetry or other new data practices are introduced.
