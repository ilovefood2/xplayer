// SPDX-License-Identifier: MIT
import AVFoundation
import CryptoKit
import UIKit
@preconcurrency import MobileVLCKit

struct MediaInfo {
    var thumbnail: UIImage?
    var duration: Double?
}

/// Thumbnails and durations for library rows, generated once per file version
/// and cached on the device. Nothing leaves the device.
@MainActor
final class MediaInfoStore: ObservableObject {
    @Published private(set) var info: [String: MediaInfo] = [:]
    private var queued: [(key: String, url: URL)] = []
    private var requested = Set<String>()
    private var running = 0
    private let cache: URL

    init(cache: URL? = nil) {
        self.cache = cache ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MediaInfo", isDirectory: true)
        try? FileManager.default.createDirectory(at: self.cache, withIntermediateDirectories: true)
    }

    /// Changes whenever the file is replaced or edited, so stale artwork is never shown.
    static func key(for entry: VideoEntry) -> String {
        let source = "\(entry.path)|\(entry.size)|\(entry.modified.timeIntervalSince1970)"
        return SHA256.hash(data: Data(source.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    func info(for entry: VideoEntry) -> MediaInfo? { info[Self.key(for: entry)] }

    func request(_ entry: VideoEntry, url: URL) {
        let key = Self.key(for: entry)
        guard !entry.isFolder, info[key] == nil, requested.insert(key).inserted else { return }
        queued.append((key, url))
        startNext()
    }

    private func startNext() {
        // Decoding is heavy; two at a time keeps scrolling smooth.
        while running < 2, !queued.isEmpty {
            let job = queued.removeFirst()
            running += 1
            Task {
                let result = await load(job.key, url: job.url)
                info[job.key] = result
                running -= 1
                startNext()
            }
        }
    }

    private func load(_ key: String, url: URL) async -> MediaInfo {
        let imageURL = cache.appendingPathComponent(key + ".jpg")
        let durationURL = cache.appendingPathComponent(key + ".duration")
        if let data = try? Data(contentsOf: durationURL), let text = String(data: data, encoding: .utf8) {
            return MediaInfo(thumbnail: UIImage(contentsOfFile: imageURL.path), duration: Double(text))
        }
        let generated = LibraryFiles.nativeExtensions.contains(url.pathExtension.lowercased())
            ? await Self.native(url) : await VLCThumbnail.generate(url)
        if let image = generated.thumbnail, let jpeg = image.jpegData(compressionQuality: 0.7) {
            try? jpeg.write(to: imageURL, options: .atomic)
        }
        try? Data(String(generated.duration ?? 0).utf8).write(to: durationURL, options: .atomic)
        return generated
    }

    nonisolated private static func native(_ url: URL) async -> MediaInfo {
        let asset = AVURLAsset(url: url)
        let duration = try? await asset.load(.duration).seconds
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 320, height: 320)
        let at = CMTime(seconds: min(10, max(0, (duration ?? 0) * 0.1)), preferredTimescale: 600)
        let image = try? await generator.image(at: at).image
        return MediaInfo(thumbnail: image.map(UIImage.init(cgImage:)),
                         duration: duration.flatMap { $0.isFinite && $0 > 0 ? $0 : nil })
    }
}

/// MKV, AVI, WebM, and MPEG-TS artwork comes from VLC's thumbnailer.
@MainActor
private final class VLCThumbnail: NSObject, VLCMediaThumbnailerDelegate {
    private var continuation: CheckedContinuation<MediaInfo, Never>?
    private var thumbnailer: VLCMediaThumbnailer?
    private let media: VLCMedia

    private init(_ url: URL) { media = VLCMedia(url: url) }

    static func generate(_ url: URL) async -> MediaInfo {
        let job = VLCThumbnail(url)
        return await withCheckedContinuation { continuation in
            job.continuation = continuation
            job.start()
        }
    }

    private func start() {
        let thumbnailer = VLCMediaThumbnailer(media: media, andDelegate: self)
        thumbnailer.thumbnailWidth = 320
        thumbnailer.thumbnailHeight = 180
        thumbnailer.snapshotPosition = 0.1
        self.thumbnailer = thumbnailer
        thumbnailer.fetchThumbnail()
        // The thumbnailer has its own timeout; this guards against a silent decoder.
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in self?.finish(nil) }
    }

    private func finish(_ image: CGImage?) {
        guard let continuation else { return }
        self.continuation = nil
        let length = Double(media.length.intValue) / 1000
        continuation.resume(returning: MediaInfo(thumbnail: image.map(UIImage.init(cgImage:)),
                                                 duration: length > 0 ? length : nil))
        thumbnailer = nil
    }

    nonisolated func mediaThumbnailer(_ mediaThumbnailer: VLCMediaThumbnailer, didFinishThumbnail thumbnail: CGImage) {
        let image = thumbnail
        DispatchQueue.main.async { self.finish(image) }
    }

    nonisolated func mediaThumbnailerDidTimeOut(_ mediaThumbnailer: VLCMediaThumbnailer) {
        DispatchQueue.main.async { self.finish(nil) }
    }
}

extension LibraryFiles {
    /// Formats Apple's player decodes; the rest use MobileVLCKit.
    static let nativeExtensions: Set<String> = ["mp4", "m4v", "mov"]
    static let vlcExtensions: Set<String> = ["mkv", "avi", "webm", "ts", "mts", "m2ts"]
}

enum DurationText {
    static func format(_ seconds: Double) -> String {
        let value = Int(seconds.rounded())
        return value >= 3600
            ? String(format: "%d:%02d:%02d", value / 3600, value / 60 % 60, value % 60)
            : String(format: "%d:%02d", value / 60, value % 60)
    }
}
