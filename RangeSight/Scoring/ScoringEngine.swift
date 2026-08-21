public struct CircularScoringZone: ScoringZone, Equatable {
    public let id: String
    public let label: String
    public let scoreValue: Double
    public let center: PhysicalPoint
    public let radius: Double

    public init(
        id: String,
        label: String,
        scoreValue: Double,
        center: PhysicalPoint,
        radius: Double
    ) {
        precondition(radius > 0, "Scoring-zone radius must be greater than zero.")
        self.id = id
        self.label = label
        self.scoreValue = scoreValue
        self.center = center
        self.radius = radius
    }

    public func contains(_ point: PhysicalPoint) -> Bool {
        guard point.unit == center.unit else {
            return false
        }

        return GroupMetricCalculator.distance(point, center) <= radius
    }

    public func distanceToNearestBoundary(from point: PhysicalPoint) -> Double {
        guard point.unit == center.unit else {
            return .infinity
        }

        return abs(radius - GroupMetricCalculator.distance(point, center))
    }
}

public enum ScoringTieBreak: String, Sendable {
    case highestScoreWins
    case lowestScoreWins
}

public struct ScoringTarget: Sendable {
    public let targetDefinitionID: TargetDefinitionID
    public let targetDefinitionRevision: Int
    public let physicalDimensions: PhysicalDimensions?
    public let zones: [any ScoringZone]
    public let tieBreak: ScoringTieBreak
    public let scoreUncertaintyMargin: Double

    public init(
        targetDefinitionID: TargetDefinitionID,
        targetDefinitionRevision: Int,
        physicalDimensions: PhysicalDimensions? = nil,
        zones: [any ScoringZone],
        tieBreak: ScoringTieBreak = .highestScoreWins,
        scoreUncertaintyMargin: Double = 0
    ) {
        precondition(targetDefinitionRevision > 0, "Target-definition revision must be positive.")
        precondition(scoreUncertaintyMargin >= 0, "Score uncertainty margin cannot be negative.")
        self.targetDefinitionID = targetDefinitionID
        self.targetDefinitionRevision = targetDefinitionRevision
        self.physicalDimensions = physicalDimensions
        self.zones = zones
        self.tieBreak = tieBreak
        self.scoreUncertaintyMargin = scoreUncertaintyMargin
    }

    public var maximumScorePerShot: Double? {
        switch tieBreak {
        case .highestScoreWins:
            return zones.map { $0.scoreValue }.max()
        case .lowestScoreWins:
            return zones.map { $0.scoreValue }.min()
        }
    }
}

public struct ScoreEvaluation: Equatable, Sendable {
    public let zoneID: String
    public let label: String
    public let value: Double
    public let targetDefinitionRevision: Int
    public let reviewable: Bool

    public var shotScore: ShotScore {
        ShotScore(
            value: value,
            targetDefinitionRevision: targetDefinitionRevision,
            reviewable: reviewable
        )
    }
}

public struct TargetScoringEngine: ScoringEngine {
    public init() {}

    public func score(_ point: PhysicalPoint, using target: ScoringTarget) -> ScoreEvaluation? {
        let containingZones = target.zones.filter { $0.contains(point) }

        guard let selectedZone = selectedZone(from: containingZones, target: target) else {
            return nil
        }

        return ScoreEvaluation(
            zoneID: selectedZone.id,
            label: selectedZone.label,
            value: selectedZone.scoreValue,
            targetDefinitionRevision: target.targetDefinitionRevision,
            reviewable: selectedZone.distanceToNearestBoundary(from: point) <= target.scoreUncertaintyMargin
        )
    }

    private func selectedZone(from zones: [any ScoringZone], target: ScoringTarget) -> (any ScoringZone)? {
        switch target.tieBreak {
        case .highestScoreWins:
            return zones.max { left, right in
                left.scoreValue < right.scoreValue
            }
        case .lowestScoreWins:
            return zones.min { left, right in
                left.scoreValue < right.scoreValue
            }
        }
    }
}

