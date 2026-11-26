#if DEBUG
import Foundation

enum UITestDesignSystemGallery {
    private static let flag = "-YubaiDesignSystemGallery"
    private static let arguments = ProcessInfo.processInfo.arguments
    static let enabled = arguments.contains(flag) || ProcessInfo.processInfo.environment["YUBAI_DS_GALLERY"] == "1"
    static let component = arguments.firstIndex(of: flag).flatMap { index in
        arguments.dropFirst(index + 1).first.flatMap { $0.hasPrefix("-") ? nil : $0 }
    }
}

/// Pure app-side wire contract, also compiled by scripts/test-ui-helpers.py.
/// XCTest truncates AX snapshot values at 512 characters (run 12 retained two
/// exact 512-character JSON prefixes). Keep every value below that boundary;
/// one subtree snapshot carries a manifest and generation-matched data parts.
enum UITestMetricsPayload {
    static let identifier = "uiTestWindowMetrics"
    static let partLength = 400
    struct Packet {
        let manifest: String
        let parts: [(identifier: String, value: String)]
    }
    static func dictionary(safeArea: [Double], transitioning: Bool, activeTransitions: [String],
                           focused: String, focusedAfterAppearance: Bool?, scrolls: [[String: Any]],
                           bamboo: [String: Any]?, bambooSurface: [String: Any]?,
                           paperDiagnostics: String? = nil, inputFocusEvents: [String]? = nil, focusedHost: String? = nil, nativeSheetFrame: [Double]? = nil) -> [String: Any] {
        var value: [String: Any] = ["safeArea": safeArea, "transitioning": transitioning,
            "activeTransitions": activeTransitions, "focused": focused, "scrolls": scrolls]
        if let focusedAfterAppearance { value["focusedAfterAppearance"] = focusedAfterAppearance }
        if let bamboo { value["bamboo"] = bamboo }
        if let bambooSurface { value["bambooSurface"] = bambooSurface }
        if let paperDiagnostics { value["paperDiagnostics"] = paperDiagnostics }
        if let inputFocusEvents { value["inputFocusEvents"] = inputFocusEvents }
        if let focusedHost { value["focusedHost"] = focusedHost }
        if let nativeSheetFrame { value["nativeSheetFrame"] = nativeSheetFrame }
        return value
    }
    static func bamboo(ready: [String], pending: Int, pendingKeys: [String], failed: [String],
                       failedStages: [String: String], renders: Int, mainRenders: Int,
                       activeRenders: Int, maxConcurrentRenders: Int, lastFailure: [String: Any]?) -> [String: Any] {
        ["ready": ready, "pending": pending, "pendingKeys": pendingKeys, "failed": failed,
         "failedStages": failedStages, "renders": renders, "mainRenders": mainRenders,
         "activeRenders": activeRenders, "maxConcurrentRenders": maxConcurrentRenders,
         "lastFailure": lastFailure.map { $0 as Any } ?? NSNull()]
    }
    static func encode(_ value: [String: Any]) throws -> Packet {
        // JSONSerialization rejects NaN/inf and unsupported/wrapped objects.
        // Never publish an empty or partial string on serialization failure.
        let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        let bytes = Array(data.base64EncodedString().utf8)
        let checksum = digest(data)
        let parts = stride(from: 0, to: bytes.count, by: partLength).enumerated().map { index, offset in
            (identifier: identifier + "." + checksum + "." + String(index),
             value: String(decoding: bytes[offset..<min(offset + partLength, bytes.count)], as: UTF8.self))
        }
        let manifest = try JSONSerialization.data(withJSONObject: ["version": 1, "checksum": checksum,
            "bytes": data.count, "parts": parts.count], options: [.sortedKeys])
        return Packet(manifest: String(decoding: manifest, as: UTF8.self), parts: parts)
    }
    static func failure(_ error: Error) -> Packet {
        let message = String(String(describing: error).prefix(200))
        let data = try! JSONSerialization.data(withJSONObject: ["error": message], options: [.sortedKeys])
        return Packet(manifest: String(decoding: data, as: UTF8.self), parts: [])
    }
    private static func digest(_ data: Data) -> String {
        String(data.reduce(UInt64(14695981039346656037)) { ($0 ^ UInt64($1)) &* 1099511628211 }, radix: 16)
    }
}

