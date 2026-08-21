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

public enum DistanceUnit: String, Codable, Equatable, Hashable, Sendable {
    case yard
    case meter
}

public enum LengthUnit: String, Codable, Equatable, Hashable, Sendable {
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

    public init(x: Double, y: Double, unit: LengthUnit) {
        self.x = x
        self.y = y
        self.unit = unit
    }
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

    public init(
        id: FirearmProfileID,
        nickname: String,
        category: FirearmCategory,
        caliber: String?,
        notes: String?,
        createdAt: Date
    ) {
        self.id = id
        self.nickname = nickname
        self.category = category
        self.caliber = caliber
        self.notes = notes
        self.createdAt = createdAt
    }
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

    public init(
        platform: Platform,
        modelName: String?,
        osVersion: String?,
        appVersion: String?
    ) {
        self.platform = platform
        self.modelName = modelName
        self.osVersion = osVersion
        self.appVersion = appVersion
    }
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

    public init(
        id: RangeSessionID,
        startedAt: Date,
        endedAt: Date?,
        distance: Double,
        distanceUnit: DistanceUnit,
        firearmID: FirearmProfileID?,
        targetDefinitionID: TargetDefinitionID,
        device: DeviceMetadata
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.distance = distance
        self.distanceUnit = distanceUnit
        self.firearmID = firearmID
        self.targetDefinitionID = targetDefinitionID
        self.device = device
    }
}

public struct RangeString: Codable, Equatable, Sendable {
    public let id: RangeStringID
    public let sessionID: RangeSessionID
    public let index: Int
    public let baselineAssetID: SessionAssetID?
    public let startedAt: Date
    public let endedAt: Date?

    public init(
        id: RangeStringID,
        sessionID: RangeSessionID,
        index: Int,
        baselineAssetID: SessionAssetID?,
        startedAt: Date,
        endedAt: Date?
    ) {
        self.id = id
        self.sessionID = sessionID
        self.index = index
        self.baselineAssetID = baselineAssetID
        self.startedAt = startedAt
        self.endedAt = endedAt
    }
}

public struct ShotScore: Codable, Equatable, Sendable {
    public let value: Double
    public let targetDefinitionRevision: Int
    public let reviewable: Bool

    public init(value: Double, targetDefinitionRevision: Int, reviewable: Bool) {
        self.value = value
        self.targetDefinitionRevision = targetDefinitionRevision
        self.reviewable = reviewable
    }
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

public enum ImpactCorrectionProvenance: String, Codable, CaseIterable, Sendable {
    case detectorConfirmed
    case userConfirmedCandidate
    case userAdded
    case userMoved
    case userDeleted
}

public enum AcceptedImpactState: String, Codable, CaseIterable, Sendable {
    case accepted
    case deleted
}

public struct RawImpactEvidence: Codable, Equatable, Sendable {
    public let detectorEventID: String?
    public let candidateID: String?
    public let coordinate: NormalizedTargetCoordinate?
    public let confidence: Double?
    public let timestamp: Date?

    public init(
        detectorEventID: String? = nil,
        candidateID: String? = nil,
        coordinate: NormalizedTargetCoordinate? = nil,
        confidence: Double? = nil,
        timestamp: Date? = nil
    ) throws {
        if let confidence {
            guard (0...1).contains(confidence) else {
                throw DomainValidationError.confidenceOutOfBounds
            }
        }

        self.detectorEventID = detectorEventID
        self.candidateID = candidateID
        self.coordinate = coordinate
        self.confidence = confidence
        self.timestamp = timestamp
    }
}

public struct AcceptedImpact: Codable, Equatable, Sendable, Identifiable {
    public let id: ShotID
    public let stringID: RangeStringID
    public let createdAt: Date
    public let rawEvidence: RawImpactEvidence?
    public let finalCoordinate: NormalizedTargetCoordinate
    public let state: AcceptedImpactState
    public let provenance: ImpactCorrectionProvenance
    public let displayOrdinal: Int

