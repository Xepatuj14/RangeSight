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
    public let zones: [any ScoringZone]
    public let tieBreak: ScoringTieBreak
    public let scoreUncertaintyMargin: Double

    public init(
        targetDefinitionID: TargetDefinitionID,
        targetDefinitionRevision: Int,
        zones: [any ScoringZone],
        tieBreak: ScoringTieBreak = .highestScoreWins,
        scoreUncertaintyMargin: Double = 0
    ) {
        precondition(targetDefinitionRevision > 0, "Target-definition revision must be positive.")
        precondition(scoreUncertaintyMargin >= 0, "Score uncertainty margin cannot be negative.")
        self.targetDefinitionID = targetDefinitionID
        self.targetDefinitionRevision = targetDefinitionRevision
        self.zones = zones
        self.tieBreak = tieBreak
        self.scoreUncertaintyMargin = scoreUncertaintyMargin
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
