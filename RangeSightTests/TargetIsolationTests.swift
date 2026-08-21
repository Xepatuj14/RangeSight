import XCTest
@testable import RangeSightCore

final class TargetIsolationTests: XCTestCase {
    func testOutsideROIChangeProducesNoCandidatesOrImpacts() throws {
        var processor = try processor()
        let outcome = try processor.process(frame(index: 1, changes: [(targetB, [(4, 4), (5, 4)])]))

        XCTAssertEqual(outcome.status, .monitoring)
        XCTAssertEqual(outcome.changeResult?.candidates, [])
        XCTAssertEqual(outcome.newImpactEvents, [])
        XCTAssertEqual(outcome.isolatedFrame?.dimensions, try FrameDimensions(width: 10, height: 10))
    }

    func testAdjacentTargetChangeWithAudioProducesNoImpact() throws {
        var processor = try processor(audio: true)
        processor.recordAudioImpulse(try audioImpulse(id: "neighbor-shot", timestamp: 0.04))
        let outcome = try processor.process(frame(index: 1, timestamp: 0.05, changes: [(targetB, [(3, 3), (4, 3)])]))

        XCTAssertEqual(outcome.changeResult?.candidates, [])
        XCTAssertEqual(outcome.newImpactEvents, [])
    }

    func testOwnTargetPersistentChangeProducesOneImpactWithAudioSupport() throws {
        var processor = try processor(audio: true)
        processor.recordAudioImpulse(try audioImpulse(id: "own-shot", timestamp: 0.04))

        _ = try processor.process(frame(index: 1, timestamp: 0.05, changes: [(targetA, ownImpactPixels)]))
        _ = try processor.process(frame(index: 2, timestamp: 0.09, changes: [(targetA, ownImpactPixels)]))
        let outcome = try processor.process(frame(index: 3, timestamp: 0.13, changes: [(targetA, ownImpactPixels)]))

        XCTAssertEqual(outcome.newImpactEvents.count, 1)
        let event = try XCTUnwrap(outcome.newImpactEvents.first)
        XCTAssertTrue(event.audioAssisted)
        XCTAssertEqual(event.supportingAudioEventID, "own-shot")
        XCTAssertEqual(event.normalizedCoordinate.x, 0.45, accuracy: 0.000001)
        XCTAssertEqual(event.normalizedCoordinate.y, 0.5, accuracy: 0.000001)
    }

    func testBothTargetsChangingEmitsOnlyLockedTargetImpact() throws {
        var processor = try processor()
        let changes = [(targetA, ownImpactPixels), (targetB, [(2, 2), (3, 2), (2, 3), (3, 3)])]

        _ = try processor.process(frame(index: 1, changes: changes))
        _ = try processor.process(frame(index: 2, changes: changes))
        let outcome = try processor.process(frame(index: 3, changes: changes))

        XCTAssertEqual(outcome.newImpactEvents.count, 1)
        let event = try XCTUnwrap(outcome.newImpactEvents.first)
        XCTAssertEqual(event.normalizedCoordinate.x, 0.45, accuracy: 0.000001)
        XCTAssertEqual(event.normalizedCoordinate.y, 0.5, accuracy: 0.000001)
    }

    func testTargetReplacementFailsContinuityAndTransitionsToTargetLost() throws {
        let configuration = try TargetIsolationConfiguration(
            normalizedROIMargin: 0,
            minimumROIDimensions: try FrameDimensions(width: 4, height: 4),
            maximumConsecutiveIdentityFailuresBeforeTargetLost: 2
        )
        var processor = try processor(configuration: configuration)

        let first = try processor.process(frame(index: 1, replacementFeaturesInLockedROI: true))
        let second = try processor.process(frame(index: 2, replacementFeaturesInLockedROI: true))

        XCTAssertEqual(first.status, .skippedFrame)
        XCTAssertEqual(first.newImpactEvents, [])
        XCTAssertEqual(second.status, .targetLost)
        XCTAssertEqual(second.newImpactEvents, [])
        XCTAssertTrue(processor.isTargetLost)
        XCTAssertTrue(processor.targetLostEscapes.canReLockTarget)
        XCTAssertTrue(processor.targetLostEscapes.canEndString)
    }

