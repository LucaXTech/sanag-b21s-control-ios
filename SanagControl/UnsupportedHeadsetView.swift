import CoreBluetooth
import SwiftUI
import Combine

/// User-initiated, model-filtered discovery for unsupported BLE headphones.
/// All operations are read-only GATT discovery: no characteristic reads,
/// subscriptions, writes, persistent identifiers or automatic uploads.
@MainActor
final class UnsupportedHeadsetInspector: NSObject, ObservableObject {
    struct Candidate: Identifiable {
        let id: UUID // CoreBluetooth identifier; stays on this device.
        let name: String
        let rssi: Int
    }

    struct Characteristic: Identifiable {
        var id: String { uuid }
        let uuid: String
        let properties: String
    }

    struct Service: Identifiable {
        var id: String { uuid }
        let uuid: String
        var characteristics: [Characteristic]
    }

    @Published private(set) var matches: [Candidate] = []
    @Published private(set) var services: [Service] = []
    @Published private(set) var scanning = false
    @Published private(set) var connected = false
    @Published private(set) var inspected = false
    @Published private(set) var selectedName: String?
    @Published private(set) var status = "Enter a headphone brand or model to search."

    private var central: CBCentralManager!
    private var devices: [UUID: CBPeripheral] = [:]
    private var selectedPeripheral: CBPeripheral?
    private var scanRequested = false
    private var modelQuery = ""
    private var hasSearched = false
    private var remainingServices = Set<String>()

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    func search(model: String) {
        let text = String(model.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        guard text.count >= 3 else {
            status = "Enter at least 3 characters from the headphone brand or model."
            return
        }
        disconnect()
        modelQuery = text
        hasSearched = true
        matches = []
        devices = [:]
        services = []
        inspected = false
        selectedName = nil
        scanRequested = true

        guard central.state == .poweredOn else {
            status = "Waiting for Bluetooth permission or availability…"
            return
        }
        beginScan()
    }

    private func beginScan() {
        guard scanRequested, central.state == .poweredOn else { return }
        central.stopScan()
        central.scanForPeripherals(withServices: nil,
                                   options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        scanning = true
        status = "Looking for BLE headphones matching “\(modelQuery)”…"
    }

    func stopScan() {
        scanRequested = false
        central?.stopScan()
        scanning = false
    }

    func inspect(_ candidate: Candidate) {
        guard central.state == .poweredOn,
              let device = devices[candidate.id],
              let observed = matches.first(where: { $0.id == candidate.id }),
              observed.name.localizedCaseInsensitiveContains(modelQuery) else { return }
        stopScan()
        if let existing = selectedPeripheral { central.cancelPeripheralConnection(existing) }
        selectedPeripheral = device
        selectedName = candidate.name
        services = []
        inspected = false
        connected = false
        remainingServices = []
        device.delegate = self
        status = "Connecting to \(candidate.name) to discover GATT metadata…"
        central.connect(device, options: nil)
    }

    func disconnect() {
        stopScan()
        if let device = selectedPeripheral { central.cancelPeripheralConnection(device) }
        selectedPeripheral = nil
        connected = false
        remainingServices = []
    }

    func close() {
        disconnect()
        devices.removeAll()
    }

    /// A requested model can be sent even if it has no observable BLE interface.
    /// Never attach GATT data from a different typed model.
    func contributionDetails(for model: String) -> (status: String, services: [String], characteristics: [String]) {
        let matchesSearch = model.trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare(modelQuery) == .orderedSame
        if matchesSearch && inspected {
            return (
                "observed",
                Array(Set(services.map { $0.uuid })).sorted(),
                Array(Set(services.flatMap { $0.characteristics.map { $0.uuid } })).sorted()
            )
        }
        if matchesSearch && hasSearched && !scanning && matches.isEmpty {
            return ("not_found", [], [])
        }
        return ("not_checked", [], [])
    }

    var reportText: String {
        let model = modelQuery.replacingOccurrences(of: "\n", with: " ")
        var rows = [
            "Headphone compatibility request",
            "Model entered by user: \(model)",
            "Status: unsupported / not verified",
            "iOS BLE discovery: \(inspected ? "GATT inspected" : "not available or not completed")"
        ]
        if inspected {
            for service in services {
                rows.append("Service: \(service.uuid)")
                for characteristic in service.characteristics {
                    rows.append("  Characteristic: \(characteristic.uuid) [\(characteristic.properties)]")
                }
            }
        }
        rows.append("Please add support if a safe, model-specific BLE protocol can be confirmed.")
        rows.append("No serial number, MAC address, CoreBluetooth UUID or raw packets included.")
        return rows.joined(separator: "\n")
    }

    var requestURL: URL? {
        let model = modelQuery.replacingOccurrences(of: "\n", with: " ")
        guard model.count >= 3 else { return nil }
        var url = URLComponents(string: "https://github.com/LucaXTech/sanag-b21s-control-ios/issues/new")
        url?.queryItems = [
            URLQueryItem(name: "title", value: "[Headset] Support request: \(model)"),
            URLQueryItem(name: "body", value: reportText)
        ]
        return url?.url
    }

    private static func describe(_ properties: CBCharacteristicProperties) -> String {
        var values: [String] = []
        if properties.contains(.read) { values.append("read") }
        if properties.contains(.write) { values.append("write") }
        if properties.contains(.writeWithoutResponse) { values.append("writeWithoutResponse") }
        if properties.contains(.notify) { values.append("notify") }
        if properties.contains(.indicate) { values.append("indicate") }
        return values.isEmpty ? "other" : values.joined(separator: ", ")
    }
}

extension UnsupportedHeadsetInspector: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            if scanRequested { beginScan() }
        } else {
            scanning = false
            connected = false
            status = central.state == .unauthorized
                ? "Bluetooth permission was denied. Enable it in iPhone Settings."
                : "Bluetooth LE is unavailable. Try again when it is enabled."
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any],
                        rssi RSSI: NSNumber) {
        guard scanning else { return }
        let advertised = (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
            ?? peripheral.name ?? ""
        guard advertised.localizedCaseInsensitiveContains(modelQuery),
              !advertised.localizedCaseInsensitiveContains("B21S") else { return }
        devices[peripheral.identifier] = peripheral
        let candidate = Candidate(id: peripheral.identifier, name: advertised, rssi: RSSI.intValue)
        if let index = matches.firstIndex(where: { $0.id == candidate.id }) {
            matches[index] = candidate
        } else if matches.count < 30 {
            matches.append(candidate)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard peripheral.identifier == selectedPeripheral?.identifier else { return }
        connected = true
        status = "Connected. Discovering GATT services and characteristics only."
        peripheral.delegate = self
        peripheral.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager,
                        didFailToConnect peripheral: CBPeripheral, error: Error?) {
        guard peripheral.identifier == selectedPeripheral?.identifier else { return }
        connected = false
        status = "BLE connection failed. You can still request support for this model."
    }

    func centralManager(_ central: CBCentralManager,
                        didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard peripheral.identifier == selectedPeripheral?.identifier else { return }
        connected = false
        status = inspected
            ? "Disconnected. The discovered GATT metadata is available for your report."
            : "Disconnected before discovery completed."
    }
}

extension UnsupportedHeadsetInspector: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard peripheral.identifier == selectedPeripheral?.identifier else { return }
        guard error == nil else {
            status = "Could not discover services. You can still request support."
            return
        }
        let discovered = peripheral.services ?? []
        services = discovered.map { Service(uuid: $0.uuid.uuidString, characteristics: []) }
        remainingServices = Set(discovered.map { $0.uuid.uuidString })
        if remainingServices.isEmpty {
            inspected = true
            status = "Device not supported yet. No GATT services were exposed."
        } else {
            status = "Found \(discovered.count) GATT services. Reading characteristic metadata…"
            for service in discovered { peripheral.discoverCharacteristics(nil, for: service) }
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard peripheral.identifier == selectedPeripheral?.identifier else { return }
        let identifier = service.uuid.uuidString
        if let index = services.firstIndex(where: { $0.uuid == identifier }) {
            services[index].characteristics = (service.characteristics ?? []).map {
                Characteristic(uuid: $0.uuid.uuidString,
                               properties: Self.describe($0.properties))
            }
        }
        remainingServices.remove(identifier)
        if remainingServices.isEmpty {
            inspected = true
            status = "These headphones are not supported yet. Request support to help add them."
        }
    }
}

