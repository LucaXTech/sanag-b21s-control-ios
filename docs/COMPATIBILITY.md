# Device compatibility and evidence

| Device or family | Evidence classification | EQ preset selection | Auto-restore | Battery | Notes |
|---|---|---|---|---|---|
| **Sanag B21S** | **Hardware-verified on one owner's device** | Verified: codes 0–5 | Verified in the owner's test conditions; iOS background behavior is not guaranteed | Experimental (not cross-checked yet) | BLE service `FAA0`, write `FAA1`, notify `FAA2`; packet family `AA ...`, replies `A5 ...` |
| Other Sanag catalog records with protocol label `HP0036_1_3_1` | **Catalog candidates only** | Not tested | Not tested | Not tested | An earlier static catalog comparison identified 65 other entries with the same label. This alone proves no BLE compatibility. |
| JAJK JR50, LA5X | **Catalog candidates only** | Not tested | Not tested | Not tested | Different names in the Sanag catalog; no live hardware confirmation. |
| SOUNDPEATS devices | **Not established** | Not tested with this app | Not tested | Not tested | Analysis of SOUNDPEATS 2.5.2 showed different protocol families; no assumption of shared EQ commands. |

## How to contribute a new device

1. Search existing [compatibility reports](https://github.com/LucaXTech/sanag-b21s-control-ios/issues/new/choose) and this table before testing.
2. Record brand, marketed model name, and firmware **version only if readily available**.
3. With the device under your control, use a read-only BLE scanner to note the advertised local name, service UUIDs, and characteristic UUIDs. Avoid publishing serial numbers, MAC addresses, CoreBluetooth IDs, paired device lists, and unredacted screenshots.
4. If you have an already-tested, safe operation with the device's official application, describe the *result*. Do not try undocumented writes to an unknown device.
5. Open a GitHub **Device compatibility report** and state what was physically tested versus inferred from documents or APK analysis.

A match on `FAA0`/`FAA1`/`FAA2` is **not enough**: an unrelated body-composition scale family has been documented with those UUIDs and a different application protocol. A positive match requires device-specific packet evidence and a response observed on hardware.

The repository maintainer will review reports before promoting any model to `Verified`.
