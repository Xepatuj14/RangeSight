import XCTest
@testable import RangeSightCore

final class SessionStateTests: XCTestCase {
    func testDocumentedSessionStatePath() {
        XCTAssertEqual(SessionStateMachine.nextState(from: .idle, event: .beginSetup), .setup)
        XCTAssertEqual(SessionStateMachine.nextState(from: .setup, event: .startPreview), .preview)
        XCTAssertEqual(SessionStateMachine.nextState(from: .preview, event: .lockTarget), .locked)
        XCTAssertEqual(SessionStateMachine.nextState(from: .locked, event: .startString), .monitoring)
        XCTAssertEqual(SessionStateMachine.nextState(from: .monitoring, event: .endString), .reviewing)
        XCTAssertEqual(SessionStateMachine.nextState(from: .reviewing, event: .save), .saved)
    }

    func testInvalidTransitionsReturnNil() {
        XCTAssertNil(SessionStateMachine.nextState(from: .idle, event: .startString))
        XCTAssertNil(SessionStateMachine.nextState(from: .saved, event: .startString))
    }

    func testRepeatedSessionActionsAreRejectedAfterStateHasAdvanced() {
        XCTAssertNil(SessionStateMachine.nextState(from: .monitoring, event: .startString))
        XCTAssertNil(SessionStateMachine.nextState(from: .reviewing, event: .endString))
        XCTAssertNil(SessionStateMachine.nextState(from: .saved, event: .save))
        XCTAssertNil(SessionStateMachine.nextState(from: .saved, event: .endString))
    }
}
