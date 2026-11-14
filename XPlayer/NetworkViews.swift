// SPDX-License-Identifier: MIT
import SwiftUI

/// Saved SMB and WebDAV shares, browsable and playable without copying files.
struct NetworkScreen: View {
    @EnvironmentObject private var network: NetworkStore
    @EnvironmentObject private var library: LibraryStore
    @State private var editing: NetworkServer?
    @State private var deleting: NetworkServer?
    @State private var link = false
    var body: some View {
        List {
            if !network.servers.isEmpty {
                Section("Shares") {
                    ForEach(network.servers) { server in
                        NavigationLink {
                            ShareFolderScreen(server: server, url: try? server.rootURL(), title: server.name)
                        } label: {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(server.name)
                                    Text(server.address).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                            } icon: {
                                Image(systemName: server.kind == .smb ? "server.rack" : "globe").foregroundStyle(Color.teal)
                            }
                        }
                        .contextMenu {
                            Button("Edit", systemImage: "pencil") { editing = server }
                            Button("Remove", systemImage: "trash", role: .destructive) { deleting = server }
                        }
                        .swipeActions {
                            Button("Remove", systemImage: "trash", role: .destructive) { deleting = server }
                            Button("Edit", systemImage: "pencil") { editing = server }.tint(.gray)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .overlay {
            if network.servers.isEmpty {
                ContentUnavailableView {
                    Label("No network shares", systemImage: "server.rack")
                } description: {
                    Text("Add an SMB share from a Mac, PC, or NAS, or a WebDAV folder, to browse and play its videos.")
                } actions: {
                    Button("Add Share") { editing = NetworkServer(name: "", kind: .smb, address: "") }
                        .buttonStyle(.borderedProminent).accessibilityIdentifier("addShareEmpty")
                    Button("Open Video Link") { link = true }
                }
            }
        }
        .navigationTitle("Network")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Add Share", systemImage: "plus") { editing = NetworkServer(name: "", kind: .smb, address: "") }
                    Button("Open Video Link", systemImage: "link") { link = true }
                } label: { Image(systemName: "plus") }.accessibilityLabel("Network actions")
            }
        }
        .sheet(item: $editing) { ShareEditor(server: $0) }
        .sheet(isPresented: $link) { NetworkVideoSheet() }
        .alert("Remove \(deleting?.name ?? "share")?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Cancel", role: .cancel) { deleting = nil }
            Button("Remove", role: .destructive) {
                if let deleting { library.perform { try network.delete(deleting) } }
                deleting = nil
            }
        } message: { Text("This removes the saved address and password from this device. Files on the server are not affected.") }
    }
}

