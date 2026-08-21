import XCTest
@testable import RangeSightCore

final class ReleaseHardeningTests: XCTestCase {
    func testReleaseGateBlocksKnownP0AndP1Defects() throws {
        let p1 = try ReleaseDefect(id: "camera-unrecoverable", severity: .p1, summary: "Camera workflow cannot recover.")
        let p2 = try ReleaseDefect(id: "minor-layout", severity: .p2, summary: "History layout needs device review.")

        XCTAssertEqual(
            ReleaseGateEvaluator.verdict(for: [p1, p2], hasPhysicalDeviceValidation: true),
            .notReady
        )
    }

    func testReleaseGateAllowsInternalOnlyWithoutPhysicalValidation() throws {
        let p2 = try ReleaseDefect(id: "range-validation-pending", severity: .p2, summary: "Physical validation still pending.")

        XCTAssertEqual(
            ReleaseGateEvaluator.verdict(for: [p2], hasPhysicalDeviceValidation: false),
            .readyForInternalTestFlightOnly
        )
    }

    func testPermissionCopyProvidesRecoveryGuidance() {
        XCTAssertEqual(
            ReleasePermissionCopy.cameraMessage(for: .denied),
            "Camera access is required to monitor a target. Enable Camera in Settings."
        )
        XCTAssertEqual(
            ReleasePermissionCopy.microphoneMessage(for: .denied),
            "Audio Assist is unavailable. Visual detection will continue."
        )
        XCTAssertEqual(
            ReleasePermissionCopy.audioCaptureMessage(for: .failed("native failure")),
            "Audio Assist could not start. Visual detection will continue."
        )
    }

    func testPrivacyDisclosureStatesLocalFirstBehaviorWithoutOverclaiming() {
        XCTAssertTrue(ReleasePrivacyDisclosure.allCopy.contains(ReleasePrivacyDisclosure.onDeviceAnalysis))
        XCTAssertTrue(ReleasePrivacyDisclosure.allCopy.contains(ReleasePrivacyDisclosure.cameraRetention))
        XCTAssertTrue(ReleasePrivacyDisclosure.allCopy.contains(ReleasePrivacyDisclosure.audioRetention))
        XCTAssertTrue(ReleasePrivacyDisclosure.allCopy.contains(ReleasePrivacyDisclosure.offlineUse))
        XCTAssertTrue(ReleasePrivacyDisclosure.allCopy.contains(ReleasePrivacyDisclosure.exports))
    }
}