    public init(
        id: ShotID,
        stringID: RangeStringID,
        createdAt: Date,
        rawEvidence: RawImpactEvidence?,
        finalCoordinate: NormalizedTargetCoordinate,
        state: AcceptedImpactState,
        provenance: ImpactCorrectionProvenance,
        displayOrdinal: Int
    ) throws {
        guard displayOrdinal > 0 else {
            throw DomainValidationError.nonPositiveOrdinal
        }

        self.id = id
        self.stringID = stringID
        self.createdAt = createdAt
        self.rawEvidence = rawEvidence
        self.finalCoordinate = finalCoordinate
        self.state = state
        self.provenance = provenance
        self.displayOrdinal = displayOrdinal
    }

    public var isAcceptedForScoring: Bool {
        state == .accepted
    }
}

public struct ImpactCorrectionCounters: Codable, Equatable, Sendable {
    public var autoConfirmedCount: Int
    public var userConfirmedCandidateCount: Int
    public var userAddedCount: Int
    public var userMovedCount: Int
    public var userDeletedCount: Int

    public init(
        autoConfirmedCount: Int = 0,
        userConfirmedCandidateCount: Int = 0,
        userAddedCount: Int = 0,
        userMovedCount: Int = 0,
        userDeletedCount: Int = 0
    ) {
        self.autoConfirmedCount = autoConfirmedCount
        self.userConfirmedCandidateCount = userConfirmedCandidateCount
        self.userAddedCount = userAddedCount
        self.userMovedCount = userMovedCount
        self.userDeletedCount = userDeletedCount
    }
}

public struct ImpactCorrectionState: Codable, Equatable, Sendable {
    public private(set) var impacts: [AcceptedImpact]
    public private(set) var unresolvedMediumCandidates: [RawImpactEvidence]
    public private(set) var counters: ImpactCorrectionCounters
    private var nextManualImpactNumber: Int

    public init(
        impacts: [AcceptedImpact] = [],
        unresolvedMediumCandidates: [RawImpactEvidence] = [],
        counters: ImpactCorrectionCounters? = nil
    ) {
        self.impacts = impacts
        self.unresolvedMediumCandidates = unresolvedMediumCandidates
        self.counters = counters ?? Self.counters(for: impacts)
        self.nextManualImpactNumber = impacts.count + 1
        recalculateOrdinals()
    }

    public var acceptedImpacts: [AcceptedImpact] {
        impacts
            .filter(\.isAcceptedForScoring)
            .sorted { lhs, rhs in
                if lhs.createdAt == rhs.createdAt {
                    return lhs.id.rawValue < rhs.id.rawValue
                }

                return lhs.createdAt < rhs.createdAt
            }
    }

    public mutating func ingestDetectorEvent(
        id: ShotID,
        stringID: RangeStringID,
        eventID: String,
        coordinate: NormalizedTargetCoordinate,
        confidence: Double,
        timestamp: Date
    ) throws -> AcceptedImpact {
        let raw = try RawImpactEvidence(
            detectorEventID: eventID,
            candidateID: eventID,
            coordinate: coordinate,
            confidence: confidence,
            timestamp: timestamp
        )
        let impact = try AcceptedImpact(
            id: id,
            stringID: stringID,
            createdAt: timestamp,
            rawEvidence: raw,
            finalCoordinate: coordinate,
            state: .accepted,
            provenance: .detectorConfirmed,
            displayOrdinal: acceptedImpacts.count + 1
        )
        impacts.append(impact)
        recalculateOrdinals()
        return impact
    }

    public mutating func addMediumCandidate(_ rawEvidence: RawImpactEvidence) {
        unresolvedMediumCandidates.append(rawEvidence)
    }

