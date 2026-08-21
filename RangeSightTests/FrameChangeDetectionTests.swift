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

    func testShiftedIdenticalImageProducesNoCandidatesAfterAlignment() throws {
        let result = try structuredChangeResult(
            currentPixels: shiftedStructuredPixels(dx: 2, dy: 0),
            currentFeatures: translatedFeatures(dx: 0.1, dy: 0)
        )

        XCTAssertEqual(result.status, .noChange)
        XCTAssertEqual(result.candidates, [])
        XCTAssertEqual(result.changedPixelRatio, 0, accuracy: 0.000001)
        XCTAssertEqual(result.validComparisonPixelRatio, 0.9, accuracy: 0.000001)
    }

    func testShiftedImageWithLocalizedChangeProducesOneAlignedCandidate() throws {
        let injectedReferenceCoordinates = [(x: 8, y: 9), (x: 9, y: 9), (x: 8, y: 10), (x: 9, y: 10)]
        var currentPixels = shiftedStructuredPixels(dx: 2, dy: 0)

        for coordinate in injectedReferenceCoordinates {
            currentPixels[coordinate.y * structuredWidth + coordinate.x + 2] = 0.05
        }

        let result = try structuredChangeResult(
            currentPixels: currentPixels,
            currentFeatures: translatedFeatures(dx: 0.1, dy: 0)
        )

        XCTAssertEqual(result.status, .localizedChangeDetected)
        XCTAssertEqual(result.candidates.count, 1)

        let candidate = try XCTUnwrap(result.candidates.first)
        XCTAssertEqual(candidate.areaPixels, 4)
        XCTAssertEqual(candidate.centroid.x, 0.45, accuracy: 0.000001)
        XCTAssertEqual(candidate.centroid.y, 0.5, accuracy: 0.000001)
    }

    func testExcessiveMotionSkipsChangeCandidates() throws {
        let reference = try structuredFrame(index: 0, timestamp: 0, pixels: structuredPixels(), features: features())
        let current = try structuredFrame(
            index: 1,
            timestamp: 0.04,
            pixels: shiftedStructuredPixels(dx: 5, dy: 0),
            features: translatedFeatures(dx: 0.2, dy: 0)
        )
        let referenceRegistration = try RegistrationReferenceFrame(frame: reference, minimumFeatureCount: 3)
        let registration = try FrameRegistrationEngine().register(currentFrame: current, against: referenceRegistration)

        XCTAssertEqual(registration.status, .failed)
        XCTAssertEqual(registration.rejectionReason, .excessiveMotion)

        let result = try FrameChangeDetector().detectChanges(
            referenceFrame: reference,
            currentFrame: current,
            registration: registration
        )

        XCTAssertEqual(result.status, .skippedDueToRegistration)
        XCTAssertEqual(result.candidates, [])
        XCTAssertEqual(result.validComparisonPixelRatio, 0)
    }

    func testNonOverlapEdgePixelsAreIgnoredAfterTranslation() throws {
        var currentPixels = shiftedStructuredPixels(dx: 2, dy: 0)

        for y in 0..<structuredHeight {
            currentPixels[y * structuredWidth + 0] = 0.98
            currentPixels[y * structuredWidth + 1] = 0.98
        }

        let result = try structuredChangeResult(
            currentPixels: currentPixels,
            currentFeatures: translatedFeatures(dx: 0.1, dy: 0)
        )

        XCTAssertEqual(result.status, .noChange)
        XCTAssertEqual(result.candidates, [])
        XCTAssertEqual(result.changedPixelRatio, 0, accuracy: 0.000001)
    }

    func testSmallRotationProducesNoFalseLocalizedCandidateAfterAlignment() throws {
        let radians = 0.04
        let currentToReferenceTransform = try RegistrationTransform(
            translationX: 0.5 - (cos(radians) * 0.5 - sin(radians) * 0.5),
            translationY: 0.5 - (sin(radians) * 0.5 + cos(radians) * 0.5),
            rotationRadians: radians,
            scale: 1
        )
        let currentPixels = try transformedStructuredPixels(currentToReferenceTransform: currentToReferenceTransform)

        let result = try structuredChangeResult(
            currentPixels: currentPixels,
            currentFeatures: rotatedFeatures(radians: -radians)
        )

        XCTAssertEqual(result.status, .noChange)
        XCTAssertEqual(result.candidates, [])
        XCTAssertLessThan(result.maximumMagnitude, 0.18)
    }

    func testSmallScaleProducesNoFalseLocalizedCandidateAfterAlignment() throws {
        let scale = 1.04
        let currentToReferenceTransform = try RegistrationTransform(
            translationX: 0.5 - scale * 0.5,
            translationY: 0.5 - scale * 0.5,
            rotationRadians: 0,
            scale: scale
        )
        let currentPixels = try transformedStructuredPixels(currentToReferenceTransform: currentToReferenceTransform)

        let result = try structuredChangeResult(
            currentPixels: currentPixels,
            currentFeatures: scaledFeatures(scale: 1 / scale)
        )

        XCTAssertEqual(result.status, .noChange)
        XCTAssertEqual(result.candidates, [])
        XCTAssertLessThan(result.maximumMagnitude, 0.18)
    }

    func testPersistentCandidateReachesHighConfidenceOnce() throws {
        var confirmer = TemporalImpactConfirmer()
        _ = try confirmer.process(temporalChangeResult(frame: 0, candidates: []))
        _ = try confirmer.process(temporalChangeResult(frame: 1, candidates: [temporalCandidate(frame: 1, x: 0.45, y: 0.5)]))
        _ = try confirmer.process(temporalChangeResult(frame: 2, candidates: [temporalCandidate(frame: 2, x: 0.452, y: 0.501)]))
        let result = try confirmer.process(temporalChangeResult(frame: 3, candidates: [temporalCandidate(frame: 3, x: 0.451, y: 0.499)]))

        XCTAssertEqual(result.highConfidenceCandidates.count, 1)
        XCTAssertEqual(result.emittedCandidates.filter { $0.state == .highConfidence }.count, 1)
        XCTAssertEqual(result.knownImpactCount, 1)
        XCTAssertEqual(result.highConfidenceCandidates.first?.observedFrameCount, 3)
    }

    func testTransientCandidateIsRejectedWithoutHighConfidence() throws {
        var confirmer = TemporalImpactConfirmer()
        let first = try confirmer.process(temporalChangeResult(frame: 1, candidates: [temporalCandidate(frame: 1, x: 0.45, y: 0.5)]))
        let second = try confirmer.process(temporalNoChangeResult(frame: 2))
        let third = try confirmer.process(temporalNoChangeResult(frame: 3))

        XCTAssertEqual(first.emittedCandidates.first?.confidenceBand, .low)
        XCTAssertTrue(second.emittedCandidates.contains { $0.state == .rejectedTransient })
        XCTAssertTrue(third.highConfidenceCandidates.isEmpty)
    }

    func testMovingCandidateDoesNotBecomeOneStableImpact() throws {
        var confirmer = TemporalImpactConfirmer()
        let first = try confirmer.process(temporalChangeResult(frame: 1, candidates: [temporalCandidate(frame: 1, x: 0.35, y: 0.5)]))
        let second = try confirmer.process(temporalChangeResult(frame: 2, candidates: [temporalCandidate(frame: 2, x: 0.45, y: 0.5)]))
        let third = try confirmer.process(temporalChangeResult(frame: 3, candidates: [temporalCandidate(frame: 3, x: 0.55, y: 0.5)]))

        let highCount = [first, second, third].flatMap(\.highConfidenceCandidates).count
        XCTAssertEqual(highCount, 0)
        XCTAssertEqual(third.knownImpactCount, 0)
    }

    func testKnownImpactSuppressesRediscoveredCandidate() throws {
        let known = try KnownImpact(
            id: "known-1",
            centroid: try NormalizedImagePoint(x: 0.45, y: 0.5),
            radius: 0.035,
            firstConfirmedFrameSequenceIndex: 10,
            firstConfirmedTimestamp: 0.4
        )
        var confirmer = TemporalImpactConfirmer(knownImpacts: [known])
        let result = try confirmer.process(temporalChangeResult(frame: 11, candidates: [temporalCandidate(frame: 11, x: 0.452, y: 0.501)]))

        XCTAssertEqual(result.emittedCandidates.count, 1)
        XCTAssertEqual(result.emittedCandidates.first?.state, .suppressedKnownImpact)
        XCTAssertEqual(result.emittedCandidates.first?.suppressionReason, .knownImpactOverlap)
        XCTAssertEqual(result.highConfidenceCandidates, [])
    }

    func testNearbyNewImpactOutsideSuppressionRadiusRemainsEligible() throws {
        let known = try KnownImpact(
            id: "known-1",
            centroid: try NormalizedImagePoint(x: 0.45, y: 0.5),
            radius: 0.035,
            firstConfirmedFrameSequenceIndex: 10,
            firstConfirmedTimestamp: 0.4
        )
        var confirmer = TemporalImpactConfirmer(knownImpacts: [known])
        _ = try confirmer.process(temporalChangeResult(frame: 11, candidates: [temporalCandidate(frame: 11, x: 0.50, y: 0.5)]))
        _ = try confirmer.process(temporalChangeResult(frame: 12, candidates: [temporalCandidate(frame: 12, x: 0.501, y: 0.5)]))
        let result = try confirmer.process(temporalChangeResult(frame: 13, candidates: [temporalCandidate(frame: 13, x: 0.499, y: 0.5)]))

        XCTAssertEqual(result.highConfidenceCandidates.count, 1)
        XCTAssertEqual(result.highConfidenceCandidates.first?.state, .highConfidence)
        XCTAssertEqual(result.knownImpactCount, 2)
    }

    func testConfidenceBandsProgressWithPersistenceAndQuality() throws {
        var confirmer = TemporalImpactConfirmer()
        let low = try confirmer.process(temporalChangeResult(frame: 1, candidates: [temporalCandidate(frame: 1, x: 0.45, y: 0.5)]))
        let medium = try confirmer.process(temporalChangeResult(frame: 2, candidates: [temporalCandidate(frame: 2, x: 0.451, y: 0.5)]))
        let high = try confirmer.process(temporalChangeResult(frame: 3, candidates: [temporalCandidate(frame: 3, x: 0.45, y: 0.501)]))

        XCTAssertEqual(low.emittedCandidates.first?.confidenceBand, .low)
        XCTAssertEqual(medium.emittedCandidates.first?.confidenceBand, .medium)
        XCTAssertEqual(high.emittedCandidates.first?.confidenceBand, .high)
    }

    func testWeakerAcceptedRegistrationLowersTemporalConfidence() throws {
        var strongConfirmer = TemporalImpactConfirmer()
        _ = try strongConfirmer.process(temporalChangeResult(frame: 1, candidates: [temporalCandidate(frame: 1, x: 0.45, y: 0.5, registrationConfidence: 1)]))
        _ = try strongConfirmer.process(temporalChangeResult(frame: 2, candidates: [temporalCandidate(frame: 2, x: 0.451, y: 0.5, registrationConfidence: 1)]))
        let strong = try strongConfirmer.process(temporalChangeResult(frame: 3, candidates: [temporalCandidate(frame: 3, x: 0.45, y: 0.501, registrationConfidence: 1)]))

        var weakerConfirmer = TemporalImpactConfirmer()
        _ = try weakerConfirmer.process(temporalChangeResult(frame: 1, candidates: [temporalCandidate(frame: 1, x: 0.45, y: 0.5, registrationConfidence: 0.65)]))
        _ = try weakerConfirmer.process(temporalChangeResult(frame: 2, candidates: [temporalCandidate(frame: 2, x: 0.451, y: 0.5, registrationConfidence: 0.65)]))
        let weaker = try weakerConfirmer.process(temporalChangeResult(frame: 3, candidates: [temporalCandidate(frame: 3, x: 0.45, y: 0.501, registrationConfidence: 0.65)]))

        let strongConfidence = try XCTUnwrap(strong.highConfidenceCandidates.first?.confidence)
        let weakerConfidence = try XCTUnwrap(weaker.highConfidenceCandidates.first?.confidence)
        XCTAssertLessThan(weakerConfidence, strongConfidence)
    }

    func testReplayHarnessExercisesTemporalConfirmationProcessor() async throws {
        let frames = [
            try structuredFrame(index: 0, timestamp: 0, pixels: structuredPixels(), features: features()),
            try structuredFrame(index: 1, timestamp: 0.04, pixels: structuredPixelsWithImpact(), features: features()),
            try structuredFrame(index: 2, timestamp: 0.08, pixels: structuredPixelsWithImpact(), features: features()),
            try structuredFrame(index: 3, timestamp: 0.12, pixels: structuredPixelsWithImpact(), features: features())
        ]

        let result = try await ReplayHarness.run(
            manifest: try ReplayManifest(id: "temporal-confirmation-fixture"),
            configuration: try ReplayRunConfiguration(algorithmVersion: "temporal-confirmation-slice-11"),
            frameSource: try ArrayReplayFrameSource(frames: frames),
            processor: TemporalConfirmationProcessor()
        )

        XCTAssertEqual(result.completionReason, .endOfStream)
        let finalStages = result.frameResults[3].events.map(\.stage)
        XCTAssertEqual(finalStages, [.frameRegistration, .changeMapGeneration, .temporalConfirmation])

        let temporalDiagnostics = try XCTUnwrap(result.frameResults[3].events.last?.diagnostics)
        let expectedHigh = try VisionFrameDiagnostic(key: "temporalHighConfidenceCount", value: 1)
        let expectedKnown = try VisionFrameDiagnostic(key: "temporalKnownImpactCount", value: 1)
        XCTAssertTrue(temporalDiagnostics.contains(expectedHigh))
        XCTAssertTrue(temporalDiagnostics.contains(expectedKnown))
    }

    func testLiveImpactSessionEmitsOrderedConfirmedEvents() throws {
        var session = LiveImpactSession()
        session.startString()

        _ = try session.process(liveTemporalResult(frame: 3, candidates: [liveTemporalCandidate(id: "impact-a", frame: 3, x: 0.42, y: 0.51, band: .high, state: .highConfidence)]))
        let second = try session.process(liveTemporalResult(frame: 6, candidates: [liveTemporalCandidate(id: "impact-b", frame: 6, x: 0.58, y: 0.48, band: .high, state: .highConfidence)]))

        XCTAssertEqual(second.totalEventCount, 2)
        XCTAssertEqual(session.orderedEvents.map(\.shotIndex), [1, 2])
        XCTAssertEqual(session.orderedEvents.map(\.temporalCandidateID), ["impact-a", "impact-b"])
        XCTAssertEqual(session.orderedEvents[0].normalizedCoordinate.x, 0.42, accuracy: 0.000001)
        XCTAssertEqual(session.orderedEvents[1].normalizedCoordinate.x, 0.58, accuracy: 0.000001)
    }

    func testLiveImpactSessionSuppressesDuplicateHighCandidateID() throws {
        var session = LiveImpactSession()
        session.startString()

        _ = try session.process(liveTemporalResult(frame: 3, candidates: [liveTemporalCandidate(id: "impact-a", frame: 3, x: 0.42, y: 0.51, band: .high, state: .highConfidence)]))
        let duplicate = try session.process(liveTemporalResult(frame: 4, candidates: [liveTemporalCandidate(id: "impact-a", frame: 4, x: 0.421, y: 0.511, band: .high, state: .highConfidence)]))

        XCTAssertEqual(duplicate.newEvents, [])
        XCTAssertEqual(session.orderedEvents.count, 1)
        XCTAssertEqual(session.orderedEvents.first?.shotIndex, 1)
    }

    func testLiveImpactSessionDoesNotEmitLowConfidenceShot() throws {
        var session = LiveImpactSession()
        session.startString()

        let outcome = try session.process(liveTemporalResult(frame: 2, candidates: [liveTemporalCandidate(id: "low-a", frame: 2, x: 0.45, y: 0.5, confidence: 0.42, band: .low, state: .lowConfidence)]))

        XCTAssertEqual(outcome.newEvents, [])
        XCTAssertEqual(outcome.totalEventCount, 0)
        XCTAssertEqual(session.orderedEvents, [])
    }

    func testLiveImpactSessionPreservesMediumCandidateWithoutShot() throws {
        var session = LiveImpactSession()
        session.startString()

        let outcome = try session.process(liveTemporalResult(frame: 2, candidates: [liveTemporalCandidate(id: "medium-a", frame: 2, x: 0.45, y: 0.5, confidence: 0.72, band: .medium, state: .mediumConfidence)]))

        XCTAssertEqual(outcome.newEvents, [])
        XCTAssertEqual(outcome.mediumConfidenceCandidates.count, 1)
        XCTAssertEqual(outcome.mediumConfidenceCandidates.first?.temporalCandidateID, "medium-a")
        XCTAssertEqual(session.orderedEvents, [])
    }

    func testLiveImpactSessionHandlesRegistrationFailureWithoutEvent() throws {
        var session = LiveImpactSession()
        session.startString()

        _ = try session.process(liveTemporalResult(frame: 1, candidates: []))
        let failure = try session.process(liveTemporalResult(frame: 2, candidates: [], skippedFrame: true))
        let recovered = try session.process(liveTemporalResult(frame: 3, candidates: [liveTemporalCandidate(id: "impact-a", frame: 3, x: 0.42, y: 0.51, band: .high, state: .highConfidence)]))

        XCTAssertEqual(failure.status, .degraded)
        XCTAssertEqual(failure.newEvents, [])
        XCTAssertEqual(failure.totalEventCount, 0)
        XCTAssertEqual(recovered.status, .monitoring)
        XCTAssertEqual(recovered.newEvents.count, 1)
        XCTAssertEqual(session.orderedEvents.count, 1)
        XCTAssertEqual(session.orderedEvents.first?.shotIndex, 1)
    }

    func testLiveImpactSessionIgnoresResultsAfterEndString() throws {
        var session = LiveImpactSession()
        session.startString()
        session.endString()

        let outcome = try session.process(liveTemporalResult(frame: 3, candidates: [liveTemporalCandidate(id: "impact-a", frame: 3, x: 0.42, y: 0.51, band: .high, state: .highConfidence)]))

        XCTAssertEqual(outcome.status, .ended)
        XCTAssertEqual(outcome.newEvents, [])
        XCTAssertEqual(session.orderedEvents, [])
    }

    func testLiveImpactSessionDropsOutOfOrderResults() throws {
        var session = LiveImpactSession()
        session.startString()

        _ = try session.process(liveTemporalResult(frame: 5, candidates: []))
        let old = try session.process(liveTemporalResult(frame: 4, candidates: [liveTemporalCandidate(id: "impact-a", frame: 4, x: 0.42, y: 0.51, band: .high, state: .highConfidence)]))

        XCTAssertTrue(old.droppedOutOfOrderResult)
        XCTAssertEqual(old.newEvents, [])
        XCTAssertEqual(session.orderedEvents, [])
    }

    func testLiveImpactSessionDoesNotEmitEventForAudioImpulseWithoutVisualChange() throws {
        var session = LiveImpactSession(audioAssistConfiguration: try AudioAssistConfiguration(preEventBufferDuration: 0.2, postEventVisualWindowDuration: 0.4))
        session.startString()
        session.recordAudioImpulse(try audioImpulse(id: "neighbor-lane", timestamp: 1))

        let outcome = try session.process(liveTemporalResult(frame: 10, timestamp: 1.1, candidates: []))

        XCTAssertEqual(session.bufferedAudioImpulses.map(\.id), ["neighbor-lane"])
        XCTAssertEqual(outcome.newEvents, [])
        XCTAssertEqual(outcome.totalEventCount, 0)
        XCTAssertEqual(session.orderedEvents, [])
    }

    func testLiveImpactSessionAllowsVisualOnlyEventWithoutAudioImpulse() throws {
        var session = LiveImpactSession(audioAssistConfiguration: try AudioAssistConfiguration(preEventBufferDuration: 0.2, postEventVisualWindowDuration: 0.4))
        session.startString()

        let outcome = try session.process(
            liveTemporalResult(
                frame: 10,
                timestamp: 1.2,
                candidates: [liveTemporalCandidate(id: "impact-visual", frame: 10, timestamp: 1.2, x: 0.45, y: 0.52, band: .high, state: .highConfidence)]
            )
        )

        XCTAssertEqual(outcome.newEvents.count, 1)
        XCTAssertFalse(try XCTUnwrap(outcome.newEvents.first).audioAssisted)
        XCTAssertNil(outcome.newEvents.first?.supportingAudioEventID)
        XCTAssertEqual(session.orderedEvents.count, 1)
    }

    func testLiveImpactSessionAttachesMatchedAudioSupportToVisualEvent() throws {
        var session = LiveImpactSession(audioAssistConfiguration: try AudioAssistConfiguration(preEventBufferDuration: 0.2, postEventVisualWindowDuration: 0.4))
        session.startString()
        session.recordAudioImpulse(try audioImpulse(id: "audio-a", timestamp: 1.0, strength: 1.7))

        let outcome = try session.process(
            liveTemporalResult(
                frame: 10,
                timestamp: 1.16,
                candidates: [liveTemporalCandidate(id: "impact-a", frame: 10, timestamp: 1.16, x: 0.45, y: 0.52, band: .high, state: .highConfidence)]
            )
        )

        let event = try XCTUnwrap(outcome.newEvents.first)
        XCTAssertTrue(event.audioAssisted)
        XCTAssertEqual(event.supportingAudioEventID, "audio-a")
        XCTAssertEqual(event.audioImpulseStrength, 1.7)
        XCTAssertEqual(event.confidenceBand, .high)
        XCTAssertEqual(event.source, .automaticVisualConfirmation)
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

    private var structuredWidth: Int {
        20
    }

    private var structuredHeight: Int {
        20
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

    private func structuredChangeResult(
        currentPixels: [Double],
        currentFeatures: [RegistrationFeature]
    ) throws -> ChangeDetectionResult {
        let reference = try structuredFrame(index: 0, timestamp: 0, pixels: structuredPixels(), features: features())
        let current = try structuredFrame(index: 1, timestamp: 0.04, pixels: currentPixels, features: currentFeatures)
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

    private func structuredPixels() -> [Double] {
        var pixels = Array(repeating: 0.2, count: structuredWidth * structuredHeight)

        for y in 4...15 {
            for x in 5...14 {
                pixels[y * structuredWidth + x] = 0.55
            }
        }

        for y in 7...12 {
            pixels[y * structuredWidth + 9] = 0.82
            pixels[y * structuredWidth + 10] = 0.82
        }

        for x in 6...13 {
            pixels[10 * structuredWidth + x] = 0.72
        }

        return pixels
    }

    private func structuredPixelsWithImpact() -> [Double] {
        var pixels = structuredPixels()

        for coordinate in [(x: 8, y: 9), (x: 9, y: 9), (x: 8, y: 10), (x: 9, y: 10)] {
            pixels[coordinate.y * structuredWidth + coordinate.x] = 0.05
        }

        return pixels
    }

    private func shiftedStructuredPixels(dx: Int, dy: Int) -> [Double] {
        let reference = structuredPixels()
        var shifted = Array(repeating: 0.2, count: structuredWidth * structuredHeight)

        for y in 0..<structuredHeight {
            for x in 0..<structuredWidth {
                let shiftedX = x + dx
                let shiftedY = y + dy

                guard (0..<structuredWidth).contains(shiftedX),
                      (0..<structuredHeight).contains(shiftedY) else {
                    continue
                }

                shifted[shiftedY * structuredWidth + shiftedX] = reference[y * structuredWidth + x]
            }
        }

        return shifted
    }

    private func transformedStructuredPixels(currentToReferenceTransform transform: RegistrationTransform) throws -> [Double] {
        let reference = try LuminanceFrame(width: structuredWidth, height: structuredHeight, pixels: structuredPixels())
        var transformed = Array(repeating: 0.2, count: structuredWidth * structuredHeight)

        for y in 0..<structuredHeight {
            for x in 0..<structuredWidth {
                let currentX = (Double(x) + 0.5) / Double(structuredWidth)
                let currentY = (Double(y) + 0.5) / Double(structuredHeight)
                let cosine = cos(transform.rotationRadians)
                let sine = sin(transform.rotationRadians)
                let referenceX = transform.scale * (cosine * currentX - sine * currentY) + transform.translationX
                let referenceY = transform.scale * (sine * currentX + cosine * currentY) + transform.translationY

                if let value = bilinearSample(reference, normalizedX: referenceX, normalizedY: referenceY) {
                    transformed[y * structuredWidth + x] = value
                }
            }
        }

        return transformed
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

    private func audioImpulse(id: String, timestamp: TimeInterval, strength: Double = 1) throws -> AudioImpulseCandidate {
        try AudioImpulseCandidate(
            id: id,
            timestamp: timestamp,
            peakAmplitude: 0.9,
            rmsEnergy: 0.22,
            baselineEnergy: 0.02,
            energyRiseRatio: 11,
            strength: strength,
            source: .synthetic,
            diagnosticReason: .peakAndEnergyRise
        )
    }

    private func structuredFrame(
        index: Int,
        timestamp: TimeInterval,
        pixels: [Double],
        features: [RegistrationFeature]
    ) throws -> VisionFrame {
        let luminance = try LuminanceFrame(width: structuredWidth, height: structuredHeight, pixels: pixels)

        return try VisionFrame(
            sequenceIndex: index,
            timestamp: timestamp,
            dimensions: try FrameDimensions(width: structuredWidth, height: structuredHeight),
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

    private func rotatedFeatures(radians: Double) throws -> [RegistrationFeature] {
        try features().map { feature in
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

    private func scaledFeatures(scale: Double) throws -> [RegistrationFeature] {
        try features().map { feature in
            let x = (feature.point.x - 0.5) * scale + 0.5
            let y = (feature.point.y - 0.5) * scale + 0.5

            return try RegistrationFeature(
                id: feature.id,
                point: try NormalizedImagePoint(x: x, y: y)
            )
        }
    }

    private func bilinearSample(_ frame: LuminanceFrame, normalizedX: Double, normalizedY: Double) -> Double? {
        let pixelX = normalizedX * Double(frame.width) - 0.5
        let pixelY = normalizedY * Double(frame.height) - 0.5

        guard pixelX >= 0, pixelX <= Double(frame.width - 1),
              pixelY >= 0, pixelY <= Double(frame.height - 1) else {
            return nil
        }

        let x0 = Int(floor(pixelX))
        let y0 = Int(floor(pixelY))
        let x1 = min(x0 + 1, frame.width - 1)
        let y1 = min(y0 + 1, frame.height - 1)
        let tx = pixelX - Double(x0)
        let ty = pixelY - Double(y0)
        let top = frame.luminanceAt(x: x0, y: y0) * (1 - tx) + frame.luminanceAt(x: x1, y: y0) * tx
        let bottom = frame.luminanceAt(x: x0, y: y1) * (1 - tx) + frame.luminanceAt(x: x1, y: y1) * tx

        return top * (1 - ty) + bottom * ty
    }

    private func temporalChangeResult(frame: Int, candidates: [ChangeCandidate]) throws -> ChangeDetectionResult {
        ChangeDetectionResult(
            status: candidates.isEmpty ? .noChange : .localizedChangeDetected,
            frameSequenceIndex: frame,
            frameTimestamp: Double(frame) * 0.04,
            changedPixelRatio: candidates.isEmpty ? 0 : 0.01,
            maximumMagnitude: candidates.map(\.magnitude).max() ?? 0,
            validComparisonPixelRatio: 1,
            candidates: candidates,
            registrationStatus: .registered
        )
    }

    private func temporalNoChangeResult(frame: Int) throws -> ChangeDetectionResult {
        try temporalChangeResult(frame: frame, candidates: [])
    }

    private func temporalCandidate(
        frame: Int,
        x: Double,
        y: Double,
        magnitude: Double = 0.72,
        contrast: Double = 0.72,
        registrationConfidence: Double = 1
    ) throws -> ChangeCandidate {
        let halfSize = 0.01
        return try ChangeCandidate(
            id: "candidate-\(frame)-\(x)-\(y)",
            frameSequenceIndex: frame,
            frameTimestamp: Double(frame) * 0.04,
            bounds: try NormalizedImageRegion(
                minX: max(0, x - halfSize),
                minY: max(0, y - halfSize),
                maxX: min(1, x + halfSize),
                maxY: min(1, y + halfSize)
            ),
            centroid: try NormalizedImagePoint(x: x, y: y),
            areaPixels: 4,
            magnitude: magnitude,
            contrast: contrast,
            registrationConfidence: registrationConfidence
        )
    }

    private func liveTemporalResult(
        frame: Int,
        timestamp: TimeInterval? = nil,
        candidates: [TemporalImpactCandidate],
        skippedFrame: Bool = false
    ) -> TemporalConfirmationResult {
        TemporalConfirmationResult(
            frameSequenceIndex: frame,
            frameTimestamp: timestamp ?? Double(frame) * 0.04,
            rawCandidateCount: candidates.count,
            emittedCandidates: candidates,
            activeTrackCount: 0,
            knownImpactCount: candidates.filter { $0.state == .highConfidence }.count,
            skippedFrame: skippedFrame
        )
    }

    private func liveTemporalCandidate(
        id: String,
        frame: Int,
        timestamp: TimeInterval? = nil,
        x: Double,
        y: Double,
        confidence: Double = 0.93,
        band: TemporalConfidenceBand,
        state: TemporalCandidateState
    ) throws -> TemporalImpactCandidate {
        try TemporalImpactCandidate(
            id: id,
            sourceCandidateID: "source-\(id)",
            state: state,
            centroid: try NormalizedImagePoint(x: x, y: y),
            bounds: try NormalizedImageRegion(
                minX: max(0, x - 0.01),
                minY: max(0, y - 0.01),
                maxX: min(1, x + 0.01),
                maxY: min(1, y + 0.01)
            ),
            firstObservedFrameSequenceIndex: max(0, frame - 2),
            lastObservedFrameSequenceIndex: frame,
            firstObservedTimestamp: timestamp.map { max(0, $0 - 0.08) } ?? Double(max(0, frame - 2)) * 0.04,
            lastObservedTimestamp: timestamp ?? Double(frame) * 0.04,
            observedFrameCount: state == .lowConfidence ? 1 : 3,
            consecutiveObservationCount: state == .lowConfidence ? 1 : 3,
            missedFrameCount: 0,
            maximumCentroidDrift: 0.002,
            confidence: confidence,
            confidenceBand: band
        )
    }
}
