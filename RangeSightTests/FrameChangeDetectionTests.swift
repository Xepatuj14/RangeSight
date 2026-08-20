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
            features: translatedFeatures(dx: 0.25, dy: 0)
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
}
