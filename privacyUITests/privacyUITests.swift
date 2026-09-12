//
//  privacyUITests.swift
//  privacyUITests
//
//  Created by PangHuang on 5/17/26.
//

import XCTest

final class privacyUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testExample() throws {
        // UI tests must launch the application that they test.
        let app = XCUIApplication()
        app.launch()

        // Use XCTAssert and related functions to verify your tests produce the correct results.
        // XCUIAutomation Documentation
        // https://developer.apple.com/documentation/xcuiautomation
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}

// Temporary review capture automation; removed after capture.
extension privacyUITests {
    @MainActor
    func testReviewCapture() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-review-membership-capture", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 60))
        sleep(15)
        print("REVIEW_UI_START\n" + app.debugDescription + "\nREVIEW_UI_END")
        let top = XCTAttachment(screenshot: app.screenshot()); top.name = "membership-overview"; top.lifetime = .keepAlways; add(top)
        app.swipeUp()
        sleep(2)
        print("REVIEW_PLANS_START\n" + app.debugDescription + "\nREVIEW_PLANS_END")
        let plans = XCTAttachment(screenshot: app.screenshot()); plans.name = "membership-plans"; plans.lifetime = .keepAlways; add(plans)
    }
}
