import Foundation
import RangeSightCore

struct MockShotMarker: Identifiable, Equatable {
    let id: Int
    let normalized: NormalizedTargetCoordinate
    let score: Int
    let confidence: Double
    let source: ShotSource

    func moved(to coordinate: NormalizedTargetCoordinate, score: Int) -> MockShotMarker {
        MockShotMarker(
            id: id,
            normalized: coordinate,
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

struct MockStringSummary: Identifiable, Equatable {
    let id: String
    let title: String
    let shots: Int
    let score: Int
    let groupSize: String
}

struct MockHistorySession: Identifiable, Equatable {
    let id: String
    let date: String
    let firearm: String
    let distance: String
    let target: String
    let bestGroup: String
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
    let summaries: [MockStringSummary]
    let history: [MockHistorySession]

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
            MockShotMarker(id: 1, normalized: coordinate(x: 0.48, y: 0.52), score: 10, confidence: 0.93, source: .autoConfirmed),
            MockShotMarker(id: 2, normalized: coordinate(x: 0.56, y: 0.47), score: 10, confidence: 0.91, source: .autoConfirmed),
            MockShotMarker(id: 3, normalized: coordinate(x: 0.72, y: 0.50), score: 8, confidence: 0.88, source: .userConfirmed),
            MockShotMarker(id: 4, normalized: coordinate(x: 0.86, y: 0.50), score: 6, confidence: 0.79, source: .userConfirmed),
            MockShotMarker(id: 5, normalized: coordinate(x: 0.50, y: 0.24), score: 8, confidence: 0.95, source: .autoConfirmed)
        ],
        candidates: [
            MockImpactCandidateMarker(id: "candidate-1", normalized: coordinate(x: 0.62, y: 0.40), confidence: 0.72)
        ],
        summaries: [
            MockStringSummary(id: "string-1", title: "String 1", shots: 5, score: 42, groupSize: "2.4 in"),
            MockStringSummary(id: "string-2", title: "String 2", shots: 5, score: 38, groupSize: "3.1 in")
        ],
        history: [
            MockHistorySession(id: "session-1", date: "Today", firearm: "Range 9", distance: "7 yd", target: "Bullseye Practice", bestGroup: "2.4 in"),
            MockHistorySession(id: "session-2", date: "Aug 18", firearm: "Range 9", distance: "10 yd", target: "Bullseye", bestGroup: "3.8 in")
        ]
    )

    private static func coordinate(x: Double, y: Double) -> NormalizedTargetCoordinate {
        do {
            return try NormalizedTargetCoordinate(x: x, y: y)
        } catch {
            preconditionFailure("Invalid mock target coordinate: \(x), \(y)")
        }
    }
}
