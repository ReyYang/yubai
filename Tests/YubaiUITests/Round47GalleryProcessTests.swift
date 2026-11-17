import XCTest

final class Round47GalleryProcessTests: XCTestCase {
    private func settledPaper() -> UIWindowMetrics {
        UIWindowMetrics(safeArea: [0, 0, 440, 956], transitioning: false, focused: "", scrolls: [],
                        bambooSurface: .init(required: false, key: nil))
    }
    func testEachStopGetsItsSelectedBudgetAfterAnExpiredPreviousStop() {
        var now: TimeInterval = 0
        let budget = GalleryStopBudget(clock: { Date(timeIntervalSinceReferenceDate: now) })
        for duration: TimeInterval in [90, 180, 240, 90] {
            budget.begin(duration)
            XCTAssertEqual(budget.deadline.timeIntervalSinceReferenceDate - now, duration)
            now += duration + 10
            budget.end()
            XCTAssertEqual(budget.deadline, .distantFuture)
            now += 120
        }
    }
    func testColdLaunchAndSlowFirstRootReadLeaveTheUnspentStopBudget() {
        var now: TimeInterval = 0
        let budget = GalleryStopBudget(clock: { Date(timeIntervalSinceReferenceDate: now) })
        budget.begin(90)
        now += 3
        budget.excluding {
            // Xcode launch retries can outlast a whole navigation budget.
            now += 180
            let root = UITransitionWait.run(timeout: 15, deadline: budget.deadline.timeIntervalSinceReferenceDate, read: {
                now += 40; return self.settledPaper()
            }, clock: { now }, poll: { now += $0 })
            XCTAssertTrue(root.settled, root.description)
            XCTAssertEqual(root.reads, 1)
        }
        XCTAssertEqual(budget.deadline.timeIntervalSinceReferenceDate - now, 87)
        let end = budget.deadline
        now += 30 // Actual route work is still charged to this same deadline.
        let capture = UIBambooWait.forCapture(deadline: end.timeIntervalSinceReferenceDate,
            read: { self.settledPaper() }, clock: { now }, poll: { now += $0 })
        XCTAssertTrue(capture.ready, capture.description)
        XCTAssertEqual(budget.deadline, end)
        XCTAssertEqual(budget.deadline.timeIntervalSinceReferenceDate - now, 57)
    }
    func testSlowAuditLeavesTimeForTheFirstCaptureReadWithoutRenewingTheBudget() {
        var now: TimeInterval = 0, reads = 0
        let budget = GalleryStopBudget(clock: { Date(timeIntervalSinceReferenceDate: now) })
        budget.begin(90)
        now += 70
        budget.excluding { now += 200 } // Native audit/retry and restored layout.
        XCTAssertEqual(budget.deadline.timeIntervalSinceReferenceDate - now, 20)
        let end = budget.deadline
        let capture = UIBambooWait.forCapture(deadline: end.timeIntervalSinceReferenceDate, read: {
            reads += 1; return reads == 1 ? nil : self.settledPaper()
        }, clock: { now }, poll: { now += $0 })
        XCTAssertTrue(capture.ready, capture.description)
        XCTAssertEqual(reads, 2)
        XCTAssertEqual(capture.unreadableReads, 1)
        XCTAssertEqual(budget.deadline, end)
        XCTAssertLessThan(budget.deadline.timeIntervalSinceReferenceDate - now, 20)
    }
    func testExcludedWorkCannotReviveAnActuallyExhaustedNavigationBudget() {
        var now: TimeInterval = 0
        let budget = GalleryStopBudget(clock: { Date(timeIntervalSinceReferenceDate: now) })
        budget.begin(90)
        now += 91
        budget.excluding { now += 200 }
        XCTAssertEqual(budget.deadline.timeIntervalSinceReferenceDate - now, -1)
        let transition = UITransitionWait.run(deadline: budget.deadline.timeIntervalSinceReferenceDate,
            read: { XCTFail("An exhausted stop must still fail"); return self.settledPaper() }, clock: { now })
        let capture = UIBambooWait.forCapture(deadline: budget.deadline.timeIntervalSinceReferenceDate,
            read: { XCTFail("An exhausted stop must not capture successfully"); return self.settledPaper() }, clock: { now })
        XCTAssertFalse(transition.settled)
        XCTAssertEqual(transition.reads, 0)
        XCTAssertFalse(capture.ready)
        XCTAssertEqual(capture.elapsed, 0)
    }
    func testFailedLaunchRestoresBudgetAndRecoveryDoesNotInheritItsExpiredDeadline() {
        enum LaunchError: Error { case failed }
        var now: TimeInterval = 0
        let budget = GalleryStopBudget(clock: { Date(timeIntervalSinceReferenceDate: now) })
        budget.begin(90)
        now += 4
        XCTAssertThrowsError(try budget.excluding { now += 180; throw LaunchError.failed })
        XCTAssertEqual(budget.deadline.timeIntervalSinceReferenceDate - now, 86)
        now += 87
        budget.excluding {
            now += 120
            let recovery = UITransitionWait.run(timeout: 15, deadline: budget.deadline.timeIntervalSinceReferenceDate,
                read: { self.settledPaper() }, clock: { now }, poll: { now += $0 })
            XCTAssertTrue(recovery.settled, recovery.description)
            XCTAssertEqual(recovery.reads, 1)
        }
        XCTAssertEqual(budget.deadline.timeIntervalSinceReferenceDate - now, -1)
        budget.end()
        budget.begin(90)
        let next = UIBambooWait.forCapture(deadline: budget.deadline.timeIntervalSinceReferenceDate,
            read: { self.settledPaper() }, clock: { now }, poll: { now += $0 })
        XCTAssertTrue(next.ready, next.description)
        XCTAssertEqual(budget.deadline.timeIntervalSinceReferenceDate - now, 90)
    }
    func testNestedExcludedWorkAndWorkOutsideAStopDoNotAccumulateExtraBudget() {
        var now: TimeInterval = 0
        let budget = GalleryStopBudget(clock: { Date(timeIntervalSinceReferenceDate: now) })
        budget.excluding { now += 120 }
        XCTAssertEqual(budget.deadline, .distantFuture)
        budget.begin(90)
        now += 10
        budget.excluding {
            now += 20
            budget.excluding { now += 30 }
            now += 40
        }
        XCTAssertEqual(budget.deadline.timeIntervalSinceReferenceDate - now, 80)
    }

