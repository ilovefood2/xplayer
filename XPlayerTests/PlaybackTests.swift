// SPDX-License-Identifier: MIT
import AVFoundation
import Combine
import Network
import UIKit
import XCTest
@testable import XPlayer

final class PlaybackTests: XCTestCase {
    @MainActor func testRealVideoDecodesAndPlaylistAdvancesAutomatically() async throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let library = LibraryStore(root: temporary.appendingPathComponent("Videos"), metadata: temporary.appendingPathComponent("playlists.json"))
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "clip", withExtension: "mp4"))
        try FileManager.default.copyItem(at: fixture, to: library.root.appendingPathComponent("first.mp4"))
        try FileManager.default.copyItem(at: fixture, to: library.root.appendingPathComponent("second.mp4"))
        library.refresh()
        let playback = PlaybackController()
        defer { playback.stop() }
        let advanced = expectation(description: "Video decoded, played, and advanced to second item")
        let observation = playback.$index.dropFirst().first { $0 == 1 }.sink { _ in advanced.fulfill() }
        playback.play(["missing.mp4", "first.mp4", "second.mp4"], library: library)
        XCTAssertEqual(playback.paths, ["first.mp4", "second.mp4"])
        playback.previous()
        XCTAssertEqual(playback.index, 0)
        await fulfillment(of: [advanced], timeout: 20)
        XCTAssertNil(playback.error)
        XCTAssertEqual(playback.title, "second.mp4")
        playback.next()
        XCTAssertEqual(playback.index, 1)
        playback.previous()
        XCTAssertEqual(playback.title, "first.mp4")
        playback.stop()
        XCTAssertNil(playback.player.currentItem)
        withExtendedLifetime(observation) {}
    }
    @MainActor func testNetworkURLValidationPreservesSignedQueries() throws {
        let address = "https://media.example.invalid/movie.mp4?token=a%2Fb&expires=123"
        XCTAssertEqual(try PlaybackController.networkURL(" \(address)\n").absoluteString, address)
        XCTAssertEqual(try PlaybackController.networkURL("http://127.0.0.1:8080/live.m3u8").port, 8080)
        for invalid in ["", "movie.mp4", "file:///tmp/video.mp4", "ftp://host/video", "https:///", "https://user:password@host/video", "http://host:99999/video", "https://host/\nvideo"] {
            XCTAssertThrowsError(try PlaybackController.networkURL(invalid), invalid)
        }
    }

    @MainActor func testHLSStreamDecodes() async throws {
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "stream", withExtension: "ts"))
        let playlist = "#EXTM3U\n#EXT-X-VERSION:3\n#EXT-X-TARGETDURATION:8\n#EXT-X-MEDIA-SEQUENCE:0\n#EXTINF:8.0,\nstream.ts\n#EXT-X-ENDLIST\n"
        let server = try VideoHTTPServer(files: ["/live.m3u8": Data(playlist.utf8), "/stream.ts": Data(contentsOf: fixture)])
        defer { server.stop() }
        let ready = expectation(description: "HLS fixture server ready")
        server.start { ready.fulfill() }
        await fulfillment(of: [ready], timeout: 5)
        let playback = PlaybackController()
        defer { playback.stop() }
        let window = try XCTUnwrap((UIApplication.shared.connectedScenes.first as? UIWindowScene)?.windows.first)
        let layer = AVPlayerLayer(player: playback.player)
        layer.frame = window.bounds
        window.layer.addSublayer(layer)
        defer { layer.removeFromSuperlayer() }
        playback.playNetwork(try PlaybackController.networkURL("http://127.0.0.1:\(try XCTUnwrap(server.port))/live.m3u8"))
        let item = try XCTUnwrap(playback.player.currentItem)
        let ended = expectation(forNotification: .AVPlayerItemDidPlayToEndTime, object: item)
        await fulfillment(of: [ended], timeout: 20)
        XCTAssertNil(playback.error)
        XCTAssertEqual(item.status, .readyToPlay)
    }

    @MainActor func testNetworkVideoDecodesAndCanSwitchBackToLocalPlayback() async throws {
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "clip", withExtension: "mp4"))
        let server = try VideoHTTPServer(files: ["/clip.mp4": try Data(contentsOf: fixture)])
        defer { server.stop() }
        let ready = expectation(description: "HTTP fixture server ready")
        server.start { ready.fulfill() }
        await fulfillment(of: [ready], timeout: 5)
        let port = try XCTUnwrap(server.port)
        let playback = PlaybackController()
        defer { playback.stop() }
        playback.playNetwork(try PlaybackController.networkURL("http://127.0.0.1:\(port)/clip.mp4?token=private"))
        let item = try XCTUnwrap(playback.player.currentItem)
        XCTAssertEqual(playback.title, "clip.mp4")
        let ended = expectation(forNotification: .AVPlayerItemDidPlayToEndTime, object: item)
        await fulfillment(of: [ended], timeout: 20)
        XCTAssertNil(playback.error)
        XCTAssertEqual(item.status, .readyToPlay)
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let library = LibraryStore(root: temporary.appendingPathComponent("Videos"), metadata: temporary.appendingPathComponent("playlists.json"))
        try FileManager.default.copyItem(at: fixture, to: library.root.appendingPathComponent("local.mp4"))
        library.refresh()
        playback.play(["local.mp4"], library: library)
        XCTAssertEqual(playback.title, "local.mp4")
        XCTAssertTrue((playback.player.currentItem?.asset as? AVURLAsset)?.url.isFileURL == true)
    }

}

