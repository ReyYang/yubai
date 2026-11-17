import XCTest

/// These use a virtual clock: even the slow-query and timeout cases take no
/// wall-clock sleeps and make no automation session or application requests.
final class Round47FrameWaitTests: XCTestCase {
    private func transition(_ active: Bool, focused: String = "") -> UIWindowMetrics {
        UIWindowMetrics(safeArea: [0, 62, 440, 860], transitioning: active, focused: focused, scrolls: [],
                        activeTransitions: active ? ["Sheet:coordinator=true,presenting=true,dismissing=false"] : [])
    }
    func testTransitionWaitRetriesAnUnreadableProbeAndRequiresActualCompletion() {
        var now: TimeInterval = 0, reads = 0
        let result = UITransitionWait.run(read: {
            reads += 1
            return reads == 1 ? nil : self.transition(reads < 4, focused: "butlerAICorrectionText")
        }, clock: { now }, poll: { now += $0 })
        XCTAssertTrue(result.settled, result.description)
        XCTAssertEqual(result.reads, 4, result.description)
        XCTAssertEqual(result.unreadableReads, 1, result.description)
        XCTAssertEqual(result.observed?.focused, "butlerAICorrectionText")
    }
    func testUnreadableTransitionTelemetryIsNeitherCompletionNorAnActiveController() {
        var now: TimeInterval = 0
        let result = UITransitionWait.run(timeout: 1, read: { nil }, clock: { now }, poll: { now += $0 })
        XCTAssertFalse(result.settled, result.description)
        XCTAssertEqual(result.reads, result.unreadableReads)
        XCTAssertNil(result.observed)
        XCTAssertNil(result.lastReadable)
        XCTAssertTrue(result.description.contains("observed={unreadable}"))
    }
    func testActiveTransitionFailureRetainsTheControllerAndFocusedField() {
        var now: TimeInterval = 0
        let result = UITransitionWait.run(timeout: 1, read: { self.transition(true, focused: "entriesSearch") },
                                          clock: { now }, poll: { now += $0 })
        XCTAssertFalse(result.settled, result.description)
        XCTAssertEqual(result.unreadableReads, 0)
        XCTAssertTrue(result.description.contains("Sheet:coordinator=true"))
        XCTAssertTrue(result.description.contains("focused=entriesSearch"))
    }
    func testTransitionFailureDistinguishesACoveredProbeFromItsLastReadableState() {
        var now: TimeInterval = 0, reads = 0
        let result = UITransitionWait.run(timeout: 1, read: {
            reads += 1
            return reads == 1 ? self.transition(true) : nil
        }, clock: { now }, poll: { now += $0 })
        XCTAssertFalse(result.settled, result.description)
        XCTAssertNil(result.observed)
        XCTAssertEqual(result.lastReadable?.transitioning, true)
        XCTAssertGreaterThan(result.unreadableReads, 0)
    }
    func testExpiredTransitionDeadlineDoesNotReadOrClaimAnObservedTransition() {
        let result = UITransitionWait.run(deadline: 5, read: { XCTFail("Expired gate must not query"); return nil }, clock: { 5 })
        XCTAssertFalse(result.settled, result.description)
        XCTAssertEqual(result.reads, 0)
        XCTAssertEqual(result.unreadableReads, 0)
        XCTAssertEqual(result.elapsed, 0)
        XCTAssertNil(result.lastReadable)
    }
    func testTransitionCompletionAfterTheHardDeadlineStillFails() {
        var now: TimeInterval = 0
        let result = UITransitionWait.run(deadline: 1, read: { now += 2; return self.transition(false) },
                                          clock: { now }, poll: { now += $0 })
        XCTAssertFalse(result.settled, result.description)
        XCTAssertEqual(result.observed?.transitioning, false)
        XCTAssertEqual(result.reads, 1)
    }
    func testNativeProbeDecodesAppearanceAtFocusAcquisitionAndPanOrigins() throws {
        let json = #"{"safeArea":[0,62,440,860],"transitioning":false,"focused":"butlerAICorrectionText","focusedAfterAppearance":true,"scrolls":[{"identifier":"entriesScroll","frame":[0,130,440,668],"remainingDown":423,"remainingUp":0,"panPoints":[[13.2,651.04],[426.8,651.04],[1]]}]}"#
        let metrics = try XCTUnwrap(UIWindowMetrics.decode(json))
        XCTAssertEqual(metrics.focusedAfterAppearance, true)
        XCTAssertEqual(metrics.scrolls.first?.panOrigins, [CGPoint(x: 13.2, y: 651.04), CGPoint(x: 426.8, y: 651.04)])
    }
    private func bamboo(ready: [String] = [], pending: [String] = [], failed: [String] = [],
                        renders: Int = 2, mainRenders: Int = 0, activeRenders: Int = 0, maxConcurrentRenders: Int = 1,
                        lastFailure: UIWindowMetrics.Bamboo.Failure? = nil) -> UIWindowMetrics.Bamboo {
        UIWindowMetrics.Bamboo(ready: ready, renders: renders, mainRenders: mainRenders,
            activeRenders: activeRenders, maxConcurrentRenders: maxConcurrentRenders, pending: pending.count,
            pendingKeys: pending, failed: failed, failedStages: failed.isEmpty ? [:] : [failed[0]: "blurOutput"],
            lastFailure: lastFailure)
    }
    func testColdBambooWaitRequiresBothActualCompletionsBeyondTheOldThirtySeconds() {
        var now: TimeInterval = 0
        let result = UIBambooWait.run(read: {
            now += 1
            if now < 35 { return self.bamboo(pending: ["light@3.0", "dark@3.0"]) }
            if now < 46 { return self.bamboo(ready: ["light@3.0"], pending: ["dark@3.0"]) }
            return self.bamboo(ready: ["light@3.0", "dark@3.0"])
        }, clock: { now }, poll: { now += $0 })
        XCTAssertTrue(result.ready, result.description)
        XCTAssertGreaterThanOrEqual(now, 46)
        XCTAssertLessThan(now, UIBambooWait.timeout)
    }
    func testBambooRenderFailureStopsImmediatelyWithAllObservedDiagnostics() {
        var now: TimeInterval = 0
        let failure = UIWindowMetrics.Bamboo.Failure(key: "light@3.0", stage: "blurOutput", attempt: 1)
        let result = UIBambooWait.run(read: {
            self.bamboo(pending: ["dark@3.0"], failed: ["light@3.0"], renders: 1, lastFailure: failure)
        }, clock: { now }, poll: { now += $0 })
        XCTAssertFalse(result.ready, result.description)
        XCTAssertEqual(now, 0)
        for field in ["ready=", "pending=", "failed=", "renders=", "mainRenders=", "stage=blurOutput", "attempt=1"] {
            XCTAssertTrue(result.description.contains(field), result.description)
        }
    }
    func testBambooRecoveredFailureStillFailsTheRenderProofAndCaptureGate() {
        var now: TimeInterval = 0
        let failure = UIWindowMetrics.Bamboo.Failure(key: "dark@3.0", stage: "inputEmpty", attempt: 1)
        let result = UIBambooWait.run(read: {
            self.bamboo(ready: ["light@3.0", "dark@3.0"], renders: 3, lastFailure: failure)
        }, clock: { now }, poll: { now += $0 })
        XCTAssertFalse(result.ready, result.description)
        XCTAssertEqual(now, 0)
        XCTAssertTrue(result.description.contains("stage=inputEmpty"), result.description)
    }
    func testBambooMainThreadRenderFailsEvenWhenBothImagesAreReady() {
        var now: TimeInterval = 0
        let result = UIBambooWait.run(read: {
            self.bamboo(ready: ["light@3.0", "dark@3.0"], mainRenders: 1)
        }, clock: { now }, poll: { now += $0 })
        XCTAssertFalse(result.ready, result.description)
        XCTAssertEqual(now, 0)
        XCTAssertTrue(result.description.contains("mainRenders=1"), result.description)
    }
    func testOverlappingBambooRendersFailEvenAfterBothImagesFinish() {
        var now: TimeInterval = 0
        let result = UIBambooWait.run(read: {
            self.bamboo(ready: ["light@3.0", "dark@3.0"], maxConcurrentRenders: 2)
        }, clock: { now }, poll: { now += $0 })
        XCTAssertFalse(result.ready, result.description)
        XCTAssertEqual(now, 0, result.description)
        XCTAssertTrue(result.description.contains("maxConcurrentRenders=2"), result.description)
    }
    func testBambooCaptureWaitsUntilTheWorkerHasDrainedItsPool() {
        var now: TimeInterval = 0
        let result = UIBambooWait.run(timeout: 1, read: {
            self.bamboo(ready: ["light@3.0", "dark@3.0"], activeRenders: 1)
        }, clock: { now }, poll: { now += $0 })
        XCTAssertFalse(result.ready, result.description)
        XCTAssertTrue(result.description.contains("activeRenders=1"), result.description)
    }
    func testBambooOneAppearanceOrMismatchedScalesCannotPassAndCannotExtendTheBound() {
        for ready in [["light@3.0"], ["light@3.0", "dark@2.0"]] {
            var now: TimeInterval = 0
            let result = UIBambooWait.run(timeout: 3, read: {
                now += 1; return self.bamboo(ready: ready, renders: ready.count)
            }, clock: { now }, poll: { now += $0 })
            XCTAssertFalse(result.ready, result.description)
            XCTAssertLessThan(now, 4.2)
        }
    }
    func testBambooPendingWorkPreventsCaptureEvenWithAnOlderReadyPair() {
        var now: TimeInterval = 0
        let result = UIBambooWait.run(timeout: 1, read: {
            self.bamboo(ready: ["light@2.0", "dark@2.0"], pending: ["light@3.0", "dark@3.0"], renders: 4)
        }, clock: { now }, poll: { now += $0 })
        XCTAssertFalse(result.ready, result.description)
        XCTAssertTrue(result.description.contains("pending=2"), result.description)
    }
    func testBambooUnreadableProbeReportsTheProblemAndLastReadableState() {
        var now: TimeInterval = 0, reads = 0
        let result = UIBambooWait.run(timeout: 1, read: {
            reads += 1
            return reads == 1 ? self.bamboo(ready: ["light@3.0"], pending: ["dark@3.0"]) : nil
        }, clock: { now }, poll: { now += $0 })
        XCTAssertFalse(result.ready, result.description)
        XCTAssertGreaterThan(result.unreadableReads, 0)
        XCTAssertTrue(result.description.contains("diagnostics unreadable"), result.description)
        XCTAssertTrue(result.description.contains("lastReadable={ready="), result.description)
        XCTAssertTrue(result.description.contains("dark@3.0"), result.description)
    }
    func testBambooWaitCannotAcceptASlowFirstReadPastItsOwnOrGalleryDeadline() {
        for deadline in [TimeInterval?.none, .some(1)] {
            var now: TimeInterval = 0
            let result = UIBambooWait.run(timeout: 2, deadline: deadline, read: {
                now += 3; return self.bamboo(ready: ["light@3.0", "dark@3.0"])
            }, clock: { now }, poll: { now += $0 })
            XCTAssertFalse(result.ready, result.description)
            XCTAssertEqual(now, 3)
        }
    }
    func testBambooProbeDecodesFailureStageAndEveryCompletionField() throws {
        let json = #"{"safeArea":[0,0,440,956],"transitioning":false,"focused":"","scrolls":[],"bamboo":{"ready":["light@3.0"],"pending":1,"pendingKeys":["dark@3.0"],"failed":["dark@3.0"],"failedStages":{"dark@3.0":"blurOutput"},"renders":2,"mainRenders":0,"activeRenders":1,"maxConcurrentRenders":1,"lastFailure":{"key":"dark@3.0","stage":"blurOutput","attempt":1}}}"#
        let value = try XCTUnwrap(UIWindowMetrics.decode(json)?.bamboo)
        XCTAssertEqual(value.ready, ["light@3.0"], value.description)
        XCTAssertEqual(value.pendingKeys, ["dark@3.0"], value.description)
        XCTAssertEqual(value.pending, 1, value.description)
        XCTAssertEqual(value.activeRenders, 1, value.description)
        XCTAssertEqual(value.maxConcurrentRenders, 1, value.description)
        XCTAssertEqual(value.failedStages["dark@3.0"], "blurOutput", value.description)
        XCTAssertEqual(value.lastFailure?.stage, "blurOutput", value.description)
        XCTAssertFalse(value.isReady, value.description)
    }
    private func surface(_ required: Bool, key: String? = nil, bamboo: UIWindowMetrics.Bamboo? = nil) -> UIWindowMetrics {
        UIWindowMetrics(safeArea: [0, 0, 440, 956], transitioning: false, focused: "", scrolls: [],
                        bamboo: bamboo, bambooSurface: .init(required: required, key: key))
    }
    func testCaptureWithoutBambooReturnsOnItsFirstObservationWithNoRenderWait() {
        // A cold first window, a plain pushed page, a sheet or a locked root
        // need no cache work. Even unrelated pending renders cannot delay them.
        for state in [bamboo(renders: 0, maxConcurrentRenders: 0),
                      bamboo(pending: ["light@3.0", "dark@3.0"], renders: 0), nil] {
            var now: TimeInterval = 0, reads = 0
            let result = UIBambooWait.forCapture(read: {
                reads += 1; return self.surface(false, bamboo: state)
            }, clock: { now }, poll: { now += $0 })
            XCTAssertTrue(result.ready, result.description)
            XCTAssertEqual(result.surface?.required, false, result.description)
            XCTAssertEqual(reads, 1, result.description)
            XCTAssertEqual(now, 0, result.description)
        }
    }
    func testCaptureRetriesAnInitiallyUnreadableProbeBeforeAcceptingANonBambooSurface() {
        var now: TimeInterval = 0, reads = 0
        let result = UIBambooWait.forCapture(read: {
            reads += 1; return reads == 1 ? nil : self.surface(false)
        }, clock: { now }, poll: { now += $0 })
        XCTAssertTrue(result.ready, result.description)
        XCTAssertEqual(reads, 2, result.description)
        XCTAssertEqual(result.unreadableReads, 1, result.description)
        XCTAssertLessThan(now, 1, result.description)
    }
    func testCaptureRetriesUnreadableStateAndStillRequiresBothRastersOnABambooSurface() {
        var now: TimeInterval = 0, reads = 0
        let result = UIBambooWait.forCapture(read: {
            reads += 1
            if reads == 1 { return nil }
            let state = reads < 4 ? self.bamboo(ready: ["light@3.0"], pending: ["dark@3.0"])
                : self.bamboo(ready: ["light@3.0", "dark@3.0"])
            return self.surface(true, key: "light@3.0", bamboo: state)
        }, clock: { now }, poll: { now += $0 })
        XCTAssertTrue(result.ready, result.description)
        XCTAssertEqual(reads, 4, result.description)
        XCTAssertEqual(result.unreadableReads, 1, result.description)
    }
    func testCaptureCannotUseAnOlderScaleForTheCurrentSurface() {
        var now: TimeInterval = 0, reads = 0
        let result = UIBambooWait.forCapture(read: {
            reads += 1
            let scale = reads == 1 ? "2.0" : "3.0"
            return self.surface(true, key: "light@3.0", bamboo: self.bamboo(ready: ["light@" + scale, "dark@" + scale]))
        }, clock: { now }, poll: { now += $0 })
        XCTAssertTrue(result.ready, result.description)
        XCTAssertEqual(reads, 2, result.description)
        XCTAssertTrue(result.observed?.ready.contains("light@3.0") == true, result.description)
    }
    func testCaptureWithoutSurfaceMetadataCannotBypassTheGateEvenWithReadyRasters() {
        var now: TimeInterval = 0
        let result = UIBambooWait.forCapture(timeout: 1, read: {
            var metrics = self.surface(false, bamboo: self.bamboo(ready: ["light@3.0", "dark@3.0"]))
            metrics.bambooSurface = nil
            metrics.paperDiagnostics = "visited=34 markers=1 emptyMarkers=1 attached=1"
            return metrics
        }, clock: { now }, poll: { now += $0 })
        XCTAssertFalse(result.ready, result.description)
        XCTAssertGreaterThan(result.unreadableReads, 0, result.description)
        XCTAssertLessThanOrEqual(now, 1, result.description)
        XCTAssertTrue(result.description.contains("packet decoded; bambooSurface missing"), result.description)
        XCTAssertTrue(result.description.contains("emptyMarkers=1"), result.description)
    }
    func testCaptureReportsPacketAndMissingRasterDiagnosticsSeparately() {
        for missingPacket in [false, true] {
            var now: TimeInterval = 0
            let result = UIBambooWait.forCapture(timeout: 1, read: {
                missingPacket ? nil : self.surface(true, key: "light@3.0", bamboo: nil)
            }, clock: { now }, poll: { now += $0 })
            XCTAssertFalse(result.ready, result.description)
            XCTAssertTrue(result.description.contains(missingPacket ? "window metrics packet unreadable" : "packet decoded; bamboo diagnostics missing"), result.description)
            XCTAssertFalse(result.description.contains("bambooSurface missing"), result.description)
        }
    }
    func testCaptureOfABambooSurfaceCannotPassWhenNoWarmWasRequested() {
        var now: TimeInterval = 0
        let result = UIBambooWait.forCapture(timeout: 1, read: {
            self.surface(true, key: "light@3.0", bamboo: self.bamboo(renders: 0, maxConcurrentRenders: 0))
        }, clock: { now }, poll: { now += $0 })
        XCTAssertFalse(result.ready, result.description)
        XCTAssertEqual(result.observed?.renders, 0, result.description)
        XCTAssertLessThanOrEqual(now, 1, result.description)
    }
    func testCaptureStillFailsImmediatelyForEveryRasterFailureOnABambooSurface() {
        let failure = UIWindowMetrics.Bamboo.Failure(key: "light@3.0", stage: "blurOutput", attempt: 1)
        for state in [bamboo(failed: ["light@3.0"], lastFailure: failure),
                      bamboo(ready: ["light@3.0", "dark@3.0"], mainRenders: 1),
                      bamboo(ready: ["light@3.0", "dark@3.0"], maxConcurrentRenders: 2)] {
            var now: TimeInterval = 0
            let result = UIBambooWait.forCapture(read: {
                self.surface(true, key: "light@3.0", bamboo: state)
            }, clock: { now }, poll: { now += $0 })
            XCTAssertFalse(result.ready, result.description)
            XCTAssertEqual(now, 0, result.description)
        }
    }
    func testCaptureRechecksTheSurfaceWhileWaitingForPendingRasters() {
        var now: TimeInterval = 0, reads = 0
        let result = UIBambooWait.forCapture(read: {
            reads += 1
            return self.surface(reads == 1, key: reads == 1 ? "light@3.0" : nil,
                                bamboo: self.bamboo(pending: ["light@3.0", "dark@3.0"], renders: 0))
        }, clock: { now }, poll: { now += $0 })
        XCTAssertTrue(result.ready, result.description)
        XCTAssertEqual(reads, 2, result.description)
        XCTAssertEqual(result.surface?.required, false, result.description)
        XCTAssertLessThan(now, 1, result.description)
    }
    func testCaptureCannotAcceptAnObservationPastItsHardDeadline() {
        for required in [false, true] {
            var now: TimeInterval = 0
            let result = UIBambooWait.forCapture(timeout: 2, deadline: 1, read: {
                now += 3
                return self.surface(required, key: required ? "light@3.0" : nil,
                                    bamboo: self.bamboo(ready: ["light@3.0", "dark@3.0"]))
            }, clock: { now }, poll: { now += $0 })
            XCTAssertFalse(result.ready, result.description)
            XCTAssertEqual(now, 3, result.description)
        }
    }
    func testProbeDecodesTheActualBambooSurfaceAndAnExplicitPlainSurface() throws {
        for (required, key) in [(true, "\"dark@3.0\""), (false, "null")] {
            let json = "{\"safeArea\":[0,0,440,956],\"transitioning\":false,\"focused\":\"\",\"scrolls\":[],\"bambooSurface\":{\"required\":\(required),\"key\":\(key)}}"
            let value = try XCTUnwrap(UIWindowMetrics.decode(json)?.bambooSurface)
            XCTAssertEqual(value.required, required, value.description)
            XCTAssertEqual(value.key, required ? "dark@3.0" : nil, value.description)
        }
    }
    func testDisappearanceWaitAcceptsASlowFirstObservation() {
        var now: TimeInterval = 0
        XCTAssertTrue(UIConditionWait.run(read: { now += 14; return true }, clock: { now }, poll: { now += $0 }))
    }
    func testDisappearanceWaitDoesNotRestartForAStillPresentedSheet() {
        var now: TimeInterval = 0
        var reads = 0
        XCTAssertFalse(UIConditionWait.run(timeout: 3, read: {
            reads += 1; now += 1; return false
        }, clock: { now }, poll: { now += $0 }))
        XCTAssertLessThanOrEqual(reads, 4)
    }
    func testDisappearanceWaitNeverAcceptsALateReadPastTheCallersDeadline() {
        var now: TimeInterval = 0
        XCTAssertFalse(UIConditionWait.run(deadline: 5, read: { now += 14; return true }, clock: { now }, poll: { now += $0 }))
    }
    private let frame = CGRect(x: 36, y: 173.333, width: 368, height: 64)

