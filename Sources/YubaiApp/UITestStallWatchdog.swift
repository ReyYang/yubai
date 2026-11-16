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
    static func records(latest: Bool) -> String {
        guard let value = yubai_stall_watchdog_copy_records(latest ? 1 : 0) else { return "" }
        defer { free(value) }
        return String(cString: value)
    }
}

/// No timer, state publication, or stack capture in accessibility getters.
/// Separate latest/history values keep failures small and retain every record
/// across the many fixture processes in one gallery walk.
private struct UITestStallProbe: UIViewRepresentable {
    func makeUIView(context: Context) -> Probe { Probe() }
    func updateUIView(_ view: Probe, context: Context) {}
    final class Probe: UIView {
        private var records: [UIAccessibilityElement] = []
        private var chunks: [UIAccessibilityElement] = []
        private var chunkedHistory = ""
        init() {
            super.init(frame: .zero)
            isUserInteractionEnabled = false; backgroundColor = .clear
            records = [Record(container: self, latest: true), Record(container: self, latest: false)]
            updateAccessibility()
            NotificationCenter.default.addObserver(self, selector: #selector(updateAccessibility),
                name: UIAccessibility.voiceOverStatusDidChangeNotification, object: nil)
        }
        required init?(coder: NSCoder) { fatalError() }
        @objc private func updateAccessibility() { accessibilityElementsHidden = UIAccessibility.isVoiceOverRunning }
        override var accessibilityElements: [Any]? {
            get {
                // XCTest snapshots cap a single AX value at roughly 500 chars.
                // Export short immutable chunks, preserving every byte in the
                // test attachment even after multiple stalls in one process.
                let history = UITestStallWatchdog.records(latest: false)
                if history != chunkedHistory {
                    chunkedHistory = history; chunks = []
                    let characters = Array(history)
                    for start in stride(from: 0, to: characters.count, by: 300) {
                        let chunk = UIAccessibilityElement(accessibilityContainer: self)
                        chunk.isAccessibilityElement = true
                        chunk.accessibilityIdentifier = "uiTestStallChunk_\(start / 300)"
                        chunk.accessibilityValue = String(characters[start..<min(start + 300, characters.count)])
                        chunk.accessibilityFrameInContainerSpace = CGRect(x: YubaiSpace.none, y: YubaiSpace.none, width: YubaiSize.separator, height: YubaiSize.separator)
                        chunks.append(chunk)
                    }
                }
                // Stable element identities across the many normal snapshots.
                return records + chunks
            }
            set {}
        }
    }
    final class Record: UIAccessibilityElement {
        let latest: Bool
        init(container: UIView, latest: Bool) {
            self.latest = latest
            super.init(accessibilityContainer: container)
            isAccessibilityElement = true
            accessibilityIdentifier = latest ? "uiTestMainThreadStall" : "uiTestMainThreadStallRecords"
            accessibilityFrameInContainerSpace = CGRect(x: YubaiSpace.none, y: YubaiSpace.none, width: YubaiSize.separator, height: YubaiSize.separator)
        }
        override var accessibilityValue: String? {
            get { UITestStallWatchdog.records(latest: latest) }
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
