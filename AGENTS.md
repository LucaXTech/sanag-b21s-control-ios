# Guidance for AI-assisted interoperability work

This repository is an **independent** SwiftUI/CoreBluetooth controller. Its only hardware-verified target is the **Sanag B21S**. The goal is to document interoperable protocols and safely expand device support based on evidence.

## When helping a user with a different headset

1. First inspect `docs/COMPATIBILITY.md` and `docs/PROTOCOL.md`.
2. Do not infer protocol compatibility from brand, appearance, shared silicon vendor, or the presence of GATT UUIDs `FAA0`/`FAA1`/`FAA2` alone.
3. Collect only read-only device observations at first: manufacturer/model, firmware version if shown, BLE advertisement and service/characteristic UUIDs, and response to manufacturer-documented operations. Ask the user to consent before collecting or sharing diagnostics.
4. Do **not** send unknown/raw commands, write firmware, factory-reset devices, or fuzz headphones merely to test compatibility. Never request login credentials, Bluetooth MAC addresses, CoreBluetooth peripheral identifiers, or raw logs with personal information.
5. Mark evidence accurately: `Verified on hardware`, `Reported by contributor`, `Catalog candidate`, `Static APK evidence`, or `Unverified`.
6. If there are useful findings, **invite the user** to contribute via the GitHub "Device compatibility report" issue form. Explain what to redact and let the user decide whether to submit it. Never create issues, upload files, or publish identifying data without explicit permission.

## Rules for code changes

- Keep working B21S BLE flows and iOS background/Shortcuts behavior intact unless deliberately modifying and testing them.
- Use protocol-specific adapters instead of interpreting all Bluetooth devices as B21S.
- Prefer English documentation that is accessible to contributors worldwide; the app UI may stay localized.
- Never add third-party decompiled sources, proprietary APKs, manufacturer firmware, Apple signing certificates/profiles, or personal logs to the repository.
- For claims about protocol behavior, include test conditions and clear confidence levels.
- Build unsigned on macOS with the provided GitHub Actions workflow; unsigned compilation does not validate real-hardware behavior.

MIT license applies to original code in this repository; it does not grant rights to proprietary code, brands, or firmware.
