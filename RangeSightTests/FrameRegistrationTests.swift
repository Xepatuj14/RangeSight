import Foundation
import XCTest
@testable import RangeSightCore

final class FrameRegistrationTests: XCTestCase {
    func testIdenticalFrameRegistersWithIdentityTransform() throws {
        let reference = try referenceFrame()
        let current = try frame(index: 1, timestamp: 0.04, features: baseFeatures())
        let result = try FrameRegistrationEngine().register(
            currentFrame: current,
            against: try RegistrationReferenceFrame(frame: reference, minimumFeatureCount: 3)
        )

        XCTAssertEqual(result.status, .registered)
        XCTAssertEqual(result.referenceFrameSequenceIndex, 0)
        XCTAssertEqual(result.currentFrameSequenceIndex, 1)
        XCTAssertEqual(result.matchedFeatureCount, 4)
        XCTAssertEqual(result.confidence, 1, accuracy: 0.000001)
        XCTAssertEqual(result.transform?.translationX ?? 1, 0, accuracy: 0.000001)
        XCTAssertEqual(result.transform?.translationY ?? 1, 0, accuracy: 0.000001)
        XCTAssertEqual(result.transform?.rotationRadians ?? 1, 0, accuracy: 0.000001)
        XCTAssertEqual(result.transform?.scale ?? 0, 1, accuracy: 0.000001)
    }

    func testHorizontalTranslationRegistersWithinTolerance() throws {
        let result = try registrationResult(currentFeatures: translatedFeatures(dx: 0.04, dy: 0))

        XCTAssertEqual(result.status, .registered)
        XCTAssertEqual(result.transform?.translationX ?? 0, -0.04, accuracy: 0.000001)
        XCTAssertEqual(result.transform?.translationY ?? 1, 0, accuracy: 0.000001)
        XCTAssertEqual(result.rootMeanSquareError ?? 1, 0, accuracy: 0.000001)
    }

    func testVerticalTranslationRegistersWithinTolerance() throws {
        let result = try registrationResult(currentFeatures: translatedFeatures(dx: 0, dy: -0.03))

        XCTAssertEqual(result.status, .registered)
        XCTAssertEqual(result.transform?.translationX ?? 1, 0, accuracy: 0.000001)
        XCTAssertEqual(result.transform?.translationY ?? 0, 0.03, accuracy: 0.000001)
        XCTAssertEqual(result.rootMeanSquareError ?? 1, 0, accuracy: 0.000001)
    }

    func testCombinedTranslationRegistersWithinTolerance() throws {
        let result = try registrationResult(currentFeatures: translatedFeatures(dx: 0.025, dy: -0.035))

        XCTAssertEqual(result.status, .registered)
        XCTAssertEqual(result.transform?.translationX ?? 0, -0.025, accuracy: 0.000001)
        XCTAssertEqual(result.transform?.translationY ?? 0, 0.035, accuracy: 0.000001)
    }

    func testSmallRotationRegistersWithinTolerance() throws {
        let radians = 0.04
        let result = try registrationResult(currentFeatures: rotatedFeatures(radians: radians))

        XCTAssertEqual(result.status, .registered)
        XCTAssertEqual(result.transform?.rotationRadians ?? 0, -radians, accuracy: 0.000001)
        XCTAssertEqual(result.transform?.scale ?? 0, 1, accuracy: 0.000001)
    }

    func testProcessorUsesReplayHarnessPath() async throws {
        let frames = [
            try referenceFrame(),
            try frame(index: 1, timestamp: 0.04, features: translatedFeatures(dx: 0.02, dy: 0.01))
        ]

        let result = try await ReplayHarness.run(
            manifest: try ReplayManifest(id: "registration-fixture"),
            configuration: try ReplayRunConfiguration(algorithmVersion: "registration-slice-9"),
            frameSource: try ArrayReplayFrameSource(frames: frames),
            processor: FrameRegistrationProcessor()
        )

        XCTAssertEqual(result.completionReason, .endOfStream)
        XCTAssertEqual(result.frameResults.map { $0.events.first?.stage }, [.frameRegistration, .frameRegistration])

        let secondDiagnostics = try XCTUnwrap(result.frameResults.last?.events.first?.diagnostics)
        let expectedStatus = try VisionFrameDiagnostic(key: "registrationStatus", value: 2)
        let expectedReference = try VisionFrameDiagnostic(key: "referenceFrameIndex", value: 0)
        XCTAssertTrue(secondDiagnostics.contains(expectedStatus))
        XCTAssertTrue(secondDiagnostics.contains(expectedReference))
    }

    func testMissingReferenceReportsReferenceUnavailable() throws {
        let current = try frame(index: 1, timestamp: 0.04, features: baseFeatures())
        let result = try FrameRegistrationEngine().register(currentFrame: current, against: nil)

        XCTAssertEqual(result.status, .referenceUnavailable)
        XCTAssertNil(result.transform)
        XCTAssertEqual(result.confidence, 0)
    }

