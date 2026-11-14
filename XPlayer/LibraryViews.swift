// SPDX-License-Identifier: MIT
import SwiftUI
import UniformTypeIdentifiers

struct NameRequest: Identifiable {
    let id = UUID()
    let title: String
    var value: String = ""
    let save: (String) throws -> Void
}

struct NameSheet: View {
    let request: NameRequest
    @State private var value: String
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool
    init(request: NameRequest) { self.request = request; _value = State(initialValue: request.value) }
    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $value).focused($focused).accessibilityIdentifier("nameField")
                    .submitLabel(.done).onSubmit(save)
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle(request.title).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).disabled(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            }
            .onAppear { focused = true }
        }.presentationDetents([.medium, .large])
    }
    private func save() {
        do { try request.save(value); dismiss() } catch { self.error = error.localizedDescription }
    }
}

struct ImportPicker: UIViewControllerRepresentable {
    let folder: Bool
    let completion: ([URL]) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        var videoTypes: [UTType] = [.mpeg4Movie, .quickTimeMovie, .avi, .mpeg2TransportStream]
        if let m4v = UTType(filenameExtension: "m4v") { videoTypes.append(m4v) }
        videoTypes.append(UTType(importedAs: "org.matroska.mkv", conformingTo: .movie))
        videoTypes.append(UTType(importedAs: "org.webmproject.webm", conformingTo: .movie))
        videoTypes.append(UTType(importedAs: "public.avchd-mpeg-2-transport-stream", conformingTo: .mpeg2TransportStream))
        // Subtitle files can be imported next to their videos.
        for ext in ["srt", "vtt", "ass", "ssa"] { if let type = UTType(filenameExtension: ext) { videoTypes.append(type) } }
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: folder ? [.folder] : videoTypes, asCopy: false)
        picker.allowsMultipleSelection = true
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let completion: ([URL]) -> Void
        init(completion: @escaping ([URL]) -> Void) { self.completion = completion }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { completion(urls) }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { completion([]) }
    }
}

enum ImportSelection: String, Identifiable {
    case videos, folder
    var id: String { rawValue }
}

