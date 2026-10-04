import CoreGraphics
import Foundation

struct BatchItem: Identifiable, Equatable {
    enum Status: Equatable {
        case pending
        case processing
        case completed(output: URL, elapsed: TimeInterval)
        case failed(String)
        case skipped
        case cancelled

        var isFinished: Bool {
            switch self {
            case .pending, .processing: false
            case .completed, .failed, .skipped, .cancelled: true
            }
        }
    }

    let id: UUID
    let url: URL
    var pixelSize: CGSize?
    var status: Status

    init(url: URL, pixelSize: CGSize? = nil, status: Status = .pending) {
        id = UUID()
        self.url = url
        self.pixelSize = pixelSize
        self.status = status
    }

    var outputURL: URL? {
        if case .completed(let output, _) = status { return output }
        return nil
    }

    var errorMessage: String? {
        if case .failed(let message) = status { return message }
        return nil
    }
}

enum InputDiscovery {
    /// Extensions the processing runtime can decode.
    static let supportedExtensions: Set<String> = [
        "png", "jpg", "jpeg", "webp", "heic", "heif", "avif", "jxl", "tif", "tiff", "bmp", "gif"
    ]

    static func isSupported(_ url: URL) -> Bool {
        supportedExtensions.contains(url.pathExtension.lowercased())
    }

    /// Expands dropped or chosen URLs into supported image files. Folders
    /// contribute their top-level images; earlier Vivid results are skipped
    /// so re-adding a folder does not upscale its own outputs.
    static func imageURLs(from urls: [URL], fileManager: FileManager = .default) -> [URL] {
        var results: [URL] = []
        for url in urls where url.isFileURL {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { continue }
            if isDirectory.boolValue {
                let contents = (try? fileManager.contentsOfDirectory(
                    at: url,
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles]
                )) ?? []
                results += contents
                    .filter { isSupported($0) && !isVividOutput($0) }
                    .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            } else if isSupported(url) {
                results.append(url)
            }
        }
        return results
    }

    static func isVividOutput(_ url: URL) -> Bool {
        url.deletingPathExtension().lastPathComponent.contains("-vivid-upscale-")
    }
}
