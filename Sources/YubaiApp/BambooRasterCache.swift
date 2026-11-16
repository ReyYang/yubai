import SwiftUI
import Observation
import CoreImage
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Layout only reads finished images. Each appearance/scale is prepared once
/// by the launch surface's task, including the other appearance for a switch.
@MainActor @Observable final class BambooRasterCache {
    static let shared = BambooRasterCache()
    nonisolated static let padding: CGFloat = 32
    struct Key: Hashable, Sendable {
        let dark: Bool
        let scale: CGFloat
        init(scheme: ColorScheme, scale: CGFloat) { dark = scheme == .dark; self.scale = scale }
    }
    private var images: [Key: Image] = [:]
    @ObservationIgnored private var pending: [Key: Task<CGImage?, Never>] = [:]
    @ObservationIgnored private var failed: Set<Key> = []

    // Never add a cache-miss renderer here: SwiftUI calls this from body.
    func image(scheme: ColorScheme, scale: CGFloat) -> Image? {
        images[Key(scheme: scheme, scale: scale)]
    }
    func warm(scheme: ColorScheme, scale: CGFloat) async {
        guard scale.isFinite, scale > 0 else { return }
        await prepare(Key(scheme: scheme, scale: scale))
        await prepare(Key(scheme: scheme == .dark ? .light : .dark, scale: scale))
    }
    private func prepare(_ key: Key) async {
        guard images[key] == nil, !failed.contains(key) else { return }
        if let task = pending[key] { _ = await task.value; return }
        // Resolve the existing dynamic token on its UI actor. The bitmap,
        // asset rasterization, blur and CIContext are exclusively worker work.
        #if os(iOS)
        let traits = UITraitCollection(userInterfaceStyle: key.dark ? .dark : .light)
        let tint = UIColor(YubaiColor.bambooShadow).resolvedColor(with: traits).cgColor
        #else
        let appearance = NSAppearance(named: key.dark ? .darkAqua : .aqua)!
        var tint = NSColor.clear.cgColor
        appearance.performAsCurrentDrawingAppearance { tint = NSColor(YubaiColor.bambooShadow).cgColor }
        #endif
        let task = Task.detached(priority: .utility) {
            autoreleasepool { BambooRasterizer.render(scale: key.scale, tint: tint) }
        }
        pending[key] = task
        if let pixels = await task.value {
            images[key] = Image(decorative: pixels, scale: key.scale, orientation: .up).renderingMode(.original)
        } else { failed.insert(key) }
        pending[key] = nil
    }

    #if DEBUG && targetEnvironment(simulator)
    var diagnostics: [String: Any] {
        ["ready": images.keys.map { ($0.dark ? "dark" : "light") + "@\($0.scale)" }.sorted(),
         "renders": BambooRasterizer.statistics.count, "mainRenders": BambooRasterizer.statistics.mainCount,
         "pending": pending.count]
    }
    #endif
}

/// No SwiftUI rendering or actor-bound code is allowed in this worker.
private enum BambooRasterizer {
    private static let context = CIContext()
    #if DEBUG && targetEnvironment(simulator)
    static let statistics = RenderStatistics()
    final class RenderStatistics: @unchecked Sendable {
        private let lock = NSLock()
        private var renders = 0
        private var mainRenders = 0
        var count: Int { lock.lock(); defer { lock.unlock() }; return renders }
        var mainCount: Int { lock.lock(); defer { lock.unlock() }; return mainRenders }
        func record() {
            lock.lock(); defer { lock.unlock() }
            renders += 1
            if Thread.isMainThread { mainRenders += 1 }
        }
    }
    #endif
    static func render(scale: CGFloat, tint: CGColor) -> CGImage? {
        #if DEBUG && targetEnvironment(simulator)
        statistics.record()
        #endif
        precondition(!Thread.isMainThread, "Bamboo rasterization must never run during layout")
        let padding = BambooRasterCache.padding
        let alignment = YubaiSize.bambooShadow
        let size = CGSize(width: alignment.width + padding * 2, height: alignment.height + padding * 2)
        let pixels: CGImage
        #if os(iOS)
        guard let asset = UIImage(named: "BambooShadow"), asset.size.width > 0, asset.size.height > 0 else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale; format.opaque = false; format.preferredRange = .standard
        let fit = min(alignment.width / asset.size.width, alignment.height / asset.size.height)
        let fitted = CGSize(width: asset.size.width * fit, height: asset.size.height * fit)
        let rect = CGRect(x: (size.width - fitted.width) / 2, y: (size.height - fitted.height) / 2, width: fitted.width, height: fitted.height)
        let bitmap = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            asset.withTintColor(UIColor(cgColor: tint), renderingMode: .alwaysOriginal).draw(in: rect)
        }
        guard let bitmapPixels = bitmap.cgImage else { return nil }
        pixels = bitmapPixels
        #else
        guard let asset = NSImage(named: "BambooShadow"), asset.size.width > 0, asset.size.height > 0 else { return nil }
        var proposed = CGRect(origin: .zero, size: CGSize(width: alignment.width * scale, height: alignment.height * scale))
        guard let source = asset.cgImage(forProposedRect: &proposed, context: nil, hints: nil),
              let bitmap = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale),
                  bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        bitmap.scaleBy(x: scale, y: scale)
        let fit = min(alignment.width / asset.size.width, alignment.height / asset.size.height)
        let fitted = CGSize(width: asset.size.width * fit, height: asset.size.height * fit)
        bitmap.draw(source, in: CGRect(x: (size.width - fitted.width) / 2, y: (size.height - fitted.height) / 2, width: fitted.width, height: fitted.height))
        bitmap.setBlendMode(.sourceIn); bitmap.setFillColor(tint)
        bitmap.fill(CGRect(origin: .zero, size: size))
        guard let bitmapPixels = bitmap.makeImage() else { return nil }
        pixels = bitmapPixels
        #endif
        guard hasVisiblePixels(pixels) else { return nil }
        let input = CIImage(cgImage: pixels)
        let blurred = input.applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 6 * scale])
        guard let output = context.createCGImage(blurred, from: input.extent), hasVisiblePixels(output) else { return nil }
        return output
    }
    private static func hasVisiblePixels(_ image: CGImage) -> Bool {
        let sample = YubaiSize.bambooVisibilitySample
        let width = Int(sample.width), height = Int(sample.height)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        return pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(origin: .zero, size: sample))
            return stride(from: 3, to: buffer.count, by: 4).contains { buffer[$0] > 0 }
        }
    }
}
