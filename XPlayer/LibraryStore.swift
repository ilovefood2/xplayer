// SPDX-License-Identifier: MIT
import Foundation
import Combine

struct VideoEntry: Identifiable, Hashable {
    var id: String { path }
    let path: String
    let isFolder: Bool
    var name: String { (path as NSString).lastPathComponent }
    var parent: String {
        let value = (path as NSString).deletingLastPathComponent
        return value == "." ? "" : value
    }
}

struct Playlist: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var paths: [String] = []
}

private struct LibraryMetadata: Codable {
    var version: Int?
    var playlists: [Playlist]
    var favorites: Set<String>
}

struct LibraryError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

enum LibraryFiles {
    static let extensions: Set<String> = ["mp4", "m4v", "mov", "mkv", "avi", "webm", "ts", "mts", "m2ts"]

    static func validName(_ raw: String) throws -> String {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != ".", name != "..", !name.hasPrefix("."),
              !name.contains("/"), !name.contains(":"), !name.contains("\\"),
              !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              name.utf8.count <= 200 else {
            throw LibraryError(message: "Use a name of 1–200 bytes without slashes, colons, or a leading dot.")
        }
        return name
    }

    static func url(_ path: String, root: URL) throws -> URL {
        let base = root.standardizedFileURL.resolvingSymlinksInPath()
        guard path.isEmpty || (!path.hasPrefix("/") && path.split(separator: "/").allSatisfy {
            $0 != ".." && $0 != "." && !$0.hasPrefix(".")
        }) else { throw LibraryError(message: "Invalid library path.") }
        guard path.split(separator: "/").first?.lowercased() != "inbox" else {
            throw LibraryError(message: "Inbox is managed by iOS. Import its videos using Files, or choose another folder name.")
        }
        // Resolving a non-existent leaf does not reliably resolve its symlink parents.
        var componentURL = base
        for component in path.split(separator: "/") {
            componentURL.appendPathComponent(String(component))
            let attributes = try? FileManager.default.attributesOfItem(atPath: componentURL.path)
            guard attributes?[.type] as? FileAttributeType != .typeSymbolicLink else {
                throw LibraryError(message: "Symbolic links are not supported in the video library.")
            }
        }
        let result = base.appendingPathComponent(path).standardizedFileURL
        let resolved = result.resolvingSymlinksInPath()
        guard resolved.path == base.path || resolved.path.hasPrefix(base.path + "/"),
              resolved.path == result.path else {
            throw LibraryError(message: "Links outside the video library are not supported.")
        }
        return result
    }

