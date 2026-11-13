import XCTest

/// All walks and UI tests share the same bounded launch recovery. Only Xcode's
/// launch timeout is held for a retry; unrelated XCTest failures are recorded.
class YubaiUITestCase: XCTestCase {
    private var launching = false
    private var launchTimeouts: [XCTIssue] = []
    private var otherLaunchFailure = false

    override func record(_ issue: XCTIssue) {
        if launching && issue.compactDescription.contains("Timed out while launching application via Xcode") {
            launchTimeouts.append(issue)
            return
        }
        if launching { otherLaunchFailure = true }
        recordUIIssue(issue)
    }
    func recordUIIssue(_ issue: XCTIssue) { super.record(issue) }

    @discardableResult func launchApp(_ app: XCUIApplication, timeout: TimeInterval = 15) -> Bool {
        var lastTimeout: XCTIssue?
        for attempt in 0..<3 {
            launchTimeouts = []; otherLaunchFailure = false
            let previous = continueAfterFailure
            continueAfterFailure = true; launching = true
            app.launch()
            launching = false; continueAfterFailure = previous
            if otherLaunchFailure { return false }
            if let issue = launchTimeouts.last { lastTimeout = issue }
            if launchTimeouts.isEmpty && app.wait(for: .runningForeground, timeout: timeout) { return true }
            app.terminate()
            if attempt < 2 { print("Retrying Xcode launch (attempt \(attempt + 2)/3)") }
        }
        if let lastTimeout { recordUIIssue(lastTimeout) }
        else { XCTFail("Application did not reach the foreground after three launch attempts") }
        return false
    }

    /// Two independent snapshots must agree, with no fixed animation sleep.
    func waitForStableFrame(_ target: XCUIElement, timeout: TimeInterval = 6) -> Bool {
        var previous: CGRect?
        let condition = NSPredicate { _, _ in
            guard target.exists, let snapshot = try? target.snapshot(), !snapshot.frame.isEmpty else { previous = nil; return false }
            let frame = snapshot.frame
            defer { previous = frame }
            guard let previous else { return false }
            return abs(frame.minX - previous.minX) < 0.1 && abs(frame.minY - previous.minY) < 0.1 &&
                abs(frame.width - previous.width) < 0.1 && abs(frame.height - previous.height) < 0.1
        }
        return XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: condition, object: nil)], timeout: timeout) == .completed
    }

    /// The run-3 "Continue" belongs to this UIKit keyboard introduction, not
    /// Yubai. Scope the action to its system owner, independent of localization.
    @discardableResult func dismissKeyboardIntroduction(in app: XCUIApplication) -> Bool {
        let introduction = app.otherElements["UIContinuousPathIntroductionView"].firstMatch
        guard introduction.exists else { return true }
        let action = introduction.buttons.firstMatch
        guard action.exists && action.isHittable else { return false }
        action.tap()
        let closed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !introduction.exists }, object: nil)
        return XCTWaiter.wait(for: [closed], timeout: 4) == .completed
    }

    func typeIntoField(_ text: String, identifier: String, in app: XCUIApplication) {
        let field = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5), identifier)
        XCTAssertTrue(waitForStableFrame(field), identifier)
        field.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), identifier)
        XCTAssertTrue(dismissKeyboardIntroduction(in: app))
        field.typeText(text)
    }

    /// The native tree flattens navigationCapsule into mainNavigation. Its three
    /// real tab buttons are present on every root; their union plus the existing
    /// 6pt surface inset is exactly the capsule, excluding the home entry pill.
    func capsuleFrame(in app: XCUIApplication) -> CGRect {
        let tabs = ["tab_now", "tab_ledger", "tab_yubai"].map { app.buttons[$0] }
        for tab in tabs { XCTAssertTrue(tab.waitForExistence(timeout: 5), tab.identifier) }
        return tabs.map(\.frame).reduce(CGRect.null) { $0.union($1) }.insetBy(dx: -6, dy: -6)
    }
}
