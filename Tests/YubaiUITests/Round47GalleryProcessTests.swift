import XCTest

final class Round47GalleryProcessTests: XCTestCase {
    func testInitialNotRunningStateIsNotACrash() {
        var history = GalleryProcessHistory()
        XCTAssertNil(history.observeStopped())
    }
    func testDeathAtCaptureBelongsToCorrectionAndIsRecordedOnce() {
        var history = GalleryProcessHistory()
        history.launched(in: "Correction")
        XCTAssertEqual(history.observeStopped(), "Correction")
        XCTAssertNil(history.observeStopped())
    }
    func testDelayedCrashDoesNotMoveToYearlyAfterHealthyRelaunch() {
        var history = GalleryProcessHistory()
        history.launched(in: "Correction")
        XCTAssertEqual(history.observeStopped(), "Correction")
        history.launched(in: "Mismatch")
        history.launched(in: "Yearly")
        XCTAssertEqual(history.crashOwner(fallback: "Yearly"), "Correction")
    }
    func testHealthyIntentionalRelaunchDoesNotCreatePendingCrash() {
        var history = GalleryProcessHistory()
        history.launched(in: "Correction")
        history.launched(in: "Yearly")
        XCTAssertEqual(history.crashOwner(fallback: "Yearly"), "Yearly")
    }
    func testStopsReusingAProcessUpdateItsOwner() {
        var history = GalleryProcessHistory()
        history.launched(in: "Evidence")
        history.enterStop("Correction")
        XCTAssertEqual(history.observeStopped(), "Correction")
    }
    func testSeveralDelayedCrashesRetainTheirProcessOrder() {
        var history = GalleryProcessHistory()
        history.launched(in: "First")
        XCTAssertEqual(history.observeStopped(), "First")
        history.launched(in: "Second")
        XCTAssertEqual(history.observeStopped(), "Second")
        history.launched(in: "Third")
        XCTAssertEqual(history.crashOwner(fallback: "Third"), "First")
        XCTAssertEqual(history.crashOwner(fallback: "Third"), "Second")
    }
}
