import Foundation
import RangeSightCore

struct MockShotMarker: Identifiable, Equatable {
    let id: Int
    let normalized: NormalizedTargetCoordinate
    let originalNormalized: NormalizedTargetCoordinate?
    let score: Int
    let confidence: Double
    let source: ShotSource

    func moved(to coordinate: NormalizedTargetCoordinate, score: Int) -> MockShotMarker {
        MockShotMarker(
            id: id,
            normalized: coordinate,
            originalNormalized: originalNormalized ?? normalized,
            score: score,
            confidence: confidence,
            source: .corrected
        )
    }
}

struct MockImpactCandidateMarker: Identifiable, Equatable {
    let id: String
    let normalized: NormalizedTargetCoordinate
    let confidence: Double
}

struct MockRangeSessionData: Equatable {
    let targetName: String
    let distance: String
    let firearm: String
    let shotCount: Int
    let latestScore: String
    let groupSize: String
    let status: String
    let qualityStatus: String
    let shots: [MockShotMarker]
    let candidates: [MockImpactCandidateMarker]

    static let sample = MockRangeSessionData(
        targetName: "RangeSight 8 in Bullseye Practice",
        distance: "7 yd",
        firearm: "Range 9",
        shotCount: 5,
        latestScore: "10",
        groupSize: "2.4 in",
        status: "Monitoring",
        qualityStatus: "Target ready",
        shots: [
            MockShotMarker(id: 1, normalized: coordinate(x: 0.48, y: 0.52), originalNormalized: nil, score: 10, confidence: 0.93, source: .autoConfirmed),
            MockShotMarker(id: 2, normalized: coordinate(x: 0.56, y: 0.47), originalNormalized: nil, score: 10, confidence: 0.91, source: .autoConfirmed),
            MockShotMarker(id: 3, normalized: coordinate(x: 0.72, y: 0.50), originalNormalized: nil, score: 8, confidence: 0.88, source: .userConfirmed),
            MockShotMarker(id: 4, normalized: coordinate(x: 0.86, y: 0.50), originalNormalized: nil, score: 6, confidence: 0.79, source: .userConfirmed),
            MockShotMarker(id: 5, normalized: coordinate(x: 0.50, y: 0.24), originalNormalized: nil, score: 8, confidence: 0.95, source: .autoConfirmed)
        ],
        candidates: [
            MockImpactCandidateMarker(id: "candidate-1", normalized: coordinate(x: 0.62, y: 0.40), confidence: 0.72)
        ]
    )

    private static func coordinate(x: Double, y: Double) -> NormalizedTargetCoordinate {
        do {
            return try NormalizedTargetCoordinate(x: x, y: y)
        } catch {
            return try! NormalizedTargetCoordinate(x: 0.5, y: 0.5)
        }
    }
}