/// A non-clipping wrapper can have empty/offscreen bounds while its paper
/// child still fills the window. Only clipping ancestors cut that child out.
enum UITestPaperSurfaceSelection {
    struct Sample {
        var value: [String: Any]?
        var visited = 0
        var invisible = 0
        var invalid = 0
        var clipped = 0
        var markers = 0
        var emptyMarkers = 0
        var offscreenMarkers = 0
        var exhausted = false
        var description: String {
            "visited=\(visited) invisible=\(invisible) invalid=\(invalid) clipped=\(clipped) " +
                "markers=\(markers) emptyMarkers=\(emptyMarkers) offscreenMarkers=\(offscreenMarkers) exhausted=\(exhausted)"
        }
    }
    static func first<Node>(in root: Node, viewport: CGRect, children: (Node) -> [Node],
                            visible: (Node) -> Bool, frame: (Node) -> CGRect, clips: (Node) -> Bool,
                            surface: (Node) -> [String: Any]?) -> [String: Any]? {
        sample(in: root, viewport: viewport, children: children, visible: visible, frame: frame, clips: clips, surface: surface).value
    }
    static func sample<Node>(in root: Node, viewport: CGRect, children: (Node) -> [Node],
                             visible: (Node) -> Bool, frame: (Node) -> CGRect, clips: (Node) -> Bool,
                             surface: (Node) -> [String: Any]?, limit: Int = 2048) -> Sample {
        var pending: [(Node, CGRect)] = [(root, viewport)]
        var remaining = limit
        var result = Sample()
        while remaining > 0, let (node, viewport) = pending.popLast() {
            remaining -= 1; result.visited += 1
            guard visible(node) else { result.invisible += 1; continue }
            let bounds = frame(node)
            guard !bounds.isNull, !bounds.isInfinite else { result.invalid += 1; continue }
            if let value = surface(node) {
                result.markers += 1
                if bounds.isEmpty { result.emptyMarkers += 1 }
                else if !bounds.intersects(viewport) { result.offscreenMarkers += 1 }
                else { result.value = value; return result }
            }
            let clip = clips(node) ? viewport.intersection(bounds) : viewport
            guard !clip.isEmpty, !clip.isNull else { result.clipped += 1; continue }
            let next = children(node), capacity = max(0, remaining - pending.count)
            // Truncating this branch and then falling back to a background
            // could select paper behind an unvisited foreground surface.
            guard next.count <= capacity else { result.exhausted = true; return result }
            pending.append(contentsOf: next.map { ($0, clip) })
        }
        // Unknown metadata is never permission to bypass the raster gate.
        result.exhausted = result.exhausted || !pending.isEmpty
        return result
    }
}
#endif

#if DEBUG && targetEnvironment(simulator)
import Observation
import YubaiCore
#if os(iOS)
import UIKit
import SwiftUI
#endif

#if os(iOS)
/// Metadata on the actual paper background, independent of fixtures/routes.
/// Native front-to-back traversal selects the captured surface, so a sheet or
/// pushed page does not inherit the covered ledger's raster prerequisite.
struct UITestPaperSurface: UIViewRepresentable {
    let bambooKey: String?
    func makeUIView(context: Context) -> Probe { Probe(bambooKey: bambooKey) }
    func updateUIView(_ view: Probe, context: Context) {
        guard view.bambooKey != bambooKey else { return }
        view.bambooKey = bambooKey
        UITestWindowMetrics.invalidate(in: view.window)
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: Probe, context: Context) -> CGSize? {
        // The transparent UIView has no intrinsic content. Use the actual
        // paper proposal rather than the native view's empty fitting size.
        proposal.replacingUnspecifiedDimensions(by: .zero)
    }
    final class Probe: UIView {
        private struct WeakProbe { weak var view: Probe? }
        private static var probes: [WeakProbe] = []
        static func diagnostics(in window: UIWindow) -> String {
            probes = probes.filter { $0.view != nil }
            let attached = probes.compactMap(\.view).filter { $0.window === window }
            let details = attached.prefix(8).map { marker -> String in
                var view: UIView? = marker
                var blockers: [String] = []
                var clip = window.bounds
                while let current = view {
                    if current.isHidden || current.alpha <= 0 {
                        blockers.append("\(type(of: current)):hidden=\(current.isHidden),alpha=\(current.alpha)")
                    }
                    if current.clipsToBounds { clip = clip.intersection(current.convert(current.bounds, to: window)) }
                    view = current.superview
                }
                return "key=\(marker.bambooKey ?? "plain"),frame=\(marker.convert(marker.bounds, to: window)),clip=\(clip),blockers=\(blockers)"
            }
            return "live=\(probes.count) attached=\(attached.count) [" + details.joined(separator: "; ") + "]"
        }
        var bambooKey: String?
        private weak var previousWindow: UIWindow?
        private var sampledBounds = CGRect.null
        init(bambooKey: String?) {
            self.bambooKey = bambooKey
            super.init(frame: .zero)
            backgroundColor = .clear; isOpaque = false; isUserInteractionEnabled = false
            isAccessibilityElement = false; accessibilityElementsHidden = true
            Self.probes = Self.probes.filter { $0.view != nil }
            Self.probes.append(WeakProbe(view: self))
        }
        required init?(coder: NSCoder) { fatalError() }
        override func didMoveToWindow() {
            super.didMoveToWindow()
            UITestWindowMetrics.invalidate(in: previousWindow)
            UITestWindowMetrics.invalidate(in: window)
            previousWindow = window
        }
        override func layoutSubviews() {
            super.layoutSubviews()
            guard sampledBounds != bounds else { return }
            sampledBounds = bounds
            UITestWindowMetrics.invalidate(in: window)
        }
    }
}

