import Foundation

/// Model-specific, community-sourced BLE protocol descriptions.
/// Protocol facts are independently encoded here; no third-party source code is copied.
/// No family is promoted to "verified on iOS" until tested with physical headphones.
enum ExperimentalHeadset: String, CaseIterable, Identifiable {
    case tozoT10 = "TOZO T10"
    case marshallMotifII = "Marshall Motif II ANC"

    var id: String { rawValue }

    static func match(advertisedName: String) -> ExperimentalHeadset? {
        let normalized = advertisedName.uppercased()
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
        if normalized.contains("TOZO") && normalized.contains("T10") { return .tozoT10 }
        if normalized.contains("MOTIF II") && normalized.contains("ANC") { return .marshallMotifII }
        return nil
    }

    var serviceUUID: String {
        switch self {
        case .tozoT10: return "B610"
        case .marshallMotifII: return "FA302D24-D775-4343-B9ED-8CC68ACE3284"
        }
    }

    var writeUUID: String {
        switch self {
        case .tozoT10: return "B611"
        case .marshallMotifII: return "00000013-1337-1DEA-FEED-C0FFEE70C0DE"
        }
    }

    var notifyUUID: String? {
        switch self {
        case .tozoT10: return "B612"
        case .marshallMotifII: return nil
        }
    }

    var supportingSource: String {
        switch self {
        case .tozoT10: return "https://github.com/GabriWar/tozo-control"
        case .marshallMotifII: return "https://github.com/c0ffee-audio/marshall-protocol"
        }
    }
}

/// Wire encodings sourced from published interoperability research. Do not send to
/// unknown peripherals or infer compatibility from a matching UUID alone.
enum TOZOT10Commands {
    static func get(_ parameter: UInt8) -> [UInt8] {
        [0x00, parameter, 0x00, 0x00]
    }

    static let battery = get(0x02)
    static let gameModeStatus = get(0x06)
    static let equalizerStatus = get(0x0B)

    static func set(_ parameter: UInt8, payload: [UInt8]) -> [UInt8]? {
        guard !payload.isEmpty, payload.count <= 255 else { return nil }
        return [0x10, parameter, UInt8(payload.count)] + payload +
            [UInt8(truncatingIfNeeded: payload.reduce(0) { $0 + Int($1) })]
    }

    static func gameMode(_ enabled: Bool) -> [UInt8] {
        // Known T10 one-byte payload and additive checksum.
        set(0x06, payload: [enabled ? 0x01 : 0x00])!
    }

    static func equalizer(gains: [UInt8], qFactors: [UInt8]) -> [UInt8]? {
        guard gains.count == 10, qFactors.count == 10,
              gains.allSatisfy({ $0 <= 50 }) else { return nil }
        return set(0x0B, payload: gains + qFactors)
    }

    /// The public protocol reports battery bytes at offsets 3 and 4.
    /// Call only for a response received after a battery request.
    static func batteryLevels(_ response: [UInt8]) -> (left: Int, right: Int)? {
        guard response.count >= 5,
              response[3] <= 100, response[4] <= 100 else { return nil }
        return (Int(response[3]), Int(response[4]))
    }
}

enum MarshallMotifIICommands {
    static let ancUUID = "00000013-1337-1DEA-FEED-C0FFEE70C0DE"
    static let equalizerUUID = "00000017-1337-1DEA-FEED-C0FFEE70C0DE"

    enum ANC: UInt8, CaseIterable {
        case off = 0
        case noiseCancellation = 1
        case transparency = 2
    }

    enum EQ: UInt8, CaseIterable {
        case flat = 0
        case rock = 2
        case metal = 3
        case pop = 4
        case hipHop = 5
        case electronic = 6
        case jazz = 7
        case bassBoost = 8
        case midBoost = 9
        case trebleBoost = 10
    }

    static func anc(_ value: ANC) -> [UInt8] { [value.rawValue] }

    /// Assign a known preset to slot zero, then activate it.
    /// Must be sent in order, requiring a successful first write.
    static func equalizer(_ preset: EQ) -> [[UInt8]] {
        [[0x01, 0x00, preset.rawValue], [0x00, 0x00]]
    }
}