    func testSlowSnapshotsStillRequireAndReceiveTwoMatchingReads() {
        var time: TimeInterval = 0
        let result = UIFrameWait.run(read: { time += 5; return self.frame }, clock: { time }, poll: { time += $0 })
        XCTAssertTrue(result.stable)
        XCTAssertEqual(result.samples.count, 2)
        XCTAssertGreaterThan(time, 10)
    }
    func testBudgetStartsAfterFirstSuccessfulRead() {
        var time: TimeInterval = 0, reads = 0
        let result = UIFrameWait.run(timeout: 6, read: {
            reads += 1; time += reads == 1 ? 7 : 5
            return self.frame
        }, clock: { time }, poll: { time += $0 })
        XCTAssertTrue(result.stable)
        XCTAssertEqual(reads, 2)
    }
    func testMovingControlNeverPassesAndCannotExtendItsDeadline() {
        var time: TimeInterval = 0, reads = 0
        let result = UIFrameWait.run(timeout: 1, read: {
            reads += 1; time += 0.1
            return self.frame.offsetBy(dx: 0, dy: CGFloat(reads))
        }, clock: { time }, poll: { time += $0 })
        XCTAssertFalse(result.stable)
        XCTAssertLessThan(time, 1.3)
        XCTAssertGreaterThan(reads, 2)
    }
    func testMissingAndEmptyFramesNeverPass() {
        for empty in [CGRect?.none, .some(.zero), .some(.null), .some(.infinite)] {
            var time: TimeInterval = 0
            let result = UIFrameWait.run(timeout: 1, read: { time += 0.1; return empty }, clock: { time }, poll: { time += $0 })
            XCTAssertFalse(result.stable)
            XCTAssertLessThan(time, 1.3)
        }
    }
    func testMissingReadBreaksConsecutiveAgreement() {
        var time: TimeInterval = 0, reads = 0
        let result = UIFrameWait.run(read: {
            reads += 1; time += 0.1
            return reads == 2 ? nil : self.frame
        }, clock: { time }, poll: { time += $0 })
        XCTAssertTrue(result.stable)
        XCTAssertEqual(reads, 4)
    }
    func testEachFrameComponentMustSettle() {
        var time: TimeInterval = 0, reads = 0
        let frames = [frame, frame.offsetBy(dx: 2, dy: 0), frame.offsetBy(dx: 2, dy: 2),
                      CGRect(x: frame.minX + 2, y: frame.minY + 2, width: 370, height: 64),
                      CGRect(x: frame.minX + 2, y: frame.minY + 2, width: 370, height: 66)]
        let result = UIFrameWait.run(read: {
            let value = frames[min(reads, frames.count - 1)]; reads += 1; time += 0.1
            return value
        }, clock: { time }, poll: { time += $0 })
        XCTAssertTrue(result.stable)
        XCTAssertEqual(reads, 6)
    }
    func testInFlightReadPastObservationDeadlineCannotPass() {
        var time: TimeInterval = 0
        var reads = 0
        let result = UIFrameWait.run(timeout: 1, read: {
            reads += 1; time += 2
            return self.frame.offsetBy(dx: CGFloat(reads), dy: 0)
        }, clock: { time }, poll: { time += $0 })
        XCTAssertFalse(result.stable)
        XCTAssertEqual(result.samples.count, 2)
    }
    func testIdenticalReadsRemainStableWhenSecondSnapshotExceedsDeadline() {
        var time: TimeInterval = 0, reads = 0
        let result = UIFrameWait.run(read: {
            reads += 1; time += reads == 1 ? 0.353 : 14.314
            return self.frame
        }, clock: { time }, poll: { time += $0 })
        XCTAssertTrue(result.stable)
        XCTAssertEqual(result.samples.count, 2)
    }
    func testLateMatchingTailCannotEraseEarlierMovementOrMissingRead() {
        for first in [CGRect?.none, .some(frame.offsetBy(dx: 2, dy: 0))] {
            var time: TimeInterval = 0, reads = 0
            let result = UIFrameWait.run(timeout: 1, read: {
                reads += 1; time += reads == 3 ? 2 : 0.1
                return reads == 1 ? first : self.frame
            }, clock: { time }, poll: { time += $0 })
            XCTAssertFalse(result.stable)
            XCTAssertEqual(reads, 3)
        }
    }
    func testCallerDeadlineCapsTheFirstReadAndStabilization() {
        var time: TimeInterval = 0
        let result = UIFrameWait.run(timeout: 12, deadline: 1, read: { time += 2; return self.frame }, clock: { time }, poll: { time += $0 })
        XCTAssertFalse(result.stable)
        XCTAssertEqual(result.samples.count, 1)
        XCTAssertEqual(time, 2)
    }
    func testCallerDeadlineStillCapsALateSecondMatchingRead() {
        var time: TimeInterval = 0
        let result = UIFrameWait.run(timeout: 12, deadline: 3, read: { time += 2; return self.frame },
                                     clock: { time }, poll: { time += $0 })
        XCTAssertFalse(result.stable)
        XCTAssertEqual(result.samples.count, 2)
    }
}
