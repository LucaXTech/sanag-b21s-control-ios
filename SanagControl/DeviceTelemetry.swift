import Foundation
import Combine

/// One HTTPS contribution channel for supported-headset observations and explicit
/// support requests. Automatic observations require opt-in; manual requests are
/// always confirmed by a separate, clearly labeled user action.
@MainActor
final class DeviceTelemetry: ObservableObject {
    static let shared = DeviceTelemetry()

    private enum Keys {
        static let decided = "B21S.Telemetry.ConsentDecided"
        static let enabled = "B21S.Telemetry.Enabled"
        static let legacySuccess = "B21S.Telemetry.LastSuccessfulUpload"
        static let prefix = "HeadphoneContributions.LastSuccess."
    }

    @Published private(set) var hasDecided: Bool
    @Published var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: Keys.enabled)
            if !hasDecided {
                hasDecided = true
                defaults.set(true, forKey: Keys.decided)
            }
            if !isEnabled { automaticTask?.cancel() }
            if isEnabled && !oldValue {
                B21SBluetoothManager.shared.reportTechnicalInfoIfNeeded()
            }
        }
    }

    @Published private(set) var isSubmittingSupportRequest = false
    @Published private(set) var supportResult: String?

    var isConfigured: Bool { endpoint != nil }

    private var endpoint: URL? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "DeviceReportURL") as? String,
              let url = URL(string: raw),
              url.scheme?.lowercased() == "https", url.host != nil,
              url.path == "/v1/report" else { return nil }
        return url
    }

    private let defaults = UserDefaults.standard
    private let minimumInterval: TimeInterval = 30 * 24 * 60 * 60
    private var automaticTask: Task<Void, Never>?
    private var manualTask: Task<Void, Never>?

    private init() {
        hasDecided = UserDefaults.standard.bool(forKey: Keys.decided)
        isEnabled = UserDefaults.standard.bool(forKey: Keys.enabled)
    }

    func setConsent(_ allowed: Bool) {
        hasDecided = true
        defaults.set(true, forKey: Keys.decided)
        isEnabled = allowed
    }

    private func successKey(kind: String, model: String) -> String {
        // Keep per-model throttling local. Never transmit this local key.
        Keys.prefix + kind + "." + model.lowercased()
    }

    private func hasRecentSuccess(kind: String, model: String) -> Bool {
        if let stored = defaults.object(forKey: successKey(kind: kind, model: model)) as? Date,
           Date().timeIntervalSince(stored) < minimumInterval { return true }
        if kind == "observation" && model == "sanag B21S",
           let legacy = defaults.object(forKey: Keys.legacySuccess) as? Date,
           Date().timeIntervalSince(legacy) < minimumInterval { return true }
        return false
    }

    private func rememberSuccess(kind: String, model: String) {
        defaults.set(Date(), forKey: successKey(kind: kind, model: model))
    }

    private func validModel(_ input: String) -> String? {
        let normalized = input.precomposedStringWithCompatibilityMapping
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard (3...80).contains(normalized.count),
              !normalized.contains(where: { $0.isNewline }),
              normalized.unicodeScalars.allSatisfy({
                  CharacterSet.alphanumerics.contains($0) ||
                  CharacterSet(charactersIn: " ._()+&/-").contains($0)
              }) else { return nil }
        return normalized
    }

    private func cleanUUIDs(_ input: [String]) -> [String]? {
        guard input.count <= 32 else { return nil }
        let normalized = Array(Set(input.map { $0.uppercased() })).sorted()
        let pattern = #"^(?:[0-9A-F]{4}|[0-9A-F]{8}|[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12})$"#
        let matcher = try? NSRegularExpression(pattern: pattern)
        guard normalized.allSatisfy({ text in
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            return matcher?.firstMatch(in: text, range: range) != nil
        }) else { return nil }
        return normalized
    }

    private func makeReport(kind: String, model: String, bleStatus: String,
                            services: [String], characteristics: [String]) -> ContributionReport? {
        guard let model = validModel(model),
              let services = cleanUUIDs(services),
              let characteristics = cleanUUIDs(characteristics) else { return nil }
        guard bleStatus == "observed" || (services.isEmpty && characteristics.isEmpty) else { return nil }
        guard kind == "support_request" ||
              (kind == "observation" && bleStatus == "observed" &&
               !services.isEmpty && !characteristics.isEmpty) else { return nil }
        return ContributionReport(
            schemaVersion: 2,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.5.0",
            kind: kind, model: model, bleStatus: bleStatus,
            services: services, characteristics: characteristics
        )
    }

    func submitIfNeeded(model: String, services: [String], characteristics: [String]) {
        guard hasDecided, isEnabled, automaticTask == nil, let endpoint else { return }
        guard let report = makeReport(kind: "observation", model: model,
                                      bleStatus: "observed",
                                      services: services, characteristics: characteristics),
              !hasRecentSuccess(kind: "observation", model: report.model) else { return }
        automaticTask = Task {
            defer { automaticTask = nil }
            if await send(report, to: endpoint), isEnabled, !Task.isCancelled {
                rememberSuccess(kind: "observation", model: report.model)
            }
        }
    }

    /// Invoked ONLY after the user confirms exactly what will be sent.
    /// It works without a GitHub account or global automatic-sharing consent.
    func submitSupportRequest(model: String, bleStatus: String,
                              services: [String], characteristics: [String]) {
        guard !isSubmittingSupportRequest else { return }
        supportResult = nil
        guard let endpoint else {
            supportResult = "Support requests are unavailable in this build."
            return
        }
        guard let report = makeReport(kind: "support_request", model: model,
                                      bleStatus: bleStatus, services: services,
                                      characteristics: characteristics) else {
            supportResult = "Please enter a valid headphone brand and model."
            return
        }
        guard !hasRecentSuccess(kind: "support_request", model: report.model) else {
            supportResult = "You already requested support for this model in the last 30 days."
            return
        }
        isSubmittingSupportRequest = true
        manualTask = Task {
            defer {
                isSubmittingSupportRequest = false
                manualTask = nil
            }
            if await send(report, to: endpoint) {
                rememberSuccess(kind: "support_request", model: report.model)
                supportResult = "Request received. Thanks for helping us improve compatibility!"
            } else {
                supportResult = "Could not send the request. Check your connection and try again."
            }
        }
    }

    private func send(_ report: ContributionReport, to url: URL) async -> Bool {
        guard let payload = try? JSONEncoder().encode(report) else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = payload
        request.timeoutInterval = 12
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return !Task.isCancelled && (response as? HTTPURLResponse)?.statusCode == 204
        } catch {
            return false
        }
    }
}

private struct ContributionReport: Encodable {
    let schemaVersion: Int
    let appVersion: String
    let kind: String
    let model: String
    let bleStatus: String
    let services: [String]
    let characteristics: [String]
}
