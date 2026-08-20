import Foundation

public enum DomainSchema {
    public static let currentVersion = 1
}

public struct FirearmProfileID: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String
    public init(_ rawValue: String) throws {
        guard !rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DomainValidationError.invalidIdentifier("FirearmProfileID")
        }
        self.rawValue = rawValue
    }
    public init(rawValue: String) {
        precondition(!rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        self.rawValue = rawValue
    }
}

public struct TargetDefinitionID: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String
    public init(_ rawValue: String) throws {
        guard !rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DomainValidationError.invalidIdentifier("TargetDefinitionID")
        }
        self.rawValue = rawValue
    }
    public init(rawValue: String) {
        precondition(!rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        self.rawValue = rawValue
    }
}

public struct RangeSessionID: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String
    public init(_ rawValue: String) throws {
        guard !rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DomainValidationError.invalidIdentifier("RangeSessionID")
        }
        self.rawValue = rawValue
    }
    public init(rawValue: String) {
        precondition(!rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        self.rawValue = rawValue
    }
}

public struct RangeStringID: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String
    public init(_ rawValue: String) throws {
        guard !rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DomainValidationError.invalidIdentifier("RangeStringID")
        }
        self.rawValue = rawValue
    }
    public init(rawValue: String) {
        precondition(!rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        self.rawValue = rawValue
    }
}

public struct ShotID: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String
    public init(_ rawValue: String) throws {
        guard !rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DomainValidationError.invalidIdentifier("ShotID")
        }
        self.rawValue = rawValue
    }
    public init(rawValue: String) {
        precondition(!rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        self.rawValue = rawValue
    }
}

public struct SessionAssetID: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) {
        precondition(!rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        self.rawValue = rawValue
    }
}

public enum DistanceUnit: String, Codable, Sendable {
    case yard
    case meter
}

public enum LengthUnit: String, Codable, Sendable {
    case inch
    case millimeter
}

public enum FirearmCategory: String, Codable, Sendable {
    case handgun
    case rimfireRifle
    case centerfireRifle
    case other
}

public enum TargetSupportedMode: String, Codable, Sendable {
    case genericImpact
    case groupMetrics
    case scoring
}

public enum ShotSource: String, Codable, CaseIterable, Sendable {
    case autoConfirmed = "auto_confirmed"
    case userConfirmed = "user_confirmed"
    case manualAdded = "manual_added"
    case corrected
}

public enum AssetRetentionPolicy: String, Codable, Sendable {
    case session
    case debugOptIn
    case discardAfterReview
}

public struct NormalizedTargetCoordinate: Codable, Equatable, Sendable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) throws {
        guard (0...1).contains(x), (0...1).contains(y) else {
            throw DomainValidationError.coordinateOutOfBounds
        }
        self.x = x
        self.y = y
    }
}

public struct PhysicalPoint: Codable, Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let unit: LengthUnit
}

public struct PhysicalDimensions: Codable, Equatable, Sendable {
    public let width: Double
    public let height: Double
    public let unit: LengthUnit

    public init(width: Double, height: Double, unit: LengthUnit) throws {
        guard width > 0, height > 0 else {
            throw DomainValidationError.nonPositiveMeasurement
        }
        self.width = width
        self.height = height
        self.unit = unit
    }
}

public struct AimPoint: Codable, Equatable, Sendable {
    public let id: String
    public let label: String
    public let normalized: NormalizedTargetCoordinate
}

public struct ScoringZoneDefinition: Codable, Equatable, Sendable {
    public let id: String
    public let label: String
    public let scoreValue: Double
    public let reviewMargin: Double?
}

public struct FirearmProfile: Codable, Equatable, Sendable {
    public let id: FirearmProfileID
    public let nickname: String
    public let category: FirearmCategory
    public let caliber: String?
    public let notes: String?
    public let createdAt: Date
}

public struct TargetDefinition: Codable, Equatable, Sendable {
    public let id: TargetDefinitionID
    public let name: String
    public let revision: Int
    public let physicalDimensions: PhysicalDimensions?
    public let scoringZones: [ScoringZoneDefinition]
    public let aimPoints: [AimPoint]
    public let supportedModes: [TargetSupportedMode]
}

public struct DeviceMetadata: Codable, Equatable, Sendable {
    public enum Platform: String, Codable, Sendable {
        case iOS
        case unknown
    }

    public let platform: Platform
    public let modelName: String?
    public let osVersion: String?
    public let appVersion: String?
}

public struct RangeSession: Codable, Equatable, Sendable {
    public let id: RangeSessionID
    public let startedAt: Date
    public let endedAt: Date?
    public let distance: Double
    public let distanceUnit: DistanceUnit
    public let firearmID: FirearmProfileID?
    public let targetDefinitionID: TargetDefinitionID
    public let device: DeviceMetadata
}

public struct RangeString: Codable, Equatable, Sendable {
    public let id: RangeStringID
    public let sessionID: RangeSessionID
    public let index: Int
    public let baselineAssetID: SessionAssetID?
    public let startedAt: Date
    public let endedAt: Date?
}

public struct ShotScore: Codable, Equatable, Sendable {
    public let value: Double
    public let targetDefinitionRevision: Int
    public let reviewable: Bool
}

public struct Shot: Codable, Equatable, Sendable {
    public let id: ShotID
    public let stringID: RangeStringID
    public let ordinal: Int
    public let timestamp: Date
    public let normalized: NormalizedTargetCoordinate
    public let physical: PhysicalPoint?
    public let confidence: Double
    public let source: ShotSource
    public let corrected: Bool
    public let originalNormalized: NormalizedTargetCoordinate?
    public let score: ShotScore?

    public init(
        id: ShotID,
        stringID: RangeStringID,
        ordinal: Int,
        timestamp: Date,
        normalized: NormalizedTargetCoordinate,
        physical: PhysicalPoint? = nil,
        confidence: Double,
        source: ShotSource,
        corrected: Bool,
        originalNormalized: NormalizedTargetCoordinate? = nil,
        score: ShotScore? = nil
    ) throws {
        guard ordinal > 0 else { throw DomainValidationError.nonPositiveOrdinal }
        guard (0...1).contains(confidence) else { throw DomainValidationError.confidenceOutOfBounds }
        self.id = id
        self.stringID = stringID
        self.ordinal = ordinal
        self.timestamp = timestamp
        self.normalized = normalized
        self.physical = physical
        self.confidence = confidence
        self.source = source
        self.corrected = corrected
        self.originalNormalized = originalNormalized
        self.score = score
    }
}

public struct DetectionDiagnostic: Codable, Equatable, Sendable {
    public let id: String
    public let shotID: ShotID?
    public let candidateID: String?
    public let registrationError: Double?
    public let qualityMetrics: [String: Double]
    public let detectorVersion: String
}

public struct SessionAsset: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case baselineImage
        case targetImage
        case debugSnapshot
    }

    public let id: SessionAssetID
    public let sessionID: RangeSessionID
    public let stringID: RangeStringID?
    public let uri: String
    public let kind: Kind
    public let retentionPolicy: AssetRetentionPolicy
    public let createdAt: Date
}

public enum DomainValidationError: Error, Equatable {
    case invalidIdentifier(String)
    case coordinateOutOfBounds
    case confidenceOutOfBounds
    case nonPositiveMeasurement
    case nonPositiveOrdinal
}