    func testMinorCameraMovementContinuesMonitoring() throws {
        var processor = try processor()
        let outcome = try processor.process(frame(index: 1, translatedFeatureDX: 0.01))

        XCTAssertEqual(outcome.status, .monitoring)
        XCTAssertEqual(outcome.registration?.status, .registered)
        XCTAssertFalse(processor.isTargetLost)
    }

    func testRelockSameTargetPreservesKnownImpactSuppression() throws {
        var processor = try processor()

        _ = try processor.process(frame(index: 1, changes: [(targetA, ownImpactPixels)]))
        _ = try processor.process(frame(index: 2, changes: [(targetA, ownImpactPixels)]))
        let confirmed = try processor.process(frame(index: 3, changes: [(targetA, ownImpactPixels)]))
        XCTAssertEqual(confirmed.newImpactEvents.count, 1)

        let newReference = try lockedReference(baseline: frame(index: 4, changes: [(targetA, ownImpactPixels)]))
        processor.reLockSameTarget(with: newReference)
        let rediscovered = try processor.process(frame(index: 5, changes: [(targetA, ownImpactPixels)]))

        XCTAssertEqual(rediscovered.newImpactEvents, [])
        XCTAssertEqual(rediscovered.temporalResult?.knownImpactCount, 1)
    }

    func testROILocalCoordinateMapsToFullFrameWithoutCropOffsetLeakage() throws {
        let reference = try lockedReference()
        let localPoint = try NormalizedImagePoint(x: 0.5, y: 0.5)
        let sourcePoint = try TargetROIMapper.sourcePoint(
            fromROILocalPoint: localPoint,
            region: reference.analysisRegion,
            sourceDimensions: reference.sourceDimensions
        )

        XCTAssertEqual(sourcePoint.x, 0.25, accuracy: 0.000001)
        XCTAssertEqual(sourcePoint.y, 0.5, accuracy: 0.000001)
    }

    func testROIEdgeBoundaryIsExplicit() throws {
        var processor = try processor()
        let outsideEdge = try processor.process(frame(index: 1, changes: [(targetB, [(0, 4), (0, 5)])]))
        let insideEdge = try processor.process(frame(index: 2, changes: [(targetA, [(9, 4), (9, 5)])]))

        XCTAssertEqual(outsideEdge.changeResult?.candidates, [])
        let changeResult = try XCTUnwrap(insideEdge.changeResult)
        XCTAssertEqual(changeResult.candidates.count, 1)
        let candidate = try XCTUnwrap(changeResult.candidates.first)
        XCTAssertEqual(candidate.centroid.x, 0.95, accuracy: 0.000001)
    }

    func testIsolationDiagnosticsExposeReferenceAndFailureStateWithoutRawFrames() throws {
        var processor = try processor()
        let outcome = try processor.process(frame(index: 1, changes: [(targetB, [(4, 4), (5, 4)])]))
        let diagnosticKeys = Set(outcome.diagnostics.visionDiagnostics.map(\.key))

        XCTAssertEqual(outcome.diagnostics.lockID, "lock-a")
        XCTAssertTrue(diagnosticKeys.contains("roiWidth"))
        XCTAssertTrue(diagnosticKeys.contains("registrationConfidence"))
        XCTAssertTrue(diagnosticKeys.contains("consecutiveIdentityFailures"))
    }

    private let ownImpactPixels = [(4, 4), (4, 5)]

    private var targetA: PixelRegion {
        try! PixelRegion(x: 0, y: 0, width: 10, height: 10)
    }

    private var targetB: PixelRegion {
        try! PixelRegion(x: 10, y: 0, width: 10, height: 10)
    }

    private func processor(
        configuration: TargetIsolationConfiguration = try! TargetIsolationConfiguration(
            normalizedROIMargin: 0,
            minimumROIDimensions: try! FrameDimensions(width: 4, height: 4),
            maximumConsecutiveIdentityFailuresBeforeTargetLost: 3
        ),
        audio: Bool = false
    ) throws -> TargetIsolatedLiveImpactProcessor {
        TargetIsolatedLiveImpactProcessor(
            reference: try lockedReference(configuration: configuration),
            configuration: configuration,
            audioAssistConfiguration: audio ? AudioAssistConfiguration.default : nil
        )
    }