public enum SupportedTargetCatalog {
    public static let bullseyePracticeID = TargetDefinitionID(rawValue: "rangesight-bullseye-practice-8in")

    public static var allTargetDefinitions: [TargetDefinition] {
        [bullseyePracticeTargetDefinition]
    }

    public static var bullseyePracticeTargetDefinition: TargetDefinition {
        TargetDefinition(
            id: bullseyePracticeID,
            name: "RangeSight 8 in Bullseye Practice",
            revision: 1,
            physicalDimensions: try! PhysicalDimensions(width: 8, height: 8, unit: .inch),
            scoringZones: [
                ScoringZoneDefinition(id: "ten-ring", label: "10", scoreValue: 10, reviewMargin: 0.03),
                ScoringZoneDefinition(id: "eight-ring", label: "8", scoreValue: 8, reviewMargin: 0.03),
                ScoringZoneDefinition(id: "six-ring", label: "6", scoreValue: 6, reviewMargin: 0.03),
                ScoringZoneDefinition(id: "four-ring", label: "4", scoreValue: 4, reviewMargin: 0.03)
            ],
            aimPoints: [
                AimPoint(id: "center", label: "Center", normalized: try! NormalizedTargetCoordinate(x: 0.5, y: 0.5))
            ],
            supportedModes: [.genericImpact, .groupMetrics, .scoring]
        )
    }

    public static func scoringTarget(for targetDefinitionID: TargetDefinitionID) -> ScoringTarget? {
        guard targetDefinitionID == bullseyePracticeID else {
            return nil
        }

        let dimensions = try! PhysicalDimensions(width: 8, height: 8, unit: .inch)
        let center = PhysicalPoint(x: 0, y: 0, unit: .inch)
        return ScoringTarget(
            targetDefinitionID: bullseyePracticeID,
            targetDefinitionRevision: 1,
            physicalDimensions: dimensions,
            zones: [
                CircularScoringZone(id: "ten-ring", label: "10", scoreValue: 10, center: center, radius: 1),
                CircularScoringZone(id: "eight-ring", label: "8", scoreValue: 8, center: center, radius: 2),
                CircularScoringZone(id: "six-ring", label: "6", scoreValue: 6, center: center, radius: 3),
                CircularScoringZone(id: "four-ring", label: "4", scoreValue: 4, center: center, radius: 4)
            ],
            scoreUncertaintyMargin: 0.03
        )
    }
}

public enum ImpactScoringStatus: String, Codable, Equatable, Sendable {
    case scored
    case miss
    case unavailable
}

public enum StringScoringStatus: String, Codable, Equatable, Sendable {
    case scored
    case unavailable
    case noAcceptedImpacts
}

public struct AcceptedImpactScoreResult: Codable, Equatable, Sendable, Identifiable {
    public let id: ShotID
    public let displayOrdinal: Int
    public let acceptedNormalizedCoordinate: NormalizedTargetCoordinate
    public let physicalCoordinate: PhysicalPoint?
    public let targetDefinitionID: TargetDefinitionID?
    public let targetDefinitionRevision: Int?
    public let zoneID: String?
    public let zoneLabel: String?
    public let scoreValue: Double?
    public let status: ImpactScoringStatus
    public let reviewable: Bool

    public init(
        id: ShotID,
        displayOrdinal: Int,
        acceptedNormalizedCoordinate: NormalizedTargetCoordinate,
        physicalCoordinate: PhysicalPoint?,
        targetDefinitionID: TargetDefinitionID?,
        targetDefinitionRevision: Int?,
        zoneID: String?,
        zoneLabel: String?,
        scoreValue: Double?,
        status: ImpactScoringStatus,
        reviewable: Bool
    ) {
        self.id = id
        self.displayOrdinal = displayOrdinal
        self.acceptedNormalizedCoordinate = acceptedNormalizedCoordinate
        self.physicalCoordinate = physicalCoordinate
        self.targetDefinitionID = targetDefinitionID
        self.targetDefinitionRevision = targetDefinitionRevision
        self.zoneID = zoneID
        self.zoneLabel = zoneLabel
        self.scoreValue = scoreValue
        self.status = status
        self.reviewable = reviewable
    }

