import SwiftUI
import Observation
import Foundation
import CoreGraphics
import CoreImage
import Dispatch
import os

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
        // Only value types cross to the worker. In particular, do not capture
        // a dynamic platform color or its bridged CGColor from the UI actor.
        let tintRGB = key.dark ? YubaiColor.bambooShadowDarkRGB : YubaiColor.bambooShadowLightRGB
        let task = Task { @MainActor in
            defer { self.pending[key] = nil }
            // A transient allocation/first-use failure must not erase the
            // shadow for the process lifetime. Retry once per warm request;
            // after that, a later surface/appearance request may try again.
            // Concurrent warm calls share this entire operation, retries too.
            for attempt in 1...2 {
                let result = await BambooRasterizer.render(scale: key.scale, tintRGB: tintRGB)
                switch result {
                case .success(let pixels):
                    self.images[key] = Image(decorative: pixels.image, scale: key.scale, orientation: .up).renderingMode(.original)
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
            "renders": statistics.count, "mainRenders": statistics.mainCount,
            "activeRenders": statistics.active, "maxConcurrentRenders": statistics.maximum, "lastFailure": NSNull()]
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

/// One process-wide serial executor owns every temporary graphics object,
/// including pool drainage. No UIKit/AppKit image cache or drawing is involved.
private enum BambooRasterizer {
    // A CGImage created by Core Image owns its immutable pixel storage. ARC
    // retains it in this result before the pool drains; no borrowed UIImage
    // backing, mutable context or caller-owned byte buffer escapes the worker.
    struct Raster: @unchecked Sendable { let image: CGImage }
    enum Failure: String, Error, Sendable {
        case bitmapContext, bitmapPixels
        case inputSampleContext, inputEmpty, blurOutput, outputSampleContext, outputEmpty
    }
    private static let worker = DispatchQueue(label: "app.yubai.personal.bamboo-raster", qos: .userInitiated)

    static func render(scale: CGFloat, tintRGB: UInt32) async -> Result<Raster, Failure> {
        await withCheckedContinuation { continuation in
            worker.async {
                #if DEBUG && targetEnvironment(simulator)
                statistics.begin()
                #endif
                let result = autoreleasepool { draw(scale: scale, tintRGB: tintRGB) }
                #if DEBUG && targetEnvironment(simulator)
                statistics.end()
                #endif
                // Publish only after all temporary releases have completed.
                continuation.resume(returning: result)
            }
        }
    }
    #if DEBUG && targetEnvironment(simulator)
    static let statistics = RenderStatistics()
    final class RenderStatistics: @unchecked Sendable {
        private let lock = NSLock()
        private var renders = 0
        private var mainRenders = 0
        private var active = 0
        private var maximum = 0
        var snapshot: (count: Int, mainCount: Int, active: Int, maximum: Int) {
            lock.lock(); defer { lock.unlock() }; return (renders, mainRenders, active, maximum)
        }
        func begin() {
            lock.lock(); defer { lock.unlock() }
            renders += 1
            active += 1; maximum = max(maximum, active)
            if Thread.isMainThread { mainRenders += 1 }
        }
        func end() { lock.lock(); defer { lock.unlock() }; active -= 1 }
    }
    #endif
    private static func draw(scale: CGFloat, tintRGB: UInt32) -> Result<Raster, Failure> {
        dispatchPrecondition(condition: .onQueue(worker))
        precondition(!Thread.isMainThread, "Bamboo rasterization must never run during layout")
        let padding = BambooRasterCache.padding
        let alignment = YubaiSize.bambooShadow
        let size = CGSize(width: alignment.width + padding * 2, height: alignment.height + padding * 2)
        guard let bitmap = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale),
                  bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return .failure(.bitmapContext) }
        bitmap.scaleBy(x: scale, y: scale)
        let tint = CGColor(red: CGFloat((tintRGB >> 16) & 255) / 255,
                           green: CGFloat((tintRGB >> 8) & 255) / 255,
                           blue: CGFloat(tintRGB & 255) / 255, alpha: 1)
        bitmap.setFillColor(tint)
        BambooSilhouette.draw(in: bitmap, size: size, alignment: alignment)
        guard let pixels = bitmap.makeImage() else { return .failure(.bitmapPixels) }
        guard let inputVisible = hasVisiblePixels(pixels) else { return .failure(.inputSampleContext) }
        guard inputVisible else { return .failure(.inputEmpty) }
        let input = CIImage(cgImage: pixels)
        let blurred = input.applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 6 * scale])
        let context = CIContext()
        guard let output = context.createCGImage(blurred, from: input.extent) else { return .failure(.blurOutput) }
        guard let outputVisible = hasVisiblePixels(output) else { return .failure(.outputSampleContext) }
        guard outputVisible else { return .failure(.outputEmpty) }
        return .success(Raster(image: output))
    }

    private static func hasVisiblePixels(_ image: CGImage) -> Bool? {
        let sample = YubaiSize.bambooVisibilitySample
        let width = Int(sample.width), height = Int(sample.height)
        // The context owns the sample storage too; never let an autoreleased
        // graphics object keep a pointer borrowed from a Swift array.
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = context.data else { return nil }
        context.draw(image, in: CGRect(origin: .zero, size: sample))
        return withExtendedLifetime(context) {
            let buffer = UnsafeRawBufferPointer(start: data, count: width * height * 4)
            return stride(from: 3, to: buffer.count, by: 4).contains { buffer[$0] > 0 }
        }
    }
}