    func testIncompatibleDimensionsAreRejected() throws {
        let reference = try RegistrationReferenceFrame(frame: referenceFrame(), minimumFeatureCount: 3)
        let current = try VisionFrame(
            sequenceIndex: 1,
            timestamp: 0.04,
            dimensions: try FrameDimensions(width: 1280, height: 720),
            orientation: .landscapeRight,
            content: .fixtureFeatures(baseFeatures())
        )

        let result = try FrameRegistrationEngine().register(currentFrame: current, against: reference)

        XCTAssertEqual(result.status, .failed)
        XCTAssertEqual(result.rejectionReason, .incompatibleDimensions)
        XCTAssertNil(result.transform)
    }

    func testInsufficientFeaturesAreRejected() throws {
        let result = try registrationResult(
            currentFeatures: [
                try RegistrationFeature(id: "top-left", point: try NormalizedImagePoint(x: 0.2, y: 0.2))
            ]
        )

        XCTAssertEqual(result.status, .failed)
        XCTAssertEqual(result.rejectionReason, .insufficientFeatures)
        XCTAssertNil(result.transform)
    }

    func testExcessiveMotionIsRejectedWithoutPretendingSuccess() throws {
        let result = try registrationResult(currentFeatures: translatedFeatures(dx: 0.3, dy: 0))

        XCTAssertEqual(result.status, .failed)
        XCTAssertEqual(result.rejectionReason, .excessiveMotion)
        XCTAssertNotNil(result.transform)
    }

    func testLowConfidenceRegistrationIsReported() throws {
        let configuration = try FrameRegistrationConfiguration(
            minimumFeatureCount: 3,
            maximumRootMeanSquareError: 0.03,
            minimumConfidence: 0.8
        )
        let result = try registrationResult(
            currentFeatures: [
                try RegistrationFeature(id: "top-left", point: try NormalizedImagePoint(x: 0.23, y: 0.2)),
                try RegistrationFeature(id: "top-right", point: try NormalizedImagePoint(x: 0.78, y: 0.18)),
                try RegistrationFeature(id: "bottom-right", point: try NormalizedImagePoint(x: 0.82, y: 0.78)),
                try RegistrationFeature(id: "bottom-left", point: try NormalizedImagePoint(x: 0.2, y: 0.8))
            ],
            configuration: configuration
        )

        XCTAssertEqual(result.status, .lowConfidence)
        XCTAssertEqual(result.rejectionReason, .qualityBelowThreshold)
        XCTAssertNotNil(result.rootMeanSquareError)
    }

    private func registrationResult(
        currentFeatures: [RegistrationFeature],
        configuration: FrameRegistrationConfiguration = .default
    ) throws -> FrameRegistrationResult {
        try FrameRegistrationEngine(configuration: configuration).register(
            currentFrame: frame(index: 1, timestamp: 0.04, features: currentFeatures),
            against: RegistrationReferenceFrame(frame: referenceFrame(), minimumFeatureCount: configuration.minimumFeatureCount)
        )
    }

    private func referenceFrame() throws -> VisionFrame {
        try frame(index: 0, timestamp: 0, features: baseFeatures())
    }

    private func frame(index: Int, timestamp: TimeInterval, features: [RegistrationFeature]) throws -> VisionFrame {
        try VisionFrame(
            sequenceIndex: index,
            timestamp: timestamp,
            dimensions: try FrameDimensions(width: 1920, height: 1080),
            orientation: .landscapeRight,
            content: .fixtureFeatures(features)
        )
    }

    private func baseFeatures() throws -> [RegistrationFeature] {
        [
            try RegistrationFeature(id: "top-left", point: try NormalizedImagePoint(x: 0.2, y: 0.2)),
            try RegistrationFeature(id: "top-right", point: try NormalizedImagePoint(x: 0.8, y: 0.2)),
            try RegistrationFeature(id: "bottom-right", point: try NormalizedImagePoint(x: 0.8, y: 0.8)),
            try RegistrationFeature(id: "bottom-left", point: try NormalizedImagePoint(x: 0.2, y: 0.8))
        ]
    }

    private func translatedFeatures(dx: Double, dy: Double) throws -> [RegistrationFeature] {
        try baseFeatures().map { feature in
            try RegistrationFeature(
                id: feature.id,
                point: try NormalizedImagePoint(x: feature.point.x + dx, y: feature.point.y + dy)
            )
        }
    }

    private func rotatedFeatures(radians: Double) throws -> [RegistrationFeature] {
        try baseFeatures().map { feature in
            let x = feature.point.x - 0.5
            let y = feature.point.y - 0.5
            let rotatedX = cos(radians) * x - sin(radians) * y + 0.5
            let rotatedY = sin(radians) * x + cos(radians) * y + 0.5

            return try RegistrationFeature(
                id: feature.id,
                point: try NormalizedImagePoint(x: rotatedX, y: rotatedY)
            )
        }
    }
}
