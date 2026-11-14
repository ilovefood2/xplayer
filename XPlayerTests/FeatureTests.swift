// SPDX-License-Identifier: MIT
import AVFoundation
import UIKit
import XCTest
@testable import XPlayer

/// Sorting, renaming, resume, subtitles, tracks, repeat/shuffle, thumbnails, and network shares.
final class FeatureTests: XCTestCase {
    private var temporary: URL!
    override func setUpWithError() throws {
        temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        UserDefaults.standard.removeObject(forKey: "repeatMode")
        UserDefaults.standard.removeObject(forKey: "shufflePlayback")
    }
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporary)
        UserDefaults.standard.removeObject(forKey: "repeatMode")
        UserDefaults.standard.removeObject(forKey: "shufflePlayback")
    }

    @MainActor private func store() -> LibraryStore {
        LibraryStore(root: temporary.appendingPathComponent("Documents"), metadata: temporary.appendingPathComponent("playlists.json"))
    }
    private func write(_ text: String, to path: String, in root: URL) throws {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }
    private func fixture(_ name: String, _ ext: String, to path: String, in root: URL) throws {
        let source = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: ext))
        let target = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: source, to: target)
    }
    @MainActor private func waitUntil(_ seconds: Double = 15, file: StaticString = #filePath, line: UInt = #line,
                                      _ condition: () -> Bool) async throws {
        for _ in 0..<Int(seconds * 10) {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTFail("Condition not met within \(seconds) seconds", file: file, line: line)
    }

    // MARK: Library

    func testSortingKeepsFoldersFirstAndOrdersByEachKey() {
        let old = Date(timeIntervalSince1970: 1_000), new = Date(timeIntervalSince1970: 2_000)
        let entries = [
            VideoEntry(path: "b.mp4", isFolder: false, size: 10, added: new, modified: old),
            VideoEntry(path: "Folder", isFolder: true, added: old, modified: old),
            VideoEntry(path: "a10.mp4", isFolder: false, size: 30, added: old, modified: new),
            VideoEntry(path: "a2.mp4", isFolder: false, size: 20, added: old, modified: old),
        ]
        XCTAssertEqual(LibrarySort.name.sorted(entries, ascending: true).map(\.path), ["Folder", "a2.mp4", "a10.mp4", "b.mp4"])
        XCTAssertEqual(LibrarySort.name.sorted(entries, ascending: false).map(\.path), ["Folder", "b.mp4", "a10.mp4", "a2.mp4"])
        XCTAssertEqual(LibrarySort.size.sorted(entries, ascending: false).map(\.path), ["Folder", "a10.mp4", "a2.mp4", "b.mp4"])
        XCTAssertEqual(LibrarySort.added.sorted(entries, ascending: false).map(\.path), ["Folder", "b.mp4", "a2.mp4", "a10.mp4"])
        XCTAssertEqual(LibrarySort.modified.sorted(entries, ascending: true).map(\.path), ["Folder", "a2.mp4", "b.mp4", "a10.mp4"])
    }

    @MainActor func testScanRecordsSizeAndDates() throws {
        let library = store()
        try write("12345", to: "clip.mp4", in: library.root)
        library.refresh()
        let entry = try XCTUnwrap(library.entries.first)
        XCTAssertEqual(entry.size, 5)
        XCTAssertGreaterThan(entry.modified.timeIntervalSince1970, 0)
    }

    @MainActor func testRenamingAVideoKeepsItsExtensionReferencesAndSubtitles() throws {
        let library = store()
        try write("video", to: "Shows/Episode.mkv", in: library.root)
        try write("1\n00:00:01,000 --> 00:00:02,000\nHi\n", to: "Shows/Episode.srt", in: library.root)
        try write("1\n00:00:01,000 --> 00:00:02,000\nNi hao\n", to: "Shows/Episode.zh.ass", in: library.root)
        library.refresh()
        let id = try library.createPlaylist("Watch", paths: ["Shows/Episode.mkv"])
        try library.toggleFavorite("Shows/Episode.mkv")
        library.recordPosition(120, duration: 600, for: "Shows/Episode.mkv")
        try library.rename(VideoEntry(path: "Shows/Episode.mkv", isFolder: false), to: "Pilot")
        XCTAssertEqual(library.videos().map(\.path), ["Shows/Pilot.mkv"])
        XCTAssertEqual(library.playlists.first { $0.id == id }?.paths, ["Shows/Pilot.mkv"])
        XCTAssertTrue(library.favorites.contains("Shows/Pilot.mkv"))
        XCTAssertEqual(library.resumePosition(for: "Shows/Pilot.mkv"), 120)
        let files = try FileManager.default.contentsOfDirectory(atPath: library.root.appendingPathComponent("Shows").path).sorted()
        XCTAssertEqual(files, ["Pilot.mkv", "Pilot.srt", "Pilot.zh.ass"])
        XCTAssertThrowsError(try library.rename(VideoEntry(path: "Shows/Pilot.mkv", isFolder: false), to: "../escape"))
    }

    @MainActor func testResumePositionsPersistClearNearTheEdgesAndFollowDeletes() throws {
        let metadata = temporary.appendingPathComponent("playlists.json")
        let root = temporary.appendingPathComponent("Documents")
        let library = LibraryStore(root: root, metadata: metadata)
        try write("video", to: "movie.mp4", in: root)
        library.refresh()
        library.recordPosition(3, duration: 600, for: "movie.mp4")
        XCTAssertNil(library.resumePosition(for: "movie.mp4"), "The first seconds are not worth resuming")
        library.recordPosition(250.4, duration: 600, for: "movie.mp4")
        XCTAssertEqual(LibraryStore(root: root, metadata: metadata).resumePosition(for: "movie.mp4"), 250)
        library.recordPosition(595, duration: 600, for: "movie.mp4")
        XCTAssertNil(library.resumePosition(for: "movie.mp4"), "A finished video starts over")
        library.recordPosition(100, duration: 600, for: "movie.mp4")
        try library.delete(VideoEntry(path: "movie.mp4", isFolder: false))
        XCTAssertTrue(library.positions.isEmpty)
    }

    @MainActor func testImportBringsSubtitleFilesWithoutCountingThem() throws {
        let library = store()
        let source = temporary.appendingPathComponent("Movie Night")
        try write("video", to: "Film.mp4", in: source)
        try write("1\n00:00:01,000 --> 00:00:02,000\nHi\n", to: "Film.srt", in: source)
        try write("notes", to: "notes.txt", in: source)
        let result = LibraryFiles.importVideos([source], into: library.root)
        XCTAssertTrue(result.hasPrefix("Imported 1 video."), result)
        XCTAssertTrue(result.contains("Skipped 1"), result)
        XCTAssertTrue(FileManager.default.fileExists(atPath: library.root.appendingPathComponent("Movie Night/Film.srt").path))
        XCTAssertEqual(LibraryStore.sidecars(of: library.root.appendingPathComponent("Movie Night/Film.mp4")).map(\.lastPathComponent), ["Film.srt"])
    }

    // MARK: Subtitles

    func testSubtitleFormatsAndEncodingsParse() throws {
        let srt = "1\r\n00:00:01,000 --> 00:00:02,500\r\n<i>Hello</i>\r\nworld\r\n\r\n2\r\n00:00:03,000 --> 00:00:04,000\r\nBye\r\n"
        let cues = SubtitleFiles.parse(srt, format: "srt")
        XCTAssertEqual(cues, [SubtitleCue(start: 1, end: 2.5, text: "Hello\nworld"), SubtitleCue(start: 3, end: 4, text: "Bye")])
        XCTAssertEqual(SubtitleFiles.text(at: 1.2, in: cues), "Hello\nworld")
        XCTAssertNil(SubtitleFiles.text(at: 2.7, in: cues))
        let vtt = "WEBVTT\n\n00:01.000 --> 00:02.000 align:middle\nShort &amp; sweet\n"
        XCTAssertEqual(SubtitleFiles.parse(vtt, format: "vtt"), [SubtitleCue(start: 1, end: 2, text: "Short & sweet")])
        let ass = "[Events]\nFormat: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\nDialogue: 0,0:00:01.50,0:00:03.00,Default,,0,0,0,,{\\i1}Line one\\NLine, two\n"
        XCTAssertEqual(SubtitleFiles.parse(ass, format: "ass"), [SubtitleCue(start: 1.5, end: 3, text: "Line one\nLine, two")])
        // Chinese subtitle files are commonly GB18030, not UTF-8.
        let gb = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
        let data = try XCTUnwrap("1\n00:00:01,000 --> 00:00:02,000\n你好，世界\n".data(using: String.Encoding(rawValue: gb)))
        XCTAssertNil(String(data: data, encoding: .utf8))
        XCTAssertEqual(SubtitleFiles.parse(try XCTUnwrap(SubtitleFiles.decode(data)), format: "srt").first?.text, "你好，世界")
        let copy = try XCTUnwrap(Optional(SubtitleFiles.utf8Copy(of: { let url = temporary.appendingPathComponent("gb.srt"); try? data.write(to: url); return url }())))
        XCTAssertTrue(String(data: try Data(contentsOf: copy), encoding: .utf8)?.contains("你好") == true)
    }

    // MARK: Playback

    @MainActor func testNativePlaybackResumesListsTracksAndShowsSidecarSubtitles() async throws {
        let library = store()
        try fixture("tracks", "mp4", to: "Show/tracks.mp4", in: library.root)
        try write("1\n00:00:00,000 --> 00:00:30,000\nSidecar line\n", to: "Show/tracks.en.srt", in: library.root)
        library.refresh()
        library.recordPosition(5.5, duration: 6, for: "Show/tracks.mp4")
        XCTAssertNil(library.resumePosition(for: "Show/tracks.mp4"), "Within the last 10 seconds clears")
        let playback = PlaybackController()
        defer { playback.stop() }
        playback.play(["Show/tracks.mp4"], library: library)
        try await waitUntil { playback.audioOptions.count == 2 && playback.subtitleOptions.count >= 3 }
        XCTAssertEqual(playback.subtitleOptions.first, TrackOption.off)
        XCTAssertTrue(playback.subtitleOptions.contains { $0.id == "f:0" && $0.name == "en · SRT" })
        XCTAssertEqual(playback.selectedSubtitle, "f:0", "A matching subtitle file is shown automatically")
        try await waitUntil { playback.subtitleText == "Sidecar line" }
        let embedded = try XCTUnwrap(playback.subtitleOptions.first { $0.id.hasPrefix("e:") })
        playback.selectSubtitle(embedded.id)
        try await waitUntil { playback.subtitleText == nil }
        playback.selectAudio("a:1")
        XCTAssertEqual(playback.selectedAudio, "a:1")
        try await waitUntil {
            guard let item = playback.player.currentItem else { return false }
            return item.currentMediaSelection.selectedMediaOption(in: item.asset.mediaSelectionGroup(forMediaCharacteristic: .audible)!)?.extendedLanguageTag == "ja"
        }
    }

    @MainActor func testPlaybackResumesFromTheSavedPositionAndRecordsProgress() async throws {
        let library = store()
        try fixture("seek", "mp4", to: "seek.mp4", in: library.root)
        try fixture("seek", "mkv", to: "seek.mkv", in: library.root)
        library.refresh()
        let window = try XCTUnwrap((UIApplication.shared.connectedScenes.first as? UIWindowScene)?.windows.first)
        for path in ["seek.mp4", "seek.mkv"] {
            library.recordPosition(40, duration: 90, for: path)
            let playback = PlaybackController()
            playback.vlcVideoView.frame = window.bounds
            window.addSubview(playback.vlcVideoView)
            defer { playback.vlcVideoView.removeFromSuperview() }
            playback.play([path], library: library)
            try await waitUntil { playback.resumedFrom == 40 }
            if path.hasSuffix("mkv") {
                try await waitUntil { playback.vlcTime >= 40 }
            } else {
                try await waitUntil { playback.player.currentTime().seconds >= 40 }
            }
            XCTAssertTrue(playback.skip(seconds: 15))
            try await Task.sleep(for: .seconds(1))
            playback.pause()
            XCTAssertGreaterThanOrEqual(library.resumePosition(for: path) ?? 0, 54, path)
            weak var decoder = playback.vlcPlayer
            playback.stop()
            try await waitUntil { decoder == nil }
        }
    }

    @MainActor func testVLCListsAudioAndSubtitleTracksIncludingSidecars() async throws {
        let library = store()
        try fixture("tracks", "mkv", to: "tracks.mkv", in: library.root)
        try write("1\n00:00:00,000 --> 00:00:30,000\nSidecar\n", to: "tracks.srt", in: library.root)
        library.refresh()
        let playback = PlaybackController()
        let window = try XCTUnwrap((UIApplication.shared.connectedScenes.first as? UIWindowScene)?.windows.first)
        playback.vlcVideoView.frame = window.bounds
        window.addSubview(playback.vlcVideoView)
        defer { playback.stop(); playback.vlcVideoView.removeFromSuperview() }
        playback.play(["tracks.mkv"], library: library)
        try await waitUntil { playback.audioOptions.count == 2 && playback.subtitleOptions.count >= 3 }
        let japanese = try XCTUnwrap(playback.audioOptions.last)
        playback.selectAudio(japanese.id)
        try await waitUntil { "v:\(playback.vlcPlayer?.currentAudioTrackIndex ?? -2)" == japanese.id }
        playback.selectSubtitle(TrackOption.off.id)
        try await waitUntil { playback.vlcPlayer?.currentVideoSubTitleIndex == -1 }
        // Let VLC finish shutting down before the next test holds the main thread.
        weak var decoder = playback.vlcPlayer
        playback.stop()
        try await waitUntil { decoder == nil }
    }

    @MainActor func testRepeatOneRepeatAllAndShuffle() async throws {
        let library = store()
        for name in ["a", "b", "c", "d"] { try fixture("clip", "mp4", to: "\(name).mp4", in: library.root) }
        library.refresh()
        let playback = PlaybackController()
        defer { playback.stop(); playback.setRepeatMode(.off); playback.setShuffled(false) }
        playback.setRepeatMode(.all)
        playback.play(["a.mp4", "b.mp4", "c.mp4", "d.mp4"], startingAt: "d.mp4", library: library)
        XCTAssertEqual(playback.index, 3)
        try await waitUntil(25) { playback.index == 0 }
        XCTAssertEqual(playback.title, "a.mp4", "Repeat All wraps to the first video")
        playback.setRepeatMode(.one)
        try await waitUntil(25) { (playback.player.currentTime().seconds) > 0.5 }
        try await Task.sleep(for: .seconds(6))
        XCTAssertEqual(playback.title, "a.mp4", "Repeat One stays on the same video")
        playback.setShuffled(true)
        XCTAssertEqual(playback.title, "a.mp4", "Shuffling keeps the current video playing")
        XCTAssertEqual(Set(playback.paths), ["a.mp4", "b.mp4", "c.mp4", "d.mp4"])
        playback.setShuffled(false)
        XCTAssertEqual(playback.paths, ["a.mp4", "b.mp4", "c.mp4", "d.mp4"])
        XCTAssertEqual(playback.index, 0)
    }

    @MainActor func testThumbnailsAndDurationsForNativeAndVLCFormats() async throws {
        let library = store()
        try fixture("seek", "mp4", to: "seek.mp4", in: library.root)
        try fixture("tracks", "mkv", to: "tracks.mkv", in: library.root)
        library.refresh()
        let info = MediaInfoStore(cache: temporary.appendingPathComponent("cache"))
        for entry in library.videos() { info.request(entry, url: try library.fileURL(entry.path)) }
        try await waitUntil(30) { library.videos().allSatisfy { info.info(for: $0) != nil } }
        let mp4 = try XCTUnwrap(info.info(for: XCTUnwrap(library.videos().first { $0.path == "seek.mp4" })))
        XCTAssertNotNil(mp4.thumbnail)
        XCTAssertEqual(mp4.duration ?? 0, 90, accuracy: 1)
        let mkv = try XCTUnwrap(info.info(for: XCTUnwrap(library.videos().first { $0.path == "tracks.mkv" })))
        XCTAssertNotNil(mkv.thumbnail)
        XCTAssertEqual(mkv.duration ?? 0, 6, accuracy: 1)
        // A second store reads the cache instead of decoding again.
        let cached = MediaInfoStore(cache: temporary.appendingPathComponent("cache"))
        let entry = try XCTUnwrap(library.videos().first)
        cached.request(entry, url: try library.fileURL(entry.path))
        try await waitUntil { cached.info(for: entry)?.thumbnail != nil }
    }

    // MARK: Network

    func testShareAddressesNormalizeAndRejectEmbeddedPasswords() throws {
        XCTAssertEqual(try NetworkServer(name: "", kind: .smb, address: "nas.local").rootURL().absoluteString, "smb://nas.local/")
        XCTAssertEqual(try NetworkServer(name: "", kind: .smb, address: "smb://10.0.0.2/Videos").rootURL().absoluteString, "smb://10.0.0.2/Videos/")
        XCTAssertEqual(try NetworkServer(name: "", kind: .webdav, address: "nas.local/dav").rootURL().absoluteString, "https://nas.local/dav/")
        XCTAssertThrowsError(try NetworkServer(name: "", kind: .webdav, address: "https://u:p@nas.local/").rootURL())
        XCTAssertThrowsError(try NetworkServer(name: "", kind: .smb, address: "https://nas.local/").rootURL())
        let credentials = ShareCredentials(username: "OFFICE\\kai", password: "s3cret")
        XCTAssertEqual(credentials.vlcOptions(for: .smb), [":smb-user=kai", ":smb-pwd=s3cret", ":smb-domain=OFFICE"])
        XCTAssertEqual(ShareCredentials(username: "kai", password: "pw").httpHeaders["Authorization"], "Basic a2FpOnB3")
        XCTAssertTrue(ShareCredentials().vlcOptions(for: .smb).isEmpty)
    }

    @MainActor func testSharesKeepPasswordsInTheKeychainAndRecentLinksAreBounded() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "xplayer.tests.\(UUID().uuidString)"))
        let file = temporary.appendingPathComponent("shares.json")
        let store = NetworkStore(file: file, defaults: defaults)
        let server = NetworkServer(name: " Home NAS ", kind: .webdav, address: "https://nas.local/dav", username: "kai")
        try store.save(server, password: "s3cret")
        defer { Keychain.delete(server.id) }
        XCTAssertFalse(String(data: try Data(contentsOf: file), encoding: .utf8)!.contains("s3cret"), "No password on disk")
        let reopened = NetworkStore(file: file, defaults: defaults)
        XCTAssertEqual(reopened.servers.first?.name, "Home NAS")
        XCTAssertEqual(reopened.credentials(for: try XCTUnwrap(reopened.servers.first)).password, "s3cret")
        try reopened.delete(try XCTUnwrap(reopened.servers.first))
        XCTAssertEqual(Keychain.password(for: server.id), "")
        for number in 0..<25 { store.remember(URL(string: "https://example.invalid/\(number).mp4")!) }
        store.remember(URL(string: "https://example.invalid/3.mp4")!)
        XCTAssertEqual(store.recentLinks.count, NetworkStore.recentLimit)
        XCTAssertEqual(store.recentLinks.first?.lastPathComponent, "3.mp4")
        XCTAssertEqual(store.recentLinks.filter { $0.lastPathComponent == "3.mp4" }.count, 1)
        XCTAssertEqual(NetworkStore(file: file, defaults: defaults).recentLinks.count, NetworkStore.recentLimit)
        store.clearRecents()
        XCTAssertTrue(NetworkStore(file: file, defaults: defaults).recentLinks.isEmpty)
    }

    static func listing(_ base: String, _ entries: [(String, Bool)]) -> String {
        let responses = ([(base, true)] + entries).map { href, folder in
            "<d:response><d:href>\(href)</d:href><d:propstat><d:prop>\(folder ? "<d:resourcetype><d:collection/></d:resourcetype>" : "<d:resourcetype/>")</d:prop></d:propstat></d:response>"
        }.joined()
        return #"<?xml version="1.0"?><d:multistatus xmlns:d="DAV:">"# + responses + "</d:multistatus>"
    }

    @MainActor func testWebDAVListingRequiresCredentialsAndPlaysWithThem() async throws {
        let header = "Basic " + Data("kai:pw".utf8).base64EncodedString()
        let video = try Data(contentsOf: XCTUnwrap(Bundle(for: Self.self).url(forResource: "clip", withExtension: "mp4")))
        let server = try VideoHTTPServer(
            files: ["/dav/Movies/clip.mp4": video],
            listings: [
                "/dav/": Self.listing("/dav/", [("/dav/Movies/", true), ("/dav/notes.txt", false), ("/elsewhere/x.mp4", false)]),
                "/dav/Movies/": Self.listing("/dav/Movies/", [("/dav/Movies/clip.mp4", false), ("/dav/Movies/Caf%C3%A9%20100%25.mkv", false)]),
            ],
            authorization: header)
        defer { server.stop() }
        let ready = expectation(description: "WebDAV fixture ready")
        server.start { ready.fulfill() }
        await fulfillment(of: [ready], timeout: 5)
        let root = try XCTUnwrap(URL(string: "http://127.0.0.1:\(try XCTUnwrap(server.port))/dav/"))
        do {
            _ = try await WebDAV.list(root, credentials: ShareCredentials())
            XCTFail("Listing without credentials must fail")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("rejected"), error.localizedDescription)
        }
        let credentials = ShareCredentials(username: "kai", password: "pw")
        let top = try await WebDAV.list(root, credentials: credentials)
        XCTAssertEqual(top.map(\.name), ["Movies", "notes.txt"], "The folder itself and paths outside it are dropped")
        let movies = try await WebDAV.list(XCTUnwrap(top.first { $0.isFolder }).url, credentials: credentials)
        XCTAssertEqual(Set(movies.map(\.name)), ["clip.mp4", "Café 100%.mkv"])
        let clip = try XCTUnwrap(movies.first { $0.name == "clip.mp4" })
        let playback = PlaybackController()
        defer { playback.stop() }
        playback.playShare(movies, startingAt: clip, kind: .webdav, credentials: credentials)
        try await waitUntil { playback.player.currentItem?.status == .readyToPlay }
        XCTAssertNil(playback.error)
        XCTAssertEqual(playback.title, "clip.mp4")
        XCTAssertEqual(playback.paths.count, 2)
    }
}
