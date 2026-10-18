// SPDX-License-Identifier: MIT
import AVFoundation
import Combine
import UIKit
import MobileVLCKit
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
    @MainActor func testMatroskaDecodesAudioAndVideoSeeksAndAdvancesToMP4() async throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let library = LibraryStore(root: temporary.appendingPathComponent("Videos"), metadata: temporary.appendingPathComponent("playlists.json"))
        for ext in ["mkv", "mp4"] {
            let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "clip", withExtension: ext))
            try FileManager.default.copyItem(at: fixture, to: library.root.appendingPathComponent("clip." + ext))
        }
        library.refresh()
        let playback = PlaybackController()
        let window = try XCTUnwrap((UIApplication.shared.connectedScenes.first as? UIWindowScene)?.windows.first)
        playback.vlcVideoView.frame = window.bounds
        window.addSubview(playback.vlcVideoView)
        defer { playback.stop(); playback.vlcVideoView.removeFromSuperview() }
        playback.play(["clip.mkv", "clip.mp4"], library: library)
        let vlc = try XCTUnwrap(playback.vlcPlayer)
        try await waitUntil { vlc.media?.statistics.decodedVideo ?? 0 > 0 && vlc.media?.statistics.decodedAudio ?? 0 > 0 && vlc.media?.statistics.displayedPictures ?? 0 > 0 && playback.vlcTime > 0 }
        XCTAssertGreaterThan(vlc.videoSize.width, 0)
        XCTAssertTrue(playback.vlcSeekable)
        playback.pause()
        try await waitUntil { !vlc.isPlaying }
        playback.seekVLC(to: 0.65)
        playback.toggleVLCPlayback()
        try await waitUntil { playback.vlcTime > 3 }
        let advanced = expectation(description: "MKV advanced to native MP4")
        let observation = playback.$index.dropFirst().first { $0 == 1 }.sink { _ in advanced.fulfill() }
        await fulfillment(of: [advanced], timeout: 15)
        XCTAssertNil(playback.error)
        XCTAssertNil(playback.vlcPlayer)
        XCTAssertNotNil(playback.player.currentItem)
        playback.previous()
        XCTAssertNotNil(playback.vlcPlayer)
        XCTAssertNil(playback.player.currentItem)
        playback.stop()
        XCTAssertNil(playback.vlcPlayer)
        withExtendedLifetime(observation) {}
    }

    @MainActor func testNetworkMatroskaWithAndWithoutExtension() async throws {
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "clip", withExtension: "mkv"))
        let bytes = try Data(contentsOf: fixture)
        let server = try VideoHTTPServer(files: ["/clip.mkv": bytes, "/download": bytes])
        defer { server.stop() }
        let ready = expectation(description: "Matroska HTTP server ready")
        server.start { ready.fulfill() }
        await fulfillment(of: [ready], timeout: 5)
        let playback = PlaybackController()
        let window = try XCTUnwrap((UIApplication.shared.connectedScenes.first as? UIWindowScene)?.windows.first)
        playback.vlcVideoView.frame = window.bounds
        window.addSubview(playback.vlcVideoView)
        defer { playback.stop(); playback.vlcVideoView.removeFromSuperview() }
        for path in ["clip.mkv", "download"] {
            playback.playNetwork(try PlaybackController.networkURL("http://127.0.0.1:\(try XCTUnwrap(server.port))/\(path)"))
            try await waitUntil { playback.vlcPlayer?.media?.statistics.decodedVideo ?? 0 > 0 }
            XCTAssertNil(playback.error)
            playback.stop()
        }
    }

    @MainActor func testDamagedVLCFormatsReportAnErrorAndStop() async throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let library = LibraryStore(root: temporary.appendingPathComponent("Videos"), metadata: temporary.appendingPathComponent("playlists.json"))
        let playback = PlaybackController()
        defer { playback.stop() }
        for ext in ["mkv", "avi", "webm"] {
            let name = "broken." + ext
            try Data("not a video".utf8).write(to: library.root.appendingPathComponent(name))
            library.refresh()
            playback.play([name], library: library)
            try await waitUntil { playback.error != nil }
            playback.stop()
            XCTAssertNil(playback.vlcPlayer)
        }
    }


    @MainActor func testAVIAndWebMDecodeSeekAndAdvanceInMixedQueue() async throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let library = LibraryStore(root: temporary.appendingPathComponent("Videos"), metadata: temporary.appendingPathComponent("playlists.json"))
        let names = ["clip.avi", "clip.webm", "vp9.webm", "av1.webm", "clip.mp4"]
        for name in names {
            let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: nil))
            try FileManager.default.copyItem(at: fixture, to: library.root.appendingPathComponent(name))
        }
        library.refresh()
        let playback = PlaybackController()
        let window = try XCTUnwrap((UIApplication.shared.connectedScenes.first as? UIWindowScene)?.windows.first)
        playback.vlcVideoView.frame = window.bounds
        window.addSubview(playback.vlcVideoView)
        defer { playback.stop(); playback.vlcVideoView.removeFromSuperview() }
        playback.play(names, library: library)
        for index in 0..<4 {
            XCTAssertEqual(playback.index, index)
            let vlc = try XCTUnwrap(playback.vlcPlayer)
            try await waitUntil {
                (vlc.media?.statistics.decodedVideo ?? 0) > 0 &&
                (vlc.media?.statistics.decodedAudio ?? 0) > 0 &&
                (vlc.media?.statistics.displayedPictures ?? 0) > 0 && playback.vlcSeekable
            }
            playback.seekVLC(to: 0.65)
            try await waitUntil { playback.vlcTime > 3 }
            try await waitUntil { playback.index == index + 1 }
            XCTAssertNil(playback.error)
        }
        XCTAssertNil(playback.vlcPlayer)
        XCTAssertNotNil(playback.player.currentItem)
    }

    @MainActor func testAVIAndWebMNetworkPlaybackDecodesAudioAndVideo() async throws {
        let names = ["clip.avi", "clip.webm", "vp9.webm", "av1.webm"]
        var files: [String: Data] = [:]
        for name in names {
            let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: nil))
            files["/" + name] = try Data(contentsOf: fixture)
        }
        let server = try VideoHTTPServer(files: files)
        defer { server.stop() }
        let ready = expectation(description: "AVI and WebM HTTP fixture server ready")
        server.start { ready.fulfill() }
        await fulfillment(of: [ready], timeout: 5)
        let playback = PlaybackController()
        let window = try XCTUnwrap((UIApplication.shared.connectedScenes.first as? UIWindowScene)?.windows.first)
        playback.vlcVideoView.frame = window.bounds
        window.addSubview(playback.vlcVideoView)
        defer { playback.stop(); playback.vlcVideoView.removeFromSuperview() }
        for name in names {
            playback.playNetwork(try PlaybackController.networkURL("http://127.0.0.1:\(try XCTUnwrap(server.port))/\(name)"))
            let vlc = try XCTUnwrap(playback.vlcPlayer)
            try await waitUntil {
                (vlc.media?.statistics.decodedVideo ?? 0) > 0 &&
                (vlc.media?.statistics.decodedAudio ?? 0) > 0
            }
            XCTAssertNil(playback.error)
            playback.stop()
        }
    }


    @MainActor func testFinderTransportStreamsDecodeAudioVideoAndSeek() async throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let library = LibraryStore(root: temporary.appendingPathComponent("Documents"), metadata: temporary.appendingPathComponent("playlists.json"))
        for ext in ["ts", "mts", "m2ts"] {
            let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "finder", withExtension: ext == "ts" ? "ts" : "m2ts"))
            try FileManager.default.copyItem(at: fixture, to: library.root.appendingPathComponent("Finder." + ext.uppercased()))
        }
        library.refresh()
        let playback = PlaybackController()
        let window = try XCTUnwrap((UIApplication.shared.connectedScenes.first as? UIWindowScene)?.windows.first)
        playback.vlcVideoView.frame = window.bounds
        window.addSubview(playback.vlcVideoView)
        defer { playback.stop(); playback.vlcVideoView.removeFromSuperview() }
        for ext in ["ts", "mts", "m2ts"] {
            playback.play(["Finder." + ext.uppercased()], library: library)
            let vlc = try XCTUnwrap(playback.vlcPlayer, playback.error ?? "VLC player was not created")
            try await waitUntil {
                (vlc.media?.statistics.decodedVideo ?? 0) > 0 &&
                (vlc.media?.statistics.decodedAudio ?? 0) > 0 &&
                (vlc.media?.statistics.displayedPictures ?? 0) > 0 && playback.vlcSeekable
            }
            playback.seekVLC(to: 0.6)
            try await waitUntil { playback.vlcTime > 2 }
            XCTAssertNil(playback.error)
            playback.stop()
        }
    }

    @MainActor func testVLCShutdownReleasesImmediateAndPlayingDecoders() async throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let library = LibraryStore(root: temporary.appendingPathComponent("Documents"), metadata: temporary.appendingPathComponent("playlists.json"))
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "finder", withExtension: "ts"))
        try FileManager.default.copyItem(at: fixture, to: library.root.appendingPathComponent("clip.ts"))
        library.refresh()
        let playback = PlaybackController()
        let window = try XCTUnwrap((UIApplication.shared.connectedScenes.first as? UIWindowScene)?.windows.first)
        playback.vlcVideoView.frame = window.bounds
        window.addSubview(playback.vlcVideoView)
        defer { playback.stop(); playback.vlcVideoView.removeFromSuperview() }
        for waitForVideo in [false, true] {
            playback.play(["clip.ts"], library: library)
            weak var decoder = playback.vlcPlayer
            XCTAssertNotNil(decoder, playback.error ?? "VLC player was not created")
            if waitForVideo {
                try await waitUntil { (decoder?.media?.statistics.displayedPictures ?? 0) > 0 }
            }
            playback.stop()
            XCTAssertNil(playback.vlcPlayer)
            try await waitUntil { decoder == nil }
        }
    }

    @MainActor private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<150 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTFail("Playback did not reach the expected state within 15 seconds")
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
