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
    private func revealed(_ frame: CGRect, ancestors: [CGRect] = [], keyboards: [CGRect] = [],
                          exists: Bool = true, enabled: Bool = true, hittable: Bool = true, fact: Bool = false) -> Bool {
        UIViewportGeometry.revealed(exists: exists, enabled: enabled, hittable: hittable, staticText: fact,
            frame: frame, scrollAncestors: ancestors, keyboards: keyboards)
    }
    func testRunSixYesterdayChipFitsItsOwnScaledFooterScroll() {
        let chip = CGRect(x: 73.52727272727272, y: 651.521212121212, width: 48.18181818181817, height: 44.0060606060606)
        let strip = CGRect(x: 15.709090909090909, y: 651.5212121212121, width: 408.5818181818182, height: 44.0060606060606)
        XCTAssertTrue(revealed(chip, ancestors: [strip]))
        XCTAssertFalse(revealed(chip.offsetBy(dx: 0, dy: 2), ancestors: [strip]))
    }
    func testRunSixSalaryChipFitsBothScaledScrollAncestors() {
        let chip = CGRect(x: 27.27272727272727, y: 544.2363636363636, width: 48.18181818181817, height: 44.0060606060606)
        let strip = CGRect(x: 27.272727272727273, y: 544.2363636363636, width: 385.4545454545455, height: 44.0060606060606)
        let outer = CGRect(x: 8, y: 356.32727272727277, width: 424, height: 233.5212121212121)
        XCTAssertTrue(revealed(chip, ancestors: [outer, strip]))
        XCTAssertFalse(revealed(chip.offsetBy(dx: -2, dy: 0), ancestors: [outer, strip]))
        XCTAssertFalse(revealed(chip, ancestors: [outer.offsetBy(dx: 0, dy: 200), strip]))
    }
    func testRunSixFrequentManagerUsesItsRealCloseControl() {
        let close = CGRect(x: 20, y: 148, width: 112.3, height: 50.7)
        XCTAssertTrue(revealed(close))
        XCTAssertFalse(revealed(close, exists: false))
    }
    func testRunSixCorrectionActionIsInsideItsOwnFixedBar() {
        XCTAssertTrue(revealed(CGRect(x: 170, y: 858, width: 87.7, height: 44)))
    }
    func testRunSixTopupPartialMustDragBeforeItIsReachable() {
        let action = CGRect(x: 36, y: 742.7, width: 181, height: 47)
        let viewport = CGRect(x: 0, y: 136, width: 440, height: 650)
        XCTAssertFalse(revealed(action, ancestors: [viewport]))
        var progress = UIRevealProgress()
        XCTAssertEqual(progress.next(.init(target: action, viewport: viewport)), .drag(up: true, distance: 24))
        XCTAssertTrue(revealed(action.offsetBy(dx: 0, dy: -24), ancestors: [viewport]))
    }
    func testRunSixMemoriesClearTheVisibleAskBarWithoutExcludingItsFade() {
        XCTAssertTrue(revealed(CGRect(x: 20, y: 680, width: 400, height: 64),
            ancestors: [CGRect(x: 0, y: 136, width: 440, height: 620)]))
    }
    func testKeyboardIsSubtractedFromTheInnermostScrollWithoutAnInventedGap() {
        let outer = CGRect(x: 8, y: 400, width: 424, height: 400)
        let keyboard = CGRect(x: 0, y: 610, width: 440, height: 346)
        XCTAssertFalse(revealed(CGRect(x: 20, y: 600, width: 100, height: 44), ancestors: [outer], keyboards: [keyboard]))
        XCTAssertTrue(revealed(CGRect(x: 20, y: 566, width: 100, height: 44), ancestors: [outer], keyboards: [keyboard]))
        XCTAssertTrue(revealed(CGRect(x: 20, y: 600, width: 100, height: 44), keyboards: [keyboard]))
    }
    func testRunSevenFloatingMenuOverHomeScrollHasNoScrollAncestor() {
        let home = CGRect(x: 0, y: 130, width: 440, height: 656)
        for menu in [CGRect(x: 105, y: 730, width: 230, height: 56), CGRect(x: 32, y: 730, width: 376, height: 56)] {
            XCTAssertTrue(UIViewportGeometry.overlaps(menu, home))
            XCTAssertTrue(revealed(menu))
            XCTAssertFalse(revealed(menu, hittable: false))
        }
    }
    func testRunSevenCapsuleTabsHaveNoScrollAncestor() {
        for x: CGFloat in [104, 260] {
            XCTAssertTrue(revealed(CGRect(x: x, y: 868, width: 76, height: 48)))
        }
    }
    func testRunSevenMiddleRowsNeedNoProbeMetadata() {
        XCTAssertNil(UIWindowMetrics.decode(nil))
        let home = CGRect(x: 0, y: 130, width: 440, height: 656)
        XCTAssertTrue(revealed(CGRect(x: 358.3, y: 270, width: 45.7, height: 44), ancestors: [home]))
        XCTAssertTrue(revealed(CGRect(x: 20, y: 138, width: 400, height: 79.7), ancestors: [home]))
        XCTAssertTrue(revealed(CGRect(x: 36, y: 352.3, width: 368, height: 52),
            ancestors: [CGRect(x: 0, y: 0, width: 440, height: 838)]))
    }
    func testNativeHittabilityCannotOverrideWholeFrameScrollContainment() {
        let viewport = CGRect(x: 0, y: 130, width: 440, height: 656)
        let row = CGRect(x: 20, y: 742.7, width: 181, height: 47)
        XCTAssertFalse(revealed(row, ancestors: [viewport]))
        XCTAssertFalse(revealed(row.offsetBy(dx: 0, dy: 200), ancestors: [viewport]))
        XCTAssertTrue(revealed(CGRect(x: 20, y: 742.5, width: 181, height: 44), ancestors: [viewport]))
        XCTAssertFalse(revealed(CGRect(x: 20, y: 742.6, width: 181, height: 44), ancestors: [viewport]))
    }
    func testControlsRequireExistenceEnabledAndHittableButFactsOnlyNeedGeometry() {
        let frame = CGRect(x: 62, y: 747.8, width: 316, height: 26.3)
        let viewport = CGRect(x: 0, y: 130, width: 440, height: 656)
        XCTAssertFalse(revealed(frame, enabled: false))
        XCTAssertFalse(revealed(frame, hittable: false))
        XCTAssertFalse(revealed(frame, exists: false))
        XCTAssertTrue(revealed(frame, ancestors: [viewport], enabled: false, hittable: false, fact: true))
        XCTAssertFalse(revealed(frame.offsetBy(dx: 0, dy: 200), ancestors: [viewport], fact: true))
        XCTAssertFalse(revealed(.zero, fact: true))
    }
}
