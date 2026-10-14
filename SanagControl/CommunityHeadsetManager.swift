import Foundation
import Combine
import CoreBluetooth

/// Explicit model-selection adapter; never connects to arbitrary BLE devices.
/// Experimental commands require a recognized name, matching GATT service,
/// characteristic properties and a manual user action.
@MainActor
final class CommunityHeadsetManager: NSObject, ObservableObject {
    struct Candidate: Identifiable {
        let id: UUID
        let profile: ExperimentalHeadset
        let rssi: Int
    }

    @Published private(set) var candidates: [Candidate] = []
    @Published private(set) var scanning = false
    @Published private(set) var ready = false
    @Published private(set) var status = "Select Scan to find supported headphone models."
    @Published private(set) var selectedModel: ExperimentalHeadset?
    @Published private(set) var battery: String?

    private var central: CBCentralManager!
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var selected: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    private var notifyCharacteristic: CBCharacteristic?
    private var eqCharacteristic: CBCharacteristic?
    private var pendingMarshallStep: [UInt8]?
    private var awaitingBattery = false
    private var scanRequested = false

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    func scan() {
        guard central.state == .poweredOn else {
            scanRequested = true
            status = "Bluetooth LE is not available. Check Bluetooth permissions."
            return
        }
        disconnect()
        scanRequested = true
        candidates.removeAll()
        peripherals.removeAll()
        central.scanForPeripherals(withServices: nil, options: [
            CBCentralManagerScanOptionAllowDuplicatesKey: false
        ])
        scanning = true
        status = "Scanning for TOZO T10 and Marshall Motif II ANC…"
    }

    func stopScan() {
        scanRequested = false
        central.stopScan()
        scanning = false
        if !ready { status = "Scan stopped." }
    }

    func connect(_ candidate: Candidate) {
        guard central.state == .poweredOn,
              let peripheral = peripherals[candidate.id],
              !scanning || scanRequested else { return }
        // Check the observed name again; do not trust a stale UI selection.
        guard ExperimentalHeadset.match(advertisedName: peripheral.name ?? candidate.profile.rawValue) == candidate.profile else {
            status = "The selected device identity could not be confirmed."
            return
        }
        disconnect()
        selected = peripheral
        selectedModel = candidate.profile
        peripheral.delegate = self
        status = "Connecting to \(candidate.profile.rawValue)…"
        central.connect(peripheral, options: nil)
    }

    func disconnect() {
        stopScan()
        if let selected { central.cancelPeripheralConnection(selected) }
        selected = nil
        selectedModel = nil
        ready = false
        writeCharacteristic = nil
        notifyCharacteristic = nil
        eqCharacteristic = nil
        pendingMarshallStep = nil
        awaitingBattery = false
        battery = nil
    }

    func requestBattery() {
        guard ready, selectedModel == .tozoT10,
              sendTOZO(TOZOT10Commands.battery) else { return }
        awaitingBattery = true
        status = "Battery request sent; waiting for notification."
    }

    func setGameMode(_ enabled: Bool) {
        guard ready, selectedModel == .tozoT10 else { return }
        if sendTOZO(TOZOT10Commands.gameMode(enabled)) {
            status = "Game Mode request sent; hardware confirmation is not yet available."
        }
    }

    func setANC(_ mode: MarshallMotifIICommands.ANC) {
        guard ready, selectedModel == .marshallMotifII,
              let peripheral = selected, let char = writeCharacteristic,
              char.uuid.uuidString.uppercased() == MarshallMotifIICommands.ancUUID,
              char.properties.contains(.write) else { return }
        peripheral.writeValue(Data(MarshallMotifIICommands.anc(mode)),
                              for: char, type: .withResponse)
        status = "ANC command sent; waiting for acknowledgement."
    }

    func setMarshallEQ(_ preset: MarshallMotifIICommands.EQ) {
        guard ready, selectedModel == .marshallMotifII,
              pendingMarshallStep == nil,
              let peripheral = selected, let char = eqCharacteristic,
              char.uuid.uuidString.uppercased() == MarshallMotifIICommands.equalizerUUID,
              char.properties.contains(.write) else { return }
        let packets = MarshallMotifIICommands.equalizer(preset)
        pendingMarshallStep = packets[1]
        peripheral.writeValue(Data(packets[0]), for: char, type: .withResponse)
        status = "Assigning EQ preset; waiting for acknowledgement before activation."
    }

    /// The same consented v2 contribution channel used by the B21S manager.
    /// Only after an exact model profile and expected GATT channels are present.
    private func reportIfConsented() {
        guard ready, let peripheral = selected, let model = selectedModel else { return }
        DeviceTelemetry.shared.submitIfNeeded(
            model: model.rawValue,
            services: peripheral.services?.map { $0.uuid.uuidString } ?? [],
            characteristics: peripheral.services?.flatMap { $0.characteristics ?? [] }
                .map { $0.uuid.uuidString } ?? []
        )
    }

    private func sendTOZO(_ bytes: [UInt8]) -> Bool {
        guard let peripheral = selected, let char = writeCharacteristic,
              char.uuid == CBUUID(string: "B611") else { return false }
        let type: CBCharacteristicWriteType
        if char.properties.contains(.writeWithoutResponse) {
            type = .withoutResponse
        } else if char.properties.contains(.write) {
            type = .withResponse
        } else { return false }
        peripheral.writeValue(Data(bytes), for: char, type: type)
        return true
    }

