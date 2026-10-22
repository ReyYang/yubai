import Foundation
import CArchive

enum RecoveryCompression {
    static func encode(_ bytes: Data) throws -> Data {
        var output = Data(count: bytes.count + bytes.count / 1000 + 1024); var size = output.count
        let result = output.withUnsafeMutableBytes { out in bytes.withUnsafeBytes { source in
            yubai_gzip(source.bindMemory(to: UInt8.self).baseAddress, bytes.count, out.bindMemory(to: UInt8.self).baseAddress, &size)
        } }
        guard result == 0 else { throw YubaiError.invalid("无法压缩恢复版本。") }
        output.count = size; return output
    }
    static func decode(_ bytes: Data) throws -> Data {
        var capacity = min(max(bytes.count * 4, 4096), LedgerCodec.capacity)
        while true {
            var output = Data(count: capacity); var size = capacity
            let result = output.withUnsafeMutableBytes { out in bytes.withUnsafeBytes { source in
                yubai_gunzip(source.bindMemory(to: UInt8.self).baseAddress, bytes.count, out.bindMemory(to: UInt8.self).baseAddress, &size)
            } }
            if result == 0 { output.count = size; return output }
            guard result == 1, capacity < LedgerCodec.capacity else { throw YubaiError.invalid("恢复版本损坏或超过安全容量。") }
            capacity = min(capacity * 2, LedgerCodec.capacity)
        }
    }
}
