import Foundation
import Combine
import CoreBluetooth
import UIKit

/// Controller per Sanag B21S: connessione automatica, reconnect persistente e state restoration BLE.
/// iOS può sospendere/terminare l'app o ignorare eventi dopo un'uscita forzata: nessuna garanzia 24/7.
@MainActor
final class B21SBluetoothManager: NSObject, ObservableObject {
    static let shared = B21SBluetoothManager()

    struct FoundDevice: Identifiable {
        let id: UUID
        let name: String
        let rssi: Int
    }

    @Published private(set) var bluetoothStatus = "Inizializzazione Bluetooth…"
    @Published private(set) var connectionStatus = "Non connesso"
    @Published private(set) var foundDevices: [FoundDevice] = []
    @Published private(set) var isScanning = false
    @Published private(set) var isConnected = false
    @Published private(set) var isReady = false
    @Published private(set) var actualPreset: Int?
    @Published private(set) var batteryLevel: Int?
    @Published private(set) var savedPreset: Int?
    @Published private(set) var knownPeripheralID: UUID?
    @Published private(set) var events: [String] = []

    @Published var autoRestore: Bool {
        didSet { defaults.set(autoRestore, forKey: Self.autoRestoreKey) }
    }
    @Published var autoConnect: Bool {
        didSet {
            defaults.set(autoConnect, forKey: Self.autoConnectKey)
            if autoConnect {
                manualDisconnect = false
                if central?.state == .poweredOn { resumeConnection() }
            } else if isScanning {
                central?.stopScan()
                isScanning = false
                log("Ricerca automatica disattivata")
            }
        }
    }

    private static let autoRestoreKey = "B21S.AutoRestore"
    private static let autoConnectKey = "B21S.AutoConnect"
    private static let savedPresetKey = "B21S.SavedPreset"
    private static let peripheralIDKey = "B21S.KnownPeripheralID"
    private static let recentEventsKey = "B21S.Events"
    private static let restorationIdentifier = "com.lucaxtech.sanagcontrol.ble.central.v2"

    private let defaults = UserDefaults.standard
    private let serviceUUID = CBUUID(string: "FAA0")
    private let writeUUID = CBUUID(string: "FAA1")
    private let notifyUUID = CBUUID(string: "FAA2")
    private let advertisedUUID = CBUUID(string: "A0FA")

    private var central: CBCentralManager!
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var connectedPeripheral: CBPeripheral?
    private var connectingPeripheralID: UUID?
    private var writeCharacteristic: CBCharacteristic?
    private var notifyCharacteristic: CBCharacteristic?
    private var manualDisconnect = false
    private var restoredBySystem = false
    // Comandi Rapidi: conserva l'azione fino all'ACK BLE o al timeout.
    // L'azione non lascia un processo permanentemente in esecuzione.
    private var shortcutPending: (preset: Int, continuation: CheckedContinuation<Bool, Never>)?

