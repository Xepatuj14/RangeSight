import XCTest
@testable import RangeSightCore

final class NavigationStateTests: XCTestCase {
    func testAllScreensHaveActionsAndUniqueIDs() {
        var ids = Set<AppScreenID>()

        for screen in AppNavigation.screens {
            XCTAssertFalse(ids.contains(screen.id), "Duplicate screen id: \(screen.id)")
            ids.insert(screen.id)
            XCTAssertFalse(screen.title.isEmpty)
            XCTAssertFalse(screen.actions.isEmpty)

            for action in screen.actions {
                XCTAssertNotNil(AppNavigation.action(from: screen.id, to: action.destination))
            }
        }

        XCTAssertEqual(AppNavigation.screen(for: .home).id, .home)
        XCTAssertNil(AppNavigation.action(from: .home, to: .liveMonitor))
    }
}