// A loopback-only server exercises AVPlayer's real HTTP byte-range requests without an external service.
private final class VideoHTTPServer {
    private let listener: NWListener
    private let files: [String: Data]
    private let queue = DispatchQueue(label: "xplayer.tests.http")
    var port: UInt16? { listener.port?.rawValue }
    init(files: [String: Data]) throws {
        self.files = files
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
    }
    func start(ready: @escaping () -> Void) {
        listener.stateUpdateHandler = { if case .ready = $0 { ready() } }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { connection.cancel(); return }
            connection.start(queue: self.queue)
            self.receive(connection, header: Data())
        }
        listener.start(queue: queue)
    }
    func stop() { listener.cancel() }
    private func receive(_ connection: NWConnection, header: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] bytes, _, complete, error in
            guard let self, let bytes, error == nil else { connection.cancel(); return }
            let header = header + bytes
            guard header.count <= 16384 else { connection.cancel(); return }
            guard let text = String(data: header, encoding: .utf8), text.contains("\r\n\r\n") else {
                if complete { connection.cancel() } else { self.receive(connection, header: header) }
                return
            }
            guard let target = text.components(separatedBy: "\r\n").first?.split(separator: " ").dropFirst().first,
                  let path = URLComponents(string: String(target))?.path,
                  let data = self.files[path] else { connection.cancel(); return }
            let type = path.hasSuffix(".m3u8") ? "application/vnd.apple.mpegurl" : (path.hasSuffix(".ts") ? "video/mp2t" : "video/mp4")
            let range = text.components(separatedBy: "\r\n").first { $0.lowercased().hasPrefix("range: bytes=") }
            let values = range?.split(separator: "=", maxSplits: 1).last?.split(separator: "-", omittingEmptySubsequences: false)
            let start = values?.first.flatMap { Int($0) } ?? 0
            let end = min(values?.last.flatMap { Int($0) } ?? (data.count - 1), data.count - 1)
            guard start >= 0, start <= end else { connection.cancel(); return }
            let body = data.subdata(in: start..<(end + 1))
            var response = "HTTP/1.1 \(range == nil ? "200 OK" : "206 Partial Content")\r\nContent-Type: \(type)\r\nAccept-Ranges: bytes\r\nContent-Length: \(body.count)\r\nConnection: close\r\n"
            if range != nil { response += "Content-Range: bytes \(start)-\(end)/\(data.count)\r\n" }
            response += "\r\n"
            connection.send(content: Data(response.utf8) + body, completion: .contentProcessed { _ in connection.cancel() })
        }
    }
}
