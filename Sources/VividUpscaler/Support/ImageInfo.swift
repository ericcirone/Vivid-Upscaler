import AppKit
import ImageIO

/// Reads image dimensions and downsampled thumbnails through ImageIO so large
/// photos never have to be fully decoded just to be listed.
enum ImageInfo {
    // NSCache is internally synchronized.
    nonisolated(unsafe) private static let cache = NSCache<NSString, CGImage>()

    /// Pixel dimensions after applying the EXIF orientation.
    static func orientedPixelSize(of url: URL) -> CGSize? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { return nil }
        let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
        return (5...8).contains(orientation)
            ? CGSize(width: height, height: width)
            : CGSize(width: width, height: height)
    }

    static func thumbnail(for url: URL, maxPixelSize: Int) -> CGImage? {
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)?
            .timeIntervalSinceReferenceDate ?? 0
        let key = "\(url.path)#\(maxPixelSize)#\(modified)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        cache.setObject(thumbnail, forKey: key)
        return thumbnail
    }

    static func formatted(_ size: CGSize) -> String {
        "\(Int(size.width)) × \(Int(size.height))"
    }
}
