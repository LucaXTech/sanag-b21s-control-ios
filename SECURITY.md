# Security policy

## Supported versions

This is an early-stage interoperability application. Security fixes will target the latest available version in the `main` branch. There is no long-term support guarantee for older builds.

## Reporting vulnerabilities

Do **not** publish a vulnerability that could expose private Bluetooth identifiers, Apple signing credentials or user data in a public issue. Instead, use GitHub's **Report a vulnerability** / private security advisory feature if enabled on this repository; otherwise contact the maintainer privately through their GitHub profile before disclosing details.

Please do not attach pairing records, private logs, Apple Account tokens, certificates, provisioning profiles or original proprietary APKs.

## Scope and safety

The app sends only the known B21S EQ/status/battery frames described in `docs/PROTOCOL.md`; arbitrary raw BLE writing is intentionally not exposed through the user interface. It does not modify headphone firmware.