struct ShareEditor: View {
    @EnvironmentObject private var network: NetworkStore
    @Environment(\.dismiss) private var dismiss
    @State private var server: NetworkServer
    @State private var password: String
    @State private var error: String?
    private let isNew: Bool
    init(server: NetworkServer) {
        _server = State(initialValue: server)
        _password = State(initialValue: server.address.isEmpty ? "" : Keychain.password(for: server.id))
        isNew = server.address.isEmpty
    }
    var body: some View {
        NavigationStack {
            Form {
                Picker("Type", selection: $server.kind) {
                    ForEach(ShareKind.allCases) { Text($0.title).tag($0) }
                }.accessibilityIdentifier("shareKind")
                Section {
                    TextField(server.kind == .smb ? "nas.local or smb://192.168.1.10/Videos" : "https://nas.local/dav", text: $server.address)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityIdentifier("shareAddress")
                    TextField("Name (optional)", text: $server.name).accessibilityIdentifier("shareName")
                } header: { Text("Server") }
                Section {
                    TextField(server.kind == .smb ? "User name, or DOMAIN\\user" : "User name", text: $server.username)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("shareUser")
                    SecureField("Password", text: $password).accessibilityIdentifier("sharePassword")
                } header: { Text("Sign in (optional)") } footer: {
                    Text("Leave blank for guest access. The password is stored in this device's Keychain and sent only to this server.")
                }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle(isNew ? "Add Share" : "Edit Share").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        do { try network.save(server, password: password); dismiss() }
                        catch { self.error = error.localizedDescription }
                    }.disabled(server.address.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

struct ShareFolderScreen: View {
    let server: NetworkServer
    let url: URL?
    let title: String
    @EnvironmentObject private var network: NetworkStore
    @EnvironmentObject private var playback: PlaybackController
    @State private var items: [NetworkItem]?
    @State private var error: String?
    var body: some View {
        List {
            if let items {
                ForEach(items) { item in
                    if item.isFolder {
                        NavigationLink { ShareFolderScreen(server: server, url: item.url, title: item.name) } label: {
                            Label(item.name, systemImage: "folder.fill").foregroundStyle(.primary)
                        }
                    } else {
                        Button {
                            playback.playShare(items, startingAt: item, kind: server.kind, credentials: network.credentials(for: server))
                        } label: { Label(item.name, systemImage: "play.rectangle").foregroundStyle(.primary) }
                    }
                }
            }
        }
        .listStyle(.plain)
        .overlay {
            if let error {
                ContentUnavailableView {
                    Label("Can't open this folder", systemImage: "exclamationmark.triangle")
                } description: { Text(error) } actions: { Button("Try Again") { Task { await load() } } }
            } else if items == nil {
                ProgressView("Connecting…")
            } else if items?.isEmpty == true {
                ContentUnavailableView("No videos here", systemImage: "folder", description: Text("Only folders and supported videos are shown."))
            }
        }
        .navigationTitle(title)
        .toolbar {
            if items?.contains(where: { !$0.isFolder }) == true {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Play All", systemImage: "play.fill") {
                        if let items, let first = items.first(where: { !$0.isFolder }) {
                            playback.playShare(items, startingAt: first, kind: server.kind, credentials: network.credentials(for: server))
                        }
                    }
                }
            }
        }
        .refreshable { await load() }
        .task { if items == nil { await load() } }
    }

    private func load() async {
        error = nil
        do {
            guard let url else { throw LibraryError(message: "This share's address is not valid. Edit the share and try again.") }
            items = try await network.list(server, at: url)
        } catch {
            items = nil
            self.error = error.localizedDescription
        }
    }
}

struct NetworkVideoSheet: View {
    @EnvironmentObject private var playback: PlaybackController
    @EnvironmentObject private var network: NetworkStore
    @Environment(\.dismiss) private var dismiss
    @State private var address = ""
    @State private var error: String?
    @State private var pendingURL: URL?
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://host/video.mp4", text: $address)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityIdentifier("networkURL")
                        .submitLabel(.go).onSubmit(openVideo)
                } header: { Text("Video link") } footer: {
                    Text("Direct video or HLS link. The server receives your IP address and URL; prefer HTTPS. Recent links are kept only on this device.")
                }
                if let error { Text(error).foregroundStyle(.red) }
                if !network.recentLinks.isEmpty {
                    Section {
                        ForEach(network.recentLinks, id: \.self) { url in
                            Button { pendingURL = url; dismiss() } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(url.lastPathComponent.isEmpty ? (url.host ?? url.absoluteString) : url.lastPathComponent).lineLimit(1)
                                    Text(url.host ?? "").font(.caption).foregroundStyle(.secondary)
                                }
                            }.foregroundStyle(.primary)
                        }
                        .onDelete { offsets in offsets.map { network.recentLinks[$0] }.forEach(network.forget) }
                        Button("Clear Recent Links", role: .destructive) { network.clearRecents() }
                    } header: { Text("Recent") }
                }
            }
            .navigationTitle("Open Network Video").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Play", action: openVideo).disabled(address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onDisappear {
            if let pendingURL {
                network.remember(pendingURL)
                playback.playNetwork(pendingURL)
            }
        }
    }
    private func openVideo() {
        do { pendingURL = try PlaybackController.networkURL(address); dismiss() }
        catch { self.error = error.localizedDescription }
    }
}
