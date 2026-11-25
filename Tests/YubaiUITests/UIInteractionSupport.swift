import XCTest

/// Gallery and flow callers use the same typed, element-specific review policy.
/// A combined/unknown category must never fall through to a clipping allowance.
extension GalleryTextReview {
    static func warning(stop: String, issue: XCUIAccessibilityAuditIssue) -> String? {
        guard let target = issue.element else { return nil }
        let category: Category
        switch issue.auditType {
        case .textClipped: category = .textClipped
        case .dynamicType: category = .dynamicType
        default: category = .other
        }
        let kind: Kind = target.elementType == .button ? .button : target.elementType == .staticText ? .text : .other
        return warning(stop: stop, identifier: target.identifier, label: target.label, kind: kind,
                       category: category, selected: target.isSelected,
                       elementDescription: "identifier=\(target.identifier) label=\(target.label) frame=\(target.frame)",
                       auditText: issue.detailedDescription)
    }
}

/// One coherent inventory for both gallery and flow audits. System keyboard
/// controls never get a live per-control query (which itself can trigger AX).
struct UIAppContentAuditScope {
    private var systemNodes: Set<String> = []
    init(_ tree: XCUIElementSnapshot) {
        let roots = UIKeyboardOwnership.roots(in: tree, children: { $0.children }, isKeyboard: { $0.elementType == .keyboard },
            isWindow: { $0.elementType == .window }, isAppPage: {
                $0.identifier.hasPrefix("rootPage_") || $0.identifier == UIWindowMetrics.probeIdentifier
            },
            isIntroduction: { $0.identifier == "UIContinuousPathIntroductionView" })
        func collect(_ node: XCUIElementSnapshot) {
            systemNodes.insert(Self.identity(node))
            for child in node.children { collect(child) }
        }
        for root in roots { collect(root) }
    }
    func isSystemKeyboard(_ node: XCUIElementSnapshot) -> Bool { systemNodes.contains(Self.identity(node)) }
    func isSystemKeyboard(_ element: XCUIElement) -> Bool {
        (try? element.snapshot()).map(isSystemKeyboard) ?? false
    }
    private static func identity(_ node: XCUIElementSnapshot) -> String {
        "\(node.elementType.rawValue)|\(node.identifier)|\(node.label)|\(node.frame)"
    }
    func controls(in tree: XCUIElementSnapshot, app: XCUIApplication) -> [(target: XCUIElement, snapshot: XCUIElementSnapshot)] {
        var result: [(XCUIElement, XCUIElementSnapshot)] = []
        var ordinals: [String: Int] = [:]
        func inventory(_ node: XCUIElementSnapshot) {
            let type = node.elementType
            let key = "\(type.rawValue)|\(node.identifier)|" + (node.identifier.isEmpty ? node.label : "")
            let ordinal = ordinals[key, default: 0]
            ordinals[key] = ordinal + 1
            let interactive = [.button, .textField, .secureTextField, .textView, .switch].contains(type)
            if !isSystemKeyboard(node), (interactive || node.identifier == "toastMessage" && type == .staticText),
               !node.frame.isEmpty, tree.frame.intersects(node.frame) {
                let typed = app.descendants(matching: type)
                let scoped = node.identifier.isEmpty ? typed.matching(NSPredicate(format: "identifier == '' AND label == %@", node.label)) : typed.matching(identifier: node.identifier)
                result.append((scoped.element(boundBy: ordinal), node))
            }
            // Snapshot traversal keeps global query ordinals accurate even if
            // an app label happens to match a key. No system control is queried.
            for child in node.children { inventory(child) }
        }
        inventory(tree)
        return result
    }
}

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
    private var revealedScrollFrames: [CGRect]?
    private var revealedKeyboards: [CGRect] = []
    private var revealedOcclusions: [CGRect] = []
    private var revealedPanOcclusions: [CGRect] = []
    private(set) var revealFailure = ""
    private(set) var transitionWaitReport = ""
    private(set) var windowMetricsReadReport = ""
    private(set) var keyboardWaitReport = ""
    private var lastPrintedMetricsError = ""
    private let scriptedNow = Date().timeIntervalSince1970
    private var diagnosticApp: XCUIApplication?
    private var collectingStalls = false
    private var stallHistory: [String: String] = [:]

    func control(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        // Use the actual control type for high-frequency gallery routes. An
        // Any-descendant firstMatch asks XCTest to walk every AX node, including
        // offscreen cells and diagnostics, just to find a button identifier.
        let query: XCUIElementQuery
        if ["tab_", "keypad_", "ledgerEntry_", "entriesFilter_", "ledgerJumpMonth_", "savingMode_", "softLine_", "modeSoftLine_", "memory_", "swipeEditMemory_"].contains(where: identifier.hasPrefix) ||
            ["fundsFormula", "openSaving", "openSettings", "toggleAmountVisibility", "openLedgerSearch", "openLedgerFilters", "entriesMonth", "entriesSearchCancel",
             "expandButlerHeadline", "butlerAIAccept", "butlerAIIncorrect", "butlerAIEvidence", "openIntelligencePrivacy", "ledgerJumpYear",
             "coverFromReserve", "deficitKeep", "saveMemory", "addEntry", "manageQuickRepeats", "takeSavings", "putBackSavings",
             "confirmSavingsTransfer", "amountSheetCancel", "butlerAICorrectionSave"].contains(identifier) {
            query = app.buttons
        } else if ["butlerAIText", "ledgerStatus", "reserveTotal"].contains(identifier) { query = app.staticTexts }
        else if ["mainNavigation", "rootHeaderRegion", "quickRepeatMenu", "savingsTransferSheet", "savingsTransferPreview",
                 "transferSavedPreview", "transferAvailablePreview", "amountSheetAmount", "fixedBottomBar"].contains(identifier) || identifier.hasPrefix("rootPage_") { query = app.otherElements }
        else if ["entriesSearch", "frequentEntryPurpose"].contains(identifier) { query = app.textFields }
        else if ["butlerAICorrectionText", "memoryText"].contains(identifier) { query = app.textViews }
        else if ["entriesScroll", "formulaPage", "savingTabScroll", "whereCategoryPage", "settingsScroll", "intelligencePrivacyPage", "yubaiScroll", "butlerAIEvidencePage"].contains(identifier) {
            query = app.scrollViews
        } else { query = app.descendants(matching: .any) }
        let target = query.matching(identifier: identifier).firstMatch
        controlQueries[ObjectIdentifier(target)] = (target, identifier)
        return target
    }

    func controlIdentifier(_ target: XCUIElement) -> String {
        controlQueries[ObjectIdentifier(target)]?.1 ?? (target.exists ? target.identifier : "")
    }

    override func record(_ issue: XCTIssue) {
        if handleDeferredUIIssue(issue) { return }
        if launching && issue.compactDescription.contains("Timed out while launching application via Xcode") {
            launchTimeouts.append(issue)
            return
        }
        if launching { otherLaunchFailure = true }
        else {
            if let diagnosticApp { collectMainThreadStalls(in: diagnosticApp, context: name, attach: true) }
            attachTapFailureDiagnostics(reason: issue.compactDescription)
        }
        recordUIIssue(issue)
    }
    func handleDeferredUIIssue(_ issue: XCTIssue) -> Bool { false }
    func recordUIIssue(_ issue: XCTIssue) { super.record(issue) }

    @discardableResult func launchApp(_ app: XCUIApplication, timeout: TimeInterval = 15) -> Bool {
        diagnosticApp = app
        if !app.launchArguments.contains("--ui-test-stall-watchdog") { app.launchArguments.append("--ui-test-stall-watchdog") }
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
            if otherLaunchFailure { collectMainThreadStalls(in: app, context: name, attach: true); return false }
            if let issue = launchTimeouts.last { lastTimeout = issue }
            if launchTimeouts.isEmpty && app.wait(for: .runningForeground, timeout: timeout) { return true }
            collectMainThreadStalls(in: app, context: name + "-launch-\(attempt + 1)", attach: true)
            app.terminate()
            if attempt < 2 { print("Retrying Xcode launch (attempt \(attempt + 2)/3)") }
        }
        if let lastTimeout { recordUIIssue(lastTimeout) }
        else { XCTFail("Application did not reach the foreground after three launch attempts") }
        return false
    }

    /// Preserve every fixture process before a gallery relaunch. These reads
    /// never ask the app to capture/symbolicate a stack; the C watchdog did it.
    func collectMainThreadStalls(in app: XCUIApplication, context: String, attach: Bool = false) {
        guard !collectingStalls else { return }
        collectingStalls = true
        defer { collectingStalls = false }
        var record = "<app diagnostic unavailable; see complete stderr watchdog logs>"
        let probe = app.otherElements.matching(identifier: "uiTestMainThreadStall").firstMatch
        if app.state == .runningForeground, probe.exists, let latest = probe.value as? String {
            record = latest.isEmpty ? "<no main-thread stalls>" : latest
            if !latest.isEmpty {
                let args = app.launchArguments
                let run = args.firstIndex(of: "--test-ledger").flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil } ?? context
                stallHistory[run + " " + latest] = latest
            }
        }
        record += "\nComplete stacks: stalls/*yubai-stalls-*.log or xcodebuild-stalls.log, plus matching .symbolicated.txt; all sources retained. Only source=app denotes app work."
        if attach {
            print("GALLERY-STALL \(context) " + record)
            let attachment = XCTAttachment(string: record)
            attachment.name = context + "-STALL"; attachment.lifetime = .keepAlways; add(attachment)
        }
    }
    func printAllMainThreadStalls(context: String) {
        let report = stallHistory.keys.sorted().map { "run=\($0)\n" + stallHistory[$0]! }.joined(separator: "\n")
        print("GALLERY-STALL \(context) ALL\n" + (report.isEmpty ? "<no main-thread stalls collected>" : report))
        let attachment = XCTAttachment(string: report.isEmpty ? "<no main-thread stalls collected>" : report)
        attachment.name = context + "-STALL"; attachment.lifetime = .keepAlways; add(attachment)
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
        if tree.identifier == UIWindowMetrics.probeIdentifier {
            var values: [String: Any] = [:]
            func collect(_ node: XCUIElementSnapshot) {
                if let value = node.value { values[node.identifier] = value }
                for child in node.children { collect(child) }
            }
            collect(tree)
            let report: (String) -> Void = { self.reportWindowMetricsError($0) }
            if let manifest = values[UIWindowMetrics.probeIdentifier + ".manifest"] {
                return UIWindowMetrics.decodePayload(manifest: manifest, parts: values, onError: report)
            }
            // Preserve a useful diagnostic for older app builds and a newly
            // mounted probe whose first asynchronous sample has not arrived.
            return UIWindowMetrics.decode(tree.value, onError: report)
        }
        for child in tree.children.reversed() { if let metrics = windowMetrics(in: child) { return metrics } }
        if tree.elementType == .application {
            // UIKit can flatten a non-element container. Retain the coherent
            // app snapshot fallback, matching parts by the manifest checksum.
            var manifests: [Any] = [], parts: [String: Any] = [:]
            func collect(_ node: XCUIElementSnapshot) {
                if node.identifier == UIWindowMetrics.probeIdentifier + ".manifest", let value = node.value {
                    manifests.append(value)
                } else if node.identifier.hasPrefix(UIWindowMetrics.probeIdentifier + "."), let value = node.value {
                    parts[node.identifier] = value
                }
                for child in node.children { collect(child) }
            }
            collect(tree)
            for manifest in manifests.reversed() {
                if let metrics = UIWindowMetrics.decodePayload(manifest: manifest, parts: parts,
                    onError: { self.reportWindowMetricsError($0) }) { return metrics }
            }
        }
        return nil
    }

    private func reportWindowMetricsError(_ error: String) {
        windowMetricsReadReport = error
        if lastPrintedMetricsError != error { print(error); lastPrintedMetricsError = error }
    }

    func windowMetrics(in app: XCUIApplication) -> UIWindowMetrics? {
        // Read the small typed probe first. A full app snapshot also resolves
        // every virtualized row and the Chinese keyboard (run 11 search spent
        // its stop budget in keyboard/system and snapshot work). All probes in
        // a window return the same cached native sample. Prefer the modal's;
        // never reuse an element index across presentation/dismissal.
        let probes = app.otherElements.matching(identifier: UIWindowMetrics.probeIdentifier)
            .allElementsBoundByAccessibilityElement
        for probe in probes.reversed() {
            do {
                if let metrics = windowMetrics(in: try probe.snapshot()) {
                    windowMetricsReadReport = ""; lastPrintedMetricsError = ""
                    return metrics
                }
            } catch { reportWindowMetricsError("UI-WINDOW-METRICS snapshot failed: \(error)") }
        }
        do {
            if let metrics = windowMetrics(in: try app.snapshot()) {
                windowMetricsReadReport = ""; lastPrintedMetricsError = ""
                return metrics
            }
            if windowMetricsReadReport.isEmpty { reportWindowMetricsError("UI-WINDOW-METRICS no readable probe in application snapshot; probeCount=\(probes.count)") }
        } catch { reportWindowMetricsError("UI-WINDOW-METRICS application snapshot failed: \(error)") }
        return nil
    }

    func waitForBambooRasters(in app: XCUIApplication, deadline: Date? = nil) -> UIBambooWait.Result {
        let end = deadline.map { ProcessInfo.processInfo.systemUptime + max(0, $0.timeIntervalSinceNow) }
        return UIBambooWait.run(deadline: end, read: { self.windowMetrics(in: app)?.bamboo })
    }

    func waitForBambooCapture(in app: XCUIApplication, deadline: Date? = nil) -> UIBambooWait.Result {
        let end = deadline.map { ProcessInfo.processInfo.systemUptime + max(0, $0.timeIntervalSinceNow) }
        return UIBambooWait.forCapture(deadline: end, read: { self.windowMetrics(in: app) })
    }

    func assertBambooReadyForCapture(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let result = waitForBambooCapture(in: app)
        XCTAssertTrue(result.ready, "Bamboo must finish before capture: \(result) \(windowMetricsReadReport)", file: file, line: line)
    }

    func auditAppText(in app: XCUIApplication, dynamicType: Bool = false, handler: @escaping (XCUIAccessibilityAuditIssue) -> Bool) throws {
        let scope = UIAppContentAuditScope(try app.snapshot())
        try app.performAccessibilityAudit(for: dynamicType ? [.dynamicType, .textClipped] : [.textClipped]) { issue in
            if let element = issue.element, scope.isSystemKeyboard(element) { return true }
            return handler(issue)
        }
    }

    func waitForNativeTransition(in app: XCUIApplication, deadline: Date) -> Bool {
        let end = ProcessInfo.processInfo.systemUptime + max(0, deadline.timeIntervalSinceNow)
        let result = UITransitionWait.run(deadline: end, read: { self.windowMetrics(in: app) })
        transitionWaitReport = result.description
        if !result.settled {
            let report = "UI-TRANSITION-WAIT \(result) remaining=\(deadline.timeIntervalSinceNow) \(windowMetricsReadReport)"
            print(report)
            let attachment = XCTAttachment(string: report)
            attachment.name = "transition-wait"; attachment.lifetime = .keepAlways; add(attachment)
        }
        return result.settled
    }

    /// Save identity before a gesture that can hide its source behind a modal.
    /// Reading addEntry.identifier after the hold queried an absent button and
    /// skipped the menu postcondition. Both gallery and flows use this path.
    func longPressControl(_ target: XCUIElement, in app: XCUIApplication, deadline: Date) -> Bool {
        let identifier = controlIdentifier(target)
        guard waitForNativeTransition(in: app, deadline: deadline),
              revealControl(target, in: app, deadline: deadline),
              waitForStableFrame(target, deadline: deadline), Date() < deadline,
              target.isEnabled, target.isHittable else { return false }
        target.press(forDuration: 0.8)
        guard identifier == "addEntry" else { return Date() < deadline }
        let menu = control("quickRepeatMenu", in: app)
        let end = ProcessInfo.processInfo.systemUptime + max(0, deadline.timeIntervalSinceNow)
        guard UIConditionWait.run(timeout: 5, deadline: end, read: { menu.exists }) else {
            revealFailure = "Long-press menu did not appear: quickRepeatMenu"; return false
        }
        guard waitForNativeTransition(in: app, deadline: deadline), waitForStableFrame(menu, deadline: deadline) else {
            revealFailure = "Long-press menu did not settle: quickRepeatMenu"; return false
        }
        return true
    }

    /// Reveal the full target through all of its native scroll ancestors.
    func revealControl(_ target: XCUIElement, in app: XCUIApplication, deadline: Date,
                       searching scroll: XCUIElement? = nil) -> Bool {
        revealedScrollFrames = nil; revealedKeyboards = []; revealedOcclusions = []
        revealFailure = ""
        let identifier = controlIdentifier(target)
        guard !identifier.isEmpty else { revealFailure = "Missing control identifier"; return false }
        rememberTap(target, in: app)
        var progress = UIRevealProgress()
        var trace: [String] = []
        func attachTrace() {
            let attachment = XCTAttachment(string: trace.joined(separator: "\n"))
            attachment.name = "reveal-" + identifier; attachment.lifetime = .keepAlways; add(attachment)
        }
        var pendingTree: XCUIElementSnapshot?
        var waitedForDiscovery = false
        var searchIdentifier = scroll?.identifier
        func ready(staticText: Bool) -> Bool {
            let end = ProcessInfo.processInfo.systemUptime + max(0, deadline.timeIntervalSinceNow)
            return UIConditionWait.run(timeout: 6, deadline: end, read: {
                target.exists && (staticText || (target.isEnabled && target.isHittable))
            })
        }
        // These controls belong to the fixed header. Its small subtree proves
        // actual ownership without repeatedly enumerating every List cell and
        // (during search) the system keyboard before asking native hittability.
        let headerControls: Set<String> = ["toggleAmountVisibility", "entriesMonth", "openLedgerSearch",
            "openLedgerFilters", "entriesSearch", "entriesSearchCancel"]
        func snapshot() -> XCUIElementSnapshot? {
            if headerControls.contains(identifier) {
                let header = app.otherElements["rootHeaderRegion"].firstMatch
                if header.exists, let tree = try? header.snapshot() {
                    func containsTarget(_ node: XCUIElementSnapshot) -> Bool {
                        node.identifier == identifier || node.children.contains(where: containsTarget)
                    }
                    if containsTarget(tree) { return tree }
                }
            }
            // A keypad key lives in the fixed footer, outside the scroll. This
            // actual owner is small even with a large Form behind its sheet.
            // Keep full-tree keyboard/scroll checks whenever a keyboard is up
            // or the requested key is not owned by this footer.
            if identifier.hasPrefix("keypad_"), !app.keyboards.firstMatch.exists {
                let footer = app.otherElements["fixedBottomBar"].firstMatch
                if footer.exists, let tree = try? footer.snapshot() {
                    func containsTarget(_ node: XCUIElementSnapshot) -> Bool {
                        if node.identifier == identifier {
                            return tree.frame.insetBy(dx: -0.5, dy: -0.5).contains(node.frame)
                        }
                        return node.children.contains(where: containsTarget)
                    }
                    if containsTarget(tree) { return tree }
                }
            }
            return try? app.snapshot()
        }
        func motionSample(in tree: XCUIElementSnapshot, container: XCUIElementSnapshot, viewport: CGRect) -> UIRevealProgress.Sample? {
            var found: XCUIElementSnapshot?
            var targetFrame: CGRect?
            func find(_ node: XCUIElementSnapshot) {
                if node.identifier == identifier { targetFrame = node.frame }
                if node.elementType == container.elementType,
                   (!container.identifier.isEmpty ? node.identifier == container.identifier : node.frame == container.frame) { found = node }
                for child in node.children { find(child) }
            }
            find(tree)
            guard let found else { return nil }
            var landmarks: [String: CGFloat] = [:]
            func mark(_ node: XCUIElementSnapshot) {
                if !node.frame.isEmpty, ![.other, .scrollView, .collectionView, .table].contains(node.elementType) {
                    let key = "\(node.elementType.rawValue)|\(node.identifier)|\(node.label)"
                    if landmarks[key] == nil { landmarks[key] = node.frame.minY }
                }
                for child in node.children { mark(child) }
            }
            mark(found)
            return UIRevealProgress.Sample(target: targetFrame, viewport: viewport, landmarks: landmarks,
                scrollOffset: windowMetrics(in: tree)?.scroll(matching: found.frame)?.remainingUp)
        }
        while Date() < deadline {
            guard let tree = pendingTree ?? snapshot() else { revealFailure = "Snapshot unavailable: " + identifier; break }
            pendingTree = nil
            guard Date() < deadline else {
                revealFailure = "Stop deadline expired during snapshot: " + identifier
                break
            }
            var match: (node: XCUIElementSnapshot, ancestors: [XCUIElementSnapshot], owners: [String])?
            var searchContainer: (node: XCUIElementSnapshot, ancestors: [XCUIElementSnapshot])?
            var keyboards: [CGRect] = []
            var fixed: [(id: String, frame: CGRect)] = []
            let fixedIDs: Set<String> = ["rootHeaderRegion", "mainNavigation", "fixedBottomBar", "toastBody"]
            func collect(_ node: XCUIElementSnapshot, ancestors: [XCUIElementSnapshot], owners: [String] = []) {
                let isFixed = fixedIDs.contains(node.identifier)
                let owners = isFixed ? owners + [node.identifier] : owners
                if node.identifier == identifier { match = (node, ancestors, owners) }
                if node.elementType == .keyboard { keyboards.append(node.frame) }
                if isFixed, !node.frame.isEmpty { fixed.append((node.identifier, node.frame)) }
                let isScroll = [.scrollView, .collectionView, .table].contains(node.elementType)
                if isScroll, let searchIdentifier, node.identifier == searchIdentifier { searchContainer = (node, ancestors) }
                let next = isScroll ? ancestors + [node] : ancestors
                for child in node.children { collect(child, ancestors: next, owners: owners) }
            }
            collect(tree, ancestors: [])
            if identifier.hasPrefix("keypad_"), let match,
               !UIViewportGeometry.keyboardClears(match.node.frame, keyboards: keyboards) {
                // The purpose field's Return publishes focus before UIKit has
                // removed its keyboard. Never mistake that transition for an
                // unreachable fixed keypad, and never drag the system keyboard.
                guard waitForKeyboardDismissal(in: app, deadline: deadline) else { return false }
                guard waitForStableFrame(target, deadline: deadline) else { return false }
                continue
            }
            if match == nil && !waitedForDiscovery {
                waitedForDiscovery = true
                _ = target.waitForExistence(timeout: min(5, max(0, deadline.timeIntervalSinceNow)))
                continue
            }
            let ancestors = match?.ancestors ?? []
            // The app already reserves the measured root controls. AX can
            // retain a larger collection frame; reveal through its unobscured
            // region instead of accepting a covered row and failing early.
            let occlusions = UIViewportGeometry.fixedOcclusions(fixed, owners: match?.owners ?? [],
                hasScrollAncestors: !ancestors.isEmpty || match == nil, window: tree.frame)
            let panOcclusions = keyboards + fixed.filter { !(match?.owners ?? []).contains($0.id) }.map(\.frame)
            if let match {
                let staticText = match.node.elementType == .staticText
                let fits = UIViewportGeometry.revealed(exists: true, enabled: true, hittable: true, staticText: staticText,
                    frame: match.node.frame, scrollAncestors: ancestors.map(\.frame), keyboards: keyboards, occlusions: occlusions)
                if fits {
                    guard ready(staticText: staticText) else {
                        revealFailure = Date() >= deadline ? "Stop deadline expired during native readiness: " + identifier
                            : "Native control stayed disabled or covered: " + identifier
                        print("Reveal reached a disabled or covered control: \(identifier)")
                        return false
                    }
                    // Recheck the live target after the bounded native wait.
                    guard let current = try? target.snapshot(), Date() < deadline,
                          UIViewportGeometry.revealed(exists: true, enabled: current.isEnabled,
                            hittable: staticText || target.isHittable, staticText: staticText, frame: current.frame,
                            scrollAncestors: ancestors.map(\.frame), keyboards: keyboards, occlusions: occlusions) else { continue }
                    rememberTap(target, in: app, frame: current.frame)
                    revealedScrollFrames = ancestors.map(\.frame); revealedKeyboards = keyboards; revealedOcclusions = occlusions
                    revealedPanOcclusions = panOcclusions
                    return true
                }
            }
            // Missing virtualized rows may be searched only in a scroll view
            // supplied by their caller or observed as their actual ancestor,
            // never an unrelated page.
            // A present menu/tab/header has no scroll ancestor to drag.
            let container = ancestors.last { node in
                match.map { !node.frame.insetBy(dx: -0.5, dy: -0.5).contains($0.node.frame) } ?? false
            } ?? ancestors.last ?? (match == nil ? searchContainer?.node : nil)
            guard let container else {
                if let match { rememberTap(target, in: app, frame: match.node.frame) }
                revealFailure = "No scroll ancestor: " + identifier
                print("Reveal has no scroll ancestor: \(identifier)")
                return false
            }
            if !container.identifier.isEmpty { searchIdentifier = container.identifier }
            let containerIndex = ancestors.lastIndex { $0.elementType == container.elementType && $0.identifier == container.identifier && $0.frame == container.frame }
            let enclosingFrames = containerIndex.map { Array(ancestors.prefix($0)).map(\.frame) } ?? searchContainer?.ancestors.map(\.frame) ?? []
            let clipped = UIViewportGeometry.clipped(container.frame, to: enclosingFrames)
            // The complete target must fit above the toast. Gesture planning
            // separately keeps the physical gutter beside that same toast.
            let viewport = UIViewportGeometry.visibleParts(clipped, ancestors: [], excluding: keyboards + occlusions)
                .max(by: { $0.width * $0.height < $1.width * $1.height }) ?? .zero
            guard let sample = motionSample(in: tree, container: container, viewport: viewport) else {
                revealFailure = "Scroll ancestor disappeared: " + identifier; return false
            }
            let step = progress.next(sample)
            let travel = windowMetrics(in: tree)?.scroll(matching: container.frame)
            trace.append("target=\(String(describing: sample.target)) container=\(container.identifier) viewport=\(viewport) offset=\(String(describing: sample.scrollOffset)) remainingDown=\(String(describing: travel?.remainingDown)) \(step)")
            switch step {
            case .reached:
                // The pure rule above also checks every outer ancestor and
                // native hittability; a drag planner cannot grant reachability.
                revealFailure = "Control does not fit through all scroll ancestors: " + identifier
                print("Reveal cannot fit the control through its ancestors: \(identifier)\n" + trace.joined(separator: "\n"))
                return false
            case .stalled:
                revealFailure = "Scroll made no progress: " + identifier
                attachTrace()
                print("Reveal made no progress: \(identifier)\n" + trace.joined(separator: "\n"))
                return false
            case .drag, .dragHorizontally:
                guard let gesture = UIRevealPan.plan(step, viewport: clipped, nativeOrigins: travel?.panOrigins,
                                                    excluding: panOcclusions) else {
                    revealFailure = "No native pan lane in scroll viewport: " + identifier
                    attachTrace()
                    print("Reveal has no pan lane: \(identifier)\n" + trace.joined(separator: "\n"))
                    return false
                }
                let start = gesture.start, end = gesture.end
                trace.append("pan start=\(start) end=\(end) physicalViewport=\(clipped) occlusions=\(panOcclusions) nativeOrigins=\(String(describing: travel?.panOrigins))")
                let origin = app.coordinate(withNormalizedOffset: .zero)
                origin.withOffset(CGVector(dx: start.x - tree.frame.minX, dy: start.y - tree.frame.minY))
                    .press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: end.x - tree.frame.minX, dy: end.y - tree.frame.minY)),
                           withVelocity: .slow, thenHoldForDuration: 0.1)
            }
            let end = ProcessInfo.processInfo.systemUptime + max(0, deadline.timeIntervalSinceNow)
            guard UIRevealMotionWait.run(from: sample, deadline: end, read: {
                guard let next = snapshot() else { return nil }
                pendingTree = next
                return motionSample(in: next, container: container, viewport: viewport)
            }) else {
                revealFailure = "Scroll made no progress after gesture: " + identifier
                attachTrace()
                print("Reveal made no progress: \(identifier)\n" + trace.joined(separator: "\n"))
                return false
            }
        }
        if revealFailure.isEmpty { revealFailure = "Reveal deadline: " + identifier }
        print("Reveal deadline: \(identifier)\n" + trace.joined(separator: "\n"))
        return false
    }

    func settledControlClearsViewport(_ target: XCUIElement) -> Bool {
        guard let ancestors = revealedScrollFrames else { return false }
        let frame = lastFrameWait?.target === target ? lastFrameWait?.result.frame : (try? target.snapshot())?.frame
        return frame.map { UIViewportGeometry.revealed(exists: true, enabled: true, hittable: true,
            frame: $0, scrollAncestors: ancestors, keyboards: revealedKeyboards, occlusions: revealedOcclusions) } ?? false
    }

    /// The caller reveals the row first. Freeze its final frame and address
    /// the application, not the row's AX activation target. Success here means
    /// only that the pan was sent; callers must still assert every native action.
    func swipeToRevealTrailingActions(_ row: XCUIElement, in app: XCUIApplication, deadline: Date) -> Bool {
        let identifier = row.identifier, window = app.frame
        // Sample the final frame after the native readiness queries. No row
        // query or further reveal is allowed to retarget the planned touch.
        guard row.isEnabled, row.isHittable, waitForStableFrame(row, deadline: deadline),
              settledControlClearsViewport(row), let frames = revealedScrollFrames,
              let frame = lastFrameWait?.result.frame else {
            revealFailure = "Swipe row is not settled and clear: \(identifier); \(lastFrameWait?.result.description ?? "no frame")"
            return false
        }
        let viewport = UIViewportGeometry.clipped(window, to: frames)
        let occlusions = revealedKeyboards + revealedPanOcclusions
        guard Date() < deadline, let gesture = UIRowSwipe.plan(row: frame, viewport: viewport, excluding: occlusions) else {
            revealFailure = "No clear row swipe: \(identifier) row=\(frame) viewport=\(viewport) occlusions=\(occlusions)"
            return false
        }
        print("UI-ROW-SWIPE identifier=\(identifier) row=\(frame) viewport=\(viewport) start=\(gesture.start) end=\(gesture.end)")
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let start = origin.withOffset(CGVector(dx: gesture.start.x - window.minX, dy: gesture.start.y - window.minY))
        let end = origin.withOffset(CGVector(dx: gesture.end.x - window.minX, dy: gesture.end.y - window.minY))
        start.press(forDuration: 0, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
        return true
    }

    /// Frame a group for capture using its real scroll viewport. The optional
    /// visual clearance is the known page-fade height, not a hittability waiver;
    /// every control still passes the ordinary reveal/native hit checks.
    func revealControlsTogether(_ targets: [XCUIElement], in app: XCUIApplication, deadline: Date,
                                searching scroll: XCUIElement, bottomClearance: CGFloat = 0) -> Bool {
        guard let last = targets.last, revealControl(last, in: app, deadline: deadline, searching: scroll),
              waitForStableFrame(last, deadline: deadline),
              let frames = revealedScrollFrames, let inner = frames.last else { return false }
        let viewport = UIViewportGeometry.visibleParts(inner, ancestors: frames,
            excluding: revealedKeyboards + revealedOcclusions).max { $0.width * $0.height < $1.width * $1.height } ?? .zero
        guard !viewport.isEmpty, targets.allSatisfy(\.exists) else { return false }
        let group = targets.map(\.frame).reduce(CGRect.null) { $0.union($1) }
        if group.maxY > viewport.maxY - bottomClearance {
            // Center the answers so neither label rests in the bottom fade.
            // A single bounded drag is enough after revealing the last answer.
            let distance = min(viewport.height * 0.5, max(bottomClearance, group.midY - viewport.midY))
            let travel = windowMetrics(in: app)?.scroll(matching: inner)
            guard let gesture = UIRevealPan.plan(.drag(up: true, distance: distance), viewport: UIViewportGeometry.clipped(inner, to: frames),
                                                nativeOrigins: travel?.panOrigins, excluding: revealedPanOcclusions) else { return false }
            let start = gesture.start, end = gesture.end
            let origin = app.coordinate(withNormalizedOffset: .zero)
            origin.withOffset(CGVector(dx: start.x - app.frame.minX, dy: start.y - app.frame.minY))
                .press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: end.x - app.frame.minX, dy: end.y - app.frame.minY)),
                       withVelocity: .slow, thenHoldForDuration: 0.1)
            guard waitForStableFrame(last, deadline: deadline) else { return false }
        }
        for target in targets {
            guard revealControl(target, in: app, deadline: deadline, searching: scroll) else { return false }
        }
        // Recheck the group after all reveals, since revealing a later control
        // could have moved an earlier one. All labels must fit simultaneously.
        return targets.allSatisfy { target in
            UIViewportGeometry.revealed(exists: target.exists, enabled: target.isEnabled, hittable: target.isHittable,
                frame: target.frame, scrollAncestors: frames, keyboards: revealedKeyboards, occlusions: revealedOcclusions) &&
                target.frame.maxY <= viewport.maxY - bottomClearance + 0.5
        }
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
        let before = field.value as? String
        tapControl(field, in: app)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), identifier)
        XCTAssertTrue(dismissKeyboardIntroduction(in: app))
        XCTAssertTrue(waitForKeyboardEditing(identifier, in: app), "Keyboard/focus did not settle: " + identifier + " " + windowMetricsReadReport)
        field.typeText(text)
        var observed: String?
        let retained = UIConditionWait.run(timeout: 6, read: {
            observed = field.value as? String
            return UIFieldTextRetention.matches(observed, before: before, typed: text)
        })
        var diagnostic = ""
        if !retained {
            let metrics = windowMetrics(in: app)
            diagnostic = " focused=\(metrics?.focused ?? "unreadable") host=\(metrics?.focusedHost ?? "none") " +
                "transitioning=\(String(describing: metrics?.transitioning)) " + windowMetricsReadReport +
                " events=" + (metrics?.inputFocusEvents ?? []).joined(separator: "\n")
        }
        XCTAssertTrue(retained, "Field did not retain the full text: \(identifier) before=\(String(reflecting: before)) typed=\(String(reflecting: text)) actual=\(String(reflecting: observed))" + diagnostic)
        if text.hasSuffix("\n") { XCTAssertTrue(waitForKeyboardDismissal(in: app), "Keyboard did not dismiss after submitting " + identifier) }
    }

    func waitForKeyboardDismissal(in app: XCUIApplication, deadline: Date? = nil) -> Bool {
        let limit = deadline ?? Date().addingTimeInterval(12)
        let end = ProcessInfo.processInfo.systemUptime + max(0, limit.timeIntervalSinceNow)
        return UIConditionWait.run(timeout: 10, deadline: end, read: { !app.keyboards.firstMatch.exists }) &&
            waitForNativeTransition(in: app, deadline: limit)
    }

    func waitForKeyboardEditing(_ identifier: String, in app: XCUIApplication, deadline: Date? = nil) -> Bool {
        let limit = deadline ?? Date().addingTimeInterval(20)
        let end = ProcessInfo.processInfo.systemUptime + max(0, limit.timeIntervalSinceNow)
        var observed: UIWindowMetrics?
        keyboardWaitReport = ""
        func hasFocus() -> Bool {
            observed = windowMetrics(in: app)
            return observed?.transitioning == false && observed?.focused == identifier
        }
        func failed() -> Bool {
            keyboardWaitReport = "UI-KEYBOARD-WAIT expected=\(identifier) focused=\(observed?.focused ?? "unreadable") " +
                "transitioning=\(String(describing: observed?.transitioning)) appeared=\(String(describing: observed?.focusedAfterAppearance)) " +
                windowMetricsReadReport + " events=" + (observed?.inputFocusEvents ?? []).joined(separator: "\n")
            print(keyboardWaitReport)
            let attachment = XCTAttachment(string: keyboardWaitReport)
            attachment.name = "keyboard-wait"; attachment.lifetime = .keepAlways; add(attachment)
            return false
        }
        guard UIConditionWait.run(timeout: 10, deadline: end, read: {
            guard hasFocus() else { return false }
            return app.keyboards.firstMatch.exists
        }) else { return failed() }
        let field = control(identifier, in: app), keyboard = app.keyboards.firstMatch
        guard waitForStableFrame(keyboard, deadline: limit) && waitForStableFrame(field, deadline: limit) &&
            hasFocus() && UIViewportGeometry.keyboardClears(field.frame, keyboards: [keyboard.frame]) else { return failed() }
        return true
    }

    /// The native tree flattens navigationCapsule into mainNavigation. Its three
    /// real tab buttons are present on every root; their union plus the existing
    /// 6pt surface inset is exactly the capsule, excluding the home entry pill.
    func capsuleFrame(in app: XCUIApplication) -> CGRect {
        let tabs = ["tab_ledger", "tab_insights", "tab_yubai"].map { app.buttons[$0] }
        for tab in tabs { XCTAssertTrue(tab.waitForExistence(timeout: 5), tab.identifier) }
        return tabs.map(\.frame).reduce(CGRect.null) { $0.union($1) }.insetBy(dx: -6, dy: -6)
    }
}