/// Avoids a generic list of TVs, watches, printers and unrelated BLE devices:
/// results are shown only when their advertised names match what the user typed.
struct UnsupportedHeadsetView: View {
    @StateObject private var inspector = UnsupportedHeadsetInspector()
    @StateObject private var telemetry = DeviceTelemetry.shared
    @State private var model = ""
    @State private var showConsent = false

    var body: some View {
        Form {
            Section {
                TextField("Enter the headphone brand and model", text: $model)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                HStack {
                    Button(inspector.scanning ? "Stop search" : "Find my headphones") {
                        if inspector.scanning { inspector.stopScan() }
                        else { inspector.search(model: model) }
                    }
                    .disabled(!inspector.scanning &&
                              model.trimmingCharacters(in: .whitespacesAndNewlines).count < 3)
                    Spacer()
                    if inspector.scanning { ProgressView() }
                }
                Text(inspector.status)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Find unsupported headphones")
            } footer: {
                Text("Only nearby BLE devices whose advertised name matches the model you enter are shown. Classic-Bluetooth-only headphones may not appear.")
            }

            if !inspector.matches.isEmpty {
                Section("Matching BLE devices") {
                    ForEach(inspector.matches) { candidate in
                        Button {
                            inspector.inspect(candidate)
                        } label: {
                            HStack {
                                Text(candidate.name)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text("\(candidate.rssi) dBm")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            if inspector.connected || inspector.inspected {
                Section("Available BLE metadata") {
                    Text("These headphones are not supported yet. Only their GATT interface is being inspected; proprietary EQ/ANC commands cannot be extracted automatically.")
                        .font(.footnote)
                    if inspector.services.isEmpty {
                        Text("No services discovered.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(inspector.services) { service in
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Service \(service.uuid)")
                                .font(.subheadline.weight(.semibold))
                                .textSelection(.enabled)
                            ForEach(service.characteristics) { characteristic in
                                Text("\(characteristic.uuid) · \(characteristic.properties)")
                                    .font(.caption.monospaced())
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
            }

            Section("Request support") {
                Text("Your \(model.isEmpty ? "headphones" : model) aren't supported yet. You can send an anonymous compatibility request directly to the developer. No GitHub account needed.")
                    .font(.subheadline)
                Button {
                    showConsent = true
                } label: {
                    HStack {
                        Label("Send support request", systemImage: "paperplane")
                        Spacer()
                        if telemetry.isSubmittingSupportRequest { ProgressView() }
                    }
                }
                .disabled(telemetry.isSubmittingSupportRequest ||
                          model.trimmingCharacters(in: .whitespacesAndNewlines).count < 3 ||
                          !telemetry.isConfigured)
                if let result = telemetry.supportResult {
                    Text(result)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if !telemetry.isConfigured {
                    Text("Direct reporting is unavailable in this build.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text("We send only the model you enter, available BLE service/characteristic UUIDs and app version. No serial numbers, device identifiers, audio or logs. Your IP is processed by the hosting provider during delivery; reports are aggregated.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Unsupported headphones")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Send anonymous support request?", isPresented: $showConsent) {
            Button("Cancel", role: .cancel) { }
            Button("Send request") {
                let details = inspector.contributionDetails(for: model)
                telemetry.submitSupportRequest(
                    model: model, bleStatus: details.status,
                    services: details.services,
                    characteristics: details.characteristics
                )
            }
        } message: {
            Text("Share the headphone model you typed, the app version and any GATT UUIDs inspected, using the same compatibility reporting service. No GitHub account or automatic sharing permission is required. Review the model before submitting.")
        }
        .onChange(of: model) { _, _ in
            telemetry.clearSupportResult()
        }
        .onDisappear { inspector.close() }
    }
}
