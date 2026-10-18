// SPDX-License-Identifier: MIT
import Foundation
import Network

// A loopback-only server exercises AVPlayer's real HTTP byte-range requests without an external service.
final class VideoHTTPServer {
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
            let types = ["m3u8": "application/vnd.apple.mpegurl", "ts": "video/mp2t",
                        "mp4": "video/mp4", "avi": "video/x-msvideo", "webm": "video/webm"]
            let type = types[(path as NSString).pathExtension.lowercased()] ?? "video/x-matroska"
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