    /// Azione richiamabile da Comandi Rapidi senza aprire l'interfaccia.
    /// Attende la conferma 0x39 del firmware, o restituisce false dopo 25 secondi.
    func applySavedPresetFromShortcut() async -> Bool {
        guard let preset = savedPreset, (0...5).contains(preset) else {
            log("Automazione: nessun preset memorizzato")
            return false
        }
        guard shortcutPending == nil else {
            log("Automazione: richiesta EQ già in corso")
            return false
        }
        guard central.state != .unauthorized, central.state != .unsupported else {
            log("Automazione: Bluetooth non autorizzato o non supportato")
            return false
        }
        manualDisconnect = false
        if !autoConnect { autoConnect = true }
        return await withCheckedContinuation { continuation in
            shortcutPending = (preset, continuation)
            log("Automazione: richiesta preset \(preset)" )
            if isReady {
                sendPreset(preset, restored: true)
            } else if central.state == .poweredOn {
                resumeConnection()
            }
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 25_000_000_000)
                self?.finishShortcut(false)
            }
        }
    }

    private func finishShortcut(_ success: Bool) {
        guard let pending = shortcutPending else { return }
        shortcutPending = nil
        log(success ? "Automazione: preset confermato" : "Automazione: timeout o EQ non confermato")
        pending.continuation.resume(returning: success)
    }

    override init() {
        autoRestore = defaults.object(forKey: Self.autoRestoreKey) as? Bool ?? true
        autoConnect = defaults.object(forKey: Self.autoConnectKey) as? Bool ?? true
        savedPreset = defaults.object(forKey: Self.savedPresetKey) as? Int
        knownPeripheralID = defaults.string(forKey: Self.peripheralIDKey).flatMap(UUID.init(uuidString:))
        events = defaults.stringArray(forKey: Self.recentEventsKey) ?? []
        super.init()
        // Identificatore stabile: consente a iOS di consegnare callback BLE dopo una sospensione
        // o un riavvio del processo operato dal sistema (non dopo force-quit intenzionale).
        central = CBCentralManager(delegate: self, queue: .main, options: [
            CBCentralManagerOptionRestoreIdentifierKey: Self.restorationIdentifier
        ])
        log("Controller BLE avviato; auto-connessione \(autoConnect ? "attiva" : "disattivata")")
    }

    /// Ricerca manuale: nel foreground nessun filtro, per non perdere advertising col solo nome.
    func scan() {
        guard central.state == .poweredOn else {
            log("Bluetooth non disponibile: \(central.state.rawValue)")
            return
        }
        guard !isConnected else { return }
        manualDisconnect = false
        beginScanning()
    }

    func stopScan() {
        central.stopScan()
        isScanning = false
        if !isConnected && connectingPeripheralID == nil { connectionStatus = "Ricerca interrotta" }
        log("Scansione fermata")
    }

    func connect(to device: FoundDevice) {
        guard let peripheral = peripherals[device.id] else { return }
        manualDisconnect = false
        requestConnection(to: peripheral)
    }

    /// Sospensione volontaria per la sessione corrente (riprende con una ricerca esplicita o al riavvio).
    func disconnect() {
        manualDisconnect = true
        central.stopScan()
        isScanning = false
        if let peripheral = connectedPeripheral {
            central.cancelPeripheralConnection(peripheral)
            log("Disconnessione manuale richiesta")
        } else {
            connectingPeripheralID = nil
            connectionStatus = "Connessione sospesa"
        }
    }

    func forgetDevice() {
        guard let old = knownPeripheralID else { return }
        defaults.removeObject(forKey: Self.peripheralIDKey)
        knownPeripheralID = nil
        log("B21S memorizzate dimenticate: \(old.uuidString)")
        if let peripheral = connectedPeripheral {
            // Aspetta il callback didDisconnect prima di cercare un altro dispositivo.
            manualDisconnect = true
            central.cancelPeripheralConnection(peripheral)
        } else if central.state == .poweredOn {
            manualDisconnect = false
            connectingPeripheralID = nil
            beginScanning()
        }
    }

    func requestStatus() {
        send([0xAA, 0x76, 0x01, 0x00, 0x21], reason: "Richiesta stato EQ")
    }

    /// Comando documentato dall'APK Sanag (sendGetBatteryCMD); checksum AA+33+01=DE.
    /// Valore validato dall'osservazione di una notifica A5 33 01 4E 27 (78%).
    func requestBattery() {
        guard isReady else { return }
        send([0xAA, 0x33, 0x01, 0x00, 0xDE], reason: "Richiesta batteria B21S")
    }

    func selectPreset(_ preset: Int) {
        guard (0...5).contains(preset), isReady else { return }
        savedPreset = preset
        defaults.set(preset, forKey: Self.savedPresetKey)
        sendPreset(preset, restored: false)
    }

    func applicationDidBecomeActive() {
        if central?.state == .poweredOn, autoConnect, !manualDisconnect, !isConnected {
            resumeConnection()
        }
    }

    func applicationDidEnterBackground() {
        // La scansione senza servizi non è idonea al normale comportamento CoreBluetooth
        // in background. Se non abbiamo un connect pendente, ripartiamo con il filtro A0FA.
        if central?.state == .poweredOn, autoConnect, !manualDisconnect,
           !isConnected, connectingPeripheralID == nil {
            beginScanning()
        }
    }

    private func resumeConnection() {
        guard autoConnect && !manualDisconnect && central.state == .poweredOn else { return }
        if let peripheral = connectedPeripheral {
            if peripheral.state == .connected {
                if !isReady { prepareConnectedPeripheral(peripheral) }
            } else if connectingPeripheralID == nil {
                requestConnection(to: peripheral)
            }
            return
        }
        if let id = knownPeripheralID,
           let peripheral = central.retrievePeripherals(withIdentifiers: [id]).first {
            log("B21S note recuperate da CoreBluetooth")
            requestConnection(to: peripheral)
            return
        }
        // Fallback: prima apertura/upgrade dalla v0.1 senza identificatore salvato.
        if !isScanning { beginScanning() }
    }

    private func beginScanning() {
        guard central.state == .poweredOn, !isConnected else { return }
        central.stopScan()
        foundDevices.removeAll()
        // Senza filtro nel foreground; quando iOS sospende l'app serve uno UUID noto.
        let inBackground = UIApplication.shared.applicationState == .background
        let services: [CBUUID]? = inBackground ? [advertisedUUID] : nil
        central.scanForPeripherals(withServices: services,
                                   options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        isScanning = true
        connectionStatus = inBackground ? "Ricerca B21S in background…" : "Ricerca B21S in corso…"
        log(inBackground ? "Ricerca BLE filtrata A0FA in background" : "Ricerca BLE avviata")
    }

    private func requestConnection(to peripheral: CBPeripheral) {
        guard central.state == .poweredOn, !manualDisconnect else { return }
        if connectingPeripheralID == peripheral.identifier { return }
        if connectedPeripheral?.identifier == peripheral.identifier && peripheral.state == .connected {
            if !isReady { prepareConnectedPeripheral(peripheral) }
            return
        }
        central.stopScan()
        isScanning = false
        peripherals[peripheral.identifier] = peripheral
        connectedPeripheral = peripheral
        connectingPeripheralID = peripheral.identifier
        peripheral.delegate = self
        connectionStatus = "Connessione automatica alle B21S…"
        // La richiesta resta pendente anche se il dispositivo è spento/non raggiungibile.
        central.connect(peripheral, options: nil)
        log("Connessione richiesta: \(peripheral.name ?? peripheral.identifier.uuidString)")
    }

    private func prepareConnectedPeripheral(_ peripheral: CBPeripheral) {
        connectingPeripheralID = nil
        connectedPeripheral = peripheral
        peripheral.delegate = self
        isConnected = true
        isReady = false
        writeCharacteristic = nil
        notifyCharacteristic = nil
        connectionStatus = "Connesso · ricerca servizio EQ…"
        peripheral.discoverServices([serviceUUID])
    }

    private func sendPreset(_ preset: Int, restored: Bool) {
        let checksum = UInt8(truncatingIfNeeded: 0xAA + 0x39 + 0x01 + preset)
        send([0xAA, 0x39, 0x01, UInt8(preset), checksum],
             reason: restored ? "Ripristino preset \(preset)" : "Impostazione preset \(preset)")
    }

    private func send(_ packet: [UInt8], reason: String) {
        guard let peripheral = connectedPeripheral, let characteristic = writeCharacteristic else {
            log("Comando non inviato: caratteristica FAA1 assente")
            return
        }
        let type: CBCharacteristicWriteType
        if characteristic.properties.contains(.writeWithoutResponse) {
            type = .withoutResponse
        } else if characteristic.properties.contains(.write) {
            type = .withResponse
        } else {
            log("FAA1 non supporta la scrittura")
            return
        }
        peripheral.writeValue(Data(packet), for: characteristic, type: type)
        log("\(reason) → \(Self.hex(packet))")
    }

    private func handleResponse(_ data: Data) {
        let bytes = [UInt8](data)
        log("RX ← \(Self.hex(bytes))")
        guard bytes.count == 5, bytes[0] == 0xA5, bytes[2] == 0x01 else { return }
        let checksum = UInt8(truncatingIfNeeded: bytes.prefix(4).reduce(0) { $0 + Int($1) })
        guard checksum == bytes[4] else { log("Checksum risposta non valido"); return }
        if bytes[1] == 0x33 {
            // La famiglia 0x33 è interrogata dall'app Sanag come batteria.
            // Accettiamo solo una percentuale 0...100 per evitare valori ingannevoli.
            let level = Int(bytes[3])
            if (0...100).contains(level) {
                if batteryLevel != level { log("Batteria B21S: \(level)%") }
                batteryLevel = level
            } else {
                log("Risposta batteria inattesa: \(level)")
            }
            return
        }
        guard (bytes[1] == 0x39 || bytes[1] == 0x76), (0...5).contains(Int(bytes[3])) else { return }
        actualPreset = Int(bytes[3])
        if bytes[1] == 0x39, shortcutPending?.preset == Int(bytes[3]) {
            finishShortcut(true)
        }
        log(bytes[1] == 0x39 ? "EQ confermato: \(bytes[3])" : "Stato EQ: \(bytes[3])")
    }

    private func becameReady() {
        guard !isReady, let peripheral = connectedPeripheral else { return }
        isReady = true
        isConnected = true
        connectionStatus = "Connesso · EQ pronto"
        if knownPeripheralID != peripheral.identifier {
            knownPeripheralID = peripheral.identifier
            defaults.set(peripheral.identifier.uuidString, forKey: Self.peripheralIDKey)
            log("Identificativo B21S salvato per riconnessione automatica")
        }
        log("Servizio FAA0 e caratteristiche FAA1/FAA2 disponibili")
        requestStatus()
        requestBattery()
        if let preset = shortcutPending?.preset {
            // L'automazione ha precedenza e invia il comando una sola volta.
            sendPreset(preset, restored: true)
        } else if autoRestore, let preset = savedPreset, (0...5).contains(preset) {
            sendPreset(preset, restored: true)
        }
    }

    private func resetConnection() {
        isConnected = false
        isReady = false
        actualPreset = nil
        batteryLevel = nil
        writeCharacteristic = nil
        notifyCharacteristic = nil
        connectedPeripheral = nil
        connectingPeripheralID = nil
        connectionStatus = "Non connesso"
    }

    /// Cancella solo la cronologia locale, senza cambiare EQ o stato Bluetooth.
    func clearEventLog() {
        events.removeAll()
        defaults.removeObject(forKey: Self.recentEventsKey)
    }

    private func log(_ message: String) {
        let timestamp = Date().formatted(date: .omitted, time: .standard)
        events.insert("\(timestamp)  \(message)", at: 0)
        if events.count > 50 { events.removeLast(events.count - 50) }
        defaults.set(events, forKey: Self.recentEventsKey)
    }

    private static func hex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}

