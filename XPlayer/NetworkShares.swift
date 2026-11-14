// SPDX-License-Identifier: MIT
import Foundation
import Security
@preconcurrency import MobileVLCKit

enum ShareKind: String, Codable, CaseIterable, Identifiable {
    case smb, webdav
    var id: String { rawValue }
    var title: String { self == .smb ? "SMB (Windows/macOS/NAS)" : "WebDAV (HTTP/HTTPS)" }
}

/// A saved network share. The password is kept in the Keychain, never in this record.
struct NetworkServer: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var kind: ShareKind
    var address: String
    var username: String = ""

    /// The share's root URL, normalized from what the user typed.
    func rootURL() throws -> URL {
        var value = address.trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.contains("://") { value = (kind == .smb ? "smb://" : "https://") + value }
        guard var components = URLComponents(string: value), let scheme = components.scheme?.lowercased(),
              let host = components.host, !host.isEmpty, components.user == nil, components.password == nil,
              kind == .smb ? scheme == "smb" : ["http", "https"].contains(scheme) else {
            throw LibraryError(message: kind == .smb
                ? "Enter an SMB address such as nas.local or smb://192.168.1.10/Videos, without a password."
                : "Enter a WebDAV address such as https://nas.local/dav, without a password.")
        }
        if !components.path.hasSuffix("/") { components.path += "/" }
        guard let url = components.url else { throw LibraryError(message: "Invalid server address.") }
        return url
    }
}

struct NetworkItem: Identifiable, Hashable {
    let name: String
    let url: URL
    let isFolder: Bool
    var id: URL { url }
}

/// What a share needs to authenticate playback and listings.
struct ShareCredentials: Equatable {
    var username = ""
    var password = ""
    var isEmpty: Bool { username.isEmpty && password.isEmpty }

    var httpHeaders: [String: String] {
        guard !isEmpty else { return [:] }
        return ["Authorization": "Basic " + Data("\(username):\(password)".utf8).base64EncodedString()]
    }

    func vlcOptions(for kind: ShareKind) -> [String] {
        guard !isEmpty else { return [] }
        if kind == .webdav { return [":http-user=\(username)", ":http-pwd=\(password)"] }
        // "DOMAIN\\user" selects a Windows domain.
        let parts = username.split(separator: "\\", maxSplits: 1).map(String.init)
        let user = parts.count == 2 ? parts[1] : username
        var options = [":smb-user=\(user)", ":smb-pwd=\(password)"]
        if parts.count == 2 { options.append(":smb-domain=\(parts[0])") }
        return options
    }
}

enum Keychain {
    private static let service = "com.ilovefood2.xplayer.network-share"

    static func password(for id: UUID) -> String {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: id.uuidString, kSecReturnData as String: true]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func setPassword(_ password: String, for id: UUID) throws {
        delete(id)
        guard !password.isEmpty else { return }
        let item: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                   kSecAttrAccount as String: id.uuidString, kSecValueData as String: Data(password.utf8),
                                   kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw LibraryError(message: "The password could not be saved in the Keychain (\(status)).") }
    }

    static func delete(_ id: UUID) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: id.uuidString]
        SecItemDelete(query as CFDictionary)
    }
}

@MainActor
final class NetworkStore: ObservableObject {
    @Published private(set) var servers: [NetworkServer] = []
    @Published private(set) var recentLinks: [URL] = []
    private let file: URL
    private let defaults: UserDefaults
    static let recentLimit = 20
    private static let recentKey = "recentNetworkLinks"

    init(file: URL? = nil, defaults: UserDefaults = .standard) {
        self.file = file ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("network-shares.json")
        self.defaults = defaults
        if let data = try? Data(contentsOf: self.file), let saved = try? JSONDecoder().decode([NetworkServer].self, from: data) {
            servers = saved
        }
        recentLinks = (defaults.stringArray(forKey: Self.recentKey) ?? []).compactMap(URL.init(string:))
    }

    func credentials(for server: NetworkServer) -> ShareCredentials {
        ShareCredentials(username: server.username, password: Keychain.password(for: server.id))
    }

    func save(_ server: NetworkServer, password: String?) throws {
        var server = server
        server.name = server.name.trimmingCharacters(in: .whitespacesAndNewlines)
        server.username = server.username.trimmingCharacters(in: .whitespacesAndNewlines)
        if server.name.isEmpty { server.name = (try? server.rootURL().host) ?? server.address }
        _ = try server.rootURL()
        var updated = servers
        if let index = updated.firstIndex(where: { $0.id == server.id }) { updated[index] = server } else { updated.append(server) }
        try write(updated)
        if let password { try Keychain.setPassword(password, for: server.id) }
    }

    func delete(_ server: NetworkServer) throws {
        try write(servers.filter { $0.id != server.id })
        Keychain.delete(server.id)
    }