    public mutating func manuallyAddImpact(
        stringID: RangeStringID,
        coordinate: NormalizedTargetCoordinate,
        timestamp: Date
    ) throws -> AcceptedImpact {
        let id = ShotID(rawValue: "manual-impact-\(nextManualImpactNumber)")
        nextManualImpactNumber += 1
        let impact = try AcceptedImpact(
            id: id,
            stringID: stringID,
            createdAt: timestamp,
            rawEvidence: nil,
            finalCoordinate: coordinate,
            state: .accepted,
            provenance: .userAdded,
            displayOrdinal: acceptedImpacts.count + 1
        )
        impacts.append(impact)
        recalculateOrdinals()
        return impact
    }

    public mutating func confirmMediumCandidate(
        candidateID: String,
        as id: ShotID,
        stringID: RangeStringID,
        timestamp: Date
    ) throws -> AcceptedImpact {
        guard let candidateIndex = unresolvedMediumCandidates.firstIndex(where: { $0.candidateID == candidateID }),
              let coordinate = unresolvedMediumCandidates[candidateIndex].coordinate else {
            throw DomainValidationError.invalidIdentifier("candidateID")
        }

        let raw = unresolvedMediumCandidates.remove(at: candidateIndex)
        let impact = try AcceptedImpact(
            id: id,
            stringID: stringID,
            createdAt: timestamp,
            rawEvidence: raw,
            finalCoordinate: coordinate,
            state: .accepted,
            provenance: .userConfirmedCandidate,
            displayOrdinal: acceptedImpacts.count + 1
        )
        impacts.append(impact)
        recalculateOrdinals()
        return impact
    }

    public mutating func moveImpact(id: ShotID, to coordinate: NormalizedTargetCoordinate) throws -> AcceptedImpact {
        guard let index = impacts.firstIndex(where: { $0.id == id }) else {
            throw DomainValidationError.invalidIdentifier("ShotID")
        }

        let current = impacts[index]
        let rawEvidence = try current.rawEvidence ?? RawImpactEvidence(
            detectorEventID: nil,
            candidateID: nil,
            coordinate: current.finalCoordinate,
            confidence: nil,
            timestamp: current.createdAt
        )
        let moved = try AcceptedImpact(
            id: current.id,
            stringID: current.stringID,
            createdAt: current.createdAt,
            rawEvidence: rawEvidence,
            finalCoordinate: coordinate,
            state: current.state,
            provenance: .userMoved,
            displayOrdinal: current.displayOrdinal
        )
        impacts[index] = moved
        recalculateOrdinals()
        return moved
    }

    public mutating func deleteImpact(id: ShotID) throws -> AcceptedImpact {
        guard let index = impacts.firstIndex(where: { $0.id == id }) else {
            throw DomainValidationError.invalidIdentifier("ShotID")
        }

        let current = impacts[index]
        let deleted = try AcceptedImpact(
            id: current.id,
            stringID: current.stringID,
            createdAt: current.createdAt,
            rawEvidence: current.rawEvidence,
            finalCoordinate: current.finalCoordinate,
            state: .deleted,
            provenance: .userDeleted,
            displayOrdinal: current.displayOrdinal
        )
        impacts[index] = deleted
        recalculateOrdinals()
        return deleted
    }

    public func shotsForPersistence() throws -> [Shot] {
        try acceptedImpacts.map { impact in
            try Shot(
                id: impact.id,
                stringID: impact.stringID,
                ordinal: impact.displayOrdinal,
                timestamp: impact.createdAt,
                normalized: impact.finalCoordinate,
                confidence: impact.rawEvidence?.confidence ?? 0,
                source: shotSource(for: impact.provenance),
                corrected: impact.provenance != .detectorConfirmed,
                originalNormalized: impact.rawEvidence?.coordinate
            )
        }
    }