/// Read-only native geometry for scripted walks. No device/Release code or
/// visible controls: safe areas, transition completion and remaining scroll
/// travel must be observed rather than guessed from a full-screen AX frame.
struct UITestWindowMetrics: UIViewRepresentable {
    @MainActor static func invalidate(in window: UIWindow?) {
        if let window { Probe.cache.invalidate(in: window) }
    }
    @MainActor private static var inputFocusEvents: [String] = []
    @MainActor static func recordInputFocus(_ event: String, in window: UIWindow?) {
        inputFocusEvents.append(event)
        if inputFocusEvents.count > 24 { inputFocusEvents.removeFirst(inputFocusEvents.count - 24) }
        invalidate(in: window)
    }
    func makeUIView(context: Context) -> Probe { Probe() }
    func updateUIView(_ view: Probe, context: Context) {}
    final class Probe: UIView {
        fileprivate static let cache = MetricsCache()
        private var metadata: [UIView] = []
        private var publishedManifest = ""
        init() {
            super.init(frame: .zero)
            backgroundColor = .clear; isUserInteractionEnabled = false
            accessibilityIdentifier = UITestMetricsPayload.identifier
            isAccessibilityElement = false
            accessibilityContainerType = .semanticGroup
            updateAccessibility()
            NotificationCenter.default.addObserver(self, selector: #selector(updateAccessibility),
                name: UIAccessibility.voiceOverStatusDidChangeNotification, object: nil)
        }
        required init?(coder: NSCoder) { fatalError() }
        @objc private func updateAccessibility() {
            // Script metadata is queryable by XCTest, never a VoiceOver stop.
            metadata.forEach { $0.isAccessibilityElement = !UIAccessibility.isVoiceOverRunning }
        }
        // AX getters only schedule traversal; the subtree is published together
        // on a later turn, never mutated while XCTest is resolving a snapshot.
        override var accessibilityElements: [Any]? {
            get {
                if let window { Self.cache.request(in: window) }
                return metadata
            }
            set {}
        }
        fileprivate func apply(_ packet: UITestMetricsPayload.Packet) {
            guard publishedManifest != packet.manifest else { return }
            publishedManifest = packet.manifest
            let values = [(identifier: UITestMetricsPayload.identifier + ".manifest", value: packet.manifest)] + packet.parts
            while metadata.count > values.count { metadata.removeLast().removeFromSuperview() }
            while metadata.count < values.count {
                let node = UIView(frame: bounds)
                node.isUserInteractionEnabled = false
                addSubview(node); metadata.append(node)
            }
            for (node, value) in zip(metadata, values) {
                node.accessibilityIdentifier = value.identifier
                node.accessibilityValue = value.value
            }
            updateAccessibility()
        }
        override func layoutSubviews() {
            super.layoutSubviews()
            for node in metadata { node.frame = bounds }
        }
        override func didMoveToWindow() {
            super.didMoveToWindow()
            Self.cache.register(self)
        }
    }