extension B21SBluetoothManager: CBCentralManagerDelegate {
    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        restoredBySystem = true
        log("Ripristino CoreBluetooth avviato dal sistema")
        guard let restored = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] else { return }
        for peripheral in restored {
            peripheral.delegate = self
            peripherals[peripheral.identifier] = peripheral
        }
        guard let peripheral = restored.first(where: { $0.identifier == knownPeripheralID }) ?? restored.first else { return }
        connectedPeripheral = peripheral
        if peripheral.state == .connected {
            prepareConnectedPeripheral(peripheral)
        } else if autoConnect && !manualDisconnect {
            requestConnection(to: peripheral)
        }
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            bluetoothStatus = "Bluetooth attivo"
            if autoConnect && !manualDisconnect { resumeConnection() }
        case .poweredOff:
            bluetoothStatus = "Bluetooth disattivato"
            resetConnection()
            isScanning = false
        case .unauthorized:
            bluetoothStatus = "Permesso Bluetooth negato"
            resetConnection()
        case .unsupported:
            bluetoothStatus = "Bluetooth LE non supportato"
            resetConnection()
        default:
            bluetoothStatus = "Bluetooth non disponibile"
        }
        log(bluetoothStatus + (restoredBySystem ? " (state restoration attiva)" : ""))
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any],
                        rssi RSSI: NSNumber) {
        let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
            ?? peripheral.name ?? "Dispositivo senza nome"
        let advertised = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]) ?? []
        let likelyB21S = name.localizedCaseInsensitiveContains("B21S") ||
            (name.localizedCaseInsensitiveContains("sanag") && advertised.contains(advertisedUUID)) ||
            advertised.contains(advertisedUUID)
        guard likelyB21S else { return }
        peripherals[peripheral.identifier] = peripheral
        if let idx = foundDevices.firstIndex(where: { $0.id == peripheral.identifier }) {
            foundDevices[idx] = FoundDevice(id: peripheral.identifier, name: name, rssi: RSSI.intValue)
        } else {
            foundDevices.append(FoundDevice(id: peripheral.identifier, name: name, rssi: RSSI.intValue))
            log("Trovato: \(name) (RSSI \(RSSI) dBm)")
        }
        // Alla prima connessione v0.2 può non avere un UUID salvato (migrazione da v0.1).
        if autoConnect && !manualDisconnect && connectedPeripheral == nil &&
            (knownPeripheralID == nil || knownPeripheralID == peripheral.identifier) {
            requestConnection(to: peripheral)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        log("BLE connesso: \(peripheral.name ?? "B21S")")
        prepareConnectedPeripheral(peripheral)
    }

    func centralManager(_ central: CBCentralManager,
                        didFailToConnect peripheral: CBPeripheral,
                        error: Error?) {
        log("Connessione fallita: \(error?.localizedDescription ?? "causa sconosciuta")")
        resetConnection()
        if autoConnect && !manualDisconnect && central.state == .poweredOn {
            beginScanning()
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {
        log("Disconnesso: \(error?.localizedDescription ?? "nessun errore")")
        resetConnection()
        if autoConnect && !manualDisconnect && central.state == .poweredOn {
            // Manteniamo pendente la richiesta verso lo stesso UUID per il prossimo power-on.
            requestConnection(to: peripheral)
        } else if manualDisconnect {
            connectionStatus = "Disconnesso manualmente"
            if knownPeripheralID == nil, autoConnect, central.state == .poweredOn {
                manualDisconnect = false
                beginScanning()
            }
        }
    }
}

extension B21SBluetoothManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error { log("Errore servizi: \(error.localizedDescription)"); return }
        guard let service = peripheral.services?.first(where: { $0.uuid == serviceUUID }) else {
            log("Servizio FAA0 non trovato")
            connectionStatus = "Servizio EQ non trovato"
            return
        }
        peripheral.discoverCharacteristics([writeUUID, notifyUUID], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        if let error { log("Errore caratteristiche: \(error.localizedDescription)"); return }
        writeCharacteristic = service.characteristics?.first(where: { $0.uuid == writeUUID })
        notifyCharacteristic = service.characteristics?.first(where: { $0.uuid == notifyUUID })
        guard writeCharacteristic != nil else {
            log("Caratteristica FAA1 non trovata")
            connectionStatus = "Controllo EQ non disponibile"
            return
        }
        if let notification = notifyCharacteristic,
           notification.properties.contains(.notify) {
            peripheral.setNotifyValue(true, for: notification)
        } else {
            log("FAA2 non supporta notify; controllo senza conferme")
            becameReady()
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateNotificationStateFor characteristic: CBCharacteristic,
                    error: Error?) {
        if let error { log("Notifiche FAA2 non abilitate: \(error.localizedDescription)") }
        else { log("Notifiche FAA2: \(characteristic.isNotifying ? "attive" : "non attive")") }
        becameReady()
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        if let error { log("Errore RX: \(error.localizedDescription)"); return }
        if characteristic.uuid == notifyUUID, let data = characteristic.value { handleResponse(data) }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didWriteValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        if let error { log("Errore invio EQ: \(error.localizedDescription)") }
    }
}
