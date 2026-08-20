import Foundation
import RangeSightCore

struct MockShotMarker: Identifiable, Equatable {
    let id: Int
    let normalized: NormalizedTargetCoordinate
    let score: Int
    let confidence: Double
    let source: ShotSource
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
    let summaries: [MockStringSummary]
    let history: [MockHistorySession]

    static let sample = MockRangeSessionData(
        targetName: "USPSA Practice Paper",
        distance: "7 yd",
        firearm: "Range 9",
        shotCount: 5,
        latestScore: "A",
        groupSize: "2.4 in",
        status: "Monitoring",
        qualityStatus: "Target ready",
        shots: [
            MockShotMarker(id: 1, normalized: coordinate(x: 0.48, y: 0.52), score: 5, confidence: 0.93, source: .autoConfirmed),
            MockShotMarker(id: 2, normalized: coordinate(x: 0.56, y: 0.47), score: 5, confidence: 0.91, source: .autoConfirmed),
            MockShotMarker(id: 3, normalized: coordinate(x: 0.51, y: 0.44), score: 5, confidence: 0.88, source: .userConfirmed),
            MockShotMarker(id: 4, normalized: coordinate(x: 0.44, y: 0.58), score: 3, confidence: 0.79, source: .userConfirmed),
            MockShotMarker(id: 5, normalized: coordinate(x: 0.53, y: 0.55), score: 5, confidence: 0.95, source: .autoConfirmed)
        ],
        summaries: [
            MockStringSummary(id: "string-1", title: "String 1", shots: 5, score: 23, groupSize: "2.4 in"),
            MockStringSummary(id: "string-2", title: "String 2", shots: 5, score: 21, groupSize: "3.1 in")
        ],
        history: [
            MockHistorySession(id: "session-1", date: "Today", firearm: "Range 9", distance: "7 yd", target: "USPSA Practice", bestGroup: "2.4 in"),
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
