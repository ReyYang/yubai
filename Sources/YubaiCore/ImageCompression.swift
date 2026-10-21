import Foundation
#if canImport(ImageIO)
import ImageIO
#endif

public enum ImageCompression {
    public static func compress(_ data: Data, name: String) -> (data: Data, name: String) {
        #if canImport(ImageIO)
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 2048,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { return (data, name) }
        for (type, suffix) in [("public.heic", "heic"), ("public.jpeg", "jpg")] {
            let output = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(output, type as CFString, 1, nil) else { continue }
            CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
            guard CGImageDestinationFinalize(destination) else { continue }
            if output.length < data.count { return (output as Data, (name as NSString).deletingPathExtension + "." + suffix) }
        }
        #endif
        return (data, name)
    }
}