    func testReviewedFixedAmountWarningCoversOnlyTheTwoStopsInFullGalleryModes() {
        for mode in ["light", "dark", "a11y"] {
            for stop in ["Spend-Edit-Saving", "Spend-Edit-Deficit"] {
                let name = "V47-\(mode)-\(stop)"
                let frame = mode == "a11y" ? "{x=24.0,y=234.7,w=392.0,h=72.3}" : "{x=31.1,y=523.0,w=186.9,h=44.0}"
                let description = "identifier=savingMode_fixed label=固定金额 frame=" + frame
                let audit = "Text of this SwiftUI.AccessibilityNode may be clipped at larger Dynamic Type sizes."
                let warning = GalleryTextReview.warning(stop: name, identifier: "savingMode_fixed", label: "固定金额",
                    kind: .button, category: .textClipped, selected: true, elementDescription: description, auditText: audit)
                XCTAssertEqual(warning, name + ": Text clipped: PNG-reviewed complete fixed-amount label at largest size; " + description + " " + audit)
            }
        }
    }
    func testReviewedPaydayTitleWarningCoversAllThreeFullModes() {
        for mode in ["light", "dark", "a11y"] {
            let name = "V47-\(mode)-First-After-Setup"
            let description = "identifier= label=哪天发工资 frame={x=181.6,y=503.4,w=76.8,h=18.6}"
            let warning = GalleryTextReview.warning(stop: name, identifier: "", label: "哪天发工资", kind: .text,
                category: .textClipped, selected: false, elementDescription: description, auditText: "native audit text")
            XCTAssertEqual(warning, name + ": Text clipped: PNG-reviewed complete payday sheet title; " + description + " native audit text")
        }
    }
    func testReviewedFrequentTitleWarningRequiresTheExactSheetInFullModes() {
        for mode in ["light", "dark", "a11y"] {
            let name = "V47-\(mode)-Empty-Frequent"
            let frame = mode == "a11y" ? "{x=134.8,y=86.0,w=170.3,h=54.0}" : "{x=189.2,y=408.7,w=61.4,h=18.6}"
            let description = "identifier= label=整理常用 frame=" + frame
            let warning = GalleryTextReview.warning(stop: name, identifier: "", label: "整理常用", kind: .text,
                category: .textClipped, selected: false, elementDescription: description, auditText: "native audit text")
            XCTAssertEqual(warning, name + ": Text clipped: PNG-reviewed complete frequent sheet title; " + description + " native audit text")
            for category in [GalleryTextReview.Category.dynamicType, .other] {
                XCTAssertNil(GalleryTextReview.warning(stop: name, identifier: "", label: "整理常用", kind: .text,
                    category: category, selected: false, elementDescription: description, auditText: "audit"))
            }
            for (identifier, label, kind) in [("frequentTitle", "整理常用", GalleryTextReview.Kind.text),
                ("", "整理常用…", .text), ("", "常记的会自己出现", .text), ("", "整理常用", .button), ("", "整理常用", .other)] {
                XCTAssertNil(GalleryTextReview.warning(stop: name, identifier: identifier, label: label, kind: kind,
                    category: .textClipped, selected: false, elementDescription: description, auditText: "audit"))
            }
        }
        for stop in ["V47-hidden-Empty-Frequent", "V47-sepia-Empty-Frequent", "V47-light-Empty-Frequent-Add",
                     "V47-light-Empty-Frequent-MISSING", "V46-light-Empty-Frequent", "Empty-Frequent", ""] {
            XCTAssertNil(GalleryTextReview.warning(stop: stop, identifier: "", label: "整理常用", kind: .text,
                category: .textClipped, selected: false, elementDescription: "frame=...", auditText: "audit"))
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
            for category in [GalleryTextReview.Category.textClipped, .dynamicType] {
                XCTAssertNil(GalleryTextReview.warning(stop: "V47-light-Spend-Edit-Saving", identifier: identifier,
                    label: label, kind: kind, category: category, selected: true, elementDescription: "frame=...", auditText: "audit"))
            }
        }
        for (identifier, label, kind) in [("paydayTitle", "哪天发工资", GalleryTextReview.Kind.text),
                                         ("", "哪天发工资…", .text), ("", "哪天发工资", .button), ("", "哪天发工资", .other)] {
            XCTAssertNil(GalleryTextReview.warning(stop: "V47-light-First-After-Setup", identifier: identifier,
                label: label, kind: kind, category: .textClipped, selected: false, elementDescription: "frame=...", auditText: "audit"))
        }
    }
    func testReviewedTextCannotMatchOtherStopsOrFutureModes() {
        for stop in ["V47-light-Spend", "V47-a11y-Spend-Edit-Saving-MISSING", "V47-dark-Spend-Edit-Deficit-Other",
                     "V47-sepia-Spend-Edit-Saving", "V46-light-Spend-Edit-Saving", "Spend-Edit-Saving", ""] {
            for category in [GalleryTextReview.Category.textClipped, .dynamicType] {
                XCTAssertNil(GalleryTextReview.warning(stop: stop, identifier: "savingMode_fixed", label: "固定金额",
                    kind: .button, category: category, selected: true, elementDescription: "frame=...", auditText: "audit"))
            }
        }
        for stop in ["V47-a11y-First-After-Setup-MISSING", "V47-sepia-First-After-Setup", "V47-light-First-After",
                     "V47-light-First-After-Setup-MISSING", "First-After-Setup", ""] {
            XCTAssertNil(GalleryTextReview.warning(stop: stop, identifier: "", label: "哪天发工资", kind: .text,
                category: .textClipped, selected: false, elementDescription: "frame=...", auditText: "audit"))
        }
    }
    func testReviewedDynamicTypeWarningRequiresTheSelectedFixedAmountInBothStopsAndFullModes() {
        for mode in ["light", "dark", "a11y"] {
            for stop in ["Spend-Edit-Saving", "Spend-Edit-Deficit"] {
                let name = "V47-\(mode)-\(stop)"
                let description = "identifier=savingMode_fixed label=固定金额 frame={x=31.1,y=523.0,w=186.9,h=44.0}"
                let audit = "User will not be able to change the font size of this SwiftUI.AccessibilityNode"
                let warning = GalleryTextReview.warning(stop: name, identifier: "savingMode_fixed", label: "固定金额",
                    kind: .button, category: .dynamicType, selected: true, elementDescription: description, auditText: audit)
                XCTAssertEqual(warning, name + ": Dynamic Type: recording-reviewed selected fixed-amount label grows and stacks during live size change; " + description + " " + audit)
                XCTAssertNil(GalleryTextReview.warning(stop: name, identifier: "savingMode_fixed", label: "固定金额",
                    kind: .button, category: .dynamicType, selected: false, elementDescription: description, auditText: audit))
            }
        }
    }
    func testReviewedEntriesNeverAcceptAnotherAuditCategory() {
        for mode in ["light", "dark", "a11y"] {
            for stop in ["Spend-Edit-Saving", "Spend-Edit-Deficit"] {
                XCTAssertNil(GalleryTextReview.warning(stop: "V47-\(mode)-\(stop)", identifier: "savingMode_fixed", label: "固定金额",
                    kind: .button, category: .other, selected: true, elementDescription: "frame=...", auditText: "audit"))
            }
            for category in [GalleryTextReview.Category.dynamicType, .other] {
                XCTAssertNil(GalleryTextReview.warning(stop: "V47-\(mode)-First-After-Setup", identifier: "", label: "哪天发工资",
                    kind: .text, category: category, selected: false, elementDescription: "frame=...", auditText: "audit"))
            }
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