    public var shotScore: ShotScore? {
        guard let scoreValue, let targetDefinitionRevision else {
            return nil
        }

        return ShotScore(
            value: scoreValue,
            targetDefinitionRevision: targetDefinitionRevision,
            reviewable: reviewable
        )
    }
}

public struct StringScoringResult: Codable, Equatable, Sendable {
    public let status: StringScoringStatus
    public let targetDefinitionID: TargetDefinitionID?
    public let targetDefinitionRevision: Int?
    public let acceptedImpactCount: Int
    public let scoredImpactCount: Int
    public let missCount: Int
    public let totalScore: Double?
    public let maximumPossibleScore: Double?
    public let perImpactScores: [AcceptedImpactScoreResult]
    public let groupMetrics: GroupMetrics?

    public init(
        status: StringScoringStatus,
        targetDefinitionID: TargetDefinitionID?,
        targetDefinitionRevision: Int?,
        acceptedImpactCount: Int,
        scoredImpactCount: Int,
        missCount: Int,
        totalScore: Double?,
        maximumPossibleScore: Double?,
        perImpactScores: [AcceptedImpactScoreResult],
        groupMetrics: GroupMetrics?
    ) {
        self.status = status
        self.targetDefinitionID = targetDefinitionID
        self.targetDefinitionRevision = targetDefinitionRevision
        self.acceptedImpactCount = acceptedImpactCount
        self.scoredImpactCount = scoredImpactCount
        self.missCount = missCount
        self.totalScore = totalScore
        self.maximumPossibleScore = maximumPossibleScore
        self.perImpactScores = perImpactScores
        self.groupMetrics = groupMetrics
    }
}

public struct AcceptedImpactStringScoringEngine: Sendable {
    private let scoringEngine: TargetScoringEngine

    public init(scoringEngine: TargetScoringEngine = TargetScoringEngine()) {
        self.scoringEngine = scoringEngine
    }

    public func score(
        correctionState: ImpactCorrectionState,
        targetDefinitionID: TargetDefinitionID
    ) throws -> StringScoringResult {
        try score(acceptedImpacts: correctionState.acceptedImpacts, targetDefinitionID: targetDefinitionID)
    }

    public func shotsForPersistence(
        correctionState: ImpactCorrectionState,
        targetDefinitionID: TargetDefinitionID
    ) throws -> [Shot] {
        let scoringResult = try score(correctionState: correctionState, targetDefinitionID: targetDefinitionID)
        let scoreByImpactID = Dictionary(
            uniqueKeysWithValues: scoringResult.perImpactScores.compactMap { result in
                result.shotScore.map { (result.id, $0) }
            }
        )

        return try correctionState.shotsForPersistence().map { shot in
            try Shot(
                id: shot.id,
                stringID: shot.stringID,
                ordinal: shot.ordinal,
                timestamp: shot.timestamp,
                normalized: shot.normalized,
                physical: shot.physical,
                confidence: shot.confidence,
                source: shot.source,
                corrected: shot.corrected,
                originalNormalized: shot.originalNormalized,
                score: scoreByImpactID[shot.id]
            )
        }
    }

