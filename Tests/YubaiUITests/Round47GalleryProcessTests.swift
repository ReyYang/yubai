import XCTest

final class Round47GalleryProcessTests: XCTestCase {
    func testReviewedFixedAmountWarningCoversOnlyTheTwoStopsInEveryGalleryMode() {
        for mode in ["light", "dark", "hidden", "a11y"] {
            for stop in ["Spend-Edit-Saving", "Spend-Edit-Deficit"] {
                let name = "V47-\(mode)-\(stop)"
                let frame = mode == "a11y" ? "{x=24.0,y=234.7,w=392.0,h=72.3}" : "{x=31.1,y=523.0,w=186.9,h=44.0}"
                let description = "identifier=savingMode_fixed label=固定金额 frame=" + frame
                let audit = "Text of this SwiftUI.AccessibilityNode may be clipped at larger Dynamic Type sizes."
                let warning = GalleryTextReview.warning(stop: name, identifier: "savingMode_fixed", label: "固定金额",
                    kind: .button, elementDescription: description, auditText: audit)
                XCTAssertEqual(warning, name + ": Text clipped: PNG-reviewed complete fixed-amount label at largest size; " + description + " " + audit)
            }
        }
    }
    func testReviewedPaydayTitleWarningCoversOnlyTheThreeReviewedModes() {
        for mode in ["light", "dark", "hidden"] {
            let name = "V47-\(mode)-First-After-Setup"
            let description = "identifier= label=哪天发工资 frame={x=181.6,y=503.4,w=76.8,h=18.6}"
            let warning = GalleryTextReview.warning(stop: name, identifier: "", label: "哪天发工资", kind: .text,
                elementDescription: description, auditText: "native audit text")
            XCTAssertEqual(warning, name + ": Text clipped: PNG-reviewed complete payday sheet title; " + description + " native audit text")
        }
    }
    func testReviewedTextCannotHideDifferentLabelsIdentifiersOrElementKinds() {
        for (identifier, label, kind) in [
            ("savingMode_share", "每笔进账留几成", GalleryTextReview.Kind.button),
            ("savingMode_fixed", "固定金额…", .button),
            ("savingMode_fixed", "每笔进账留几成", .button),
            ("", "固定金额", .button),
            ("savingMode_fixed", "固定金额", .text),
            ("savingMode_fixed", "固定金额", .other)
        ] {
            XCTAssertNil(GalleryTextReview.warning(stop: "V47-light-Spend-Edit-Saving", identifier: identifier,
                label: label, kind: kind, elementDescription: "frame=...", auditText: "audit"))
        }
        for (identifier, label, kind) in [("paydayTitle", "哪天发工资", GalleryTextReview.Kind.text),
                                         ("", "哪天发工资…", .text), ("", "哪天发工资", .button), ("", "哪天发工资", .other)] {
            XCTAssertNil(GalleryTextReview.warning(stop: "V47-light-First-After-Setup", identifier: identifier,
                label: label, kind: kind, elementDescription: "frame=...", auditText: "audit"))
        }
    }
    func testReviewedTextCannotMatchOtherStopsOrFutureModes() {
        for stop in ["V47-light-Spend", "V47-a11y-Spend-Edit-Saving-MISSING", "V47-dark-Spend-Edit-Deficit-Other",
                     "V47-sepia-Spend-Edit-Saving", "V46-light-Spend-Edit-Saving", "Spend-Edit-Saving", ""] {
            XCTAssertNil(GalleryTextReview.warning(stop: stop, identifier: "savingMode_fixed", label: "固定金额",
                kind: .button, elementDescription: "frame=...", auditText: "audit"))
        }
        for stop in ["V47-a11y-First-After-Setup", "V47-sepia-First-After-Setup", "V47-light-First-After",
                     "V47-hidden-First-After-Setup-MISSING", "First-After-Setup", ""] {
            XCTAssertNil(GalleryTextReview.warning(stop: stop, identifier: "", label: "哪天发工资", kind: .text,
                elementDescription: "frame=...", auditText: "audit"))
        }
    }
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