    private func finishProfileDiscovery() {
        guard let peripheral = selected, let profile = selectedModel,
              writeCharacteristic != nil else { return }
        if profile == .tozoT10 {
            guard let notify = notifyCharacteristic,
                  notify.properties.contains(.notify) else {
                status = "This TOZO device does not expose the expected notification channel."
                return
            }
            peripheral.setNotifyValue(true, for: notify)
            status = "Enabling the TOZO notification channel…"
        } else {
            // Marshall ANC and EQ are different GATT characteristics.
            guard eqCharacteristic != nil else {
                status = "Marshall EQ characteristic was not found."
                return
            }
            ready = true
            status = "Marshall protocol located. Controls are experimental on iOS."
            reportIfConsented()
        }
    }


}

extension CommunityHeadsetManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            status = "Bluetooth ready. Scan for supported models."
            if scanRequested { scan() }
        } else {
            scanning = false
            ready = false
            status = "Bluetooth unavailable or permission denied."
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard scanning else { return }
        let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
            ?? peripheral.name ?? ""
        guard let profile = ExperimentalHeadset.match(advertisedName: name) else { return }
        // Names are just candidate hints. The exact service and characteristics
        // must also match before we enable any protocol-specific controls.
        peripherals[peripheral.identifier] = peripheral
        let candidate = Candidate(id: peripheral.identifier, profile: profile, rssi: RSSI.intValue)
        if let index = candidates.firstIndex(where: { $0.id == candidate.id }) {
            candidates[index] = candidate
        } else if candidates.count < 40 {
            candidates.append(candidate)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard peripheral.identifier == selected?.identifier,
              let profile = selectedModel else { return }
        peripheral.delegate = self
        status = "Connected. Checking exact \(profile.rawValue) GATT service…"
        peripheral.discoverServices([CBUUID(string: profile.serviceUUID)])
    }

    func centralManager(_ central: CBCentralManager,
                        didFailToConnect peripheral: CBPeripheral, error: Error?) {
        guard peripheral.identifier == selected?.identifier else { return }
        ready = false
        status = "Connection failed: \(error?.localizedDescription ?? "unknown error")"
    }

    func centralManager(_ central: CBCentralManager,
                        didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard peripheral.identifier == selected?.identifier else { return }
        ready = false
        pendingMarshallStep = nil
        status = "Headphones disconnected."
    }
}

extension CommunityHeadsetManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard peripheral.identifier == selected?.identifier,
              let profile = selectedModel else { return }
        guard error == nil,
              let service = peripheral.services?.first(where: {
                  $0.uuid == CBUUID(string: profile.serviceUUID)
              }) else {
            status = "Expected GATT service not found; no commands will be sent."
            return
        }
        if profile == .tozoT10 {
            peripheral.discoverCharacteristics([CBUUID(string: "B611"), CBUUID(string: "B612")],
                                               for: service)
        } else {
            peripheral.discoverCharacteristics([
                CBUUID(string: MarshallMotifIICommands.ancUUID),
                CBUUID(string: MarshallMotifIICommands.equalizerUUID)
            ], for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard peripheral.identifier == selected?.identifier,
              let profile = selectedModel else { return }
        guard error == nil else {
            status = "GATT characteristic discovery failed."
            return
        }
        writeCharacteristic = service.characteristics?.first(where: {
            $0.uuid == CBUUID(string: profile.writeUUID)
                && ($0.properties.contains(.write) || $0.properties.contains(.writeWithoutResponse))
        })
        if profile == .tozoT10 {
            notifyCharacteristic = service.characteristics?.first(where: {
                $0.uuid == CBUUID(string: "B612")
            })
        } else {
            eqCharacteristic = service.characteristics?.first(where: {
                $0.uuid == CBUUID(string: MarshallMotifIICommands.equalizerUUID)
                    && $0.properties.contains(.write)
            })
        }
        finishProfileDiscovery()
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard peripheral.identifier == selected?.identifier,
              selectedModel == .tozoT10 else { return }
        if error == nil && characteristic.isNotifying {
            ready = true
            status = "TOZO T10 BLE protocol found. Experimental commands are available."
            reportIfConsented()
        } else {
            status = "Could not enable TOZO notifications; no controls enabled."
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard peripheral.identifier == selected?.identifier,
              selectedModel == .tozoT10,
              characteristic.uuid == CBUUID(string: "B612"),
              error == nil,
              awaitingBattery,
              let data = characteristic.value else { return }
        // The original T10 reference parser uses response bytes 3 and 4.
        if let values = TOZOT10Commands.batteryLevels(Array(data)) {
            awaitingBattery = false
            battery = "Left: \(values.left)% · Right: \(values.right)%"
            status = "Battery response received."
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard peripheral.identifier == selected?.identifier,
              selectedModel == .marshallMotifII else { return }
        if error != nil {
            pendingMarshallStep = nil
            status = "Headphones rejected the BLE write; EQ activation cancelled."
            return
        }
        if characteristic.uuid == CBUUID(string: MarshallMotifIICommands.equalizerUUID),
           let next = pendingMarshallStep {
            pendingMarshallStep = nil
            peripheral.writeValue(Data(next), for: characteristic, type: .withResponse)
            status = "EQ preset activation sent; waiting for acknowledgement."
        } else {
            status = "BLE write acknowledged (device state not independently confirmed)."
        }
    }
}
