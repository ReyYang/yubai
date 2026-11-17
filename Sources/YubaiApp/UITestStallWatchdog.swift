#if DEBUG && os(iOS) && targetEnvironment(simulator)
import CUITestWatchdog
import Foundation
import SwiftUI
import UIKit

enum UITestStallWatchdog {
    @MainActor static func startIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("--ui-test-stall-watchdog"), UITestSupport.script != nil else { return }
        // Avoid Foundation directory discovery while measuring startup. The C
        // worker creates/opens the file; start still registers the main thread.
        let path = NSHomeDirectory() + "/Documents/tmp/yubai-stalls-\(ProcessInfo.processInfo.processIdentifier).log"
        let result = path.withCString { yubai_stall_watchdog_start($0) }
        if result != 0 { fputs("YUBAI-STALL watchdog start failed: \(result)\n", stderr) }
    }
    static func latestSummary() -> String {
        guard let value = yubai_stall_watchdog_copy_records(2) else { return "" }
        defer { free(value) }
        return String(cString: value)
    }
}

/// No timer, state publication, or stack capture in accessibility getters.
/// One bounded AX summary per surface. Complete records go to stderr and the
/// watchdog file, exported from xcodebuild even if its simulator shuts down.
private struct UITestStallProbe: UIViewRepresentable {
    func makeUIView(context: Context) -> Probe { Probe() }
    func updateUIView(_ view: Probe, context: Context) {}
    final class Probe: UIView {
        private var records: [UIAccessibilityElement] = []
        init() {
            super.init(frame: .zero)
            isUserInteractionEnabled = false; backgroundColor = .clear
            records = [Record(container: self)]
            updateAccessibility()
            NotificationCenter.default.addObserver(self, selector: #selector(updateAccessibility),
                name: UIAccessibility.voiceOverStatusDidChangeNotification, object: nil)
        }
        required init?(coder: NSCoder) { fatalError() }
        @objc private func updateAccessibility() { accessibilityElementsHidden = UIAccessibility.isVoiceOverRunning }
        override var accessibilityElements: [Any]? {
            get {
                records
            }
            set {}
        }
    }
    final class Record: UIAccessibilityElement {
        init(container: UIView) {
            super.init(accessibilityContainer: container)
            isAccessibilityElement = true
            accessibilityIdentifier = "uiTestMainThreadStall"
            accessibilityFrameInContainerSpace = CGRect(x: YubaiSpace.none, y: YubaiSpace.none, width: YubaiSize.separator, height: YubaiSize.separator)
        }
        override var accessibilityValue: String? {
            get {
                // Do not copy a growing history or create more AX children.
                UITestStallWatchdog.latestSummary()
            }
            set {}
        }
    }
}

struct UITestDiagnostics: View {
    var body: some View {
        HStack(spacing: YubaiSpace.none) {
            UITestWindowMetrics()
            if ProcessInfo.processInfo.arguments.contains("--ui-test-stall-watchdog") { UITestStallProbe() }
        }.frame(width: YubaiSize.separator, height: YubaiSize.separator)
    }
}
#endif
