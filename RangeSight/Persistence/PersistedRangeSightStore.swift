public enum PersistenceSchema {
    public static let currentVersion = 1
}

public struct PersistedRangeSightStore: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public var firearmProfiles: [FirearmProfile]
    public var targetDefinitions: [TargetDefinition]
    public var rangeSessions: [RangeSession]
    public var rangeStrings: [RangeString]
    public var shots: [Shot]
    public var detectionDiagnostics: [DetectionDiagnostic]
    public var sessionAssets: [SessionAsset]

    public init(
        schemaVersion: Int = PersistenceSchema.currentVersion,
        firearmProfiles: [FirearmProfile] = [],
        targetDefinitions: [TargetDefinition] = [],
        rangeSessions: [RangeSession] = [],
        rangeStrings: [RangeString] = [],
        shots: [Shot] = [],
        detectionDiagnostics: [DetectionDiagnostic] = [],
        sessionAssets: [SessionAsset] = []
    ) {
        self.schemaVersion = schemaVersion
        self.firearmProfiles = firearmProfiles
        self.targetDefinitions = targetDefinitions
        self.rangeSessions = rangeSessions
        self.rangeStrings = rangeStrings
        self.shots = shots
        self.detectionDiagnostics = detectionDiagnostics
        self.sessionAssets = sessionAssets
    }
}

public enum PersistenceError: Error, Equatable {
    case unsupportedSchemaVersion(Int)
    case missingRangeSession(RangeSessionID)
    case missingRangeString(RangeStringID)
}
