#if DEBUG && os(iOS) && targetEnvironment(simulator)
import CUITestWatchdog
import Foundation
import SwiftUI
import UIKit

enum UITestStallWatchdog {
    @MainActor static func startIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("--ui-test-stall-watchdog"), UITestSupport.script != nil else { return }
        let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("tmp", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let file = folder.appendingPathComponent("yubai-stalls-\(ProcessInfo.processInfo.processIdentifier).log")
            let result = file.path.withCString { yubai_stall_watchdog_start($0) }
            if result != 0 { fputs("YUBAI-STALL watchdog start failed: \(result)\n", stderr) }
        } catch { fputs("YUBAI-STALL watchdog file failed: \(error)\n", stderr) }
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
        init() {
            super.init(frame: .zero)
            isUserInteractionEnabled = false; backgroundColor = .clear
            accessibilityElements = [Record(container: self, latest: true), Record(container: self, latest: false)]
            updateAccessibility()
            NotificationCenter.default.addObserver(self, selector: #selector(updateAccessibility),
                name: UIAccessibility.voiceOverStatusDidChangeNotification, object: nil)
        }
        required init?(coder: NSCoder) { fatalError() }
        @objc private func updateAccessibility() { accessibilityElementsHidden = UIAccessibility.isVoiceOverRunning }
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
