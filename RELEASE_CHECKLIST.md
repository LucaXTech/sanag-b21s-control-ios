# Public release checklist

- [ ] Build `SanagControl.xcodeproj` successfully using Xcode 26+ / unsigned CI.
- [ ] Test installation on iPhone with Bluetooth permissions, screenshot/icon and six EQ modes.
- [ ] Compare battery percentage against iOS and official B21S app; mark confirmed only if validated.
- [ ] Re-test Shortcuts, background and off/on restore; keep iOS force-quit limitation visible.
- [ ] Review `git status` / `git diff --cached --stat` and `git diff --cached` before pushing.
- [ ] Ensure no provisioning profiles, identity information, signing materials, logs, APKs or firmware are committed.
- [ ] Validate copyright/license choice and brand disclaimer.
- [ ] Create a GitHub release after CI is green; do not attach unsigned or falsely advertised 'ready to install' IPA.

- [ ] Validate the `device_compatibility.yml` issue form on GitHub and confirm CI passes.
- [ ] Install v0.4.4 on the developer’s own iPhone and confirm EQ, Shortcuts, icon, battery UI, and background behavior after the v0.4.4 UI changes.
- [ ] Keep compatibility claims B21S-only; experimental battery decoding clearly labeled.