    @MainActor fileprivate final class MetricsCache: NSObject {
        private var values: [ObjectIdentifier: (at: TimeInterval, packet: UITestMetricsPayload.Packet)] = [:]
        private var pending: Set<ObjectIdentifier> = []
        private struct WeakProbe { weak var view: Probe? }
        private var probes: [ObjectIdentifier: WeakProbe] = [:]
        private weak var focusedResponder: UIResponder?
        private var focusedAfterAppearance: Bool?
        override init() {
            super.init()
            for name in [UITextField.textDidBeginEditingNotification, UITextField.textDidEndEditingNotification,
                         UITextView.textDidBeginEditingNotification, UITextView.textDidEndEditingNotification] {
                NotificationCenter.default.addObserver(self, selector: #selector(editingChanged(_:)), name: name, object: nil)
            }
        }
        @objc private func editingChanged(_ note: Notification) {
            guard let responder = note.object as? UIResponder else { return }
            if note.name == UITextField.textDidBeginEditingNotification || note.name == UITextView.textDidBeginEditingNotification {
                focusedResponder = responder
                focusedAfterAppearance = ((responder as? UIView)?.superview as? NativeInputAppearance)?.hasAppeared
            } else if focusedResponder === responder { focusedResponder = nil; focusedAfterAppearance = nil }
        }

        func register(_ probe: Probe) {
            probes = probes.filter { $0.value.view != nil }
            probes[ObjectIdentifier(probe)] = WeakProbe(view: probe)
            guard let window = probe.window else { return }
            if let cached = values[ObjectIdentifier(window)] { probe.apply(cached.packet) }
            request(in: window)
        }
        func invalidate(in window: UIWindow) {
            values[ObjectIdentifier(window)] = nil
            request(in: window)
        }
        func request(in window: UIWindow) {
            let key = ObjectIdentifier(window)
            // XCTest can pump the run loop between individual element reads.
            // Keep this cache across those turns: at most four samples/second.
            if let cached = values[key], ProcessInfo.processInfo.systemUptime - cached.at < 0.25 { return }
            guard pending.insert(key).inserted else { return }
            DispatchQueue.main.async { [weak self, weak window] in
                guard let self else { return }
                defer { self.pending.remove(key) }
                guard let window else { self.values[key] = nil; return }
                let packet: UITestMetricsPayload.Packet
                do { packet = try UITestMetricsPayload.encode(self.sample(in: window)) }
                catch { packet = UITestMetricsPayload.failure(error) }
                self.values[key] = (ProcessInfo.processInfo.systemUptime, packet)
                for probe in self.probes.values.compactMap(\.view) where probe.window === window {
                    probe.apply(packet)
                }
            }
        }
        private func sample(in window: UIWindow) -> [String: Any] {
            // Never send a responder-chain action from an AX getter: SwiftUI
            // can reenter its own accessibility/layout work while resolving it.
            let focused = focusedResponder?.isFirstResponder == true ? (focusedResponder as? UIView)?.accessibilityIdentifier ?? "" : ""
            func rect(_ value: CGRect) -> [Double] { [value.minX, value.minY, value.width, value.height].map(Double.init) }
            var scrolls: [[String: Any]] = []
            let windows = (window.windowScene?.windows ?? [window]).filter { !$0.isHidden && $0.alpha > 0 }
            // This metadata is advisory for reveal progress, never a reachability
            // gate. Bound even a pathological native/keyboard view hierarchy.
            var pending: [UIView] = Array(windows.prefix(2048))
            var remaining = 2048
            while remaining > 0, let view = pending.popLast() {
                remaining -= 1
                guard !view.isHidden, view.alpha > 0, view is UIWindow || view.window != nil else { continue }
                if let scroll = view as? UIScrollView, !scroll.bounds.isEmpty, scroll.isScrollEnabled {
                    let frame = scroll.convert(scroll.bounds, to: nil)
                    let scale = frame.height / max(1, scroll.bounds.height)
                    let minimum = -scroll.adjustedContentInset.top
                    let maximum = max(minimum, scroll.contentSize.height + scroll.adjustedContentInset.bottom - scroll.bounds.height)
                    scrolls.append(["identifier": scroll.accessibilityIdentifier ?? "", "frame": rect(frame),
                                    "remainingDown": Double(max(0, maximum - scroll.contentOffset.y) * scale),
                                    "remainingUp": Double(max(0, scroll.contentOffset.y - minimum) * scale),
                                    "panPoints": panPoints(in: scroll, window: scroll.window ?? window)])
                }
                pending.append(contentsOf: view.subviews.prefix(max(0, remaining - pending.count)))
            }
            var controllers = windows.compactMap(\.rootViewController)
            var activeTransitions: [String] = []
            var nativeSheetFrame: CGRect?
            var visited: Set<ObjectIdentifier> = []
            remaining = 128
            while remaining > 0, let controller = controllers.popLast() {
                remaining -= 1
                guard visited.insert(ObjectIdentifier(controller)).inserted else { continue }
                let active = controller.transitionCoordinator.map { NativePresentationTransitions.shared.isActive($0) } ?? false
                if active || controller.isBeingPresented || controller.isBeingDismissed {
                    activeTransitions.append(String(describing: type(of: controller)) +
                        ":coordinator=\(active),presenting=\(controller.isBeingPresented),dismissing=\(controller.isBeingDismissed)")
                }
                if controller.presentedViewController == nil,
                   let sheet = controller.presentationController as? UISheetPresentationController,
                   let surface = sheet.presentedView, surface.window === window {
                    nativeSheetFrame = surface.convert(surface.bounds, to: nil)
                }
                var children = controller.children
                if let presented = controller.presentedViewController { children.append(presented) }
                controllers.append(contentsOf: children.prefix(max(0, remaining - controllers.count)))
            }
            let safe = window.convert(window.safeAreaLayoutGuide.layoutFrame, to: nil)
            let paper = paperSurface(in: window)
            return UITestMetricsPayload.dictionary(safeArea: rect(safe), transitioning: !activeTransitions.isEmpty,
                activeTransitions: activeTransitions, focused: focused,
                focusedAfterAppearance: focused.isEmpty ? nil : focusedAfterAppearance, scrolls: scrolls,
                bamboo: BambooRasterCache.shared.diagnostics, bambooSurface: paper.value,
                paperDiagnostics: paper.description + " " + UITestPaperSurface.Probe.diagnostics(in: window),
                inputFocusEvents: UITestWindowMetrics.inputFocusEvents,
                focusedHost: focused.isEmpty ? nil : ((focusedResponder as? UIView)?.superview as? NativeInputAppearance)?.focusHostIdentifier,
                nativeSheetFrame: nativeSheetFrame.map(rect))
        }
        private func panPoints(in scroll: UIScrollView, window: UIWindow) -> [[Double]] {
            var viewport = scroll.convert(scroll.bounds, to: window).intersection(window.bounds)
            var ancestor = scroll.superview
            while let view = ancestor {
                if view.clipsToBounds { viewport = viewport.intersection(view.convert(view.bounds, to: window)) }
                ancestor = view.superview
            }
            guard !viewport.isEmpty, !viewport.isNull else { return [] }
            var points: [[Double]] = []
            for y in [CGFloat(0.78), 0.22, 0.5] {
                // Inset List gutters avoid a card's own buttons/recognizers.
                // Keep center candidates for full-width and nested scrolls.
                for x in [CGFloat(0.03), 0.97, 0.5] {
                    let point = CGPoint(x: viewport.minX + viewport.width * x, y: viewport.minY + viewport.height * y)
                    // The closest native scroll to the hit view owns this pan.
                    // A floating control, modal or nested editor is not a lane
                    // through which the underlying page can be scrolled.
                    var hit = window.hitTest(point, with: nil)
                    while let view = hit, !(view is UIScrollView) { hit = view.superview }
                    if hit === scroll {
                        let screen = window.convert(point, to: nil)
                        points.append([Double(screen.x), Double(screen.y)])
                    }
                }
            }
            return points
        }
        private func paperSurface(in window: UIWindow) -> UITestPaperSurfaceSelection.Sample {
            // UIKit subviews are ordered back to front. Descend the frontmost
            // visible branch first, respecting native clipping and hidden tabs.
            // The modal's own PaperCanvas wins over the presenter's background.
            UITestPaperSurfaceSelection.sample(in: window as UIView, viewport: window.bounds,
                children: { $0.subviews }, visible: { !$0.isHidden && $0.alpha > 0 && $0.window === window },
                frame: { $0.convert($0.bounds, to: window) }, clips: { $0.clipsToBounds }, surface: { view in
                if let surface = view as? UITestPaperSurface.Probe {
                    return ["required": surface.bambooKey != nil, "key": surface.bambooKey.map { $0 as Any } ?? NSNull()]
                }
                return nil
            })
        }
    }
}
#endif

@MainActor @Observable final class UITestRequestLog {
    static let shared = UITestRequestLog()
    var count = 0
    var organizationRequests = 0
    var completedOrganizationIDs: Set<String> = []
    var resentCompletedCount = 0
}

/// No fixture path or scripted response is available in device / Release builds.
/// A UUID-isolated test ledger AND an explicit script flag are both required.
enum UITestSupport {
    // Launch configuration is immutable. Copying Foundation's full environment
    // at every SwiftUI environment read was measured in main-thread stalls.
    static let launchEnvironment = ProcessInfo.processInfo.environment
    static let reduceMotion = script != nil && launchEnvironment["YUBAI_UI_TEST_REDUCE_MOTION"] == "1"
    /// Opt in only with a valid, isolated UI script; replies remain offline.
    static var allowsBackground: Bool {
        script != nil && ProcessInfo.processInfo.environment["YUBAI_UI_ALLOW_BACKGROUND"] == "1"
    }
    /// Select the same slow, cloud-enabled fixture for BG and foreground fallback checks.
    /// Explicit organization scenarios keep their existing data and timing.
    static var usesBackgroundFixture: Bool {
        script == "salary" && organizationScenario == nil &&
            ProcessInfo.processInfo.environment["YUBAI_UI_BACKGROUND_FIXTURE"] == "1"
    }
    static var organizationScenario: String? {
        guard script == "salary", let value = ProcessInfo.processInfo.environment["YUBAI_UI_ORGANIZATION_SCENARIO"],
              ["stop-second", "fail-second", "by-party", "by-party-many", "by-party-long", "questions-complete", "questions-stop", "questions-fail"].contains(value) else { return nil }
        return value
    }
    static var isByPartyScenario: Bool { organizationScenario?.hasPrefix("by-party") == true }
    @MainActor static func importRequestState(in ledger: Ledger) -> String {
        let log = UITestRequestLog.shared
        let requests = "requests=\(log.count)"
        guard script != nil, organizationScenario != nil || ProcessInfo.processInfo.environment["YUBAI_UI_TEST_IMPORT_STATE"] == "1" else { return requests }
        var state = requests + ";entries=\(ledger.activeEntries.count);classified=\(ledger.activeEntries.filter { !Classification.isPending($0) }.count);resent=\(log.resentCompletedCount)"
        if organizationScenario?.hasPrefix("questions-") == true {
            state += ";questions=\(ledger.imports.flatMap { $0.organization?.questions ?? [] }.count)"
            #if os(iOS)
            state += ";idle=\(UIApplication.shared.isIdleTimerDisabled ? 1 : 0)"
            #endif
        }
        return state
    }
    static var keepsUndoReceipt: Bool {
        script != nil && ProcessInfo.processInfo.environment["YUBAI_UI_TEST_KEEP_UNDO"] == "1"
    }
    /// Scripted replies alone do not imply that a key is configured.
    /// UI tests can explicitly simulate either state without changing Keychain.
    /// The manual background fixture defaults to a configured fake key.
    static var configuredKeyOverride: Bool? {
        guard script != nil else { return nil }
        switch ProcessInfo.processInfo.environment["YUBAI_UI_TEST_CONFIGURED_KEY"] {
        case "1": return true
        case "0": return false
        default: return usesBackgroundFixture ? true : nil
        }
    }
    /// `empty` a new ledger; `ask` scripted 问余白 replies; `import` / `salary` the import organizer.
    static let script: String? = {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "--test-ledger"), args.indices.contains(i + 1),
              UUID(uuidString: args[i + 1]) != nil,
              let name = launchEnvironment["YUBAI_UI_TEST_SCRIPT"],
              ["empty", "ask", "import", "salary"].contains(name) else { return nil }
        return name
    }()
    static var statementURL: URL? {
        guard script == "import", let i = ProcessInfo.processInfo.arguments.firstIndex(of: "--test-ledger") else { return nil }
        return FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("YubaiUITests/" + ProcessInfo.processInfo.arguments[i + 1])
            .appendingPathComponent("合成账单.csv")
    }
    static func prepare(_ repository: LedgerRepository) throws {
        guard let script else { return }
        if let url = statementURL, let encoded = ProcessInfo.processInfo.environment["YUBAI_UI_STATEMENT"],
           let data = Data(base64Encoded: encoded), data.count < 1_000_000 {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        }
        guard !FileManager.default.fileExists(atPath: repository.file.path), script != "empty" else { return }
        let now = Dates.now
        if script == "salary" {
            try repository.save(organizationScenario == nil && !usesBackgroundFixture ? salaryLedger(now: now) : organizationLedger(now: now), reason: "合成工资夹具")
            return
        }
        var ledger = Ledger()
        ledger.preferences.onboardingComplete = true; ledger.preferences.cloudAIEnabled = true
        ledger.lastReflectionWeek = ButlerCards.isoWeek(now)
        ledger.mutedTopics = ["letter"] // Keep scripted flows independent of the weekday.
        let account = Account(name: "合成银行卡", balance: 100_000, at: now)
        ledger.accounts = [account]
        if script == "import" {
            ledger.entries = [Entry(date: now.addingTimeInterval(-60), amount: 1600, accountID: account.id, title: "原有午饭", category: "餐饮")]
        } else {
            ledger.entries = [Entry(date: now, amount: 3200, accountID: account.id, title: "合成咖啡", category: "餐饮")]
        }
        try repository.save(ledger, reason: "合成测试夹具")
    }
    static func salaryLedger(now: Date) -> Ledger {
        var ledger = Ledger()
        ledger.preferences.onboardingComplete = true
        ledger.preferences.cloudAIEnabled = false
        ledger.lastReflectionWeek = ButlerCards.isoWeek(now)
        ledger.lastSubcategoryBatchDay = Dates.text(now)
        ledger.mutedTopics = ["letter"]
        let account = Account(name: "合成工资卡", balance: 200_000, at: now)
        ledger.accounts = [account]
        // Keep 未结清 reachable after dismissing the salary candidate too.
        var pendingBill = Plan(title: "合成未结清账单", amount: 99, dueDate: Dates.day(now))
        pendingBill.accountID = account.id; ledger.plans = [pendingBill]
        let month = Dates.calendar.dateInterval(of: .month, for: now)!.start
        let latestMonth = Dates.calendar.component(.day, from: now) >= 10 ? month : Dates.addMonths(-1, to: month)
        var batch = ImportBatch(filename: "合成工资流水.csv", importedCount: 6, duplicateCount: 0, skippedCount: 0)
        batch.needsOrganization = true; batch.undo = ImportUndo(updatedAt: ledger.updatedAt)
        ledger.imports = [batch]
        for offset in -2...0 {
            var entry = Entry(date: Dates.addDays(9, to: Dates.addMonths(offset, to: latestMonth)), amount: 800_000,
                              nature: .income, accountID: account.id, title: "合成公司", category: "工资奖金")
            entry.batchID = batch.id; entry.source = "文件"
            ledger.entries.append(entry)
        }
        for day in 1...90 {
            var entry = Entry(date: Dates.addDays(-day, to: Dates.day(now)), amount: 5_000, accountID: account.id,
                              title: "合成日常支出", category: day <= 3 ? Classification.pendingCategory : "餐饮")
            if day <= 3 { entry.batchID = batch.id; entry.source = "文件" }
            ledger.entries.append(entry)
        }
        return ledger
    }
    /// Three chunks by default; the manual background fixture uses five slow chunks.
    /// No salary candidate or automatic cloud work.
    static func organizationLedger(now: Date) -> Ledger {
        var ledger = salaryLedger(now: now)
        ledger.preferences.cloudAIEnabled = true
        if ["by-party-many", "by-party-long"].contains(organizationScenario ?? "") {
            // 64 groups / 75 entries: the first 61 groups cover exactly 72 entries.
            // The long variant supplies 64 rows in one group and a second live group.
            let many = organizationScenario == "by-party-many"
            ledger.entries = []
            var batch = ImportBatch(filename: "合成长列表.csv", importedCount: many ? 75 : 65, duplicateCount: 0, skippedCount: 0)
            batch.needsOrganization = true; batch.undo = ImportUndo(updatedAt: ledger.updatedAt)
            ledger.imports = [batch]
            for index in 0..<(many ? 64 : 2) {
                let count = many ? (index < 11 ? 2 : 1) : (index == 0 ? 64 : 1)
                for row in 0..<count {
                    let party = String(format: "合成对方%02d", index)
                    var entry = Entry(date: now.addingTimeInterval(-Double(index * 100 + row)), amount: 100,
                                      nature: .unknownOut, accountID: ledger.accounts[0].id, title: party + " · 合成明细\(row)")
                    entry.batchID = batch.id; entry.source = "文件"
                    ledger.entries.append(entry)
                }
            }
            if !many {
                // Force the quick card's controls to extend below an iPhone viewport.
                ledger.categories += (0..<24).map { YubaiCore.Category(String(format: "合成分类%02d", $0)) }
            }
            ButlerCards.refresh(&ledger, now: now)
            return ledger
        }
        if organizationScenario == "by-party" {
            var batch = ImportBatch(filename: "合成剩余流水.csv", importedCount: 10, duplicateCount: 0, skippedCount: 0)
            batch.needsOrganization = true; batch.undo = ImportUndo(updatedAt: ledger.updatedAt)
            ledger.imports = [batch]
            ledger.entries = (0..<10).map { index in
                let title = index == 0 ? "合成个人 · 来款" : (index <= 6 ? "合成对方甲 · 明细" : "合成对方乙 · 明细")
                var entry = Entry(date: Dates.addDays(-index - 5, to: now), amount: index == 0 ? 99 : 100,
                                  nature: index == 0 ? .unknownIn : .unknownOut, accountID: ledger.accounts[0].id, title: title)
                entry.batchID = batch.id; entry.source = "文件"
                return entry
            }
            // More than five unrelated reminders exercise fallback ordering.
            for index in 0..<6 {
                ledger.entries.append(Entry(date: Dates.addDays(-10, to: now), amount: 200,
                                            nature: .unknownIn, accountID: ledger.accounts[0].id, title: "合成旧来款\(index)", category: "其他收入"))
            }
            ButlerCards.refresh(&ledger, now: now)
            return ledger
        }
        // A known plan makes these rows association candidates; retain the
        // 30/30/10 (or 5×30) checkpoints asserted by the stop/fail UI tests.
        var plan = Plan(title: "合成关联候选", amount: 100, dueDate: Dates.addMonths(12, to: now), frequency: .monthly)
        plan.accountID = ledger.accounts[0].id; ledger.plans.append(plan)
        let count = usesBackgroundFixture ? 150 : 70
        var batch = ImportBatch(filename: "合成大量流水.csv", importedCount: count, duplicateCount: 0, skippedCount: 0)
        batch.needsOrganization = true; batch.undo = ImportUndo(updatedAt: ledger.updatedAt)
        ledger.imports = [batch]
        ledger.entries = (1...count).map { day in
            var entry = Entry(date: Dates.addDays(-day, to: Dates.day(now)), amount: 100,
                              accountID: ledger.accounts[0].id, title: "合成日常支出\(day)", category: Classification.pendingCategory)
            entry.batchID = batch.id; entry.source = "文件"
            return entry
        }
        return ledger
    }
    /// Fresh, synthetic data only. Dates follow the simulator clock.
}

