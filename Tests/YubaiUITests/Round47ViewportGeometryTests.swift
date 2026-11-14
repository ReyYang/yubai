import XCTest

final class Round47ViewportGeometryTests: XCTestCase {
    func testHomeCardCrossingHeaderUsesOnlyItsVisiblePart() {
        let row = CGRect(x: 20, y: 84.7, width: 400, height: 88)
        let header = CGRect(x: 376, y: 76, width: 44, height: 44)
        XCTAssertTrue(UIViewportGeometry.overlaps(row, header))
        let visible = UIViewportGeometry.clipped(row, to: [CGRect(x: 0, y: 130, width: 440, height: 656)])
        XCTAssertFalse(UIViewportGeometry.overlaps(visible, header))
    }
    func testLedgerRowCrossingCapsuleUsesTheCollectionViewport() {
        let row = CGRect(x: 20, y: 810.3, width: 400, height: 64)
        let tab = CGRect(x: 182, y: 868, width: 76, height: 48)
        XCTAssertTrue(UIViewportGeometry.overlaps(row, tab))
        XCTAssertFalse(UIViewportGeometry.overlaps(UIViewportGeometry.clipped(row, to: [CGRect(x: 0, y: 130, width: 440, height: 720)]), tab))
    }
    func testEveryScrollAncestorClipsTheControl() {
        let row = CGRect(x: 350, y: 760, width: 100, height: 44)
        let visible = UIViewportGeometry.clipped(row, to: [CGRect(x: 0, y: 130, width: 440, height: 650), CGRect(x: 20, y: 750, width: 400, height: 44)])
        XCTAssertEqual(visible, CGRect(x: 350, y: 760, width: 70, height: 20))
    }
    func testFullyOffViewportControlHasNoOverlap() {
        let hidden = UIViewportGeometry.clipped(CGRect(x: 20, y: 900, width: 400, height: 44), to: [CGRect(x: 0, y: 130, width: 440, height: 650)])
        XCTAssertTrue(hidden.isNull || hidden.isEmpty)
        XCTAssertFalse(UIViewportGeometry.overlaps(hidden, CGRect(x: 0, y: 900, width: 440, height: 44)))
    }
    func testStructuralRuleRejectsScrollUnderOurFixedActions() {
        let action = CGRect(x: 20, y: 800, width: 160, height: 44)
        XCTAssertFalse(UIViewportGeometry.overlaps(CGRect(x: 0, y: 116, width: 440, height: 664), action))
        XCTAssertTrue(UIViewportGeometry.overlaps(CGRect(x: 0, y: 116, width: 440, height: 699.3), action))
    }
    func testNativeNavigationClipsAccountsWithoutShrinkingItsScroll() {
        let viewport = CGRect(x: 0, y: 0, width: 440, height: 956)
        let bar = CGRect(x: 0, y: 62, width: 440, height: 54)
        let row = CGRect(x: 36, y: 53, width: 368, height: 99)
        let parts = UIViewportGeometry.visibleParts(row, ancestors: [viewport], excluding: [bar])
        XCTAssertEqual(parts.count, 2)
        XCTAssertEqual(parts.last, CGRect(x: 36, y: 116, width: 368, height: 36))
        XCTAssertFalse(parts.contains { UIViewportGeometry.overlaps($0, CGRect(x: 20, y: 62, width: 44, height: 44)) })
    }
    func testControlEntirelyInsideNativeNavigationHasNoVisibleRemainder() {
        XCTAssertTrue(UIViewportGeometry.visibleParts(CGRect(x: 24, y: 70, width: 70, height: 44), ancestors: [],
            excluding: [CGRect(x: 0, y: 62, width: 440, height: 54)]).isEmpty)
    }
    func testToastAllowanceRequiresEnoughActualScrollTravel() {
        let row = CGRect(x: 372, y: 708, width: 44, height: 44)
        let viewport = CGRect(x: 0, y: 130, width: 440, height: 656)
        let toast = CGRect(x: 20, y: 734, width: 400, height: 52)
        XCTAssertTrue(UIViewportGeometry.canClearToast(row, viewport: viewport, toast: toast, remainingDown: 40))
        XCTAssertFalse(UIViewportGeometry.canClearToast(row, viewport: viewport, toast: toast, remainingDown: 10))
    }
    func testToastCannotExemptAControlTooTallToFitAboveIt() {
        XCTAssertFalse(UIViewportGeometry.canClearToast(CGRect(x: 20, y: 130, width: 400, height: 650),
            viewport: CGRect(x: 0, y: 130, width: 440, height: 656), toast: CGRect(x: 20, y: 738, width: 400, height: 44), remainingDown: 1000))
    }
    func testNativeWindowMetricsDecodeSafeAreaAndRemainingScrollTravel() {
        let json = #"{"safeArea":[0,62,440,860],"transitioning":false,"focused":"frequentEntryPurpose","scrolls":[{"identifier":"nowScroll","frame":[0,130,440,656],"remainingDown":64,"remainingUp":0}]}"#
        let metrics = UIWindowMetrics.decode(json)
        XCTAssertEqual(metrics?.safeRectangle.maxY, 922)
        XCTAssertEqual(metrics?.focused, "frequentEntryPurpose")
        XCTAssertEqual(metrics?.scroll(matching: CGRect(x: 0, y: 130, width: 440, height: 656))?.remainingDown, 64)
        XCTAssertNil(UIWindowMetrics.decode("missing native metrics"))
    }
    func testHalfPointToleranceDoesNotPermitLargerOverlaps() {
        let fixed = CGRect(x: 0, y: 800, width: 44, height: 44)
        XCTAssertFalse(UIViewportGeometry.overlaps(CGRect(x: 0, y: 760, width: 44, height: 40.5), fixed))
        XCTAssertTrue(UIViewportGeometry.overlaps(CGRect(x: 0, y: 760, width: 44, height: 40.6), fixed))
    }
    func testRunSixYesterdayChipFitsItsOwnScaledFooterScroll() {
        let chip = CGRect(x: 73.52727272727272, y: 651.521212121212, width: 48.18181818181817, height: 44.0060606060606)
        let strip = CGRect(x: 15.709090909090909, y: 651.5212121212121, width: 408.5818181818182, height: 44.0060606060606)
        let viewport = UIViewportGeometry.usable(strip, safeArea: CGRect(x: 0, y: 62, width: 440, height: 860), top: [], bottom: [])
        var progress = UIRevealProgress()
        XCTAssertEqual(progress.next(.init(target: chip, viewport: viewport)), .reached)
        XCTAssertEqual(progress.next(.init(target: chip.offsetBy(dx: 0, dy: 2), viewport: viewport)), .stalled)
    }
    func testRunSixSalaryChipFitsBothScaledScrollAncestors() {
        let chip = CGRect(x: 27.27272727272727, y: 544.2363636363636, width: 48.18181818181817, height: 44.0060606060606)
        let strip = CGRect(x: 27.272727272727273, y: 544.2363636363636, width: 385.4545454545455, height: 44.0060606060606)
        let outer = CGRect(x: 8, y: 356.32727272727277, width: 424, height: 233.5212121212121)
        let viewport = UIViewportGeometry.usable(UIViewportGeometry.clipped(strip, to: [outer]),
            safeArea: CGRect(x: 0, y: 62, width: 440, height: 860), top: [], bottom: [])
        var progress = UIRevealProgress()
        XCTAssertEqual(progress.next(.init(target: chip, viewport: viewport)), .reached)
        XCTAssertEqual(progress.next(.init(target: chip.offsetBy(dx: -2, dy: 0), viewport: viewport)), .stalled)
    }
    func testRunSixFrequentManagerUsesItsRealCloseControl() {
        // cancelManualSheet is absent in the Butler-01 log. The matching
        // manager hierarchy exports closeSheet with this actual frame.
        let close = CGRect(x: 20, y: 148, width: 112.3, height: 50.7)
        let viewport = UIViewportGeometry.usable(CGRect(x: 0, y: 62, width: 440, height: 860),
            safeArea: CGRect(x: 0, y: 62, width: 440, height: 860), top: [], bottom: [])
        var progress = UIRevealProgress()
        XCTAssertEqual(progress.next(.init(target: close, viewport: viewport)), .reached)
        XCTAssertNotEqual(progress.next(.init(target: nil, viewport: viewport)), .reached)
    }
    func testRunSixCorrectionActionIsInsideItsOwnFixedBar() {
        let action = CGRect(x: 170, y: 858, width: 87.7, height: 44)
        var progress = UIRevealProgress()
        let viewport = UIViewportGeometry.usable(CGRect(x: 0, y: 62, width: 440, height: 860),
            safeArea: CGRect(x: 0, y: 62, width: 440, height: 860), top: [], bottom: [])
        XCTAssertEqual(progress.next(.init(target: action, viewport: viewport)), .reached)
    }
    func testRunSixTopupPartialMustDragBeforeItIsReachable() {
        let action = CGRect(x: 36, y: 742.7, width: 181, height: 47)
        let viewport = UIViewportGeometry.usable(CGRect(x: 0, y: 136, width: 440, height: 650),
            safeArea: CGRect(x: 0, y: 62, width: 440, height: 860), top: [], bottom: [CGRect(x: 98, y: 798, width: 244, height: 124)])
        var progress = UIRevealProgress()
        XCTAssertEqual(progress.next(.init(target: action, viewport: viewport)), .drag(up: true, distance: 24))
        XCTAssertEqual(progress.next(.init(target: action.offsetBy(dx: 0, dy: -24), viewport: viewport)), .reached)
    }
    func testRunSixMemoriesClearTheVisibleAskBarWithoutExcludingItsFade() {
        let row = CGRect(x: 20, y: 680, width: 400, height: 64)
        let viewport = UIViewportGeometry.usable(CGRect(x: 0, y: 136, width: 440, height: 620),
            safeArea: CGRect(x: 0, y: 62, width: 440, height: 860), top: [], bottom: [CGRect(x: 0, y: 756, width: 440, height: 200)])
        var progress = UIRevealProgress()
        XCTAssertEqual(progress.next(.init(target: row, viewport: viewport)), .reached)
    }
    func testExternalBarAndKeyboardStillExcludeCoveredControls() {
        let viewport = UIViewportGeometry.usable(CGRect(x: 8, y: 400, width: 424, height: 400),
            safeArea: CGRect(x: 0, y: 62, width: 440, height: 860), top: [], bottom: [CGRect(x: 0, y: 610, width: 440, height: 346)])
        XCTAssertEqual(viewport.maxY, 598)
        var progress = UIRevealProgress()
        XCTAssertNotEqual(progress.next(.init(target: CGRect(x: 20, y: 600, width: 100, height: 44), viewport: viewport)), .reached)
    }
    func testOnlyExternalChromeInTheSamePresentationOccludesATarget() {
        let target = "0.1.2.3.4", ancestors = ["0", "0.1", "0.1.2", "0.1.2.3"]
        XCTAssertFalse(UIViewportGeometry.isExternalRegion("0.1.2", target: target, ancestors: ancestors, surface: "0.1"))
        XCTAssertFalse(UIViewportGeometry.isExternalRegion("0.0.9", target: target, ancestors: ancestors, surface: "0.1"))
        XCTAssertTrue(UIViewportGeometry.isExternalRegion("0.1.5", target: target, ancestors: ancestors, surface: "0.1"))
        XCTAssertTrue(UIViewportGeometry.isExternalRegion("0.0.9", target: target, ancestors: ancestors, surface: nil))
    }
}
