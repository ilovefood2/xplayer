// SPDX-License-Identifier: MIT
import SwiftUI

struct PlaylistsScreen: View {
    @EnvironmentObject private var library: LibraryStore
    @State private var nameRequest: NameRequest?
    @State private var deleting: Playlist?
    var body: some View {
        List {
            ForEach(library.playlists) { playlist in
                NavigationLink { PlaylistScreen(id: playlist.id) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "play.rectangle.on.rectangle").font(.title3).foregroundStyle(Color.teal).frame(width: 28)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(playlist.name).font(.body)
                            Text("\(playlist.paths.count) video\(playlist.paths.count == 1 ? "" : "s")").font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical, 6)
                    }
                }
                .contextMenu {
                    Button("Rename", systemImage: "pencil") {
                        nameRequest = NameRequest(title: "Rename Playlist", value: playlist.name) { try library.updatePlaylist(playlist.id, name: $0) }
                    }
                    Button("Delete Playlist", systemImage: "trash", role: .destructive) { deleting = playlist }
                }
            }
        }
        .listStyle(.plain)
        .overlay {
            if library.playlists.isEmpty {
                ContentUnavailableView {
                    Label("No playlists yet", systemImage: "play.rectangle.on.rectangle")
                } description: { Text("Keep videos together in a playlist.") }
                actions: { Button("New Playlist", action: create).buttonStyle(.borderedProminent).accessibilityLabel("Create playlist") }
            }
        }
        .navigationTitle("Playlists")
        .toolbar {
            if !library.playlists.isEmpty {
                ToolbarItem(placement: .topBarTrailing) { Button(action: create) { Image(systemName: "plus") }.accessibilityLabel("Create playlist") }
            }
        }
        .sheet(item: $nameRequest) { NameSheet(request: $0) }
        .confirmationDialog("Delete playlist?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("Delete Playlist", role: .destructive) { if let deleting { library.perform { try library.deletePlaylist(deleting.id) } }; deleting = nil }
        } message: { Text("Your video files will stay in the library.") }
    }
    private func create() { nameRequest = NameRequest(title: "New Playlist") { _ = try library.createPlaylist($0) } }
}

struct PlaylistScreen: View {
    let id: UUID
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var playback: PlaybackController
    @State private var adding = false
    @State private var nameRequest: NameRequest?
    private var playlist: Playlist? { library.playlists.first { $0.id == id } }
    var body: some View {
        List {
            if let playlist {
                if !playlist.paths.isEmpty {
                    Section {
                        ForEach(Array(playlist.paths.enumerated()), id: \.offset) { offset, path in
                            Button { playback.play(playlist.paths, startingAt: path, library: library) } label: {
                                HStack {
                                    LibraryEntryRow(entry: VideoEntry(path: path, isFolder: false),
                                                    subtitle: library.exists(path) ? (path as NSString).deletingLastPathComponent : "File unavailable")
                                    if !library.exists(path) { Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange) }
                                }
                            }.tint(.primary).disabled(!library.exists(path))
                        }
                        .onMove { source, destination in
                            var paths = playlist.paths
                            paths.move(fromOffsets: source, toOffset: destination)
                            library.perform { try library.updatePlaylist(id, paths: paths) }
                        }
                        .onDelete { offsets in
                            var paths = playlist.paths
                            paths.remove(atOffsets: offsets)
                            library.perform { try library.updatePlaylist(id, paths: paths) }
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .overlay {
            if playlist?.paths.isEmpty == true {
                ContentUnavailableView {
                    Label("No videos yet", systemImage: "play.rectangle")
                } description: { Text("Choose videos from your library.") }
                actions: { Button("Add Videos") { adding = true }.buttonStyle(.borderedProminent) }
            }
        }
        .navigationTitle(playlist?.name ?? "Playlist")
        .toolbar {
            if playlist?.paths.isEmpty == false {
                ToolbarItem(placement: .topBarTrailing) { EditButton() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Add Videos", systemImage: "plus") { adding = true }
                    Button("Play All", systemImage: "play.fill") {
                        if let playlist { playback.play(playlist.paths, library: library) }
                    }.disabled(playlist?.paths.contains(where: library.exists) != true)
                    Button("Rename", systemImage: "pencil") {
                        if let playlist { nameRequest = NameRequest(title: "Rename Playlist", value: playlist.name) { try library.updatePlaylist(id, name: $0) } }
                    }
                } label: { Image(systemName: "ellipsis.circle") }.accessibilityLabel("Playlist actions")
            }
        }
        .sheet(isPresented: $adding) { VideoSelectionSheet(playlistID: id) }
        .sheet(item: $nameRequest) { NameSheet(request: $0) }
    }
}

struct VideoSelectionSheet: View {
    let playlistID: UUID
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<String> = []
    @State private var query = ""
    @State private var error: String?
    private var existing: [String] { library.playlists.first { $0.id == playlistID }?.paths ?? [] }
    private var available: [VideoEntry] { library.videos().filter { !existing.contains($0.path) && (query.isEmpty || $0.path.localizedCaseInsensitiveContains(query)) } }
    var body: some View {
        NavigationStack {
            List {
                if let error { Text(error).foregroundStyle(.red) }
                if available.isEmpty { ContentUnavailableView("No videos to add", systemImage: "film", description: Text("Import videos in Library first, or try another search.")) }
                ForEach(available) { entry in
                    Button {
                        if selected.contains(entry.path) { selected.remove(entry.path) } else { selected.insert(entry.path) }
                    } label: {
                        HStack {
                            LibraryEntryRow(entry: entry, subtitle: entry.parent)
                            Image(systemName: selected.contains(entry.path) ? "checkmark.circle.fill" : "circle")
                        }
                    }.accessibilityAddTraits(selected.contains(entry.path) ? [.isSelected] : [])
                }
            }
            .searchable(text: $query, prompt: "Search all folders")
            .navigationTitle("Add Videos").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add (\(selected.count))") {
                        do { try library.add(library.videos().map(\.path).filter { selected.contains($0) }, to: playlistID); dismiss() }
                        catch { self.error = error.localizedDescription }
                    }.disabled(selected.isEmpty)
                }
            }
        }
    }
}

struct AddToPlaylistSheet: View {
    let paths: [String]
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                if let error { Text(error).foregroundStyle(.red) }
                Section("Choose a playlist") {
                    ForEach(library.playlists) { playlist in
                        Button(playlist.name) {
                            do { try library.add(paths, to: playlist.id); dismiss() }
                            catch { self.error = error.localizedDescription }
                        }
                    }
                }
                Section("Or create a playlist") {
                    TextField("Playlist name", text: $name)
                    Button("Create and Add \(paths.count) Videos") {
                        do { try library.createPlaylist(name, paths: paths); dismiss() }
                        catch { self.error = error.localizedDescription }
                    }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || paths.isEmpty)
                }
            }
            .navigationTitle("Add to Playlist").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}