    private func write(_ value: [NetworkServer]) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(value).write(to: file, options: .atomic)
        servers = value
    }

    /// Most recent first, without duplicates. Stored only on this device.
    func remember(_ url: URL) {
        recentLinks = Array(([url] + recentLinks.filter { $0 != url }).prefix(Self.recentLimit))
        defaults.set(recentLinks.map(\.absoluteString), forKey: Self.recentKey)
    }

    func forget(_ url: URL) {
        recentLinks.removeAll { $0 == url }
        defaults.set(recentLinks.map(\.absoluteString), forKey: Self.recentKey)
    }

    func clearRecents() {
        recentLinks = []
        defaults.removeObject(forKey: Self.recentKey)
    }

    func list(_ server: NetworkServer, at url: URL) async throws -> [NetworkItem] {
        let credentials = credentials(for: server)
        let items = server.kind == .webdav
            ? try await WebDAV.list(url, credentials: credentials)
            : try await SMBBrowser.list(url, credentials: credentials)
        return items.filter { $0.isFolder || LibraryFiles.extensions.contains($0.url.pathExtension.lowercased()) }
            .sorted {
                if $0.isFolder != $1.isFolder { return $0.isFolder }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
    }
}

enum WebDAV {
    static let body = #"<?xml version="1.0" encoding="utf-8"?><d:propfind xmlns:d="DAV:"><d:prop><d:displayname/><d:resourcetype/></d:prop></d:propfind>"#

    static func list(_ url: URL, credentials: ShareCredentials, session: URLSession = .shared) async throws -> [NetworkItem] {
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.httpMethod = "PROPFIND"
        request.setValue("1", forHTTPHeaderField: "Depth")
        request.setValue("application/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
        for (name, value) in credentials.httpHeaders { request.setValue(value, forHTTPHeaderField: name) }
        request.httpBody = Data(body.utf8)
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 || status == 403 { throw LibraryError(message: "The server rejected the user name or password.") }
        guard (200..<300).contains(status) else { throw LibraryError(message: "The server returned HTTP \(status) for this folder.") }
        return try parse(data, base: url)
    }

    /// Parses a PROPFIND multistatus response, dropping the folder itself.
    static func parse(_ data: Data, base: URL) throws -> [NetworkItem] {
        let delegate = MultistatusParser()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        guard parser.parse() else { throw LibraryError(message: "The server's folder listing could not be read.") }
        let basePath = base.path.hasSuffix("/") ? base.path : base.path + "/"
        var seen = Set<URL>()
        return delegate.responses.compactMap { response in
            guard let href = response.href.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                  let resolved = URL(string: href, relativeTo: base)?.absoluteURL else { return nil }
            let path = resolved.path.hasSuffix("/") ? resolved.path : resolved.path + "/"
            // Stay inside the listed folder; a server may also echo the folder itself.
            guard path != basePath, path.hasPrefix(basePath), resolved.host == base.host else { return nil }
            var url = resolved
            if response.isCollection && !url.absoluteString.hasSuffix("/") { url = url.appendingPathComponent("", isDirectory: true) }
            guard seen.insert(url).inserted else { return nil }
            let name = response.displayName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? resolved.lastPathComponent
            return NetworkItem(name: name, url: url, isFolder: response.isCollection)
        }
    }

    private final class MultistatusParser: NSObject, XMLParserDelegate {
        struct Response { var href = "", displayName = "", isCollection = false }
        var responses: [Response] = []
        private var current: Response?
        private var text = ""

        func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
            text = ""
            if element == "response" { current = Response() }
            if element == "collection" { current?.isCollection = true }
        }
        func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }
        func parser(_ parser: XMLParser, didEndElement element: String, namespaceURI: String?, qualifiedName: String?) {
            switch element {
            case "href": if current?.href.isEmpty == true { current?.href = text }
            case "displayname": current?.displayName = text
            case "response": if let current { responses.append(current) }; current = nil
            default: break
            }
        }
    }
}

/// SMB listing uses MobileVLCKit's built-in SMB client, the same one that plays the files.
@MainActor
enum SMBBrowser {
    static func list(_ url: URL, credentials: ShareCredentials) async throws -> [NetworkItem] {
        let media = VLCMedia(url: url)
        for option in credentials.vlcOptions(for: .smb) { media.addOption(option) }
        let listing = Listing(media)
        let items = await listing.run()
        if items.isEmpty && media.parsedStatus != .done {
            throw LibraryError(message: "The share could not be opened. Check the address, user name, password, and that the device is on the same network.")
        }
        return items
    }

    @MainActor
    private final class Listing: NSObject, VLCMediaDelegate {
        private let media: VLCMedia
        private var continuation: CheckedContinuation<[NetworkItem], Never>?
        init(_ media: VLCMedia) { self.media = media }

        func run() async -> [NetworkItem] {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                media.delegate = self
                if media.parse(options: [.parseNetwork], timeout: 15_000) != 0 { finish() }
            }
        }

        nonisolated func mediaDidFinishParsing(_ aMedia: VLCMedia) {
            DispatchQueue.main.async { self.finish() }
        }

        private func finish() {
            guard let continuation else { return }
            self.continuation = nil
            media.delegate = nil
            var items: [NetworkItem] = []
            if let list = media.subitems {
                list.lock()
                for index in 0..<UInt(list.count) {
                    guard let child = list.media(at: index), let url = child.url else { continue }
                    let name = url.lastPathComponent.removingPercentEncoding ?? url.lastPathComponent
                    items.append(NetworkItem(name: name, url: url, isFolder: child.mediaType == .directory))
                }
                list.unlock()
            }
            continuation.resume(returning: items)
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
