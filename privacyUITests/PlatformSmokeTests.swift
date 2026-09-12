import XCTest
import UIKit

final class PlatformSmokeTests: XCTestCase {
    @MainActor
    func testSecuredRootLaunches() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))
        let predicate = NSPredicate { _, _ in
            ["vault.root", "onboarding.root", "lock.root"].contains {
                app.descendants(matching: .any)[$0].exists
            }
        }
        expectation(for: predicate, evaluatedWith: app)
        waitForExpectations(timeout: 20)
    }

    @MainActor
    func testIPadLandscapeKeepsSecuredRoot() throws {
        #if targetEnvironment(macCatalyst)
        throw XCTSkip("iPad orientation applies only to the mobile host.")
        #else
        let app = XCUIApplication()
        app.launch()
        guard UIDevice.current.userInterfaceIdiom == .pad else { throw XCTSkip("Requires iPad.") }
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))
        XCTAssertTrue(["vault.root", "onboarding.root", "lock.root"].contains {
            app.descendants(matching: .any)[$0].exists
        })
        #endif
    }

    @MainActor
    func testImportCanCloseOnUnlockedHost() throws {
        let app = XCUIApplication()
        app.launch()
        guard app.buttons["Import"].waitForExistence(timeout: 10) else {
            throw XCTSkip("Requires an already unlocked test host; authentication is never bypassed.")
        }
        app.buttons["Import"].firstMatch.tap()
        XCTAssertTrue(app.buttons["import.close"].waitForExistence(timeout: 5))
        app.buttons["import.close"].tap()
        XCTAssertFalse(app.buttons["import.close"].exists)
    }
}
