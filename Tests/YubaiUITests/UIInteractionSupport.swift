import XCTest

/// All walks and UI tests share the same bounded launch recovery. Only Xcode's
/// launch timeout is held for a retry; unrelated XCTest failures are recorded.
class YubaiUITestCase: XCTestCase {
    private var launching = false
    private var launchTimeouts: [XCTIssue] = []
    private var otherLaunchFailure = false
    private struct TapContext {
        let target: XCUIElement
        let app: XCUIApplication
        var frame: CGRect?
        var wasEnabled: Bool?
        var wasHittable: Bool?
    }
    private var lastTap: TapContext?
    private var lastFrameWait: (target: XCUIElement, result: UIFrameWait.Result)?
    private var attachedTapDiagnostics = false
    private var controlQueries: [ObjectIdentifier: (XCUIElement, String)] = [:]
    private var revealedViewport: CGRect?
    private let scriptedNow = Date().timeIntervalSince1970

    func control(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        let target = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
        controlQueries[ObjectIdentifier(target)] = (target, identifier)
        return target
    }

    override func record(_ issue: XCTIssue) {
        if launching && issue.compactDescription.contains("Timed out while launching application via Xcode") {
            launchTimeouts.append(issue)
            return
        }
        if launching { otherLaunchFailure = true }
        else { attachTapFailureDiagnostics(reason: issue.compactDescription) }
        recordUIIssue(issue)
    }
    func recordUIIssue(_ issue: XCTIssue) { super.record(issue) }

