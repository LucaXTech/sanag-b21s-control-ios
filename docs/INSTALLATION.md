# Build, install, and iOS signing

Sanag Control is distributed as **source code**. The repository does **not** provide a signed, universally installable `.ipa`.

## Installing from Xcode

1. Install Xcode 26 or later on a Mac.
2. Clone this repository: `git clone https://github.com/LucaXTech/sanag-b21s-control-ios.git`.
3. Open `SanagControl.xcodeproj`.
4. Under the app target's **Signing & Capabilities**, choose **Automatically manage signing** and your personal Apple Team.
5. If your Apple Team is not the upstream developer's team, change `PRODUCT_BUNDLE_IDENTIFIER` to a unique bundle identifier (both Debug and Release).
6. Select the iPhone and choose **Run**. Allow Bluetooth access when prompted.

**Do not delete an existing app if you intend to preserve saved preset and preferences.** Updates ordinarily preserve local UserDefaults only when iOS recognizes the same application identity and compatible signing.

## Why does a free Apple ID expire after 7 days?

Apple's *Personal Team* signing provision expires seven days after issuance. Rebuilding/reinstalling through Xcode renews it. A GitHub release, source repository or unmodified IPA does not remove this limitation.

## Alternatives

| Distribution / signing | Frequency | Notes |
|---|---|---|
| Xcode + free Personal Team | 7 days | Rebuild/reinstall using Xcode. |
| SideStore / AltStore Classic with free Apple Account | 7 days, refreshable | Can help refresh the signature; setup requirements and current-iOS compatibility must be checked. Not permanent signing. Re-signing with a different Team may require reinstalling, losing existing app data. |
| Paid Apple Developer Program | Generally up to one-year development/ad-hoc profile | Annual membership, account and device registration; not indefinite provisioning. |
| Official App Store distribution | No 7-day sideload expiry for installed consumer app | Requires paid developer membership and App Review; maintained like normal apps. |
| TestFlight | 90-day build expiration | Intended for testing, not permanent personal deployment. |

When testing SideStore or another signing method, **export or record your preset and settings** first. Preserving data across a *change of signing identity* is not guaranteed. Some iOS versions or beta releases may not be supported by these tools.

Apple docs: https://developer.apple.com/help/account/basics/about-your-developer-account and https://developer.apple.com/help/account/provisioning-profiles/create-an-ad-hoc-provisioning-profile/
