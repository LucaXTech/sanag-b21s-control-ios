# Contributing

Contributions are welcome for documentation, accessibility, localization, performance, tests and verified B21S protocol observations.

1. Open an issue before large changes, especially for unknown BLE commands.
2. Keep UI features separate from protocol changes. Do not introduce an arbitrary-write BLE console to the default UI.
3. Test an **unsigned Xcode build** and, when possible, on actual B21S headphones.
4. Explain whether a feature is **observed**, **inferred**, or **untested**.
5. Never commit Apple signing profiles, developer credentials, proprietary APK/firmware, non-consensual BLE logs or user diagnostics.
6. When reporting a bug, redact Bluetooth peripheral IDs, email addresses, UDIDs, logs and other identifiers.
7. Submit a pull request against `main`; include a concise explanation and any reproducible verification performed.

Source files target Swift 5 language mode on Xcode 26; concurrent CoreBluetooth delegates currently emit forward-looking Swift 6 concurrency warnings and should be carefully modernized before enabling Swift 6 language mode.

## AI-assisted compatibility contributions

If an AI assistant helps you analyze your device, follow [AGENTS.md](AGENTS.md). Share results only with your consent, redact unique Bluetooth identifiers, and use the [device compatibility report](https://github.com/LucaXTech/sanag-b21s-control-ios/issues/new/choose). Do not send raw commands to unverified hardware.