struct FolderScreen: View {
    let folder: String
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var playback: PlaybackController
    @EnvironmentObject private var mediaInfo: MediaInfoStore
    @AppStorage("librarySort") private var sort = LibrarySort.name
    @AppStorage("librarySortAscending") private var ascending = true
    @State private var query = ""
    @State private var nameRequest: NameRequest?
    @State private var importSelection: ImportSelection?
    @State private var selectedImportURLs: [URL] = []
    @State private var moving: VideoEntry?
    @State private var deleting: [VideoEntry] = []
    @State private var selecting = false
    @State private var selected: Set<String> = []
    @State private var networkVideo = false
    @State private var about = false
    @State private var adding: VideoEntry?
    private var title: String { folder.isEmpty ? "Library" : (folder as NSString).lastPathComponent }
    private var visible: [VideoEntry] {
        let matches = query.isEmpty ? library.children(of: folder) : library.entries.filter {
            (folder.isEmpty || $0.path.hasPrefix(folder + "/")) && $0.name.localizedCaseInsensitiveContains(query)
        }
        return sort.sorted(matches, ascending: ascending)
    }
    var body: some View {
        List {
            if !visible.isEmpty {
                Section {
                    ForEach(visible) { entry in
                        Group {
                            if selecting {
                                Button {
                                    if selected.contains(entry.path) { selected.remove(entry.path) } else { selected.insert(entry.path) }
                                } label: {
                                    HStack {
                                        Image(systemName: selected.contains(entry.path) ? "checkmark.circle.fill" : "circle")
                                        entryRow(entry)
                                    }
                                }
                                .accessibilityLabel(entry.name)
                                .accessibilityAddTraits(selected.contains(entry.path) ? [.isSelected] : [])
                            } else if entry.isFolder {
                                NavigationLink { FolderScreen(folder: entry.path) } label: { entryRow(entry) }
                            } else {
                                Button { playback.play(visible.filter { !$0.isFolder }.map(\.path), startingAt: entry.path, library: library) } label: { entryRow(entry) }.tint(.primary)
                            }
                        }
                        .contextMenu {
                            if !selecting {
                                if entry.isFolder {
                                    Button { play(entry) } label: { Label("Play Folder", systemImage: "play.fill") }
                                }
                                Button { adding = entry } label: { Label("Add to Playlist", systemImage: "text.badge.plus") }
                                Button { moving = entry } label: { Label("Move to Folder", systemImage: "folder") }
                                Button(entry.isFolder ? "Rename Folder" : "Rename", systemImage: "pencil") {
                                    nameRequest = NameRequest(title: entry.isFolder ? "Rename Folder" : "Rename Video",
                                                              value: entry.isFolder ? entry.name : (entry.name as NSString).deletingPathExtension) {
                                        try library.rename(entry, to: $0)
                                    }
                                }
                                if !entry.isFolder, let url = try? library.fileURL(entry.path) {
                                    ShareLink(item: url) { Label("Share", systemImage: "square.and.arrow.up") }
                                }
                                if !entry.isFolder {
                                    Button(library.favorites.contains(entry.path) ? "Remove from Favorites" : "Add to Favorites", systemImage: "heart") {
                                        library.perform { try library.toggleFavorite(entry.path) }
                                    }
                                }
                                Button("Delete", systemImage: "trash", role: .destructive) { deleting = [entry] }
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .overlay {
            if visible.isEmpty {
                ContentUnavailableView {
                    Label(query.isEmpty ? "No videos yet" : "No results", systemImage: query.isEmpty ? "play.rectangle" : "magnifyingglass")
                } description: {
                    Text(query.isEmpty ? "Import videos or folders to get started." : "Try a different name.")
                } actions: {
                    if query.isEmpty {
                        Button("Import Videos") { importSelection = .videos }.buttonStyle(.borderedProminent)
                    }
                }
            }
        }
        .navigationTitle(selecting ? "\(selected.count) Selected" : title)
        .searchable(text: $query, prompt: "Search videos and folders")
        .refreshable { library.refresh() }
        .onChange(of: query) { _, _ in selected.removeAll() }
        .onChange(of: library.entries) { _, entries in selected.formIntersection(Set(entries.map(\.path))) }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if !visible.isEmpty || selecting {
                    Button(selecting ? "Done" : "Select") {
                        selecting.toggle()
                        selected.removeAll()
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                if selecting {
                    Button(selected.count == visible.count ? "Deselect All" : "Select All") {
                        selected = selected.count == visible.count ? [] : Set(visible.map(\.path))
                    }.disabled(visible.isEmpty)
                } else {
                    Menu {
                        Button("Import Videos", systemImage: "square.and.arrow.down") { importSelection = .videos }
                        Button("Import Folder", systemImage: "folder.badge.plus") { importSelection = .folder }
                        Button("New Folder", systemImage: "folder.fill.badge.plus") {
                            nameRequest = NameRequest(title: "New Folder") { try library.createFolder($0, in: folder) }
                        }
                        Divider()
                        Menu {
                            Picker("Sort By", selection: $sort) {
                                ForEach(LibrarySort.allCases) { Text($0.title).tag($0) }
                            }
                            Picker("Order", selection: $ascending) {
                                Text(sort == .name ? "A to Z" : (sort == .size ? "Smallest First" : "Oldest First")).tag(true)
                                Text(sort == .name ? "Z to A" : (sort == .size ? "Largest First" : "Newest First")).tag(false)
                            }
                        } label: { Label("Sort By: \(sort.title)", systemImage: "arrow.up.arrow.down") }
                        Divider()
                        Button("Open Network Video", systemImage: "network") { networkVideo = true }
                        Button("Play All", systemImage: "play.fill") { playback.play(library.videos(in: folder).map(\.path), library: library) }
                            .disabled(library.videos(in: folder).isEmpty)
                        Divider()
                        Button("Help & About", systemImage: "info.circle") { about = true }
                    } label: { Image(systemName: "ellipsis.circle") }.accessibilityLabel("Library actions")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                if selecting {
                    Button("Delete Selected (\(selected.count))", systemImage: "trash", role: .destructive) {
                        deleting = visible.filter { selected.contains($0.path) }
                    }.labelStyle(.iconOnly).disabled(selected.isEmpty)
                }
            }
        }
        .sheet(isPresented: $networkVideo) { NetworkVideoSheet() }
        .sheet(isPresented: $about) { NavigationStack { AboutView() } }
        .sheet(item: $nameRequest) { NameSheet(request: $0) }
        .sheet(item: $importSelection, onDismiss: {
            let urls = selectedImportURLs
            selectedImportURLs = []
            guard !urls.isEmpty else { return }
            // Present completion alerts only after the system file picker has finished dismissing.
            Task { await library.importVideos(urls, into: folder) }
        }) { selection in
            ImportPicker(folder: selection == .folder) { urls in
                selectedImportURLs = urls
                importSelection = nil
            }.ignoresSafeArea()
        }
        .sheet(item: $moving) { MoveSheet(entry: $0) }
        .sheet(item: $adding) { entry in
            AddToPlaylistSheet(paths: entry.isFolder ? library.videos(in: entry.path).map(\.path) : [entry.path])
        }
        .alert("Delete \(deleting.count) item\(deleting.count == 1 ? "" : "s")?", isPresented: Binding(get: { !deleting.isEmpty }, set: { if !$0 { deleting = [] } })) {
            Button("Cancel", role: .cancel) { deleting = [] }
            Button("Delete from Library", role: .destructive) {
                library.perform {
                    try library.delete(deleting)
                    selected.removeAll()
                    selecting = false
                }
                deleting = []
            }
        } message: { Text("This deletes the local copies and removes them from playlists and favorites. All videos inside selected folders are included. Your original imported files are unchanged.") }
    }

    private func play(_ entry: VideoEntry) {
        playback.play(entry.isFolder ? library.videos(in: entry.path).map(\.path) : [entry.path], library: library)
    }

    private func entryRow(_ entry: VideoEntry) -> some View {
        let count = entry.isFolder ? library.videos(in: entry.path).count : 0
        return LibraryEntryRow(entry: entry,
                        subtitle: entry.isFolder ? "\(count) video\(count == 1 ? "" : "s")" : (query.isEmpty ? nil : entry.parent),
                        favorite: library.favorites.contains(entry.path),
                        progress: progress(of: entry))
    }

    private func progress(of entry: VideoEntry) -> Double? {
        guard let position = library.resumePosition(for: entry.path),
              let duration = mediaInfo.info(for: entry)?.duration, duration > 0 else { return nil }
        return min(1, position / duration)
    }
}

struct LibraryEntryRow: View {
    let entry: VideoEntry
    let subtitle: String?
    var favorite = false
    /// How much of the video has been watched, from 0 to 1.
    var progress: Double?
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var mediaInfo: MediaInfoStore
    var body: some View {
        HStack(spacing: 12) {
            if entry.isFolder {
                Image(systemName: "folder.fill").font(.title3).foregroundStyle(Color.teal).frame(width: 28)
            } else {
                thumbnail
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.name).font(.body).foregroundStyle(.primary).lineLimit(2)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                if !entry.isFolder, entry.size > 0 {
                    Text(ByteCountFormatter.string(fromByteCount: entry.size, countStyle: .file))
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 4)
            if favorite {
                Image(systemName: "heart.fill").font(.caption).foregroundStyle(Color.teal).accessibilityLabel("Favorite")
            }
        }.padding(.vertical, 6).frame(minHeight: 44)
    }

    private var thumbnail: some View {
        let info = mediaInfo.info(for: entry)
        return ZStack(alignment: .bottomTrailing) {
            Group {
                if let image = info?.thumbnail {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Image(systemName: "play.rectangle").font(.title3).foregroundStyle(Color.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.secondary.opacity(0.12))
                }
            }
            .frame(width: 80, height: 45).clipShape(RoundedRectangle(cornerRadius: 6))
            if let duration = info?.duration {
                Text(DurationText.format(duration))
                    .font(.caption2.monospacedDigit().weight(.semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 3)).padding(3)
                    .accessibilityLabel("Duration \(DurationText.format(duration))")
            }
            if let progress {
                GeometryReader { geometry in
                    Rectangle().fill(Color.teal).frame(width: geometry.size.width * progress, height: 3)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }.frame(width: 80, height: 45).clipShape(RoundedRectangle(cornerRadius: 6))
                .accessibilityLabel("Watched \(Int(progress * 100)) percent")
            }
        }
        .frame(width: 80, height: 45)
        .task(id: MediaInfoStore.key(for: entry)) {
            if let url = try? library.fileURL(entry.path) { mediaInfo.request(entry, url: url) }
        }
    }
}

struct MoveSheet: View {
    let entry: VideoEntry
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?
    var body: some View {
        NavigationStack {
            List {
                if let error { Text(error).foregroundStyle(.red) }
                destination("", name: "Library")
                ForEach(library.entries.filter { $0.isFolder && $0.path != entry.path && !$0.path.hasPrefix(entry.path + "/") }) {
                    destination($0.path, name: $0.path)
                }
            }
            .navigationTitle("Move to Folder").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
    private func destination(_ path: String, name: String) -> some View {
        Button {
            do { try library.relocate(entry, to: path); dismiss() } catch { self.error = error.localizedDescription }
        } label: { Label(name, systemImage: "folder") }.disabled(path == entry.parent)
    }
}

struct FavoritesScreen: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var playback: PlaybackController
    private var videos: [VideoEntry] { library.videos().filter { library.favorites.contains($0.path) } }
    var body: some View {
        List(videos) { entry in
            Button { playback.play(videos.map(\.path), startingAt: entry.path, library: library) } label: {
                LibraryEntryRow(entry: entry, subtitle: entry.parent)
            }.tint(.primary)
            .swipeActions {
                Button("Unfavorite", systemImage: "heart.slash") { library.perform { try library.toggleFavorite(entry.path) } }
                    .tint(.orange)
            }
            .contextMenu {
                Button("Remove from Favorites", systemImage: "heart.slash") { library.perform { try library.toggleFavorite(entry.path) } }
            }
        }
        .listStyle(.plain)
        .overlay {
            if videos.isEmpty {
                ContentUnavailableView("No favorites yet", systemImage: "heart", description: Text("Long-press a video to add it here."))
            }
        }
        .navigationTitle("Favorites")
        .refreshable { library.refresh() }
        .toolbar {
            if videos.count > 1 {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Play All", systemImage: "play.fill") { playback.play(videos.map(\.path), library: library) }.labelStyle(.iconOnly)
                }
            }
        }
    }
}
