public enum PersistenceSchema {
    public static let currentVersion = 2
}

public struct PersistedRangeSightStore: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public var firearmProfiles: [FirearmProfile]
    public var targetDefinitions: [TargetDefinition]
    public var rangeSessions: [RangeSession]
    public var rangeStrings: [RangeString]
    public var shots: [Shot]
    public var impactCorrectionHistory: [AcceptedImpact]
    public var detectionDiagnostics: [DetectionDiagnostic]
    public var sessionAssets: [SessionAsset]

    public init(
        schemaVersion: Int = PersistenceSchema.currentVersion,
        firearmProfiles: [FirearmProfile] = [],
        targetDefinitions: [TargetDefinition] = [],
        rangeSessions: [RangeSession] = [],
        rangeStrings: [RangeString] = [],
        shots: [Shot] = [],
        impactCorrectionHistory: [AcceptedImpact] = [],
        detectionDiagnostics: [DetectionDiagnostic] = [],
        sessionAssets: [SessionAsset] = []
    ) {
        self.schemaVersion = schemaVersion
        self.firearmProfiles = firearmProfiles
        self.targetDefinitions = targetDefinitions
        self.rangeSessions = rangeSessions
        self.rangeStrings = rangeStrings
        self.shots = shots
        self.impactCorrectionHistory = impactCorrectionHistory
        self.detectionDiagnostics = detectionDiagnostics
        self.sessionAssets = sessionAssets
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case firearmProfiles
        case targetDefinitions
        case rangeSessions
        case rangeStrings
        case shots
        case impactCorrectionHistory
        case detectionDiagnostics
        case sessionAssets
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        firearmProfiles = try container.decodeIfPresent([FirearmProfile].self, forKey: .firearmProfiles) ?? []
        targetDefinitions = try container.decodeIfPresent([TargetDefinition].self, forKey: .targetDefinitions) ?? []
        rangeSessions = try container.decodeIfPresent([RangeSession].self, forKey: .rangeSessions) ?? []
        rangeStrings = try container.decodeIfPresent([RangeString].self, forKey: .rangeStrings) ?? []
        shots = try container.decodeIfPresent([Shot].self, forKey: .shots) ?? []
        impactCorrectionHistory = try container.decodeIfPresent([AcceptedImpact].self, forKey: .impactCorrectionHistory) ?? []
        detectionDiagnostics = try container.decodeIfPresent([DetectionDiagnostic].self, forKey: .detectionDiagnostics) ?? []
        sessionAssets = try container.decodeIfPresent([SessionAsset].self, forKey: .sessionAssets) ?? []
    }
}

public enum PersistenceError: Error, Equatable {
    case unsupportedSchemaVersion(Int)
    case missingRangeSession(RangeSessionID)
    case missingRangeString(RangeStringID)
}
