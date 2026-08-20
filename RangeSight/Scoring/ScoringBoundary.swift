public protocol ScoringZone: Sendable {
    var id: String { get }
    var label: String { get }
    var scoreValue: Double { get }
    func contains(_ point: PhysicalPoint) -> Bool
    func distanceToNearestBoundary(from point: PhysicalPoint) -> Double
}

public protocol ScoringEngine: Sendable {
    func score(_ point: PhysicalPoint, using target: ScoringTarget) -> ScoreEvaluation?
}