    @discardableResult func launchApp(_ app: XCUIApplication, timeout: TimeInterval = 15) -> Bool {
        lastTap = nil; lastFrameWait = nil; controlQueries = [:]
        if app.launchEnvironment["YUBAI_UI_TEST_NOW"] == nil {
            app.launchEnvironment["YUBAI_UI_TEST_NOW"] = String(scriptedNow)
        }
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

    /// Keep both real snapshots, without a separate existence query per poll.
    /// A caller with a stop deadline can still cap the entire operation.
    func waitForStableFrame(_ target: XCUIElement, timeout: TimeInterval = 12, deadline: Date? = nil) -> Bool {
        let end = deadline.map { ProcessInfo.processInfo.systemUptime + max(0, $0.timeIntervalSinceNow) }
        let result = UIFrameWait.run(timeout: timeout, deadline: end, read: { (try? target.snapshot())?.frame })
        lastFrameWait = (target, result)
        if lastTap?.target === target { lastTap?.frame = result.frame }
        if !result.stable { print(result.description) }
        return result.stable
    }

    func waitForDisappearance(_ target: XCUIElement, timeout: TimeInterval = 12) -> Bool {
        UIConditionWait.run(timeout: timeout, read: { !target.exists })
    }

    /// Remember the frame already read by the settling helper. Everything else
    /// is collected on failure, so successful taps incur no diagnostic snapshot.
    func rememberTap(_ target: XCUIElement, in app: XCUIApplication, frame sampledFrame: CGRect? = nil) {
        let frame = sampledFrame ?? (lastFrameWait?.target === target ? lastFrameWait?.result.frame : nil)
        lastTap = TapContext(target: target, app: app, frame: frame)
        attachedTapDiagnostics = false
    }

    func tapControl(_ target: XCUIElement, in app: XCUIApplication, settles: Bool = true, reveals: Bool = true,
                    file: StaticString = #filePath, line: UInt = #line) {
        let deadline = Date().addingTimeInterval(180)
        if reveals && !revealControl(target, in: app, deadline: deadline) {
            XCTFail("Control not reachable: " + target.description, file: file, line: line)
            return
        }
        rememberTap(target, in: app)
        if settles && !waitForStableFrame(target) {
            XCTFail("Control frame did not settle: " + target.description, file: file, line: line)
            return
        }
        let enabled = target.isEnabled, hittable = target.isHittable
        lastTap?.wasEnabled = enabled; lastTap?.wasHittable = hittable
        guard enabled && hittable else {
            XCTFail("Control disabled or covered: " + target.description, file: file, line: line)
            return
        }
        if reveals && !settledControlClearsViewport(target) && !revealControl(target, in: app, deadline: deadline) {
            XCTFail("Control left its usable viewport: " + target.description, file: file, line: line)
            return
        }
        target.tap()
    }

    func windowMetrics(in tree: XCUIElementSnapshot) -> UIWindowMetrics? {
        if tree.identifier == UIWindowMetrics.probeIdentifier, let metrics = UIWindowMetrics.decode(tree.value) { return metrics }
        for child in tree.children.reversed() { if let metrics = windowMetrics(in: child) { return metrics } }
        return nil
    }

    func windowMetrics(in app: XCUIApplication) -> UIWindowMetrics? {
        // A modal may hide the root background from AX. Read whichever root
        // or shared-sheet probe exists; its frame/hittability are irrelevant.
        for probe in app.descendants(matching: .any).matching(identifier: UIWindowMetrics.probeIdentifier).allElementsBoundByIndex.reversed() {
            if let metrics = UIWindowMetrics.decode(probe.value) { return metrics }
        }
        return nil
    }

    func waitForNativeTransition(in app: XCUIApplication, deadline: Date) -> Bool {
        let end = ProcessInfo.processInfo.systemUptime + max(0, deadline.timeIntervalSinceNow)
        return UIConditionWait.run(timeout: 15, deadline: end, read: {
            guard let value = self.windowMetrics(in: app) else { return false }
            return !value.transitioning
        })
    }

    /// Reveal the full target through all of its native scroll ancestors.
    func revealControl(_ target: XCUIElement, in app: XCUIApplication, deadline: Date) -> Bool {
        revealedViewport = nil
        let identifier = controlQueries[ObjectIdentifier(target)]?.1 ?? (target.exists ? target.identifier : "")
        guard !identifier.isEmpty else { return false }
        rememberTap(target, in: app)
        var progress = UIRevealProgress()
        var trace: [String] = []
        var waitedForDiscovery = false
        func ready() -> Bool {
            if target.isHittable { return Date() < deadline }
            let end = ProcessInfo.processInfo.systemUptime + max(0, deadline.timeIntervalSinceNow)
            return UIConditionWait.run(timeout: 6, deadline: end, read: { target.exists && target.isHittable })
        }
        while Date() < deadline {
            guard let tree = try? app.snapshot(), Date() < deadline else { break }
            guard let metrics = windowMetrics(in: tree) else {
                print("Reveal has no native window metrics: \(identifier)")
                return false
            }
            if metrics.transitioning {
                guard waitForNativeTransition(in: app, deadline: deadline) else { return false }
                continue
            }
            var match: (XCUIElementSnapshot, [XCUIElementSnapshot])?
            var scrolls: [XCUIElementSnapshot] = []
            var topRegions: [CGRect] = [], bottomRegions: [CGRect] = [], toastRegions: [CGRect] = []
            func collect(_ node: XCUIElementSnapshot, ancestors: [XCUIElementSnapshot]) {
                if [.scrollView, .collectionView, .table].contains(node.elementType),
                   node.frame.height > 120, node.frame.width > tree.frame.width * 0.65 { scrolls.append(node) }
                if node.identifier == identifier, !node.frame.isEmpty { match = (node, ancestors) }
                if node.elementType == .navigationBar || node.identifier == "rootHeaderRegion" { topRegions.append(node.frame) }
                if node.elementType == .keyboard || ["mainNavigation", "fixedBottomBar"].contains(node.identifier) { bottomRegions.append(node.frame) }
                if ["toastMessage", "undoLastChange", "expandToast"].contains(node.identifier) { toastRegions.append(node.frame) }
                for child in node.children { collect(child, ancestors: ancestors + [node]) }
            }
            collect(tree, ancestors: [])
            if match == nil && !waitedForDiscovery {
                waitedForDiscovery = true
                _ = target.waitForExistence(timeout: min(5, max(0, deadline.timeIntervalSinceNow)))
                continue
            }
            let ancestors = match?.1.filter { [.scrollView, .collectionView, .table].contains($0.elementType) } ?? []
            func usable(_ frame: CGRect) -> CGRect {
                var viewport = frame.intersection(metrics.safeRectangle)
                guard !viewport.isNull, !viewport.isEmpty else { return .zero }
                for region in topRegions where UIViewportGeometry.overlaps(viewport, region) {
                    if region.minY <= viewport.minY + 0.5 {
                        let bottom = viewport.maxY; viewport.origin.y = max(viewport.minY, region.maxY)
                        viewport.size.height = max(0, bottom - viewport.minY)
                    }
                }
                let toasts = ["toastMessage", "undoLastChange", "expandToast"].contains(identifier) ? [] : toastRegions
                for region in bottomRegions + toasts where UIViewportGeometry.overlaps(viewport, region) {
                    viewport.size.height = max(0, min(viewport.maxY, region.minY - 12) - viewport.minY)
                }
                return viewport
            }
            let container = ancestors.last { node in
                match.map { !usable(node.frame).insetBy(dx: -0.5, dy: -0.5).contains($0.0.frame) } ?? false
            } ?? ancestors.last ?? (match == nil ? scrolls.last : nil)
            // Fixed headers and bars have no scroll ancestor. A covered fixed
            // control cannot be repaired by dragging an unrelated page.
            if let match, container == nil {
                rememberTap(target, in: app, frame: match.0.frame)
                revealedViewport = metrics.safeRectangle
                return metrics.safeRectangle.contains(match.0.frame) && ready()
            }
            guard let container else { break }
            let containerIndex = ancestors.lastIndex { $0.elementType == container.elementType && $0.identifier == container.identifier && $0.frame == container.frame }
            let enclosingFrames = containerIndex.map { Array(ancestors.prefix($0 + 1)).map(\.frame) } ?? []
            // When an outer vertical scroll clips a horizontal chip strip,
            // drag in the outer viewport, not the 22pt remnant of that strip.
            let viewport = usable(UIViewportGeometry.clipped(container.frame.intersection(tree.frame), to: enclosingFrames))
            var landmarks: [String: CGFloat] = [:]
            func mark(_ node: XCUIElementSnapshot) {
                if !node.frame.isEmpty, ![.other, .scrollView, .collectionView, .table].contains(node.elementType) {
                    let key = "\(node.elementType.rawValue)|\(node.identifier)|\(node.label)"
                    if landmarks[key] == nil { landmarks[key] = node.frame.minY }
                }
                for child in node.children { mark(child) }
            }
            mark(container)
            let sample = UIRevealProgress.Sample(target: match?.0.frame, viewport: viewport, landmarks: landmarks)
            let step = progress.next(sample)
            trace.append("target=\(String(describing: sample.target)) viewport=\(viewport) \(step)")
            switch step {
            case .reached:
                rememberTap(target, in: app, frame: match?.0.frame)
                revealedViewport = viewport
                if ready() { return true }
                print("Reveal reached a covered control: \(identifier)\n" + trace.joined(separator: "\n"))
                return false
            case .stalled:
                print("Reveal made no progress: \(identifier)\n" + trace.joined(separator: "\n"))
                return false
            case let .drag(up, distance):
                // Start well inside the viewport, away from edge effects and
                // fixed chrome. A drag from the last 16pt can hit a clipped row.
                let start = CGPoint(x: viewport.midX, y: viewport.minY + viewport.height * (up ? 0.78 : 0.22))
                let end = CGPoint(x: start.x, y: min(viewport.maxY - 12, max(viewport.minY + 12, start.y + (up ? -distance : distance))))
                let origin = app.coordinate(withNormalizedOffset: .zero)
                origin.withOffset(CGVector(dx: start.x - tree.frame.minX, dy: start.y - tree.frame.minY))
                    .press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: end.x - tree.frame.minX, dy: end.y - tree.frame.minY)),
                           withVelocity: .slow, thenHoldForDuration: 0.1)
            case let .dragHorizontally(left, distance):
                let start = CGPoint(x: viewport.minX + viewport.width * (left ? 0.78 : 0.22), y: viewport.midY)
                let end = CGPoint(x: min(viewport.maxX - 12, max(viewport.minX + 12, start.x + (left ? -distance : distance))), y: start.y)
                let origin = app.coordinate(withNormalizedOffset: .zero)
                origin.withOffset(CGVector(dx: start.x - tree.frame.minX, dy: start.y - tree.frame.minY))
                    .press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: end.x - tree.frame.minX, dy: end.y - tree.frame.minY)),
                           withVelocity: .slow, thenHoldForDuration: 0.1)
            }
        }
        print("Reveal deadline: \(identifier)\n" + trace.joined(separator: "\n"))
        return false
    }

    func settledControlClearsViewport(_ target: XCUIElement) -> Bool {
        guard let viewport = revealedViewport else { return false }
        let frame = lastFrameWait?.target === target ? lastFrameWait?.result.frame : (try? target.snapshot())?.frame
        return frame.map { viewport.insetBy(dx: -0.5, dy: -0.5).contains($0) } ?? false
    }

    /// Deliberately place a row across fixed chrome while some of it is still
    /// visible. Tests then tap the fixed control and verify its destination.
    func placeControl(_ target: XCUIElement, across fixed: XCUIElement, in scroll: XCUIElement, atTop: Bool) -> Bool {
        guard target.exists, fixed.exists, scroll.exists else { return false }
        for _ in 0..<6 {
            let row = target.frame, control = fixed.frame, viewport = scroll.frame
            if UIViewportGeometry.overlaps(row, control), !row.intersection(viewport).isEmpty { return true }
            let movement = atTop ? control.midY - row.minY : control.midY - row.maxY
            let distance = min(viewport.height * 0.45, max(12, abs(movement))) * (movement < 0 ? -1 : 1)
            let start = CGPoint(x: viewport.midX, y: viewport.minY + viewport.height * (movement < 0 ? 0.78 : 0.22))
            let end = CGPoint(x: start.x, y: min(viewport.maxY - 12, max(viewport.minY + 12, start.y + distance)))
            let origin = appCoordinate(scroll)
            origin.withOffset(CGVector(dx: start.x, dy: start.y))
                .press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: end.x, dy: end.y)),
                       withVelocity: .slow, thenHoldForDuration: 0.1)
        }
        return false
    }

    private func appCoordinate(_ element: XCUIElement) -> XCUICoordinate {
        // A scroll-relative coordinate must subtract the scroll's screen origin.
        element.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: -element.frame.minX, dy: -element.frame.minY))
    }

    func assertViewport(_ scroll: XCUIElement, clears fixed: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        guard scroll.exists, fixed.exists else {
            XCTFail("Missing scroll viewport or fixed control", file: file, line: line)
            return
        }
        XCTAssertFalse(scroll.frame.isEmpty, file: file, line: line)
        XCTAssertFalse(UIViewportGeometry.overlaps(scroll.frame, fixed.frame),
                       "Scroll viewport under fixed control: \(scroll.identifier) \(scroll.frame) / \(fixed.identifier) \(fixed.frame)", file: file, line: line)
    }

    /// AX sibling order is only a candidate for front-to-back ordering; XCTest
    /// does not expose the app's UIView.hitTest or its synthesized hit point.
    func attachTapFailureDiagnostics(reason: String) {
        guard let context = lastTap, !attachedTapDiagnostics else { return }
        attachedTapDiagnostics = true
        var lines = ["Tap failure: " + reason]
        lines.append("Before tap: isHittable=\(context.wasHittable.map(String.init(describing:)) ?? "<not sampled>") isEnabled=\(context.wasEnabled.map(String.init(describing:)) ?? "<not sampled>")")
        func describe(_ node: XCUIElementSnapshot) -> String {
            "type=\(node.elementType) identifier=\(String(reflecting: node.identifier)) label=\(String(reflecting: node.label)) frame=\(node.frame) isEnabled=\(node.isEnabled)"
        }
        var frameAtFailure: CGRect?
        if context.target.exists, let snapshot = try? context.target.snapshot() {
            frameAtFailure = snapshot.frame
            lines.append("Target now: " + describe(snapshot) + " isHittable=\(context.target.isHittable)")
        } else { lines.append("Target now: <absent>; " + context.target.description + " isHittable=false isEnabled=<unavailable>") }
        let intendedFrame = context.frame
        lines.append("Target frame before tap: " + (intendedFrame.map(String.init(describing:)) ?? "<not sampled>"))
        if let wait = lastFrameWait, wait.target === context.target { lines.append(wait.result.description) }
        if let snapshot = try? context.app.snapshot() {
            var windows: [String] = []
            func collectWindows(_ node: XCUIElementSnapshot) {
                if node.elementType == .window { windows.append(describe(node)) }
                for child in node.children { collectWindows(child) }
            }
            collectWindows(snapshot)
            lines.append("Windows (AX order):\n" + windows.joined(separator: "\n"))
            if let frame = intendedFrame ?? frameAtFailure {
                let point = CGPoint(x: frame.midX, y: frame.midY)
                lines.append("Tap center: \(point) from \(intendedFrame == nil ? "failure snapshot (original point unavailable)" : "before-tap frame"); XCTest's actual hit point is not exposed")
                func candidates(_ node: XCUIElementSnapshot, ancestors: [String]) -> [String] {
                    let path = ancestors + [describe(node)]
                    let deeper = node.children.reversed().flatMap { candidates($0, ancestors: path) }
                    if !deeper.isEmpty { return deeper }
                    return node.frame.contains(point) ? [path.joined(separator: "\n  -> ")] : []
                }
                lines.append("Deepest AX candidates containing center (reverse sibling order, not a UIKit hit-test):\n" + candidates(snapshot, ancestors: []).prefix(20).joined(separator: "\n\n"))
            }
        } else { lines.append("App snapshot and window inventory unavailable") }
        let report = lines.joined(separator: "\n")
        print("UI-TAP-DIAGNOSTICS\n" + report)
        let attachment = XCTAttachment(string: report)
        attachment.name = "tap-failure-diagnostics"; attachment.lifetime = .keepAlways; add(attachment)
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
        tapControl(field, in: app)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), identifier)
        XCTAssertTrue(dismissKeyboardIntroduction(in: app))
        field.typeText(text)
        let expected = text.trimmingCharacters(in: .newlines)
        XCTAssertTrue(UIConditionWait.run(timeout: 6, read: { (field.value as? String ?? "").contains(expected) }),
                      "Field did not retain the full text: " + identifier)
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