struct UITestTransport: ChatTransport {
    let script: String
    func send(_ request: ChatRequest) async throws -> ChatMessage {
        await MainActor.run { UITestRequestLog.shared.count += 1 }
        if ["导入整理", "导入整理·按对方"].contains(request.purpose), UITestSupport.usesBackgroundFixture {
            try await Task.sleep(for: .seconds(8))
        }
        if ["salary", "import"].contains(script), request.purpose == "导入整理·按对方" {
            let payload = try JSONValue.parse(request.messages.last?.content ?? "")
            let groups = payload["groups"]?.arrayValue ?? []
            let keys = Set(groups.compactMap { group -> String? in
                guard let party = group["party"]?.stringValue else { return nil }
                return "group:" + party + (group["inflow"] == .bool(true) ? ":in" : ":out")
            })
            await MainActor.run {
                let log = UITestRequestLog.shared
                log.organizationRequests += 1
                log.resentCompletedCount += keys.intersection(log.completedOrganizationIDs).count
                log.completedOrganizationIDs.formUnion(keys)
            }
            // Leave outgoing records on the real fallback card for grouping tests.
            if UITestSupport.isByPartyScenario {
                let results: [JSONValue] = groups.compactMap { group in
                    guard group["inflow"] == .bool(true), let id = group["id"] else { return nil }
                    return .object(["group": id, "category": .string("其他收入"), "nature": .string("income"),
                                    "purpose": .string("来自合成个人"), "confident": .bool(true)])
                }
                return ChatMessage(role: .assistant, content: try JSONValue.object(["groups": .array(results)]).jsonText())
            }
            var results: [JSONValue] = []
            for group in groups {
                guard let id = group["id"] else { continue }
                let income = group["inflow"] == .bool(true)
                if script == "import", income {
                    // Uncertain incoming groups stay on the local fallback.
                    results.append(.object(["group": id, "skip": .bool(true)]))
                } else {
                    results.append(.object(["group": id, "category": .string(income ? "工资奖金" : "餐饮"),
                        "nature": .string(income ? "income" : "expense"), "confident": .bool(true)]))
                }
            }
            return ChatMessage(role: .assistant, content: try JSONValue.object(["groups": .array(results)]).jsonText())
        }
        if script == "salary", request.purpose == "导入整理" {
            let payload = try JSONValue.parse(request.messages.last?.content ?? "")
            let batchRows = payload["batch"]?.arrayValue ?? []
            let ids = Set(batchRows.compactMap { $0["id"]?.stringValue })
            // rN names are request-local; provenance facts identify retry rows.
            let stableKeys = Set(batchRows.map { row in
                ["account", "date", "title", "amount"].map { (try? row[$0]?.jsonText()) ?? "" }.joined(separator: "|")
            })
            let scenario = UITestSupport.organizationScenario
            if UITestSupport.isByPartyScenario {
                let rows: [JSONValue] = (payload["batch"]?.arrayValue ?? []).compactMap { row in
                    guard row["inflow"] == .bool(true), let id = row["id"] else { return nil }
                    return .object(["entry": id, "category": .string("其他收入"), "nature": .string("income"),
                        "purpose": .string("来自合成个人"), "confident": .bool(true)])
                }
                return ChatMessage(role: .assistant, content: try JSONValue.object(["rows": .array(rows)]).jsonText())
            }
            let number = await MainActor.run {
                let log = UITestRequestLog.shared
                log.organizationRequests += 1
                log.resentCompletedCount += stableKeys.intersection(log.completedOrganizationIDs).count
                return log.organizationRequests
            }
            if scenario?.hasPrefix("questions-") == true, number >= 2 {
                if scenario == "questions-stop" || (scenario == "questions-fail" && number > 2) {
                    while true { try await Task.sleep(for: .seconds(1)) }
                }
                try await Task.sleep(for: .seconds(number <= 3 ? 7 : 1)) // Observe saved classifications while the next chunk is running.
                if scenario == "questions-fail" {
                    throw DeepSeekError.http(503)
                }
            }
            if scenario == "stop-second", number >= 2 {
                // Stay in a cancellable request until the UI presses Stop.
                while true { try await Task.sleep(for: .seconds(1)) }
            }
            if scenario == "fail-second", number == 2 {
                try await Task.sleep(for: .seconds(1))
                throw DeepSeekError.http(503)
            }
            if scenario == "fail-second", number == 3 {
                while true { try await Task.sleep(for: .seconds(1)) }
            }
            if scenario == "fail-second", number >= 4 {
                // Complete retry's first two chunks, then expose saved progress.
                try await Task.sleep(for: .seconds(number <= 5 ? 1 : 5))
            }
            let rows: [JSONValue] = (payload["batch"]?.arrayValue ?? []).compactMap { row in
                guard let id = row["id"]?.stringValue else { return nil }
                let income = row["inflow"] == .bool(true)
                return .object(["entry": .string(id), "category": .string(income ? "工资奖金" : "餐饮"),
                                "nature": .string(income ? "income" : "expense"), "confident": .bool(true)])
            }
            var questions: [JSONValue] = []
            // Deliberate legacy replies: questions must not suppress confident rows.
            let returnsLegacyQuestion = (scenario?.hasPrefix("questions-") == true && number == 1) ||
                (UITestSupport.usesBackgroundFixture && number == 2)
            if returnsLegacyQuestion, let id = ids.sorted().first {
                let options: [JSONValue] = [("日常支出", "expense"), ("还款", "repayment")].map { title, nature in
                    .object(["title": .string(title), "items": .array([
                        .object(["kind": .string("set_nature"), "entry": .string(id), "nature": .string(nature)])
                    ])])
                }
                questions = [.object(["text": .string("这笔支出是什么用途？"), "entry_ids": .array([.string(id)]), "options": .array(options)])]
            }
            await MainActor.run { UITestRequestLog.shared.completedOrganizationIDs.formUnion(stableKeys) }
            return ChatMessage(role: .assistant, content: try JSONValue.object(["rows": .array(rows), "items": .array([]),
                "series": .array([]), "questions": .array(questions)]).jsonText())
        }
        if request.purpose == "管家卡片与来信" || request.purpose == "导入短评" {
            return ChatMessage(role: .assistant, content: #"{"cards":[]}"#) // Use the real local templates.
        }
        if script == "import", request.purpose == "导入整理" {
            let payload = try JSONValue.parse(request.messages.last?.content ?? "")
            let batch = payload["batch"]?.arrayValue ?? []
            let id = batch.first(where: { $0["inflow"] == .bool(true) })?["id"]?.stringValue
            let rows: [JSONValue] = batch.compactMap { row in
                guard let key = row["id"]?.stringValue, key != id else { return nil }
                return .object(["entry": .string(key), "category": .string("餐饮"), "nature": .string("expense"), "confident": .bool(true)])
            }
            // Deliberate legacy question for an omitted row: only a local fallback may appear.
            var questions: [JSONValue] = []
            if let id {
                questions = [.object(["text": .string("这笔来款是什么用途？"), "entry_ids": .array([.string(id)]), "options": .array([
                .object(["title": .string("日常收入"), "items": .array([
                    .object(["kind": .string("set_nature"), "entry": .string(id), "nature": .string("income")]),
                    .object(["kind": .string("set_category"), "entry": .string(id), "category": .string("其他收入")])])]),
                .object(["title": .string("先留没写用途"), "items": .array([
                    .object(["kind": .string("set_purpose"), "entry": .string(id), "text": .string("待核对来款")])])])])])]
            }
            let result = JSONValue.object(["rows": .array(rows), "items": .array([]), "series": .array([]), "questions": .array(questions)])
            return ChatMessage(role: .assistant, content: try result.jsonText())
        }
        if script == "ask" { return try askReply(request) }
        throw YubaiError.invalid("这条 UI 测试没有配置此请求；不会访问网络。")
    }
    /// 问余白 flows: a purchase is judged by the real tool, then answered with its own bound reason.
    private func askReply(_ request: ChatRequest) throws -> ChatMessage {
        let lastUserIndex = request.messages.lastIndex { $0.role == .user } ?? request.messages.startIndex
        let turn = request.messages.suffix(from: lastUserIndex)
        let question = turn.first?.content ?? ""
        if turn.contains(where: { $0.role == .tool && $0.toolCallID == "ask-verdict" }) { return ChatMessage(role: .assistant, content: "好") }
        guard question.contains("买") else { return ChatMessage(role: .assistant, content: "这个我先记着。") }
        guard let judged = turn.last(where: { $0.role == .tool && $0.toolCallID == "ask-judge" })?.content else {
            return ChatMessage(role: .assistant, toolCalls: [ChatToolCall(id: "ask-judge", name: "judge_purchase",
                arguments: #"{"title":"降噪耳机","amount":"1299","category":"购物"}"#)])
        }
        let facts = try JSONValue.parse(judged)
        let reason = (facts["bound_reason"]?.stringValue ?? "").components(separatedBy: "。").first ?? ""
        let verdict = facts["allowed_verdicts"]?.arrayValue?.compactMap(\.stringValue).last ?? "skip"
        let args: JSONValue = .object(["verdict": .string(verdict), "reason": .string(reason), "need": .string("want")])
        return ChatMessage(role: .assistant, toolCalls: [ChatToolCall(id: "ask-verdict", name: "submit_verdict", arguments: try args.jsonText())])
    }
}
#endif