    public func score(
        acceptedImpacts: [AcceptedImpact],
        targetDefinitionID: TargetDefinitionID
    ) throws -> StringScoringResult {
        let sortedImpacts = acceptedImpacts.sorted { lhs, rhs in
            if lhs.displayOrdinal == rhs.displayOrdinal {
                return lhs.id.rawValue < rhs.id.rawValue
            }

            return lhs.displayOrdinal < rhs.displayOrdinal
        }

        guard !sortedImpacts.isEmpty else {
            return StringScoringResult(
                status: .noAcceptedImpacts,
                targetDefinitionID: targetDefinitionID,
                targetDefinitionRevision: nil,
                acceptedImpactCount: 0,
                scoredImpactCount: 0,
                missCount: 0,
                totalScore: nil,
                maximumPossibleScore: nil,
                perImpactScores: [],
                groupMetrics: nil
            )
        }

        guard let target = SupportedTargetCatalog.scoringTarget(for: targetDefinitionID),
              let dimensions = target.physicalDimensions else {
            return StringScoringResult(
                status: .unavailable,
                targetDefinitionID: targetDefinitionID,
                targetDefinitionRevision: nil,
                acceptedImpactCount: sortedImpacts.count,
                scoredImpactCount: 0,
                missCount: 0,
                totalScore: nil,
                maximumPossibleScore: nil,
                perImpactScores: sortedImpacts.map { impact in
                    AcceptedImpactScoreResult(
                        id: impact.id,
                        displayOrdinal: impact.displayOrdinal,
                        acceptedNormalizedCoordinate: impact.finalCoordinate,
                        physicalCoordinate: nil,
                        targetDefinitionID: targetDefinitionID,
                        targetDefinitionRevision: nil,
                        zoneID: nil,
                        zoneLabel: nil,
                        scoreValue: nil,
                        status: .unavailable,
                        reviewable: false
                    )
                },
                groupMetrics: nil
            )
        }

        let perImpactScores = sortedImpacts.map { impact in
            score(impact, using: target, dimensions: dimensions)
        }
        let physicalPoints = perImpactScores.compactMap(\.physicalCoordinate)
        let scoredValues = perImpactScores.compactMap(\.scoreValue)
        let groupMetrics = try? GroupMetricCalculator.metrics(
            for: physicalPoints,
            aimPoint: PhysicalPoint(x: 0, y: 0, unit: dimensions.unit)
        )
        let missCount = perImpactScores.filter { $0.status == .miss }.count
        let maximumPossibleScore = target.maximumScorePerShot.map { $0 * Double(sortedImpacts.count) }

        return StringScoringResult(
            status: .scored,
            targetDefinitionID: target.targetDefinitionID,
            targetDefinitionRevision: target.targetDefinitionRevision,
            acceptedImpactCount: sortedImpacts.count,
            scoredImpactCount: scoredValues.count,
            missCount: missCount,
            totalScore: scoredValues.reduce(0, +),
            maximumPossibleScore: maximumPossibleScore,
            perImpactScores: perImpactScores,
            groupMetrics: groupMetrics
        )
    }

    private func score(
        _ impact: AcceptedImpact,
        using target: ScoringTarget,
        dimensions: PhysicalDimensions
    ) -> AcceptedImpactScoreResult {
        let physicalPoint = TargetCoordinateConverter.physicalPoint(
            from: impact.finalCoordinate,
            dimensions: dimensions
        )
        guard let score = scoringEngine.score(physicalPoint, using: target) else {
            return AcceptedImpactScoreResult(
                id: impact.id,
                displayOrdinal: impact.displayOrdinal,
                acceptedNormalizedCoordinate: impact.finalCoordinate,
                physicalCoordinate: physicalPoint,
                targetDefinitionID: target.targetDefinitionID,
                targetDefinitionRevision: target.targetDefinitionRevision,
                zoneID: nil,
                zoneLabel: nil,
                scoreValue: nil,
                status: .miss,
                reviewable: false
            )
        }

        return AcceptedImpactScoreResult(
            id: impact.id,
            displayOrdinal: impact.displayOrdinal,
            acceptedNormalizedCoordinate: impact.finalCoordinate,
            physicalCoordinate: physicalPoint,
            targetDefinitionID: target.targetDefinitionID,
            targetDefinitionRevision: target.targetDefinitionRevision,
            zoneID: score.zoneID,
            zoneLabel: score.label,
            scoreValue: score.value,
            status: .scored,
            reviewable: score.reviewable
        )
    }
}
