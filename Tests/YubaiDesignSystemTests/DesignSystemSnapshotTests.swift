#if os(iOS) && DEBUG
import XCTest
import SwiftUI
import UIKit
import SnapshotTesting
@testable import Yubai

@MainActor
final class DesignSystemSnapshotTests: XCTestCase {
    func testGallerySections() {
        let animationsWereEnabled = UIView.areAnimationsEnabled
        UIView.setAnimationsEnabled(false)
        defer { UIView.setAnimationsEnabled(animationsWereEnabled) }
        let env = ProcessInfo.processInfo.environment
        let recordAll = env["DS_SNAPSHOT_RECORD"] == "1"
        withSnapshotTesting(record: recordAll ? .all : .missing) {
            for section in DesignSystemGalleryView.Section.snapshotSections {
                for scheme in [ColorScheme.light, ColorScheme.dark] {
                    let appearance = scheme == .light ? "light" : "dark"
                    let name = "\(section.rawValue)-\(appearance)"
                    let root = DesignSystemGalleryView(section: section)
                        .environment(\.colorScheme, scheme)
                        .environment(\.locale, Locale(identifier: "zh_CN"))
                        .environment(\.dynamicTypeSize, .large)
                        .environment(\.dsReduceMotionOverride, false)
                        .environment(\.dsAnimationsEnabled, false)
                        .transaction { transaction in
                            transaction.animation = nil
                            transaction.disablesAnimations = true
                        }
                    let host = UIHostingController(rootView: root)
                    host.safeAreaRegions = []
                    host.overrideUserInterfaceStyle = scheme == .light ? .light : .dark
                    host.view.backgroundColor = UIColor(DS.Color.bg)
                    let fitting = host.sizeThatFits(in: CGSize(width: 393, height: CGFloat.greatestFiniteMagnitude))
                    let size = CGSize(width: 393, height: ceil(max(1, fitting.height)))
                    if DesignSystemGalleryView.Section.componentSnapshotSections.contains(section) {
                        XCTAssertLessThanOrEqual(size.height, 1600, "Split oversized component snapshot: \(name)")
                    }
                    let traits = UITraitCollection(traitsFrom: [
                        UITraitCollection(displayScale: 3),
                        UITraitCollection(userInterfaceStyle: scheme == .light ? .light : .dark),
                        UITraitCollection(preferredContentSizeCategory: .large),
                        UITraitCollection(horizontalSizeClass: .compact),
                        UITraitCollection(verticalSizeClass: .regular)
                    ])
                    let config = ViewImageConfig(safeArea: .zero, size: size, traits: traits)
                    let image: Snapshotting<UIViewController, UIImage> = .image(on: config, drawHierarchyInKeyWindow: true, traits: traits)
                    // Export the exact image passed to the diff, including successful comparisons.
                    var exporting = image
                    exporting.snapshot = { controller in
                        image.snapshot(controller).map { rendered in
                            if let path = env["DS_SNAPSHOT_EXPORT_DIR"], !path.isEmpty {
                                do {
                                    let directory = URL(fileURLWithPath: path, isDirectory: true)
                                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                                    let png = try XCTUnwrap(rendered.pngData())
                                    try png.write(to: directory.appendingPathComponent(name + ".png"), options: .atomic)
                                } catch { XCTFail("PNG export failed for \(name): \(error)") }
                            }
                            return rendered
                        }
                    }
                    assertSnapshot(of: host, as: exporting, named: name, testName: "gallery")
                }
            }
        }
    }
}
#endif
