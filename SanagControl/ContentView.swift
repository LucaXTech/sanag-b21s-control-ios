import SwiftUI
import UIKit

private enum B21SUI {
    static let titles = ["Stereo+", "Pop", "Rock", "Classical", "Vocals", "Soft"]
    static let original = ["SSQVP", "Pop ultrasonico", "Rock festoso", "Classica ricerca suoni", "Lirica iniziale", "Purezza morbida"]

    static func name(_ value: Int?) -> String {
        guard let value, titles.indices.contains(value) else { return "Not detected" }
        return titles[value]
    }

    static func command(_ index: Int) -> String {
        guard (0...5).contains(index) else { return "—" }
        let checksum = UInt8(truncatingIfNeeded: 0xAA + 0x39 + 0x01 + index)
        return String(format: "AA 39 01 %02X %02X", index, checksum)
    }
}

struct ContentView: View {
    @EnvironmentObject private var ble: B21SBluetoothManager
    @StateObject private var telemetry = DeviceTelemetry.shared
    @State private var showTelemetryConsent = false
    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    deviceHero
                    presetsCard
                    NavigationLink {
                        CommunityHeadsetView()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "headphones")
                                .font(.title3)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Other supported headphones")
                                    .font(.headline)
                                Text("TOZO T10 and Marshall Motif II ANC · Experimental")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                        .padding(18)
                        .panel()
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Sanag Control")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        B21SSettingsView()
                    } label: {
                        Image(systemName: "gearshape")
                            .accessibilityLabel("Settings")
                    }
                }
            }
            .tint(.blue)
            .onAppear {
                if telemetry.isConfigured && !telemetry.hasDecided {
                    showTelemetryConsent = true
                }
            }
            .alert("Help us support more headphones",
                   isPresented: $showTelemetryConsent) {
                Button("Do not share", role: .cancel) {
                    telemetry.setConsent(false)
                }
                Button("Enable sharing") {
                    telemetry.setConsent(true)
                }
            } message: {
                Text("With your permission, the app shares a small technical compatibility report after connecting to a supported headset: its model, BLE service and characteristic UUIDs, and app version. No device identifiers, audio or logs are included. The hosting service sees your IP address in transit but does not store it in the report. You can disable sharing in Settings.")
            }
        }
    }

    // Una sola card raccoglie dispositivo, connessione, preset e batteria.
    private var deviceHero: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 11) {
                Image(systemName: "headphones")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(.cyan)
                    .frame(width: 48, height: 48)
                    .background(Color.blue.opacity(0.18), in: RoundedRectangle(cornerRadius: 15))

                VStack(alignment: .leading, spacing: 6) {
                    Text("sanag B21S")
                        .font(.headline)
                    HStack(spacing: 6) {
                        Circle()
                            .fill(ble.isReady ? Color.green : Color.orange)
                            .frame(width: 7, height: 7)
                        Text(ble.isReady ? "Connected" : ble.connectionStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 3)
                if ble.isReady {
                    batteryBadge
                }
            }

            Rectangle()
                .fill(Color.secondary.opacity(0.16))
                .frame(height: 1)

            VStack(alignment: .leading, spacing: 6) {
                Text("ACTIVE EQ PRESET")
                    .font(.caption2.weight(.semibold))
                    .tracking(1.1)
                    .foregroundStyle(.secondary)
                Text(ble.isReady ? B21SUI.name(ble.actualPreset) : "Not connected")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .contentTransition(.opacity)
            }

            if !ble.isConnected {
                Button {
                    if ble.isScanning { ble.stopScan() } else { ble.scan() }
                } label: {
                    Label(ble.isScanning ? "Stop scan" : "Find B21S", systemImage: "magnifyingglass")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(19)
        .heroPanel()
    }

    // Il pulsante occupa soltanto l'angolo superiore destro della card.
    private var batteryBadge: some View {
        Button {
            ble.requestBattery()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: batteryIcon)
                    .foregroundStyle(batteryColor)
                Text(ble.batteryLevel.map { "\($0)%" } ?? "—")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.blue.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("B21S battery: \(ble.batteryLevel.map { "\($0) percent" } ?? "not available"). Tap to refresh.")
    }

    private var batteryIcon: String {
        guard let level = ble.batteryLevel else { return "battery.0percent" }
        switch level {
        case 88...100: return "battery.100percent"
        case 63..<88: return "battery.75percent"
        case 38..<63: return "battery.50percent"
        case 13..<38: return "battery.25percent"
        default: return "battery.0percent"
        }
    }

    private var batteryColor: Color {
        guard let level = ble.batteryLevel else { return .secondary }
        return level <= 20 ? .orange : .green
    }

    private var presetsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Equalizer")
                    .font(.headline)
                Spacer()
                Button {
                    ble.requestStatus()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.subheadline.weight(.medium))
                }
                .disabled(!ble.isReady)
                .accessibilityLabel("Refresh active EQ preset")
            }

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(0..<6, id: \.self) { index in
                    let selected = ble.isReady && ble.actualPreset == index
                    Button {
                        ble.selectPreset(index)
                    } label: {
                        HStack(spacing: 5) {
                            Text(B21SUI.titles[index])
                                .font(.system(size: 16, weight: .semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.78)
                            Spacer(minLength: 2)
                            if selected {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 16))
                            }
                        }
                        .foregroundStyle(selected ? Color.white : Color.primary)
                        .padding(.horizontal, 15)
                        .frame(maxWidth: .infinity, minHeight: 69)
                        .background(
                            selected ? Color.blue : Color(.tertiarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: 17)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 17)
                                .strokeBorder(selected ? Color.cyan.opacity(0.55) : Color.clear, lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(!ble.isReady)
                    .accessibilityLabel("Preset \(B21SUI.titles[index])")
                    .accessibilityAddTraits(selected ? [.isSelected] : [])
                }
            }
        }
        .padding(18)
        .panel()
    }
}

