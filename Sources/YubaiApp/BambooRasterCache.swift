import SwiftUI
import Observation
import CoreImage
import os
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Layout only reads finished images. The cache owns preparation for both
/// appearances, even if a launch surface's task is cancelled while awaiting it.
@MainActor @Observable final class BambooRasterCache {
    static let shared = BambooRasterCache()
    nonisolated static let padding: CGFloat = 32
    struct Key: Hashable, Sendable {
        let dark: Bool
        let scale: CGFloat
        init(scheme: ColorScheme, scale: CGFloat) { dark = scheme == .dark; self.scale = scale }
        var identifier: String { (dark ? "dark" : "light") + "@\(scale)" }
    }
    private var images: [Key: Image] = [:]
    @ObservationIgnored private var pending: [Key: Task<Void, Never>] = [:]
    @ObservationIgnored private var failed: [Key: BambooRasterizer.Failure] = [:]
    private struct FailureRecord {
        let key: Key
        let stage: BambooRasterizer.Failure
        let attempt: Int
    }
    @ObservationIgnored private var lastFailure: FailureRecord?
    private static let logger = Logger(subsystem: "app.yubai.personal", category: "bamboo-raster")

    // Never add a cache-miss renderer here: SwiftUI calls this from body.
    func image(scheme: ColorScheme, scale: CGFloat) -> Image? {
        images[Key(scheme: scheme, scale: scale)]
    }
    func warm(scheme: ColorScheme, scale: CGFloat) async {
        guard scale.isFinite, scale > 0 else { return }
        // Register both before the first suspension. Neither publishing a
        // result nor starting the other appearance depends on this caller.
        let current = prepare(Key(scheme: scheme, scale: scale))
        let other = prepare(Key(scheme: scheme == .dark ? .light : .dark, scale: scale))
        await current?.value
        await other?.value
    }
    private func prepare(_ key: Key) -> Task<Void, Never>? {
        guard images[key] == nil else { return nil }
        if let task = pending[key] { return task }
        // Resolve the existing dynamic token on its UI actor. The bitmap,
        // asset rasterization, blur and CIContext are exclusively worker work.
        #if os(iOS)
        let traits = UITraitCollection(userInterfaceStyle: key.dark ? .dark : .light)
        let tint = UIColor(YubaiColor.bambooShadow).resolvedColor(with: traits).cgColor
        #else
        let appearance = NSAppearance(named: key.dark ? .darkAqua : .aqua)!
        var resolvedTint = NSColor.clear.cgColor
        appearance.performAsCurrentDrawingAppearance { resolvedTint = NSColor(YubaiColor.bambooShadow).cgColor }
        let tint = resolvedTint
        #endif
        let task = Task { @MainActor in
            defer { self.pending[key] = nil }
            // A transient allocation/first-use failure must not erase the
            // shadow for the process lifetime. Retry once per warm request;
            // after that, a later surface/appearance request may try again.
            // Concurrent warm calls share this entire operation, retries too.
            for attempt in 1...2 {
                let result = await Task.detached(priority: .userInitiated) {
                    autoreleasepool { BambooRasterizer.render(scale: key.scale, tint: tint) }
                }.value
                switch result {
                case .success(let pixels):
                    self.images[key] = Image(decorative: pixels, scale: key.scale, orientation: .up).renderingMode(.original)
                    if self.failed.removeValue(forKey: key) != nil {
                        Self.logger.info("key=\(key.identifier, privacy: .public) recovered on attempt=\(attempt)")
                    }
                    return
                case .failure(let stage):
                    self.failed[key] = stage
                    self.lastFailure = FailureRecord(key: key, stage: stage, attempt: attempt)
                    Self.logger.error("key=\(key.identifier, privacy: .public) stage=\(stage.rawValue, privacy: .public) attempt=\(attempt) of 2")
                }
            }
        }
        pending[key] = task
        return task
    }

    #if DEBUG && targetEnvironment(simulator)
    var diagnostics: [String: Any] {
        let statistics = BambooRasterizer.statistics.snapshot
        var value: [String: Any] = ["ready": images.keys.map(\.identifier).sorted(),
            "pending": pending.count, "pendingKeys": pending.keys.map(\.identifier).sorted(),
            "failed": failed.keys.map(\.identifier).sorted(),
            "failedStages": Dictionary(uniqueKeysWithValues: failed.map { ($0.key.identifier, $0.value.rawValue) }),
            "renders": statistics.count, "mainRenders": statistics.mainCount, "lastFailure": NSNull()]
        // Keep the last failure after recovery so tests cannot hide a failed
        // render behind a successful retry. This metadata is never visible UI.
        if let lastFailure {
            value["lastFailure"] = ["key": lastFailure.key.identifier, "stage": lastFailure.stage.rawValue,
                                    "attempt": lastFailure.attempt]
        }
        return value
    }
    #endif
}

