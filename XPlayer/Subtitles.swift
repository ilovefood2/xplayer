// SPDX-License-Identifier: MIT
import Foundation

struct SubtitleCue: Equatable {
    let start: Double
    let end: Double
    let text: String
}

/// A subtitle file next to a video, such as "Movie.srt" or "Movie.zh.ass".
struct SidecarSubtitle: Identifiable, Hashable {
    let url: URL
    var id: URL { url }
    /// "zh · ASS" for "Movie.zh.ass"; just the format for "Movie.srt".
    func label(forVideoStem stem: String) -> String {
        let name = url.deletingPathExtension().lastPathComponent
        let tag = name.count > stem.count ? String(name.dropFirst(stem.count + 1)) : ""
        let format = url.pathExtension.uppercased()
        return tag.isEmpty ? format : "\(tag) · \(format)"
    }
}

enum SubtitleFiles {
    /// Subtitle files are often not UTF-8: Chinese releases use GB18030 or Big5,
    /// Japanese ones Shift JIS, and older Western ones Windows-1252.
    static func decode(_ data: Data) -> String? {
        if data.starts(with: [0xEF, 0xBB, 0xBF]) { return String(data: data.dropFirst(3), encoding: .utf8) }
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]) { return String(data: data, encoding: .utf16) }
        if let text = String(data: data, encoding: .utf8) { return text }
        let fallbacks: [CFStringEncodings] = [.GB_18030_2000, .big5_HKSCS_1999, .shiftJIS, .EUC_KR]
        for encoding in fallbacks {
            let ns = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(encoding.rawValue))
            if let text = String(data: data, encoding: String.Encoding(rawValue: ns)), !text.contains("\u{FFFD}") { return text }
        }
        return String(data: data, encoding: .windowsCP1252)
    }

    static func load(_ url: URL) throws -> [SubtitleCue] {
        guard let text = decode(try Data(contentsOf: url)) else {
            throw LibraryError(message: "The subtitle file's text encoding is not supported.")
        }
        return parse(text, format: url.pathExtension.lowercased())
    }

    static func parse(_ raw: String, format: String) -> [SubtitleCue] {
        let text = raw.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        switch format {
        case "ass", "ssa": return parseASS(text)
        default: return parseTimedBlocks(text)
        }
    }

    /// SRT and WebVTT share a "start --> end" line followed by the cue text.
    private static func parseTimedBlocks(_ text: String) -> [SubtitleCue] {
        var cues: [SubtitleCue] = []
        for block in text.components(separatedBy: "\n\n") {
            let lines = block.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            guard let timing = lines.firstIndex(where: { $0.contains("-->") }) else { continue }
            let parts = lines[timing].components(separatedBy: "-->")
            guard parts.count == 2, let start = timestamp(parts[0]),
                  let end = timestamp(parts[1].split(separator: " ", omittingEmptySubsequences: true).first.map(String.init) ?? "")
            else { continue }
            let body = lines[(timing + 1)...].joined(separator: "\n")
            let cleaned = stripMarkup(body).trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty, end > start { cues.append(SubtitleCue(start: start, end: end, text: cleaned)) }
        }
        return cues.sorted { $0.start < $1.start }
    }

    /// "Dialogue: layer,start,end,style,name,marginL,marginR,marginV,effect,text"
    private static func parseASS(_ text: String) -> [SubtitleCue] {
        var cues: [SubtitleCue] = []
        for line in text.split(separator: "\n") where line.hasPrefix("Dialogue:") {
            let fields = line.dropFirst("Dialogue:".count).split(separator: ",", maxSplits: 9, omittingEmptySubsequences: false)
            guard fields.count == 10, let start = timestamp(String(fields[1])), let end = timestamp(String(fields[2])) else { continue }
            let body = String(fields[9])
                .replacingOccurrences(of: #"\{[^}]*\}"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: "\\N", with: "\n").replacingOccurrences(of: "\\n", with: "\n")
                .replacingOccurrences(of: "\\h", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !body.isEmpty, end > start { cues.append(SubtitleCue(start: start, end: end, text: body)) }
        }
        return cues.sorted { $0.start < $1.start }
    }

    /// Accepts "01:02:03,456", "01:02:03.456", "02:03.456", and ASS "1:02:03.45".
    static func timestamp(_ raw: String) -> Double? {
        let value = raw.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        let parts = value.split(separator: ":")
        guard (2...3).contains(parts.count) else { return nil }
        var seconds = 0.0
        for part in parts {
            guard let number = Double(part), number >= 0 else { return nil }
            seconds = seconds * 60 + number
        }
        return seconds
    }

    private static func stripMarkup(_ text: String) -> String {
        text.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\{\\[^}]*\}"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">").replacingOccurrences(of: "&nbsp;", with: " ")
    }

    /// The text shown at `time`, joining overlapping cues.
    static func text(at time: Double, in cues: [SubtitleCue]) -> String? {
        let visible = cues.filter { $0.start <= time && time < $0.end }.map(\.text)
        return visible.isEmpty ? nil : visible.joined(separator: "\n")
    }

    /// VLC reads subtitle files as UTF-8 unless told otherwise; give it a UTF-8
    /// copy so GB18030, Big5, and Shift JIS files display correctly.
    static func utf8Copy(of url: URL) -> URL {
        guard let data = try? Data(contentsOf: url), String(data: data, encoding: .utf8) == nil,
              let text = decode(data) else { return url }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("subtitles", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let copy = folder.appendingPathComponent(UUID().uuidString + "." + url.pathExtension)
        do { try Data(text.utf8).write(to: copy); return copy } catch { return url }
    }
}
