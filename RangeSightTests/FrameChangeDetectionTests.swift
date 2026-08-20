import Foundation
import XCTest
@testable import RangeSightCore

final class FrameChangeDetectionTests: XCTestCase {
    func testNoChangeProducesNoCandidates() throws {
        let result = try changeResult(currentPixels: basePixels())

        XCTAssertEqual(result.status, .noChange)
        XCTAssertEqual(result.candidates, [])
        XCTAssertEqual(result.changedPixelRatio, 0, accuracy: 0.000001)
    }

    func testSmallLocalizedChangeProducesOneCandidateNearKnownRegion() throws {
        let result = try changeResult(currentPixels: pixels(changing: [(4, 6), (5, 6), (4, 7), (5, 7)], to: 0.92))

        XCTAssertEqual(result.status, .localizedChangeDetected)
        XCTAssertEqual(result.candidates.count, 1)

        let candidate = try XCTUnwrap(result.candidates.first)
        XCTAssertEqual(candidate.areaPixels, 4)
        XCTAssertEqual(candidate.centroid.x, 0.5, accuracy: 0.000001)
        XCTAssertEqual(candidate.centroid.y, 0.7, accuracy: 0.000001)
        XCTAssertEqual(candidate.bounds.minX, 0.4, accuracy: 0.000001)
        XCTAssertEqual(candidate.bounds.maxX, 0.6, accuracy: 0.000001)
        XCTAssertEqual(candidate.bounds.minY, 0.6, accuracy: 0.000001)
        XCTAssertEqual(candidate.bounds.maxY, 0.8, accuracy: 0.000001)
    }

    func testMultipleLocalizedChangesProduceDistinctCandidates() throws {
        let result = try changeResult(
            currentPixels: pixels(
                changing: [(1, 1), (1, 2), (8, 7), (8, 8)],
                to: 0.95
            )
        )

        XCTAssertEqual(result.status, .localizedChangeDetected)
        XCTAssertEqual(result.candidates.count, 2)
        XCTAssertEqual(result.candidates.map { $0.areaPixels }, [2, 2])
    }

    func testGlobalBrightnessChangeIsRejected() throws {
        let brightPixels = Array(repeating: 0.75, count: pixelCount)
        let result = try changeResult(currentPixels: brightPixels)

        XCTAssertEqual(result.status, .globalChangeRejected)
        XCTAssertEqual(result.candidates, [])
        XCTAssertEqual(result.changedPixelRatio, 1, accuracy: 0.000001)
    }

    func testRegistrationFailureSkipsChangeCandidates() throws {
        let reference = try frame(index: 0, timestamp: 0, pixels: basePixels(), features: features())
        let current = try frame(
            index: 1,
            timestamp: 0.04,
            pixels: pixels(changing: [(4, 4), (5, 4)], to: 0.95),
            features: translatedFeatures(dx: 0.2, dy: 0)
        )
        let referenceRegistration = try RegistrationReferenceFrame(frame: reference, minimumFeatureCount: 3)
        let registration = try FrameRegistrationEngine().register(currentFrame: current, against: referenceRegistration)

        XCTAssertEqual(registration.status, .failed)

        let result = try FrameChangeDetector().detectChanges(
            referenceFrame: reference,
            currentFrame: current,
            registration: registration
        )

        XCTAssertEqual(result.status, .skippedDueToRegistration)
        XCTAssertEqual(result.candidates, [])
    }

    func testReplayHarnessExercisesRegisteredChangeDetectionProcessor() async throws {
        let frames = [
            try frame(index: 0, timestamp: 0, pixels: basePixels(), features: features()),
            try frame(
                index: 1,
                timestamp: 0.04,
                pixels: pixels(changing: [(4, 6), (5, 6), (4, 7), (5, 7)], to: 0.92),
                features: features()
            )
        ]

        let result = try await ReplayHarness.run(
            manifest: try ReplayManifest(id: "change-detection-fixture"),
            configuration: try ReplayRunConfiguration(algorithmVersion: "change-detection-slice-10"),
            frameSource: try ArrayReplayFrameSource(frames: frames),
            processor: RegisteredChangeDetectionProcessor()
        )

        XCTAssertEqual(result.completionReason, .endOfStream)
        let secondFrameStages = result.frameResults[1].events.map { $0.stage }
        XCTAssertEqual(secondFrameStages, [.frameRegistration, .changeMapGeneration])

        let changeDiagnostics = try XCTUnwrap(result.frameResults[1].events.last?.diagnostics)
        let expectedStatus = try VisionFrameDiagnostic(key: "changeStatus", value: 2)
        let expectedCount = try VisionFrameDiagnostic(key: "changeCandidateCount", value: 1)
        XCTAssertTrue(changeDiagnostics.contains(expectedStatus))
        XCTAssertTrue(changeDiagnostics.contains(expectedCount))
    }

    private var pixelCount: Int {
        100
    }

    private func changeResult(currentPixels: [Double]) throws -> ChangeDetectionResult {
        let reference = try frame(index: 0, timestamp: 0, pixels: basePixels(), features: features())
        let current = try frame(index: 1, timestamp: 0.04, pixels: currentPixels, features: features())
        let referenceRegistration = try RegistrationReferenceFrame(frame: reference, minimumFeatureCount: 3)
        let registration = try FrameRegistrationEngine().register(currentFrame: current, against: referenceRegistration)

        XCTAssertEqual(registration.status, .registered)

        return try FrameChangeDetector().detectChanges(
            referenceFrame: reference,
            currentFrame: current,
            registration: registration
        )
    }

    private func basePixels() -> [Double] {
        Array(repeating: 0.5, count: pixelCount)
    }

    private func pixels(changing coordinates: [(x: Int, y: Int)], to value: Double) -> [Double] {
        var pixels = basePixels()

        for coordinate in coordinates {
            pixels[coordinate.y * 10 + coordinate.x] = value
        }

        return pixels
    }

    private func frame(
        index: Int,
        timestamp: TimeInterval,
        pixels: [Double],
        features: [RegistrationFeature]
    ) throws -> VisionFrame {
        let luminance = try LuminanceFrame(width: 10, height: 10, pixels: pixels)

        return try VisionFrame(
            sequenceIndex: index,
            timestamp: timestamp,
            dimensions: try FrameDimensions(width: 10, height: 10),
            orientation: .landscapeRight,
            content: .fixtureRegisteredFrame(RegisteredFrameFixture(luminance: luminance, features: features))
        )
    }

    private func features() throws -> [RegistrationFeature] {
        [
            try RegistrationFeature(id: "top-left", point: try NormalizedImagePoint(x: 0.2, y: 0.2)),
            try RegistrationFeature(id: "top-right", point: try NormalizedImagePoint(x: 0.8, y: 0.2)),
            try RegistrationFeature(id: "bottom-right", point: try NormalizedImagePoint(x: 0.8, y: 0.8)),
            try RegistrationFeature(id: "bottom-left", point: try NormalizedImagePoint(x: 0.2, y: 0.8))
        ]
    }

    private func translatedFeatures(dx: Double, dy: Double) throws -> [RegistrationFeature] {
        try features().map { feature in
            try RegistrationFeature(
                id: feature.id,
                point: try NormalizedImagePoint(x: feature.point.x + dx, y: feature.point.y + dy)
            )
        }
    }
}
