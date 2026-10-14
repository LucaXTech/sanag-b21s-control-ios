import Foundation
import Combine

/// Opt-in compatibility reporting. No report is ever sent before consent.
/// The application intentionally never includes device identifiers, names
/// discovered over Bluetooth, exact battery level, raw packets, or event logs.
@MainActor
final class DeviceTelemetry: ObservableObject {
    static let shared = DeviceTelemetry()

    private enum Keys {
        static let decided = "B21S.Telemetry.ConsentDecided"
        static let enabled = "B21S.Telemetry.Enabled"
        static let lastSuccess = "B21S.Telemetry.LastSuccessfulUpload"
    }

    @Published private(set) var hasDecided: Bool
    @Published var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: Keys.enabled)
            if !hasDecided {
                hasDecided = true
                defaults.set(true, forKey: Keys.decided)
            }
            if !isEnabled { pendingUpload?.cancel() }
            if isEnabled && !oldValue {
                B21SBluetoothManager.shared.reportTechnicalInfoIfNeeded()
            }
        }
    }

    var isConfigured: Bool {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "DeviceReportURL") as? String,
              let url = URL(string: raw),
              url.scheme?.lowercased() == "https",
              url.host != nil else { return false }
        return true
    }

    private let defaults = UserDefaults.standard
    private var uploadInProgress = false
    private var pendingUpload: Task<Void, Never>?
    private let minimumInterval: TimeInterval = 30 * 24 * 60 * 60

    private init() {
        hasDecided = UserDefaults.standard.bool(forKey: Keys.decided)
        isEnabled = UserDefaults.standard.bool(forKey: Keys.enabled)
    }

    func setConsent(_ allowed: Bool) {
        hasDecided = true
        defaults.set(true, forKey: Keys.decided)
        isEnabled = allowed
    }

    func submitIfNeeded(model: String, services: [String], characteristics: [String]) {
        guard hasDecided, isEnabled, !uploadInProgress else { return }
        guard !services.isEmpty, !characteristics.isEmpty else { return }
        guard let rawURL = Bundle.main.object(forInfoDictionaryKey: "DeviceReportURL") as? String,
              let endpoint = URL(string: rawURL),
              endpoint.scheme?.lowercased() == "https",
              endpoint.host != nil else { return }

        if let previous = defaults.object(forKey: Keys.lastSuccess) as? Date,
           Date().timeIntervalSince(previous) < minimumInterval {
            return
        }

        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let report = CompatibilityReport(
            schemaVersion: 1,
            appVersion: appVersion,
            model: model,
            services: Array(Set(services.map { $0.uppercased() })).sorted(),
            characteristics: Array(Set(characteristics.map { $0.uppercased() })).sorted()
        )
        guard let body = try? JSONEncoder().encode(report) else { return }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.timeoutInterval = 12
        uploadInProgress = true

        pendingUpload = Task {
            defer {
                uploadInProgress = false
                pendingUpload = nil
            }
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse,
                      (200..<300).contains(http.statusCode),
                      isEnabled else { return }
                defaults.set(Date(), forKey: Keys.lastSuccess)
            } catch {
                // No retries in a loop. The next eligible connection can retry.
            }
        }
    }
}

private struct CompatibilityReport: Encodable {
    let schemaVersion: Int
    let appVersion: String
    let model: String
    let services: [String]
    let characteristics: [String]
}