/// No SwiftUI rendering or actor-bound code is allowed in this worker.
private enum BambooRasterizer {
    enum Failure: String, Error, Sendable {
        case assetMissing, assetSize, assetRaster, bitmapContext, bitmapPixels
        case inputSampleContext, inputEmpty, blurOutput, outputSampleContext, outputEmpty
    }
    private static let context = CIContext()
    #if DEBUG && targetEnvironment(simulator)
    static let statistics = RenderStatistics()
    final class RenderStatistics: @unchecked Sendable {
        private let lock = NSLock()
        private var renders = 0
        private var mainRenders = 0
        var snapshot: (count: Int, mainCount: Int) {
            lock.lock(); defer { lock.unlock() }; return (renders, mainRenders)
        }
        func record() {
            lock.lock(); defer { lock.unlock() }
            renders += 1
            if Thread.isMainThread { mainRenders += 1 }
        }
    }
    #endif
    static func render(scale: CGFloat, tint: CGColor) -> Result<CGImage, Failure> {
        #if DEBUG && targetEnvironment(simulator)
        statistics.record()
        #endif
        precondition(!Thread.isMainThread, "Bamboo rasterization must never run during layout")
        let padding = BambooRasterCache.padding
        let alignment = YubaiSize.bambooShadow
        let size = CGSize(width: alignment.width + padding * 2, height: alignment.height + padding * 2)
        let pixels: CGImage
        #if os(iOS)
        guard let asset = UIImage(named: "BambooShadow") else { return .failure(.assetMissing) }
        guard asset.size.width > 0, asset.size.height > 0 else { return .failure(.assetSize) }
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale; format.opaque = false; format.preferredRange = .standard
        let fit = min(alignment.width / asset.size.width, alignment.height / asset.size.height)
        let fitted = CGSize(width: asset.size.width * fit, height: asset.size.height * fit)
        let rect = CGRect(x: (size.width - fitted.width) / 2, y: (size.height - fitted.height) / 2, width: fitted.width, height: fitted.height)
        let bitmap = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            asset.withTintColor(UIColor(cgColor: tint), renderingMode: .alwaysOriginal).draw(in: rect)
        }
        guard let bitmapPixels = bitmap.cgImage else { return .failure(.bitmapPixels) }
        pixels = bitmapPixels
        #else
        guard let asset = NSImage(named: "BambooShadow") else { return .failure(.assetMissing) }
        guard asset.size.width > 0, asset.size.height > 0 else { return .failure(.assetSize) }
        var proposed = CGRect(origin: .zero, size: CGSize(width: alignment.width * scale, height: alignment.height * scale))
        guard let source = asset.cgImage(forProposedRect: &proposed, context: nil, hints: nil) else { return .failure(.assetRaster) }
        guard let bitmap = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale),
                  bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return .failure(.bitmapContext) }
        bitmap.scaleBy(x: scale, y: scale)
        let fit = min(alignment.width / asset.size.width, alignment.height / asset.size.height)
        let fitted = CGSize(width: asset.size.width * fit, height: asset.size.height * fit)
        bitmap.draw(source, in: CGRect(x: (size.width - fitted.width) / 2, y: (size.height - fitted.height) / 2, width: fitted.width, height: fitted.height))
        bitmap.setBlendMode(.sourceIn); bitmap.setFillColor(tint)
        bitmap.fill(CGRect(origin: .zero, size: size))
        guard let bitmapPixels = bitmap.makeImage() else { return .failure(.bitmapPixels) }
        pixels = bitmapPixels
        #endif
        guard let inputVisible = hasVisiblePixels(pixels) else { return .failure(.inputSampleContext) }
        guard inputVisible else { return .failure(.inputEmpty) }
        let input = CIImage(cgImage: pixels)
        let blurred = input.applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 6 * scale])
        guard let output = context.createCGImage(blurred, from: input.extent) else { return .failure(.blurOutput) }
        guard let outputVisible = hasVisiblePixels(output) else { return .failure(.outputSampleContext) }
        guard outputVisible else { return .failure(.outputEmpty) }
        return .success(output)
    }
    private static func hasVisiblePixels(_ image: CGImage) -> Bool? {
        let sample = YubaiSize.bambooVisibilitySample
        let width = Int(sample.width), height = Int(sample.height)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        return pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            context.draw(image, in: CGRect(origin: .zero, size: sample))
            return stride(from: 3, to: buffer.count, by: 4).contains { buffer[$0] > 0 }
        }
    }
}