    static func scan(root: URL) throws -> [VideoEntry] {
        var entries: [VideoEntry] = []
        var pending = [(url: root, path: "")]
        while let folder = pending.popLast() {
            let items = try FileManager.default.contentsOfDirectory(
                at: folder.url, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
            for item in items {
                let values = try item.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey])
                if values.isSymbolicLink == true { continue }
                if folder.path.isEmpty && item.lastPathComponent.lowercased() == "inbox" { continue }
                // Build relative paths from child names; iOS can rewrite absolute container URL prefixes.
                let path = folder.path.isEmpty ? item.lastPathComponent : folder.path + "/" + item.lastPathComponent
                if values.isDirectory == true {
                    entries.append(VideoEntry(path: path, isFolder: true))
                    pending.append((url: item, path: path))
                } else if values.isRegularFile == true && extensions.contains(item.pathExtension.lowercased()) {
                    entries.append(VideoEntry(path: path, isFolder: false))
                }
            }
        }
        return entries.sorted {
            if $0.isFolder != $1.isFolder { return $0.isFolder }
            return $0.path.localizedStandardCompare($1.path) == .orderedAscending
        }
    }

    static func uniqueDestination(_ source: URL, in folder: URL, reservingInbox: Bool) -> URL {
        let fm = FileManager.default
        var target = folder.appendingPathComponent(source.lastPathComponent)
        let isFolder = (try? source.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        let stem = isFolder ? source.lastPathComponent : source.deletingPathExtension().lastPathComponent
        let suffix = isFolder || source.pathExtension.isEmpty ? "" : "." + source.pathExtension
        var number = 2
        while fm.fileExists(atPath: target.path) || (reservingInbox && target.lastPathComponent.lowercased() == "inbox") {
            target = folder.appendingPathComponent("\(stem) (\(number))\(suffix)")
            number += 1
        }
        return target
    }

    // Copies each selection atomically; a failed selection never leaves a partial video.
    static func importVideos(_ sources: [URL], into folder: URL, reservingInbox: Bool = true) -> String {
        let fm = FileManager.default
        var imported = 0
        var skipped = 0
        var failures: [String] = []
        for source in sources {
            guard source.isFileURL else {
                failures.append("Only local files selected in Files can be imported.")
                continue
            }
            let access = source.startAccessingSecurityScopedResource()
            defer { if access { source.stopAccessingSecurityScopedResource() } }
            let staging = folder.appendingPathComponent(".import-" + UUID().uuidString)
            do {
                let sourcePath = source.resolvingSymlinksInPath().path
                let folderPath = folder.resolvingSymlinksInPath().path
                guard sourcePath != folderPath, !folderPath.hasPrefix(sourcePath + "/") else {
                    throw LibraryError(message: "Choose a folder outside the destination folder.")
                }
                var coordinationError: NSError?
                var copyError: Error?
                var count = 0
                var ignored = 0
                NSFileCoordinator().coordinate(readingItemAt: source, options: [], error: &coordinationError) { readable in
                    do { try copyVideos(readable, to: staging, count: &count, skipped: &ignored) }
                    catch { copyError = error }
                }
                if let coordinationError { throw coordinationError }
                if let copyError { throw copyError }
                if fm.fileExists(atPath: staging.path) {
                    try fm.moveItem(at: staging, to: uniqueDestination(source, in: folder, reservingInbox: reservingInbox))
                }
                imported += count
                skipped += ignored
            } catch {
                try? fm.removeItem(at: staging)
                failures.append("\(source.lastPathComponent): \(error.localizedDescription)")
            }
        }
        var summary = "Imported \(imported) video\(imported == 1 ? "" : "s")."
        if skipped > 0 { summary += " Skipped \(skipped) unsupported files or links. Supported containers: MP4, M4V, MOV, MKV, AVI, WebM, TS, MTS, M2TS." }
        if !failures.isEmpty { summary += "\n" + failures.joined(separator: "\n") }
        return summary
    }

    private static func copyVideos(_ source: URL, to target: URL, count: inout Int, skipped: inout Int) throws {
        let fm = FileManager.default
        let values = try source.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey])
        guard values.isSymbolicLink != true else { skipped += 1; return }
        if values.isDirectory == true {
            try fm.createDirectory(at: target, withIntermediateDirectories: true)
            for child in try fm.contentsOfDirectory(at: source, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
                try copyVideos(child, to: target.appendingPathComponent(child.lastPathComponent), count: &count, skipped: &skipped)
            }
        } else if values.isRegularFile == true && extensions.contains(source.pathExtension.lowercased()) {
            try fm.copyItem(at: source, to: target)
            count += 1
        } else { skipped += 1 }
    }
}

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var entries: [VideoEntry] = []
    @Published private(set) var playlists: [Playlist] = []
    @Published private(set) var favorites: Set<String> = []
    @Published private(set) var isImporting = false
    @Published var notice: String?
    let root: URL
    private let metadata: URL
    private var metadataReadable = true

    init(root: URL? = nil, metadata: URL? = nil) {
        let fm = FileManager.default
        self.root = root ?? fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.metadata = metadata ?? fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("playlists.json")
        do {
            try fm.createDirectory(at: self.root, withIntermediateDirectories: true)
            try fm.createDirectory(at: self.metadata.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fm.fileExists(atPath: self.metadata.path) {
                do {
                    let data = try Data(contentsOf: self.metadata)
                    let decoder = JSONDecoder()
                    let saved: LibraryMetadata
                    if let legacy = try? decoder.decode([Playlist].self, from: data) {
                        saved = LibraryMetadata(version: nil, playlists: legacy, favorites: [])
                    } else {
                        saved = try decoder.decode(LibraryMetadata.self, from: data)
                    }
                    guard saved.version == nil || saved.version == 2 else {
                        throw LibraryError(message: "This library was saved by an unsupported app version.")
                    }
                    if saved.version == nil {
                        // Earlier versions stored every reference relative to Documents/Videos.
                        let updated = saved.playlists.map { playlist in
                            var playlist = playlist
                            playlist.paths = playlist.paths.map { "Videos/" + $0 }
                            return playlist
                        }
                        let backup = self.metadata.appendingPathExtension("before-documents-root")
                        if fm.fileExists(atPath: backup.path) {
                            guard try Data(contentsOf: backup) == data else {
                                throw LibraryError(message: "A different saved-library backup already exists. Both files have been preserved.")
                            }
                        } else {
                            try data.write(to: backup, options: .withoutOverwriting)
                        }
                        try save(updated, favorites: Set(saved.favorites.map { "Videos/" + $0 }))
                    } else {
                        playlists = saved.playlists
                        favorites = saved.favorites
                    }
                }
                catch { metadataReadable = false; throw LibraryError(message: "Saved playlists and favorites could not be loaded or upgraded. The original data has been preserved. \(error.localizedDescription)") }
            }
        } catch { metadataReadable = false; notice = error.localizedDescription }
        refresh()
    }

    func refresh() {
        do { entries = try LibraryFiles.scan(root: root) }
        catch { notice = error.localizedDescription }
    }

    func children(of folder: String) -> [VideoEntry] { entries.filter { $0.parent == folder } }
    func videos(in folder: String = "") -> [VideoEntry] {
        entries.filter { !$0.isFolder && (folder.isEmpty || $0.path.hasPrefix(folder + "/")) }
    }
    func exists(_ path: String) -> Bool { entries.contains { $0.path == path && !$0.isFolder } }
    func fileURL(_ path: String) throws -> URL { try LibraryFiles.url(path, root: root) }

    private func save(_ value: [Playlist], favorites: Set<String>? = nil) throws {
        guard metadataReadable else { throw LibraryError(message: "Library changes are disabled because the saved library could not be read. Restore playlists.json before editing.") }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let saved = LibraryMetadata(version: 2, playlists: value, favorites: favorites ?? self.favorites)
        try encoder.encode(saved).write(to: metadata, options: .atomic)
        playlists = saved.playlists
        self.favorites = saved.favorites
    }

    func toggleFavorite(_ path: String) throws {
        guard exists(path) else { throw LibraryError(message: "This video is no longer in the library.") }
        var updated = favorites
        if updated.contains(path) { updated.remove(path) } else { updated.insert(path) }
        try save(playlists, favorites: updated)
    }

    @discardableResult func createPlaylist(_ name: String, paths: [String] = []) throws -> UUID {
        let name = try LibraryFiles.validName(name)
        var uniquePaths: [String] = []
        for path in paths where exists(path) && !uniquePaths.contains(path) { uniquePaths.append(path) }
        let playlist = Playlist(name: name, paths: uniquePaths)
        try save(playlists + [playlist])
        return playlist.id
    }

    func updatePlaylist(_ id: UUID, name: String? = nil, paths: [String]? = nil) throws {
        guard let index = playlists.firstIndex(where: { $0.id == id }) else { return }
        var updated = playlists
        if let name { updated[index].name = try LibraryFiles.validName(name) }
        if let paths { updated[index].paths = paths }
        try save(updated)
    }

    func add(_ paths: [String], to id: UUID) throws {
        guard let playlist = playlists.first(where: { $0.id == id }) else { return }
        var updated = playlist.paths
        for path in paths where exists(path) && !updated.contains(path) { updated.append(path) }
        try updatePlaylist(id, paths: updated)
    }

    func deletePlaylist(_ id: UUID) throws { try save(playlists.filter { $0.id != id }) }

    func createFolder(_ name: String, in parent: String) throws {
        let name = try LibraryFiles.validName(name)
        let url = try fileURL(parent.isEmpty ? name : parent + "/" + name)
        guard !FileManager.default.fileExists(atPath: url.path) else { throw LibraryError(message: "A file or folder with that name already exists.") }
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        refresh()
    }

    func relocate(_ entry: VideoEntry, to folder: String, name: String? = nil) throws {
        let newName = try LibraryFiles.validName(name ?? entry.name)
        let newPath = folder.isEmpty ? newName : folder + "/" + newName
        guard newPath != entry.path else { return }
        guard !entry.isFolder || !(folder == entry.path || folder.hasPrefix(entry.path + "/")) else {
            throw LibraryError(message: "A folder cannot be moved inside itself.")
        }
        let source = try fileURL(entry.path)
        let target = try fileURL(newPath)
        guard !FileManager.default.fileExists(atPath: target.path) else { throw LibraryError(message: "A file or folder with that name already exists.") }
        func relocated(_ path: String) -> String {
            if path == entry.path { return newPath }
            if entry.isFolder && path.hasPrefix(entry.path + "/") { return newPath + path.dropFirst(entry.path.count) }
            return path
        }
        var updated = playlists
        for index in updated.indices { updated[index].paths = updated[index].paths.map(relocated) }
        let updatedFavorites = Set(favorites.map(relocated))
        try FileManager.default.moveItem(at: source, to: target)
        do { try save(updated, favorites: updatedFavorites) }
        catch {
            try FileManager.default.moveItem(at: target, to: source)
            throw error
        }
        refresh()
    }

    func delete(_ entry: VideoEntry) throws { try delete([entry]) }

    func delete(_ requested: [VideoEntry]) throws {
        guard !requested.isEmpty else { return }
        // Use the current inventory, and stage each parent only once when search selects descendants too.
        let paths = Set(requested.map(\.path))
        guard !paths.contains(""), paths.allSatisfy({ path in entries.contains { $0.path == path } }) else {
            throw LibraryError(message: "The selection changed. Refresh the library and select again.")
        }
        let selected = entries.filter { entry in
            paths.contains(entry.path) && !entries.contains {
                $0.isFolder && paths.contains($0.path) && entry.path.hasPrefix($0.path + "/")
            }
        }
        func removed(_ path: String) -> Bool {
            selected.contains { path == $0.path || ($0.isFolder && path.hasPrefix($0.path + "/")) }
        }
        var updated = playlists
        for index in updated.indices { updated[index].paths.removeAll(where: removed) }
        var staged: [(source: URL, temporary: URL)] = []
        do {
            for entry in selected {
                let source = try fileURL(entry.path)
                let temporary = root.appendingPathComponent(".deleted-" + UUID().uuidString)
                try FileManager.default.moveItem(at: source, to: temporary)
                staged.append((source, temporary))
            }
            try save(updated, favorites: favorites.filter { !removed($0) })
        } catch {
            var rollbackErrors: [String] = []
            for item in staged.reversed() {
                do { try FileManager.default.moveItem(at: item.temporary, to: item.source) }
                catch { rollbackErrors.append("\(item.source.lastPathComponent): \(error.localizedDescription)") }
            }
            refresh()
            if !rollbackErrors.isEmpty {
                throw LibraryError(message: "Deletion failed. Some files remain in hidden .deleted- folders for recovery. " + rollbackErrors.joined(separator: "\n"))
            }
            throw error
        }
        defer { refresh() }
        var cleanupErrors: [String] = []
        for item in staged {
            do { try FileManager.default.removeItem(at: item.temporary) }
            catch { cleanupErrors.append(error.localizedDescription) }
        }
        if !cleanupErrors.isEmpty {
            throw LibraryError(message: "Removed from the library, but some storage could not be reclaimed: " + cleanupErrors.joined(separator: "\n"))
        }
    }

    func importVideos(_ urls: [URL], into folder: String = "") async {
        guard !isImporting else {
            notice = "An import is already running. Please wait for it to finish, then try again."
            return
        }
        do {
            let target = try fileURL(folder)
            isImporting = true
            defer { isImporting = false }
            notice = await Task.detached(priority: .userInitiated) {
                LibraryFiles.importVideos(urls, into: target, reservingInbox: folder.isEmpty)
            }.value
            refresh()
        } catch { notice = error.localizedDescription }
    }

    func perform(_ work: () throws -> Void) {
        do { try work() } catch { notice = error.localizedDescription }
    }
}
