// SPDX-License-Identifier: MIT
import XCTest
@testable import XPlayer

final class LibraryStoreTests: XCTestCase {
    private var temporary: URL!
    override func setUpWithError() throws {
        temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: temporary) }

    @MainActor private func store() -> LibraryStore {
        LibraryStore(root: temporary.appendingPathComponent("Videos"), metadata: temporary.appendingPathComponent("playlists.json"))
    }
    private func video(_ path: String, root: URL) throws {
        let target = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("test video bytes".utf8).write(to: target)
    }

    @MainActor func testFolderImportPreservesHierarchyAndNeverOverwrites() throws {
        let library = store()
        let source = temporary.appendingPathComponent("Trip")
        try video("Day 1/01.mp4", root: source)
        try video("Day 2/02.MOV", root: source)
        try video("notes.txt", root: source)
        let result = LibraryFiles.importVideos([source], into: library.root)
        XCTAssertTrue(result.contains("Imported 2 videos"))
        XCTAssertTrue(result.contains("Skipped 1"))
        _ = LibraryFiles.importVideos([source], into: library.root)
        library.refresh()
        XCTAssertEqual(library.videos().map(\.path), ["Trip/Day 1/01.mp4", "Trip/Day 2/02.MOV", "Trip (2)/Day 1/01.mp4", "Trip (2)/Day 2/02.MOV"].sorted { $0.localizedStandardCompare($1) == .orderedAscending })
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.appendingPathComponent("notes.txt").path))
    }

    @MainActor func testPlaylistOrderPersistsAndDuplicateAddsAreIgnored() throws {
        let library = store()
        try video("one.mp4", root: library.root)
        try video("two.mov", root: library.root)
        library.refresh()
        let id = try library.createPlaylist("Watch later", paths: ["one.mp4", "two.mov", "one.mp4"])
        try library.add(["two.mov", "missing.mp4"], to: id)
        try library.updatePlaylist(id, paths: ["two.mov", "one.mp4"])
        XCTAssertEqual(store().playlists.first?.paths, ["two.mov", "one.mp4"])
        try library.updatePlaylist(id, name: "Favorites", paths: ["one.mp4"])
        XCTAssertEqual(store().playlists.first?.name, "Favorites")
        try library.deletePlaylist(id)
        XCTAssertTrue(store().playlists.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: library.root.appendingPathComponent("one.mp4").path))
    }

    @MainActor func testImportsThroughAliasedContainerAppearInTheirFolders() async throws {
        let container = temporary.appendingPathComponent("real-container")
        let alias = temporary.appendingPathComponent("container-alias")
        let root = alias.appendingPathComponent("Documents/Videos")
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: container)
        let metadata = temporary.appendingPathComponent("playlists.json")
        let library = LibraryStore(root: root, metadata: metadata)
        let source = temporary.appendingPathComponent("Import Source")
        try video("clip.mp4", root: source)
        try video("Trip/Day One/nested.mov", root: source)

        await library.importVideos([source.appendingPathComponent("clip.mp4"), source.appendingPathComponent("Trip")])
        XCTAssertEqual(library.notice, "Imported 2 videos.")
        XCTAssertEqual(library.children(of: "").map(\.path), ["Trip", "clip.mp4"])
        XCTAssertEqual(library.children(of: "Trip/Day One").map(\.path), ["Trip/Day One/nested.mov"])
        XCTAssertEqual(try Data(contentsOf: library.fileURL("clip.mp4")), Data("test video bytes".utf8))

        try library.createPlaylist("Imported", paths: library.videos().map(\.path))
        let reopened = LibraryStore(root: root, metadata: metadata)
        XCTAssertEqual(reopened.children(of: "").map(\.path), ["Trip", "clip.mp4"])
        XCTAssertEqual(reopened.playlists.first?.paths, ["clip.mp4", "Trip/Day One/nested.mov"])
    }

    @MainActor func testFolderMoveAndDeleteUpdateOnlyMatchingPlaylistReferences() throws {
        let library = store()
        try video("Trip/Day 1/clip.mp4", root: library.root)
        try video("Trip2/other.mp4", root: library.root)
        library.refresh()
        try library.createPlaylist("Travel", paths: library.videos().map(\.path))
        try library.createFolder("Archive", in: "")
        try library.relocate(VideoEntry(path: "Trip", isFolder: true), to: "Archive", name: "Holiday")
        XCTAssertEqual(library.playlists[0].paths, ["Archive/Holiday/Day 1/clip.mp4", "Trip2/other.mp4"])
        XCTAssertThrowsError(try library.relocate(VideoEntry(path: "Archive", isFolder: true), to: "Archive/Holiday"))
        try library.delete(VideoEntry(path: "Archive", isFolder: true))
        XCTAssertEqual(store().playlists[0].paths, ["Trip2/other.mp4"])
        XCTAssertTrue(library.exists("Trip2/other.mp4"))
    }

    @MainActor func testFailedMetadataWriteRollsBackFileMoveAndDelete() throws {
        let library = store()
        try video("one.mp4", root: library.root)
        library.refresh()
        try FileManager.default.createDirectory(at: temporary.appendingPathComponent("playlists.json"), withIntermediateDirectories: false)
        try library.createFolder("Destination", in: "")
        let entry = VideoEntry(path: "one.mp4", isFolder: false)
        XCTAssertThrowsError(try library.relocate(entry, to: "Destination"))
        XCTAssertThrowsError(try library.delete(entry))
        XCTAssertTrue(FileManager.default.fileExists(atPath: library.root.appendingPathComponent("one.mp4").path))
    }

    @MainActor func testCorruptMetadataIsPreserved() throws {
        let original = Data("broken metadata".utf8)
        let metadata = temporary.appendingPathComponent("playlists.json")
        try original.write(to: metadata)
        let library = store()
        XCTAssertNotNil(library.notice)
        XCTAssertThrowsError(try library.createPlaylist("New"))
        XCTAssertEqual(try Data(contentsOf: metadata), original)
    }

    @MainActor func testTraversalAndSymlinksAreRejected() throws {
        let library = store()
        XCTAssertThrowsError(try library.fileURL("../secret.mp4"))
        XCTAssertThrowsError(try library.fileURL("/tmp/secret.mp4"))
        XCTAssertThrowsError(try library.createFolder("../bad", in: ""))
        try FileManager.default.createSymbolicLink(at: library.root.appendingPathComponent("escape"), withDestinationURL: temporary)
        XCTAssertThrowsError(try library.fileURL("escape/secret.mp4"))
        library.refresh()
        XCTAssertTrue(library.entries.isEmpty)
    }

    @MainActor func testCannotImportAncestorIntoItself() throws {
        let library = store()
        let result = LibraryFiles.importVideos([temporary], into: library.root)
        XCTAssertTrue(result.contains("outside the destination"))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: library.root.path).isEmpty)
    }

    @MainActor func testRemoteURLsAreRejectedWithoutCreatingFiles() async throws {
        let library = store()
        await library.importVideos([URL(string: "https://example.invalid/private.mp4")!])
        XCTAssertTrue(library.notice?.contains("Only local files") == true)
        XCTAssertFalse(library.isImporting)
        XCTAssertTrue(library.entries.isEmpty)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: library.root.path).isEmpty)
    }
    @MainActor func testLegacyPlaylistsUpgradeAndFavoritesFollowMoves() throws {
        let library = store()
        try video("Trip/one.mp4", root: library.root)
        try video("Trip2/two.mp4", root: library.root)
        let legacy = Playlist(name: "Original", paths: ["Trip/one.mp4"])
        try JSONEncoder().encode([legacy]).write(to: temporary.appendingPathComponent("playlists.json"))
        let upgraded = store()
        XCTAssertEqual(upgraded.playlists, [legacy])
        try upgraded.toggleFavorite("Trip/one.mp4")
        try upgraded.toggleFavorite("Trip2/two.mp4")
        try upgraded.relocate(VideoEntry(path: "Trip", isFolder: true), to: "", name: "Holiday")
        XCTAssertEqual(store().favorites, ["Holiday/one.mp4", "Trip2/two.mp4"])
        XCTAssertEqual(store().playlists[0].paths, ["Holiday/one.mp4"])
        try upgraded.toggleFavorite("Holiday/one.mp4")
        XCTAssertEqual(store().favorites, ["Trip2/two.mp4"])
        XCTAssertThrowsError(try upgraded.toggleFavorite("missing.mp4"))
    }

    @MainActor func testBatchDeleteDeduplicatesParentsAndPreservesUnselectedFiles() throws {
        let library = store()
        for path in ["Trip/one.mp4", "Trip2/two.mp4", "three.mov"] { try video(path, root: library.root) }
        library.refresh()
        try library.createPlaylist("All", paths: library.videos().map(\.path))
        for entry in library.videos() { try library.toggleFavorite(entry.path) }
        try library.delete([
            VideoEntry(path: "Trip", isFolder: true), VideoEntry(path: "Trip/one.mp4", isFolder: false),
            VideoEntry(path: "three.mov", isFolder: false), VideoEntry(path: "three.mov", isFolder: false)
        ])
        let reopened = store()
        XCTAssertEqual(reopened.videos().map(\.path), ["Trip2/two.mp4"])
        XCTAssertEqual(reopened.favorites, ["Trip2/two.mp4"])
        XCTAssertEqual(reopened.playlists[0].paths, ["Trip2/two.mp4"])
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: library.root.path).contains { $0.hasPrefix(".deleted-") })
    }

    @MainActor func testBatchDeleteRollsBackAllFilesWhenMetadataWriteFails() throws {
        let library = store()
        for path in ["one.mp4", "two.mp4"] { try video(path, root: library.root) }
        library.refresh()
        try library.toggleFavorite("one.mp4")
        let metadata = temporary.appendingPathComponent("playlists.json")
        try FileManager.default.removeItem(at: metadata)
        try FileManager.default.createDirectory(at: metadata, withIntermediateDirectories: false)
        XCTAssertThrowsError(try library.delete(library.videos()))
        XCTAssertEqual(library.videos().map(\.path), ["one.mp4", "two.mp4"])
        XCTAssertEqual(library.favorites, ["one.mp4"])
        for entry in library.videos() { XCTAssertEqual(try Data(contentsOf: library.fileURL(entry.path)), Data("test video bytes".utf8)) }
    }

    @MainActor func testBatchDeleteRollsBackWhenASelectedFileDisappears() throws {
        let library = store()
        for path in ["one.mp4", "two.mp4"] { try video(path, root: library.root) }
        library.refresh()
        try library.toggleFavorite("one.mp4")
        try FileManager.default.removeItem(at: library.fileURL("two.mp4"))
        XCTAssertThrowsError(try library.delete(library.videos()))
        XCTAssertEqual(try Data(contentsOf: library.fileURL("one.mp4")), Data("test video bytes".utf8))
        XCTAssertEqual(store().favorites, ["one.mp4"])
        XCTAssertThrowsError(try library.delete([VideoEntry(path: "", isFolder: true)]))
    }

    @MainActor func testMatroskaImportPreservesBytesAndFolderPlacement() async throws {
        let library = store()
        let source = temporary.appendingPathComponent("Matroska")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "clip", withExtension: "mkv"))
        try FileManager.default.copyItem(at: fixture, to: source.appendingPathComponent("sample.MKV"))
        await library.importVideos([source])
        XCTAssertEqual(library.notice, "Imported 1 video.")
        XCTAssertEqual(library.videos().map(\.path), ["Matroska/sample.MKV"])
        XCTAssertEqual(try Data(contentsOf: library.fileURL("Matroska/sample.MKV")), try Data(contentsOf: fixture))
        try library.toggleFavorite("Matroska/sample.MKV")
        XCTAssertEqual(store().favorites, ["Matroska/sample.MKV"])
    }

    @MainActor func testAVIAndWebMFolderImportPreservesBytesAndLibraryReferences() async throws {
        let library = store()
        let source = temporary.appendingPathComponent("New Formats")
        let samples = ["clip.AVI", "Nested/clip.WEBM"]
        for name in samples {
            let ext = (name as NSString).pathExtension.lowercased()
            let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "clip", withExtension: ext))
            let destination = source.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: fixture, to: destination)
        }
        await library.importVideos([source])
        XCTAssertEqual(library.notice, "Imported 2 videos.")
        let paths = samples.map { "New Formats/" + $0 }
        XCTAssertEqual(Set(library.videos().map(\.path)), Set(paths))
        for path in paths {
            let ext = (path as NSString).pathExtension.lowercased()
            let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "clip", withExtension: ext))
            XCTAssertEqual(try Data(contentsOf: library.fileURL(path)), try Data(contentsOf: fixture))
            try library.toggleFavorite(path)
        }
        try library.createPlaylist("Added formats", paths: paths)
        let reopened = store()
        XCTAssertEqual(reopened.favorites, Set(paths))
        XCTAssertEqual(reopened.playlists[0].paths, paths)
    }

}