    public mutating func recalculateOrdinals() {
        let acceptedIDs = acceptedImpacts.map(\.id)
        for index in impacts.indices {
            if let ordinalIndex = acceptedIDs.firstIndex(of: impacts[index].id) {
                let current = impacts[index]
                if let updated = try? AcceptedImpact(
                    id: current.id,
                    stringID: current.stringID,
                    createdAt: current.createdAt,
                    rawEvidence: current.rawEvidence,
                    finalCoordinate: current.finalCoordinate,
                    state: current.state,
                    provenance: current.provenance,
                    displayOrdinal: ordinalIndex + 1
                ) {
                    impacts[index] = updated
                }
            }
        }
        counters = Self.counters(for: impacts)
    }

    public static func counters(for impacts: [AcceptedImpact]) -> ImpactCorrectionCounters {
        impacts.reduce(into: ImpactCorrectionCounters()) { counters, impact in
            switch impact.provenance {
            case .detectorConfirmed:
                counters.autoConfirmedCount += 1
            case .userConfirmedCandidate:
                counters.userConfirmedCandidateCount += 1
            case .userAdded:
                counters.userAddedCount += 1
            case .userMoved:
                counters.userMovedCount += 1
            case .userDeleted:
                counters.userDeletedCount += 1
            }
        }
    }

    private func shotSource(for provenance: ImpactCorrectionProvenance) -> ShotSource {
        switch provenance {
        case .detectorConfirmed:
            return .autoConfirmed
        case .userConfirmedCandidate:
            return .userConfirmed
        case .userAdded:
            return .manualAdded
        case .userMoved:
            return .corrected
        case .userDeleted:
            return .corrected
        }
    }
}

public struct TargetDisplayGeometry: Codable, Equatable, Sendable {
    public let containerWidth: Double
    public let containerHeight: Double
    public let targetAspectRatio: Double

    public init(containerWidth: Double, containerHeight: Double, targetAspectRatio: Double = 1) throws {
        guard containerWidth > 0,
              containerHeight > 0,
              targetAspectRatio > 0,
              containerWidth.isFinite,
              containerHeight.isFinite,
              targetAspectRatio.isFinite else {
            throw DomainValidationError.nonPositiveMeasurement
        }

        self.containerWidth = containerWidth
        self.containerHeight = containerHeight
        self.targetAspectRatio = targetAspectRatio
    }

    public var targetRect: DisplayRect {
        let fittedWidth: Double
        let fittedHeight: Double

        if containerWidth / containerHeight > targetAspectRatio {
            fittedHeight = containerHeight
            fittedWidth = fittedHeight * targetAspectRatio
        } else {
            fittedWidth = containerWidth
            fittedHeight = fittedWidth / targetAspectRatio
        }

        return DisplayRect(
            minX: (containerWidth - fittedWidth) / 2,
            minY: (containerHeight - fittedHeight) / 2,
            width: fittedWidth,
            height: fittedHeight
        )
    }

    public func normalizedCoordinate(at point: DisplayPoint) throws -> NormalizedTargetCoordinate? {
        let rect = targetRect
        guard point.x >= rect.minX,
              point.x <= rect.maxX,
              point.y >= rect.minY,
              point.y <= rect.maxY else {
            return nil
        }

        return try NormalizedTargetCoordinate(
            x: (point.x - rect.minX) / rect.width,
            y: (point.y - rect.minY) / rect.height
        )
    }

    public func displayPoint(for coordinate: NormalizedTargetCoordinate) -> DisplayPoint {
        let rect = targetRect
        return DisplayPoint(
            x: rect.minX + coordinate.x * rect.width,
            y: rect.minY + coordinate.y * rect.height
        )
    }
}

public struct DisplayPoint: Codable, Equatable, Sendable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct DisplayRect: Codable, Equatable, Sendable {
    public let minX: Double
    public let minY: Double
    public let width: Double
    public let height: Double

    public init(minX: Double, minY: Double, width: Double, height: Double) {
        self.minX = minX
        self.minY = minY
        self.width = width
        self.height = height
    }

    public var maxX: Double { minX + width }
    public var maxY: Double { minY + height }
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
