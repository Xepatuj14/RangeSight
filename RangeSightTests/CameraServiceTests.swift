import XCTest
@testable import RangeSightCore

final class CameraServiceTests: XCTestCase {
    func testCameraAuthorizationStatesAreStableDomainValues() {
        XCTAssertEqual(CameraAuthorizationState.notDetermined, .notDetermined)
        XCTAssertEqual(CameraAuthorizationState.authorized, .authorized)
        XCTAssertEqual(CameraAuthorizationState.denied, .denied)
        XCTAssertEqual(CameraAuthorizationState.restricted, .restricted)
    }

    func testCameraSessionFailuresAreEquatable() {
        XCTAssertEqual(CameraSessionFailure.cameraUnavailable, .cameraUnavailable)
        XCTAssertEqual(CameraSessionFailure.cannotAddInput, .cannotAddInput)
        XCTAssertEqual(CameraSessionFailure.cannotAddOutput, .cannotAddOutput)
    }
}
