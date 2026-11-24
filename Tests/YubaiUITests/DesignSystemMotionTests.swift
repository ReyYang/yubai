#if os(iOS)
import XCTest

final class DesignSystemMotionTests: YubaiUITestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testGalleryMotionAcceptance() {
        let app = XCUIApplication()
        app.launchArguments = ["-YubaiDesignSystemGallery", "--test-ledger", UUID().uuidString,
                               "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launchEnvironment["YUBAI_UI_TEST_SCRIPT"] = "empty"
        app.launchEnvironment["YUBAI_UI_TEST_REDUCE_MOTION"] = "0"
        app.launchEnvironment["YUBAI_UI_TEST_NOW"] = "1795478400"
        app.launchEnvironment["DEEPSEEK_API_KEY"] = ""
        // launchApp adds the existing stall watchdog; animations stay enabled.
        guard launchApp(app) else { return }
        let jump = app.buttons["ds-gallery-show-motion"]
        XCTAssertTrue(jump.waitForExistence(timeout: 10)); jump.tap()
        let scroll = app.scrollViews["ds-gallery-scroll"]
        func reveal(_ element: XCUIElement) {
            for _ in 0..<8 {
                if element.exists && element.isHittable { return }
                scroll.swipeUp()
            }
            XCTAssertTrue(element.isHittable, "Unreachable gallery control: \(element.identifier)")
        }
        // Individual taps move right; play-all reverses all four. Expected run time: about 30s.
        for spring in ["snappy", "smooth", "standard", "bouncy"] {
            let button = app.buttons["ds-motion-\(spring)"]
            reveal(button)
            button.tap(); settle(1.5)
        }
        let all = app.buttons["ds-motion-all"]
        reveal(all); all.tap(); settle(1.5)
        let press = app.buttons["ds-motion-press"]
        reveal(press); press.press(forDuration: 1); settle(0.5)
        let number = app.buttons["ds-motion-number"]
        reveal(number)
        for _ in 0..<3 { number.tap(); settle(0.4) }
        XCTAssertEqual(number.value as? String, "45")
        app.buttons["ds-gallery-open-sheet"].tap(); settle(2)
        let amount = app.staticTexts["ds-gallery-sheet-amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        app.otherElements["ds-gallery-sheet"].firstMatch.swipeDown(velocity: .slow)
        settle(2)
        XCTAssertFalse(amount.exists)
        let toggle = app.switches["ds-motion-switch"]
        reveal(toggle)
        let before = toggle.value as? String
        // iOS 26 includes the label in the switch frame; tap the trailing control.
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap(); settle(1.5)
        XCTAssertNotEqual(toggle.value as? String, before)
        let accordion = app.buttons["ds-accordion-motion-shopping"]
        reveal(accordion)
        accordion.tap(); settle(1.5)
        XCTAssertEqual(accordion.value as? String, "展开")
        reveal(accordion)
        accordion.tap(); settle(1.5)
        XCTAssertEqual(accordion.value as? String, "收起")
    }

    private func settle(_ seconds: TimeInterval) {
        let pause = XCTestExpectation(description: "Spring presentation window")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { pause.fulfill() }
        XCTAssertEqual(XCTWaiter.wait(for: [pause], timeout: seconds + 1), .completed)
    }
}
#endif