    private func lockedReference(
        baseline: VisionFrame? = nil,
        configuration: TargetIsolationConfiguration = try! TargetIsolationConfiguration(
            normalizedROIMargin: 0,
            minimumROIDimensions: try! FrameDimensions(width: 4, height: 4),
            maximumConsecutiveIdentityFailuresBeforeTargetLost: 3
        )
    ) throws -> LockedTargetReference {
        try LockedTargetReference(
            id: "lock-a",
            assessment: targetLockAssessment(),
            baselineFullFrame: baseline ?? frame(index: 0),
            configuration: configuration
        )
    }

    private func targetLockAssessment() throws -> TargetLockAssessment {
        try TargetLockEvaluator.assess(
            source: .manual,
            quadrilateral: TargetQuadrilateral(
                topLeft: NormalizedImagePoint(x: 0, y: 0),
                topRight: NormalizedImagePoint(x: 0.5, y: 0),
                bottomRight: NormalizedImagePoint(x: 0.5, y: 1),
                bottomLeft: NormalizedImagePoint(x: 0, y: 1)
            ),
            qualityMetrics: ImageQualityMetrics(
                sharpness: 0.9,
                brightness: 0.5,
                clippedHighlightRatio: 0,
                clippedShadowRatio: 0,
                registrationFeatureCount: 4
            ),
            targetDimensions: nil,
            thresholds: TargetLockQualityThresholds(
                minimumTargetArea: 0.1,
                minimumSharpness: 0.1,
                minimumBrightness: 0.1,
                maximumBrightness: 0.9,
                maximumClippedRatio: 0.1,
                minimumRegistrationFeatureCount: 3
            )
        )
    }

    private func frame(
        index: Int,
        timestamp: TimeInterval? = nil,
        changes: [(PixelRegion, [(Int, Int)])] = [],
        translatedFeatureDX: Double = 0,
        replacementFeaturesInLockedROI: Bool = false
    ) throws -> VisionFrame {
        var pixels = Array(repeating: 0.45, count: 20 * 10)

        for y in 0..<10 {
            for x in 0..<20 {
                pixels[y * 20 + x] += Double((x + y) % 3) * 0.01
            }
        }

        for (region, changedPixels) in changes {
            for (localX, localY) in changedPixels {
                let x = region.x + localX
                let y = region.y + localY
                pixels[y * 20 + x] = 0.95
            }
        }

        return try VisionFrame(
            sequenceIndex: index,
            timestamp: timestamp ?? Double(index) * 0.04,
            dimensions: FrameDimensions(width: 20, height: 10),
            orientation: .landscapeLeft,
            content: .fixtureRegisteredFrame(
                RegisteredFrameFixture(
                    luminance: LuminanceFrame(width: 20, height: 10, pixels: pixels),
                    features: replacementFeaturesInLockedROI ? replacementFeatures() : features(dx: translatedFeatureDX)
                )
            )
        )
    }

    private func features(dx: Double = 0) throws -> [RegistrationFeature] {
        try [
            feature(id: "a-1", fullX: 2 + dx * 20, fullY: 2),
            feature(id: "a-2", fullX: 8 + dx * 20, fullY: 2),
            feature(id: "a-3", fullX: 2 + dx * 20, fullY: 8),
            feature(id: "a-4", fullX: 8 + dx * 20, fullY: 8),
            feature(id: "b-1", fullX: 12, fullY: 2),
            feature(id: "b-2", fullX: 18, fullY: 2),
            feature(id: "b-3", fullX: 12, fullY: 8),
            feature(id: "b-4", fullX: 18, fullY: 8)
        ]
    }

    private func replacementFeatures() throws -> [RegistrationFeature] {
        try [
            feature(id: "b-1", fullX: 2, fullY: 2),
            feature(id: "b-2", fullX: 8, fullY: 2),
            feature(id: "b-3", fullX: 2, fullY: 8),
            feature(id: "b-4", fullX: 8, fullY: 8)
        ]
    }

    private func feature(id: String, fullX: Double, fullY: Double) throws -> RegistrationFeature {
        try RegistrationFeature(
            id: id,
            point: NormalizedImagePoint(x: fullX / 20, y: fullY / 10)
        )
    }

    private func audioImpulse(id: String, timestamp: TimeInterval) throws -> AudioImpulseCandidate {
        try AudioImpulseCandidate(
            id: id,
            timestamp: timestamp,
            peakAmplitude: 0.9,
            rmsEnergy: 0.8,
            baselineEnergy: 0.1,
            energyRiseRatio: 8,
            strength: 1.2,
            source: .synthetic,
            diagnosticReason: .peakAndEnergyRise
        )
    }
}
