import Foundation
import XCTest
@testable import RangeSightCore

final class ProcessFlowTests: XCTestCase {
    func testDefaultTimeoutPoliciesAreOperationSpecific() throws {
        let policies = Dictionary(uniqueKeysWithValues: ReleaseTimeoutPolicy.defaults.map { ($0.operation, $0) })

        XCTAssertEqual(policies[.cameraStartup]?.duration, 8)
        XCTAssertEqual(policies[.targetLockAttempt]?.duration, 5)
        XCTAssertEqual(policies[.baselineAcquisition]?.duration, 8)
        XCTAssertNil(policies[.persistenceSave]?.duration)
        XCTAssertNil(policies[.validationExport]?.duration)
    }

    func testActiveStringHasNoInactivityTimeoutPolicy() {
        XCTAssertFalse(ReleaseFlowOperation.allCases.contains { $0.rawValue.contains("activeString") })
        XCTAssertFalse(ReleaseTimeoutPolicy.defaults.contains { $0.reason.localizedCaseInsensitiveContains("shot timeout") })
    }

    func testEveryAuditedUserFacingStateHasBoundedTransitionOrEscapeAction() {
        XCTAssertTrue(ReleaseFlowAudit.satisfiesUserEscapeInvariant)
        XCTAssertTrue(ReleaseFlowAudit.userEscapes.contains { $0.state == .monitoring && $0.escapeActions.contains("End String") })
        XCTAssertTrue(ReleaseFlowAudit.userEscapes.contains { $0.state == .monitoringDegraded && $0.escapeActions.contains("End String") })
        XCTAssertTrue(ReleaseFlowAudit.userEscapes.contains { $0.state == .cameraStarting && $0.automaticTransition == "Camera startup timeout" })
    }

    func testSaveFlowRejectsDoubleSaveAndPreservesFailureRetryPath() {
        XCTAssertEqual(ReleaseSaveFlow.nextState(from: .review, event: .saveTapped), .saving)
        XCTAssertNil(ReleaseSaveFlow.nextState(from: .saving, event: .saveTapped))
        XCTAssertEqual(ReleaseSaveFlow.nextState(from: .saving, event: .saveFailed), .failed)
        XCTAssertEqual(ReleaseSaveFlow.nextState(from: .failed, event: .retry), .saving)
        XCTAssertEqual(ReleaseSaveFlow.nextState(from: .failed, event: .discard), .discarded)
        XCTAssertNil(ReleaseSaveFlow.nextState(from: .saved, event: .saveTapped))
    }

    func testCameraStartupTimeoutHasUserSafeRecoveryCopy() {
        XCTAssertEqual(
            ReleasePermissionCopy.cameraSessionMessage(for: .startupTimedOut),
            "Camera didn't start. Try again or go back to setup."
        )
    }
}
