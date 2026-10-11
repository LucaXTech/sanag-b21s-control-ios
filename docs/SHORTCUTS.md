# Automatic EQ restoration using iOS Shortcuts

The app publishes the App Intent **Ripristina EQ B21S**.

1. Install the app from Xcode, open it once, connect the B21S, choose an EQ preset and enable automatic restoration in Settings.
2. Open **Shortcuts → Automation → + → Bluetooth**.
3. Select your connected **Sanag B21S**, choose **When Connected**, and set the automation to **Run Immediately** (wording may vary by iOS version).
4. Choose the **Ripristina EQ B21S** action provided by Sanag Control. **Do not add an `Open App` action**.
5. Test first by running the shortcut directly, then by turning the headphones off and back on with the iPhone locked.

The Shortcuts trigger typically observes the iOS audio Bluetooth connection. Sanag Control uses a separate BLE GATT session for the EQ protocol. iOS might not dispatch the automation every time, might delay its execution, and might show an unavoidable Shortcuts system banner. The App Intent does not itself present a confirmation dialog.

The action waits for a confirmation response up to 25 seconds. The app stores recent connection events locally under Settings → diagnostics. If the restoration fails, the action intentionally does not present a blocking dialog.

Background CoreBluetooth state restoration is a separate mechanism and **cannot guarantee launch after the user force quits the app**.