private struct B21SSettingsView: View {
    @EnvironmentObject private var ble: B21SBluetoothManager
    @StateObject private var telemetry = DeviceTelemetry.shared

    var body: some View {
        Form {
            Section {
                Toggle("Auto-connect", isOn: $ble.autoConnect)
                Toggle("Restore saved preset", isOn: $ble.autoRestore)
            } header: {
                Text("Automation")
            } footer: {
                Text("Il ripristino può avvenire anche tramite l'azione “Ripristina EQ B21S” di Comandi Rapidi. L'esecuzione in background dipende da iOS.")
            }

            Section {
                Toggle("Share anonymous compatibility data", isOn: $telemetry.isEnabled)
                    .disabled(!telemetry.isConfigured)
            } header: {
                Text("Help improve compatibility")
            } footer: {
                if telemetry.isConfigured {
                    Text("Dopo il consenso, inviamo al massimo un report ogni 30 giorni per questa installazione: modello, servizi e caratteristiche BLE osservati e versione app. Nessun identificativo persistente, audio o log. La rete trasmette l'IP al servizio, che non lo salva nel database. Puoi disattivare l'invio in qualsiasi momento.")
                } else {
                    Text("Remote reporting is not configured in this build. No data will be sent.")
                }
            }

            Section("Community-supported headphones") {
                NavigationLink {
                    CommunityHeadsetView()
                } label: {
                    Label("Other headphone models (experimental)", systemImage: "headphones")
                }
            }

            Section("B21S device") {
                if let uuid = ble.knownPeripheralID {
                    LabeledContent("Saved B21S", value: String(uuid.uuidString.suffix(8)))
                }
                if ble.isConnected {
                    Button("Disconnect") { ble.disconnect() }
                } else {
                    Button(ble.isScanning ? "Stop scan" : "Find B21S") {
                        if ble.isScanning { ble.stopScan() } else { ble.scan() }
                    }
                    ForEach(ble.foundDevices) { device in
                        Button {
                            ble.connect(to: device)
                        } label: {
                            HStack {
                                Text(device.name)
                                Spacer()
                                Text("\(device.rssi) dBm")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                if ble.knownPeripheralID != nil {
                    Button("Forget B21S", role: .destructive) { ble.forgetDevice() }
                }
            }

            Section("Advanced") {
                NavigationLink {
                    B21SProtocolView()
                } label: {
                    Label("BLE protocol and commands", systemImage: "chevron.left.forwardslash.chevron.right")
                }
                NavigationLink {
                    B21SDiagnosticsView()
                } label: {
                    Label("Logs and diagnostics", systemImage: "waveform.path.ecg")
                }
            }

            Section {
                LabeledContent("Developer", value: "Luca Serioli")
                LabeledContent("Version", value: "0.5.0")
                Text("© 2026 Luca Serioli")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("About")
            } footer: {
                Text("Independent project, not affiliated with Sanag or any headphone manufacturer. No firmware updates.")
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct B21SProtocolView: View {
    @EnvironmentObject private var ble: B21SBluetoothManager

    var body: some View {
        Form {
            Section("GATT services") {
                LabeledContent("Advertising", value: "A0FA")
                LabeledContent("EQ service", value: "FAA0")
                LabeledContent("Write", value: "FAA1")
                LabeledContent("Notifications", value: "FAA2")
            }
            Section("Read status") {
                Text("AA 76 01 00 21")
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                Button("Read active preset") { ble.requestStatus() }
                    .disabled(!ble.isReady)
            }
            Section("Battery (protocol 0x33)") {
                Text("AA 33 01 00 DE")
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                Button("Read battery") { ble.requestBattery() }
                    .disabled(!ble.isReady)
                LabeledContent("Latest response", value: ble.batteryLevel.map { "\($0)%" } ?? "Not available")
                Text("A5 33 01 XX checksum is interpreted as a battery percentage when XX is between 0 and 100. Requires further validation.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("Verified B21S EQ commands") {
                ForEach(0..<6, id: \.self) { index in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("\(index) · \(B21SUI.titles[index])")
                                .fontWeight(.semibold)
                            Spacer()
                            Text("#\(index)")
                                .foregroundStyle(.secondary)
                        }
                        Text(B21SUI.command(index))
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                        Text("Original label: \(B21SUI.original[index])")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 3)
                }
            }
            Section {
                Text("Solo lettura e comandi EQ già verificati. Non è disponibile l'invio arbitrario di pacchetti al firmware.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("BLE protocol")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct B21SDiagnosticsView: View {
    @EnvironmentObject private var ble: B21SBluetoothManager

    var body: some View {
        List {
            Section {
                HStack {
                    Button("Copy logs") {
                        UIPasteboard.general.string = ble.events.reversed().joined(separator: "\n")
                    }
                    .disabled(ble.events.isEmpty)
                    Spacer()
                    Button("Clear logs", role: .destructive) { ble.clearEventLog() }
                        .disabled(ble.events.isEmpty)
                }
            } footer: {
                Text("Logs remain on this device. Remove any identifiers before sharing.")
            }
            Section("Recent BLE events") {
                if ble.events.isEmpty {
                    Text("No events recorded")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(ble.events.enumerated()), id: \.offset) { _, entry in
                        Text(entry)
                            .font(.system(size: 12, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
            }
        }
        .navigationTitle("Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private extension View {
    func panel() -> some View {
        self.frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 22))
    }

    @ViewBuilder
    func heroPanel() -> some View {
        if #available(iOS 26.0, *) {
            self.frame(maxWidth: .infinity, alignment: .leading)
                .glassEffect(.regular, in: .rect(cornerRadius: 24))
        } else {
            self.panel()
        }
    }
}
