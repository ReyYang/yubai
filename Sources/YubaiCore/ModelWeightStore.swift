import Foundation
import CryptoKit

/// Placeholder catalog for on-device GGUF weights. URLs are not production CDN endpoints yet.
public struct ModelWeightSpec: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var displayName: String
    public var filename: String
    public var downloadURL: String
    public var expectedSHA256: String
    public var approximateBytes: Int64
    public var recommendedMinRAMGB: Int

    public init(
        id: String,
        displayName: String,
        filename: String,
        downloadURL: String,
        expectedSHA256: String,
        approximateBytes: Int64,
        recommendedMinRAMGB: Int
    ) {
        self.id = id
        self.displayName = displayName
        self.filename = filename
        self.downloadURL = downloadURL
        self.expectedSHA256 = expectedSHA256
        self.approximateBytes = approximateBytes
        self.recommendedMinRAMGB = recommendedMinRAMGB
    }
}

public enum ModelWeightCatalog {
    /// Placeholder HTTPS URLs — replace before enabling real download in production.
    public static let defaults: [ModelWeightSpec] = [
        ModelWeightSpec(
            id: "qwen25-05b-q4",
            displayName: "Qwen2.5 Instruct 0.5B Q4（覆盖档）",
            filename: "Qwen2.5-0.5B-Instruct-Q4_K_M.gguf",
            downloadURL: "https://example.invalid/yubai/models/Qwen2.5-0.5B-Instruct-Q4_K_M.gguf",
            expectedSHA256: "0000000000000000000000000000000000000000000000000000000000000000",
            approximateBytes: 400_000_000,
            recommendedMinRAMGB: 6
        ),
        ModelWeightSpec(
            id: "qwen25-15b-q4",
            displayName: "Qwen2.5 Instruct 1.5B Q4（推荐档）",
            filename: "Qwen2.5-1.5B-Instruct-Q4_K_M.gguf",
            downloadURL: "https://example.invalid/yubai/models/Qwen2.5-1.5B-Instruct-Q4_K_M.gguf",
            expectedSHA256: "1111111111111111111111111111111111111111111111111111111111111111",
            approximateBytes: 1_000_000_000,
            recommendedMinRAMGB: 8
        )
    ]

    public static func spec(id: String) -> ModelWeightSpec? {
        defaults.first { $0.id == id }
    }
}

public struct ModelWeightStatus: Equatable, Sendable {
    public var specID: String
    public var installed: Bool
    public var bytesOnDisk: Int64
    public var verified: Bool
    public init(specID: String, installed: Bool, bytesOnDisk: Int64, verified: Bool) {
        self.specID = specID
        self.installed = installed
        self.bytesOnDisk = bytesOnDisk
        self.verified = verified
    }
}

public enum ModelWeightError: LocalizedError, Equatable {
    case invalidURL
    case downloadFailed(String)
    case checksumMismatch
    case notFound
    case placeholderBlocked

    public var errorDescription: String? {
        switch self {
        case .invalidURL: return "模型下载地址无效。"
        case .downloadFailed(let message): return "下载失败：\(message)"
        case .checksumMismatch: return "模型文件校验失败，已删除不完整文件。"
        case .notFound: return "未找到本机模型文件。"
        case .placeholderBlocked: return "当前为占位下载地址，不会发起真实网络请求。请配置正式 CDN 后再下载。"
        }
    }
}

/// Download / verify / delete API for optional local weights. Does not embed GGUF in the app bundle.
public final class ModelWeightStore: @unchecked Sendable {
    public let directory: URL
    public var catalog: [ModelWeightSpec]
    /// When true, refuse example.invalid URLs (safe default for shipping builds).
    public var blockPlaceholderDownloads: Bool

    public init(
        directory: URL? = nil,
        catalog: [ModelWeightSpec] = ModelWeightCatalog.defaults,
        blockPlaceholderDownloads: Bool = true
    ) {
        if let directory {
            self.directory = directory
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            self.directory = base.appendingPathComponent("Yubai/Models", isDirectory: true)
        }
        self.catalog = catalog
        self.blockPlaceholderDownloads = blockPlaceholderDownloads
    }

    public func ensureDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    public func fileURL(for spec: ModelWeightSpec) -> URL {
        directory.appendingPathComponent(spec.filename, isDirectory: false)
    }

    public func status(for spec: ModelWeightSpec) -> ModelWeightStatus {
        let url = fileURL(for: spec)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return ModelWeightStatus(specID: spec.id, installed: false, bytesOnDisk: 0, verified: false)
        }
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        let size = Int64(values?.fileSize ?? 0)
        let verified = (try? verify(spec: spec)) == true
        return ModelWeightStatus(specID: spec.id, installed: true, bytesOnDisk: size, verified: verified)
    }

    public func anyReadyWeight() -> ModelWeightSpec? {
        catalog.first { status(for: $0).installed && status(for: $0).verified }
    }

    public var hasReadyWeight: Bool {
        anyReadyWeight() != nil
    }

    public func verify(spec: ModelWeightSpec) throws -> Bool {
        let url = fileURL(for: spec)
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        // Placeholder zero/ones hashes: treat non-empty file as "present" only when hash is placeholder;
        // real hashes must match SHA-256.
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        let digest = SHA256.hash(data: data)
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        if isPlaceholderHash(spec.expectedSHA256) {
            return !data.isEmpty
        }
        return hex.caseInsensitiveCompare(spec.expectedSHA256) == .orderedSame
    }

    public func delete(spec: ModelWeightSpec) throws {
        let url = fileURL(for: spec)
        guard FileManager.default.fileExists(atPath: url.path) else { throw ModelWeightError.notFound }
        try FileManager.default.removeItem(at: url)
    }

    /// Downloads weight. Refuses placeholder example.invalid hosts by default.
    public func download(spec: ModelWeightSpec, session: URLSession = .shared) async throws {
        try ensureDirectory()
        guard let url = URL(string: spec.downloadURL) else { throw ModelWeightError.invalidURL }
        if blockPlaceholderDownloads, isPlaceholderHost(url) {
            throw ModelWeightError.placeholderBlocked
        }
        let destination = fileURL(for: spec)
        do {
            let (temp, response) = try await session.download(from: url)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                throw ModelWeightError.downloadFailed("HTTP \(http.statusCode)")
            }
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: temp, to: destination)
        } catch let error as ModelWeightError {
            throw error
        } catch {
            throw ModelWeightError.downloadFailed(error.localizedDescription)
        }
        do {
            guard try verify(spec: spec) else { throw ModelWeightError.checksumMismatch }
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }

    /// Test helper: write bytes as if downloaded so routing can see a ready weight.
    public func installFixture(spec: ModelWeightSpec, data: Data) throws {
        try ensureDirectory()
        try data.write(to: fileURL(for: spec), options: .atomic)
        if !isPlaceholderHash(spec.expectedSHA256) {
            guard try verify(spec: spec) else { throw ModelWeightError.checksumMismatch }
        }
    }

    private func isPlaceholderHost(_ url: URL) -> Bool {
        let host = (url.host ?? "").lowercased()
        return host == "example.invalid" || host == "example.com" || host.hasSuffix(".invalid")
    }

    private func isPlaceholderHash(_ hex: String) -> Bool {
        let set = Set(hex.lowercased())
        return hex.count == 64 && (set == ["0"] || set == ["1"])
    }
}
