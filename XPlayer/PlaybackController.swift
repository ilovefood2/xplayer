// SPDX-License-Identifier: MIT
import AVKit
import MediaPlayer
import SwiftUI
@preconcurrency import MobileVLCKit

@MainActor
private final class VLCShutdown {
    private var player: VLCMediaPlayer?
    private var observer: NSObjectProtocol?

    init(_ player: VLCMediaPlayer) {
        self.player = player
        observer = NotificationCenter.default.addObserver(
            forName: Notification.Name(VLCMediaPlayerStateChanged), object: player, queue: .main
        ) { [self] _ in
            MainActor.assumeIsolated { finishIfStopped() }
        }
        player.stop()
        // A player that never started is already stopped and posts no change.
        finishIfStopped()
    }

    private func finishIfStopped() {
        guard player?.state == .stopped else { return }
        // Destroying a VLC player joins its threads, and those can be waiting
        // for the main thread. Hand the last reference to a background queue
        // after every main-thread holder (including the notification being
        // delivered now) has let go, so destruction can never block the main thread.
        let handoff = Unmanaged.passRetained(player!)
        player = nil
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1) {
            let player = handoff.takeRetainedValue()
            player.drawable = nil
        }
    }
}

enum RepeatMode: String, CaseIterable, Identifiable {
    case off, all, one
    var id: String { rawValue }
    var title: String { self == .off ? "Off" : (self == .all ? "Repeat All" : "Repeat One") }
    var symbol: String { self == .one ? "repeat.1" : "repeat" }
}

/// An audio or subtitle choice offered in the player's menu.
struct TrackOption: Identifiable, Hashable {
    let id: String
    let name: String
}

/// One entry in the playback queue: a library path, or a network address.
struct QueueItem: Equatable {
    let id: String
    var title: String
    var remoteURL: URL?
    var headers: [String: String] = [:]
    var vlcOptions: [String] = []
    /// SMB can only be read by MobileVLCKit.
    var requiresVLC = false
}

@MainActor
final class PlaybackController: NSObject, ObservableObject, VLCMediaPlayerDelegate {
    let player = AVPlayer()
    let vlcVideoView = UIView()
    @Published private(set) var vlcPlayer: VLCMediaPlayer?
    @Published private(set) var vlcIsPlaying = false
    @Published private(set) var vlcPosition: Float = 0
    @Published private(set) var vlcTime: Double = 0
    @Published private(set) var vlcDuration: Double = 0
    @Published private(set) var vlcSeekable = false
    @Published private(set) var playbackSpeed: Float = 1
    @Published var isPresented = false
    @Published private(set) var paths: [String] = []
    @Published private(set) var index = 0
    @Published var error: String?
    @Published private(set) var repeatMode: RepeatMode
    @Published private(set) var isShuffled: Bool
    @Published private(set) var audioOptions: [TrackOption] = []
    @Published private(set) var selectedAudio: String?
    @Published private(set) var subtitleOptions: [TrackOption] = []
    @Published private(set) var selectedSubtitle = TrackOption.off.id
    /// Text of an external subtitle file shown over Apple playback.
    @Published private(set) var subtitleText: String?
    /// Set when playback continued from a saved position, to offer "Start Over".
    @Published private(set) var resumedFrom: Double?
    @Published var isPictureInPictureActive = false
    private var queue: [QueueItem] = [] { didSet { paths = queue.map(\.id) } }
    private var unshuffled: [QueueItem] = []
    private var root: URL?
    private weak var library: LibraryStore?
    private var endObserver: NSObjectProtocol?
    private var failureObserver: NSKeyValueObservation?
    private var timeObserver: Any?
    private var pendingResume: Double?
    private var sidecars: [SidecarSubtitle] = []
    private var sidecarCues: [SubtitleCue] = []
    private var lastSaved = Date.distantPast
    private var backgroundVideoTrack: Int32?
    private var ownsAudioSession = false
    private static let repeatKey = "repeatMode", shuffleKey = "shufflePlayback"
    static let backgroundAudioKey = "backgroundAudio"

    var title: String {
        queue.indices.contains(index) ? queue[index].title : "xplayer"
    }
    var isRemote: Bool { queue.indices.contains(index) && queue[index].remoteURL != nil }
    /// The playing library file, for sharing.
    var currentFileURL: URL? {
        guard !isRemote, let root, queue.indices.contains(index) else { return nil }
        return try? LibraryFiles.url(queue[index].id, root: root)
    }

    override init() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [Self.backgroundAudioKey: true])
        repeatMode = RepeatMode(rawValue: defaults.string(forKey: Self.repeatKey) ?? "") ?? .off
        isShuffled = defaults.bool(forKey: Self.shuffleKey)
        super.init()
        configureRemoteCommands()
    }

    func play(_ paths: [String], startingAt path: String? = nil, library: LibraryStore) {
        let available = paths.filter(library.exists)
        guard !available.isEmpty else { library.notice = "No playable files were found. Import videos into the library first."; return }
        persistPosition()
        self.library = library
        root = library.root
        let items = available.map { QueueItem(id: $0, title: ($0 as NSString).lastPathComponent) }
        start(items, at: path.flatMap { available.firstIndex(of: $0) } ?? 0)
    }

    static func networkURL(_ address: String) throws -> URL {
        let value = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              let components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              components.port.map({ (1...65535).contains($0) }) ?? true,
              let url = components.url else {
            throw LibraryError(message: "Enter a full HTTP or HTTPS video URL without an embedded username or password.")
        }
        return url
    }

    func playNetwork(_ url: URL) {
        let remote: URL
        do { remote = try Self.networkURL(url.absoluteString) }
        catch { self.error = error.localizedDescription; return }
        persistPosition()
        root = nil
        let title = remote.lastPathComponent.isEmpty ? "Network Video" : remote.lastPathComponent
        start([QueueItem(id: remote.absoluteString, title: title, remoteURL: remote)], at: 0)
    }

    /// Plays videos from a saved network share, continuing through the folder.
    func playShare(_ items: [NetworkItem], startingAt item: NetworkItem, kind: ShareKind, credentials: ShareCredentials) {
        let videos = items.filter { !$0.isFolder }
        guard !videos.isEmpty else { return }
        persistPosition()
        root = nil
        let queue = videos.map {
            QueueItem(id: $0.url.absoluteString, title: $0.name, remoteURL: $0.url,
                      headers: kind == .webdav ? credentials.httpHeaders : [:],
                      vlcOptions: credentials.vlcOptions(for: kind), requiresVLC: kind == .smb)
        }
        start(queue, at: videos.firstIndex(of: item) ?? 0)
    }

    private func start(_ items: [QueueItem], at position: Int) {
        unshuffled = items
        var ordered = items
        var current = position
        if isShuffled && items.count > 1 {
            let first = ordered.remove(at: position)
            ordered = [first] + ordered.shuffled()
            current = 0
        }
        queue = ordered
        index = current
        isPresented = true
        loadCurrent()
    }

    func next() {
        guard index + 1 < queue.count else { return }
        persistPosition()
        index += 1
        loadCurrent()
    }

    func previous() {
        guard index > 0 else { return }
        persistPosition()
        index -= 1
        loadCurrent()
    }

    func setRepeatMode(_ mode: RepeatMode) {
        repeatMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: Self.repeatKey)
        updateRemoteCommands()
    }

    /// Shuffles what is left after the current video, or restores the original order.
    func setShuffled(_ shuffled: Bool) {
        isShuffled = shuffled
        UserDefaults.standard.set(shuffled, forKey: Self.shuffleKey)
        guard queue.indices.contains(index) else { return }
        let current = queue[index]
        if shuffled {
            queue = [current] + unshuffled.filter { $0 != current }.shuffled()
            index = 0
        } else {
            queue = unshuffled
            index = unshuffled.firstIndex(of: current) ?? 0
        }
        updateRemoteCommands()
    }

    /// The video finished: repeat it, continue the queue, or wrap around.
    private func finishedCurrent() {
        if let path = currentLibraryPath { library?.recordPosition(0, duration: 0, for: path) }
        switch repeatMode {
        case .one:
            if vlcPlayer != nil { loadCurrent(resume: false) }
            else { player.seek(to: .zero); player.play() }
        case .all where index + 1 >= queue.count:
            index = 0
            loadCurrent(resume: false)
        default:
            next()
        }
    }

    private var currentLibraryPath: String? {
        guard !isRemote, queue.indices.contains(index) else { return nil }
        return queue[index].id
    }

    private func loadCurrent(resume: Bool = true) {
        removeObservers()
        player.pause()
        player.replaceCurrentItem(with: nil)
        stopVLC()
        error = nil
        resumedFrom = nil
        pendingResume = nil
        subtitleText = nil
        sidecarCues = []
        sidecars = []
        audioOptions = []
        selectedAudio = nil
        subtitleOptions = []
        selectedSubtitle = TrackOption.off.id
        guard queue.indices.contains(index) else { return }
        let item = queue[index]
        do {
            let url: URL
            if let remote = item.remoteURL { url = remote }
            else if let root { url = try LibraryFiles.url(item.id, root: root) }
            else { return }
            if item.remoteURL == nil {
                sidecars = LibraryStore.sidecars(of: url).map(SidecarSubtitle.init(url:))
                if resume, let saved = library?.resumePosition(for: item.id) { pendingResume = saved }
            }
            if item.requiresVLC || LibraryFiles.vlcExtensions.contains(url.pathExtension.lowercased()) {
                startVLC(url, options: item.vlcOptions)
                return
            }
            startNative(url, headers: item.headers)
        } catch { self.error = error.localizedDescription }
        updateNowPlaying()
    }

    private func startNative(_ url: URL, headers: [String: String]) {
        // Audio is not a reason to refuse the video: activation fails while a
        // phone call or another app holds the audio session.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        ownsAudioSession = (try? AVAudioSession.sharedInstance().setActive(true)) != nil
        let asset = AVURLAsset(url: url, options: headers.isEmpty ? nil : ["AVURLAssetHTTPHeaderFieldsKey": headers])
        let item = AVPlayerItem(asset: asset)
        item.audioTimePitchAlgorithm = .timeDomain
        let resume = pendingResume
        failureObserver = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            let status = item.status
            Task { @MainActor [weak self] in
                guard let self, self.player.currentItem === item else { return }
                if status == .readyToPlay {
                    if let resume = self.pendingResume {
                        self.pendingResume = nil
                        await self.player.seek(to: CMTime(seconds: resume, preferredTimescale: 600))
                        self.resumedFrom = resume
                        self.player.play()
                    }
                    await self.loadNativeTracks(item)
                    self.updateNowPlaying()
                    return
                }
                guard status == .failed else { return }
                let detail = item.error?.localizedDescription ?? "This video codec is not supported by iOS."
                if let remote = self.queue[self.index].remoteURL {
                    // Extensionless network endpoints can serve Matroska too.
                    self.player.pause()
                    self.player.replaceCurrentItem(with: nil)
                    self.removeObservers()
                    self.startVLC(remote, options: self.queue[self.index].vlcOptions)
                    return
                }
                self.error = "Unable to play this video. \(detail) Try an H.264 or HEVC video in MP4, M4V, or MOV format."
            }
        }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard self?.player.currentItem === item else { return }
                self?.finishedCurrent()
            }
        }
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 4), queue: .main) { [weak self] time in
            MainActor.assumeIsolated { self?.tick(time.seconds) }
        }
        player.replaceCurrentItem(with: item)
        if resume == nil { player.play() }
        enableDefaultSidecar()
    }

    private func tick(_ seconds: Double) {
        guard seconds.isFinite else { return }
        if !sidecarCues.isEmpty {
            let text = SubtitleFiles.text(at: seconds, in: sidecarCues)
            if text != subtitleText { subtitleText = text }
        }
        if Date().timeIntervalSince(lastSaved) > 10 { persistPosition() }
    }

    private func removeObservers() {
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        failureObserver = nil
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
    }

    private func startVLC(_ url: URL, options: [String] = []) {
        // VLC activates and releases its own audio session as its audio output starts and stops.
        ownsAudioSession = false
        let vlc = VLCMediaPlayer(options: ["--no-video-title-show", "--quiet", "--no-metadata-network-access"])
        vlc.drawable = vlcVideoView
        vlc.delegate = self
        let media = VLCMedia(url: url)
        for option in options { media.addOption(option) }
        if let resume = pendingResume {
            media.addOption(":start-time=\(Int(resume))")
            pendingResume = nil
            resumedFrom = resume
        }
        vlc.media = media
        vlc.rate = playbackSpeed
        vlcPlayer = vlc
        vlcIsPlaying = true
        vlc.play()
        // Sidecar files are added as VLC subtitle tracks; the first one is shown.
        for (offset, sidecar) in sidecars.enumerated() {
            vlc.addPlaybackSlave(SubtitleFiles.utf8Copy(of: sidecar.url), type: .subtitle, enforce: offset == 0)
        }
        updateNowPlaying()
    }

    private func stopVLC() {
        let previous = vlcPlayer
        vlcPlayer = nil
        previous?.delegate = nil
        if let previous {
            // VLC stops asynchronously; retain its player and drawable until shutdown finishes.
            _ = VLCShutdown(previous)
        }
        backgroundVideoTrack = nil
        vlcIsPlaying = false
        vlcPosition = 0
        vlcTime = 0
        vlcDuration = 0
        vlcSeekable = false
    }

    // These callbacks capture only the player's identity. Holding the player itself
    // in a main-queue block can make that block its last owner; destroying a VLC
    // player on the main thread joins threads that may be waiting for the main
    // thread, which freezes the app.
    nonisolated func mediaPlayerStateChanged(_ notification: Notification) {
        guard let source = notification.object as? VLCMediaPlayer else { return }
        let state = source.state
        let id = ObjectIdentifier(source)
        Task { @MainActor [weak self] in
            guard let self, let vlc = self.vlcPlayer, ObjectIdentifier(vlc) == id else { return }
            let wasPlaying = self.vlcIsPlaying
            self.updateVLCProgress(vlc)
            if state == .error {
                self.error = "Unable to play this video. Check that the file or network link is accessible and is not damaged or DRM-protected."
            } else if state == .ended {
                self.finishedCurrent()
                return
            } else if state == .playing || state == .esAdded {
                self.loadVLCTracks(vlc)
            }
            if wasPlaying != self.vlcIsPlaying { self.updateNowPlaying() }
        }
    }

    nonisolated func mediaPlayerTimeChanged(_ notification: Notification) {
        guard let source = notification.object as? VLCMediaPlayer else { return }
        let id = ObjectIdentifier(source)
        Task { @MainActor [weak self] in
            guard let self, let vlc = self.vlcPlayer, ObjectIdentifier(vlc) == id else { return }
            self.updateVLCProgress(vlc)
            if Date().timeIntervalSince(self.lastSaved) > 10 { self.persistPosition() }
        }
    }

    private func updateVLCProgress(_ vlc: VLCMediaPlayer) {
        vlcIsPlaying = vlc.isPlaying
        vlcPosition = max(0, min(1, vlc.position))
        vlcTime = max(0, Double(vlc.time.intValue) / 1000)
        vlcDuration = max(0, Double(vlc.media?.length.intValue ?? 0) / 1000)
        vlcSeekable = vlc.isSeekable
    }

    func toggleVLCPlayback() {
        guard let vlcPlayer else { return }
        if vlcPlayer.isPlaying { vlcPlayer.pause(); persistPosition() } else { vlcPlayer.play() }
        updateNowPlaying()
    }

    func seekVLC(to position: Float) {
        guard let vlcPlayer, vlcPlayer.isSeekable, position.isFinite else { return }
        let position = max(0, min(1, position))
        vlcPlayer.position = position
        // VLC's time notifications pause too; keep the requested position usable for another skip.
        vlcPosition = position
        vlcTime = Double(vlcPlayer.media?.length.intValue ?? 0) / 1000 * Double(position)
        updateNowPlaying()
    }

    @discardableResult func skip(seconds: Double) -> Bool {
        guard seconds.isFinite else { return false }
        if let vlcPlayer {
            let duration = Double(vlcPlayer.media?.length.intValue ?? 0) / 1000
            guard vlcPlayer.isSeekable, duration > 0 else { return false }
            let target = max(0, min(duration, vlcTime + seconds))
            seekVLC(to: Float(target / duration))
        } else {
            guard let item = player.currentItem, item.status == .readyToPlay else { return false }
            let current = player.currentTime().seconds
            guard current.isFinite,
                  let range = item.seekableTimeRanges.map(\.timeRangeValue).first(where: {
                      current >= $0.start.seconds && current <= CMTimeRangeGetEnd($0).seconds
                  }) else { return false }
            let target = max(range.start.seconds, min(CMTimeRangeGetEnd(range).seconds, current + seconds))
            player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
                Task { @MainActor in self?.updateNowPlaying() }
            }
        }
        return true
    }

    /// Jumps to an absolute time, for the lock screen's scrubber.
    func seek(to seconds: Double) {
        guard seconds.isFinite else { return }
        if vlcPlayer != nil {
            guard vlcDuration > 0 else { return }
            seekVLC(to: Float(seconds / vlcDuration))
        } else {
            player.seek(to: CMTime(seconds: max(0, seconds), preferredTimescale: 600)) { [weak self] _ in
                Task { @MainActor in self?.updateNowPlaying() }
            }
        }
    }

    func startOver() {
        resumedFrom = nil
        seek(to: 0)
    }

    func clearResumeNotice() { resumedFrom = nil }

    var hasOptions: Bool {
        !audioOptions.isEmpty || !subtitleOptions.isEmpty || paths.count > 1 || repeatMode != .off || currentFileURL != nil
    }

    var speedLabel: String { String(format: "%g×", playbackSpeed) }

    func setPlaybackSpeed(_ speed: Float) {
        guard speed.isFinite else { return }
        playbackSpeed = min(2, max(0.25, speed))
        player.defaultRate = playbackSpeed
        if player.rate != 0 { player.rate = playbackSpeed }
        vlcPlayer?.rate = playbackSpeed
        updateNowPlaying()
    }

    var isPlaying: Bool { vlcPlayer != nil ? vlcIsPlaying : player.timeControlStatus != .paused }

    func resume() {
        if let vlcPlayer { if !vlcPlayer.isPlaying { vlcPlayer.play() } } else if player.currentItem != nil { player.play() }
        updateNowPlaying()
    }

    func pause() {
        player.pause()
        vlcPlayer?.pause()
        persistPosition()
        updateNowPlaying()
    }

    func stop() {
        persistPosition()
        player.pause()
        player.replaceCurrentItem(with: nil)
        removeObservers()
        stopVLC()
        subtitleText = nil
        resumedFrom = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        if ownsAudioSession {
            ownsAudioSession = false
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    /// Saves the playhead of the current library video so it can resume later.
    private func persistPosition() {
        guard let path = currentLibraryPath, let library else { return }
        lastSaved = Date()
        if let vlcPlayer {
            guard vlcPlayer.media != nil, vlcDuration > 0 else { return }
            library.recordPosition(vlcTime, duration: vlcDuration, for: path)
        } else if let item = player.currentItem, item.status == .readyToPlay {
            library.recordPosition(player.currentTime().seconds, duration: item.duration.seconds, for: path)
        }
    }

    // MARK: Background playback

    var backgroundAudioEnabled: Bool { UserDefaults.standard.bool(forKey: Self.backgroundAudioKey) }

    func enterBackground() {
        guard backgroundAudioEnabled else { pause(); return }
        persistPosition()
        // VLC must not render video while the app is in the background; keep its audio.
        if let vlcPlayer, vlcPlayer.isPlaying, backgroundVideoTrack == nil {
            backgroundVideoTrack = vlcPlayer.currentVideoTrackIndex
            vlcPlayer.currentVideoTrackIndex = -1
        }
    }

    func enterForeground() {
        if let vlcPlayer, let track = backgroundVideoTrack {
            vlcPlayer.currentVideoTrackIndex = track
        }
        backgroundVideoTrack = nil
    }

    // MARK: Audio and subtitle tracks

    private func enableDefaultSidecar() {
        guard !sidecars.isEmpty else { return }
        selectSubtitle("f:0")
    }

    private func loadNativeTracks(_ item: AVPlayerItem) async {
        let asset = item.asset
        let audible = try? await asset.loadMediaSelectionGroup(for: .audible)
        let legible = try? await asset.loadMediaSelectionGroup(for: .legible)
        guard player.currentItem === item else { return }
        if let audible, audible.options.count > 1 {
            audioOptions = audible.options.enumerated().map { TrackOption(id: "a:\($0.offset)", name: $0.element.displayName) }
            if let current = item.currentMediaSelection.selectedMediaOption(in: audible), let offset = audible.options.firstIndex(of: current) {
                selectedAudio = "a:\(offset)"
            }
        }
        var subtitles = [TrackOption.off]
        if let legible {
            subtitles += legible.options.enumerated().map { TrackOption(id: "e:\($0.offset)", name: $0.element.displayName) }
            if selectedSubtitle == TrackOption.off.id, let current = item.currentMediaSelection.selectedMediaOption(in: legible),
               let offset = legible.options.firstIndex(of: current) {
                selectedSubtitle = "e:\(offset)"
            }
        }
        subtitles += sidecarOptions()
        subtitleOptions = subtitles.count > 1 ? subtitles : []
    }

    private func sidecarOptions() -> [TrackOption] {
        guard queue.indices.contains(index) else { return [] }
        let stem = (queue[index].title as NSString).deletingPathExtension
        return sidecars.enumerated().map { TrackOption(id: "f:\($0.offset)", name: $0.element.label(forVideoStem: stem)) }
    }

    /// Runs when VLC reports new streams. Only changed values are published, so
    /// the player screen is not redrawn needlessly (which can disturb gestures).
    private func loadVLCTracks(_ vlc: VLCMediaPlayer) {
        let audioNames = vlc.audioTrackNames.compactMap { $0 as? String }
        let audioIDs = vlc.audioTrackIndexes.compactMap { ($0 as? NSNumber)?.int32Value }
        let audio = zip(audioIDs, audioNames).filter { $0.0 >= 0 }.map { TrackOption(id: "v:\($0.0)", name: $0.1) }
        let subtitleNames = vlc.videoSubTitlesNames.compactMap { $0 as? String }
        let subtitleIDs = vlc.videoSubTitlesIndexes.compactMap { ($0 as? NSNumber)?.int32Value }
        let subtitles = zip(subtitleIDs, subtitleNames).filter { $0.0 >= 0 }.map { TrackOption(id: "v:\($0.0)", name: $0.1) }
        let newAudio = audio.count > 1 ? audio : []
        let newSubtitles = subtitles.isEmpty ? [] : [TrackOption.off] + subtitles
        let audioSelection = "v:\(vlc.currentAudioTrackIndex)"
        let subtitleSelection = vlc.currentVideoSubTitleIndex >= 0 ? "v:\(vlc.currentVideoSubTitleIndex)" : TrackOption.off.id
        if audioOptions != newAudio { audioOptions = newAudio }
        if selectedAudio != audioSelection { selectedAudio = audioSelection }
        if subtitleOptions != newSubtitles { subtitleOptions = newSubtitles }
        if selectedSubtitle != subtitleSelection { selectedSubtitle = subtitleSelection }
    }

    func selectAudio(_ id: String) {
        if let vlcPlayer, let track = Int32(id.dropFirst(2)) {
            vlcPlayer.currentAudioTrackIndex = track
        } else if let item = player.currentItem, let offset = Int(id.dropFirst(2)) {
            Task {
                guard let group = try? await item.asset.loadMediaSelectionGroup(for: .audible), group.options.indices.contains(offset) else { return }
                item.select(group.options[offset], in: group)
            }
        }
        selectedAudio = id
    }

    func selectSubtitle(_ id: String) {
        selectedSubtitle = id
        if let vlcPlayer {
            vlcPlayer.currentVideoSubTitleIndex = Int32(id.dropFirst(2)) ?? -1
            return
        }
        let kind = id.prefix(2), offset = Int(id.dropFirst(2))
        sidecarCues = []
        subtitleText = nil
        if kind == "f:", let offset, sidecars.indices.contains(offset) {
            sidecarCues = (try? SubtitleFiles.load(sidecars[offset].url)) ?? []
            if sidecarCues.isEmpty { error = "This subtitle file has no readable cues." }
        }
        guard let item = player.currentItem else { return }
        Task {
            guard let group = try? await item.asset.loadMediaSelectionGroup(for: .legible) else { return }
            if kind == "e:", let offset, group.options.indices.contains(offset) {
                item.select(group.options[offset], in: group)
            } else {
                item.select(nil, in: group)
            }
        }
    }

    // MARK: Lock screen and Control Center

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in self?.resume(); return .success }
        center.pauseCommand.addTarget { [weak self] _ in self?.pause(); return .success }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            if self.isPlaying { self.pause() } else { self.resume() }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            guard let self, self.index + 1 < self.queue.count else { return .noActionableNowPlayingItem }
            self.next(); return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            guard let self, self.index > 0 else { return .noActionableNowPlayingItem }
            self.previous(); return .success
        }
        center.skipForwardCommand.preferredIntervals = [15]
        center.skipBackwardCommand.preferredIntervals = [15]
        center.skipForwardCommand.addTarget { [weak self] _ in self?.skip(seconds: 15) == true ? .success : .commandFailed }
        center.skipBackwardCommand.addTarget { [weak self] _ in self?.skip(seconds: -15) == true ? .success : .commandFailed }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            self?.seek(to: event.positionTime)
            return .success
        }
    }

    private func updateRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.nextTrackCommand.isEnabled = index + 1 < queue.count
        center.previousTrackCommand.isEnabled = index > 0
    }

    private func updateNowPlaying() {
        guard queue.indices.contains(index), player.currentItem != nil || vlcPlayer != nil else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.video.rawValue,
            MPNowPlayingInfoPropertyPlaybackQueueIndex: index,
            MPNowPlayingInfoPropertyPlaybackQueueCount: queue.count,
        ]
        let elapsed = vlcPlayer != nil ? vlcTime : player.currentTime().seconds
        let duration = vlcPlayer != nil ? vlcDuration : (player.currentItem?.duration.seconds ?? 0)
        if elapsed.isFinite { info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed }
        if duration.isFinite && duration > 0 { info[MPMediaItemPropertyPlaybackDuration] = duration }
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? Double(playbackSpeed) : 0
        info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = Double(playbackSpeed)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        updateRemoteCommands()
    }
}

extension TrackOption {
    static let off = TrackOption(id: "off", name: "Off")
}

struct NativeVideoPlayer: UIViewControllerRepresentable {
    let playback: PlaybackController
    let onInteraction: () -> Void
    let onSkip: (Double) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(playback: playback, onInteraction: onInteraction, onSkip: onSkip) }
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = playback.player
        controller.view.accessibilityIdentifier = "nativeVideo"
        controller.allowsPictureInPicturePlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        controller.delegate = context.coordinator
        context.coordinator.controller = controller
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped))
        tap.cancelsTouchesInView = false
        tap.delegate = context.coordinator
        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.doubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        doubleTap.delegate = context.coordinator
        tap.require(toFail: doubleTap)
        controller.view.addGestureRecognizer(tap)
        controller.view.addGestureRecognizer(doubleTap)
        return controller
    }
    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        context.coordinator.onInteraction = onInteraction
        context.coordinator.onSkip = onSkip
    }
    final class Coordinator: NSObject, UIGestureRecognizerDelegate, AVPlayerViewControllerDelegate {
        var onInteraction: () -> Void
        var onSkip: (Double) -> Void
        let playback: PlaybackController
        weak var controller: AVPlayerViewController?
        private var observers: [NSObjectProtocol] = []
        init(playback: PlaybackController, onInteraction: @escaping () -> Void, onSkip: @escaping (Double) -> Void) {
            self.playback = playback
            self.onInteraction = onInteraction
            self.onSkip = onSkip
            super.init()
            let center = NotificationCenter.default
            // iOS pauses a player that is attached to a view when the app leaves the
            // screen. Detach it so audio continues; picture in picture keeps it attached.
            observers.append(center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, let controller = self.controller, self.playback.backgroundAudioEnabled,
                          !self.playback.isPictureInPictureActive else { return }
                    controller.player = nil
                }
            })
            observers.append(center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, let controller = self.controller, controller.player == nil else { return }
                    controller.player = self.playback.player
                }
            })
        }
        deinit { observers.forEach(NotificationCenter.default.removeObserver) }
        func playerViewControllerWillStartPictureInPicture(_ playerViewController: AVPlayerViewController) {
            MainActor.assumeIsolated { playback.isPictureInPictureActive = true }
        }
        func playerViewControllerDidStopPictureInPicture(_ playerViewController: AVPlayerViewController) {
            MainActor.assumeIsolated { playback.isPictureInPictureActive = false }
        }
        func playerViewController(_ playerViewController: AVPlayerViewController,
                                  restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
            MainActor.assumeIsolated { playback.isPresented = true }
            completionHandler(true)
        }
        @objc func tapped() { onInteraction() }
        @objc func doubleTapped(_ tap: UITapGestureRecognizer) {
            guard let view = tap.view else { return }
            onSkip(tap.location(in: view).x < view.bounds.midX ? -15 : 15)
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            var view = touch.view
            while let current = view, current !== gestureRecognizer.view {
                if current is UIControl || current.accessibilityTraits.contains(.button) { return false }
                view = current.superview
            }
            return !UIAccessibility.isVoiceOverRunning
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            (gestureRecognizer as? UITapGestureRecognizer)?.numberOfTapsRequired == 2 && otherGestureRecognizer is UITapGestureRecognizer
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            (gestureRecognizer as? UITapGestureRecognizer)?.numberOfTapsRequired != 2
        }
    }
}

struct PlayerScreen: View {
    @ObservedObject var playback: PlaybackController
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @State private var controlsVisible = true
    @State private var nativePlaying = false
    @State private var scrubbing = false
    @State private var interaction = UUID()
    @State private var showingSpeed = false
    @State private var showingOptions = false
    @State private var seekFeedback: Double?
    @State private var seekInteraction = UUID()
    private var playing: Bool { playback.vlcPlayer != nil ? playback.vlcIsPlaying : nativePlaying }
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if playback.vlcPlayer != nil {
                    ZStack(alignment: .bottom) {
                        VLCVideoPlayer(playback: playback)
                            .overlay {
                                GeometryReader { geometry in
                                    Color.clear.contentShape(Rectangle())
                                        .gesture(SpatialTapGesture(count: 2).exclusively(before: SpatialTapGesture()).onEnded { tap in
                                            switch tap {
                                            case .first(let value): skip(value.location.x < geometry.size.width / 2 ? -15 : 15)
                                            case .second: toggleControls()
                                            }
                                        })
                                        .accessibilityRepresentation {
                                            Button(controlsVisible && playing && !voiceOverEnabled ? "Hide playback controls" : "Show playback controls", action: toggleControls)
                                                .accessibilityIdentifier("playerVideo")
                                                .accessibilityAction(named: "Skip back 15 seconds") { skip(-15) }
                                                .accessibilityAction(named: "Skip forward 15 seconds") { skip(15) }
                                        }
                                }
                            }
                        if controlsVisible {
                            VLCPlaybackControls(playback: playback) { editing in
                                scrubbing = editing
                                showControls()
                            }
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
                            .padding(16)
                        }
                    }
                } else {
                    NativeVideoPlayer(playback: playback, onInteraction: showControls, onSkip: skip)
                        .overlay(alignment: .bottom) {
                            if let text = playback.subtitleText {
                                Text(text)
                                    .font(.title3.weight(.semibold)).multilineTextAlignment(.center)
                                    .foregroundStyle(.white).shadow(color: .black, radius: 2)
                                    .padding(.horizontal, 12).padding(.vertical, 6)
                                    .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
                                    .padding(.bottom, controlsVisible ? 72 : 28).padding(.horizontal, 24)
                                    .allowsHitTesting(false).accessibilityIdentifier("subtitleText")
                            }
                        }
                }
                if let error = playback.error {
                    Text(error).font(.callout).foregroundStyle(.orange).padding().accessibilityIdentifier("playbackError")
                }
                if controlsVisible && playback.vlcPlayer == nil && playback.paths.count > 1 {
                    HStack {
                        Button { playback.previous() } label: { Label("Previous", systemImage: "backward.end.fill") }
                            .disabled(playback.index == 0)
                        Spacer()
                        Text("\(playback.index + 1) / \(playback.paths.count)").monospacedDigit().foregroundStyle(.secondary)
                        Spacer()
                        Button { playback.next() } label: { Label("Next", systemImage: "forward.end.fill") }
                            .disabled(playback.index + 1 >= playback.paths.count)
                    }.labelStyle(.iconOnly).font(.body).padding(.horizontal, 24).padding(.vertical, 12)
                }
            }
            .overlay(alignment: .top) {
                if let resumed = playback.resumedFrom {
                    HStack(spacing: 12) {
                        Text("Resumed at \(DurationText.format(resumed))").font(.subheadline)
                        Button("Start Over") { playback.startOver() }.font(.subheadline.weight(.semibold))
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule()).padding(.top, 12)
                    .accessibilityElement(children: .contain).accessibilityIdentifier("resumeBanner")
                    .task(id: resumed) {
                        try? await Task.sleep(for: .seconds(6))
                        withAnimation { playback.clearResumeNotice() }
                    }
                }
            }
            .overlay(alignment: (seekFeedback ?? 15) < 0 ? .leading : .trailing) {
                if let seekFeedback {
                    Label("15 seconds", systemImage: seekFeedback < 0 ? "gobackward.15" : "goforward.15")
                        .font(.headline).padding().background(.ultraThinMaterial, in: Capsule()).padding(24)
                        .allowsHitTesting(false).accessibilityIdentifier("seekFeedback")
                        .accessibilityLabel(seekFeedback < 0 ? "Back 15 seconds" : "Forward 15 seconds")
                }
            }
            .ignoresSafeArea(edges: controlsVisible ? [] : .all)
            .background(.black)
            .navigationTitle(playback.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(controlsVisible ? .visible : .hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Done", systemImage: "xmark") { playback.isPresented = false }.labelStyle(.iconOnly) }
                ToolbarItem(placement: .topBarTrailing) {
                    if playback.hasOptions {
                        Button("Playback options", systemImage: "ellipsis.circle") { showingOptions = true; showControls() }
                            .labelStyle(.iconOnly).accessibilityIdentifier("playerOptions")
                            .popover(isPresented: $showingOptions) { PlayerOptionsPanel(playback: playback) }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(playback.speedLabel) { showingSpeed = true; showControls() }
                        .accessibilityLabel("Playback speed, \(playback.speedLabel)")
                        .accessibilityIdentifier("playbackSpeed")
                        .accessibilityAction(named: "Skip back 15 seconds") { skip(-15) }
                        .accessibilityAction(named: "Skip forward 15 seconds") { skip(15) }
                        .popover(isPresented: $showingSpeed) {
                            VStack(spacing: 16) {
                                HStack { Text("Playback speed"); Spacer(); Text(playback.speedLabel).monospacedDigit() }
                                Slider(value: Binding(get: { playback.playbackSpeed }, set: playback.setPlaybackSpeed), in: 0.25...2, step: 0.25)
                                    .accessibilityLabel("Playback speed")
                                    .accessibilityValue(playback.speedLabel)
                                HStack { Text("0.25×"); Spacer(); Text("2×") }.font(.caption).foregroundStyle(.secondary)
                            }.padding(20).frame(width: 280).presentationCompactAdaptation(.popover)
                        }
                }
            }
        }
        .statusBarHidden(!controlsVisible)
        .onReceive(playback.player.publisher(for: \.timeControlStatus)) { nativePlaying = $0 == .playing }
        .onChange(of: playing) { _, _ in showControls() }
        .onChange(of: playback.index) { _, _ in showControls() }
        .onChange(of: playback.error) { _, _ in showControls() }
        .onChange(of: voiceOverEnabled) { _, _ in showControls() }
        .onChange(of: showingSpeed) { _, _ in showControls() }
        .onChange(of: showingOptions) { _, _ in showControls() }
        .task(id: seekInteraction) {
            guard seekFeedback != nil else { return }
            do { try await Task.sleep(for: .seconds(1)) } catch { return }
            seekFeedback = nil
        }
        .task(id: interaction) {
            // Panels keep the controls (and themselves) on screen while open.
            guard controlsVisible, playing, !scrubbing, !showingSpeed, !showingOptions, !voiceOverEnabled, playback.error == nil else { return }
            let currentInteraction = interaction
            do { try await Task.sleep(for: .seconds(3)) } catch { return }
            guard !Task.isCancelled, interaction == currentInteraction else { return }
            withAnimation { controlsVisible = false }
        }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false; playback.stop() }
    }
    private func showControls() {
        withAnimation { controlsVisible = true }
        interaction = UUID()
    }
    private func toggleControls() {
        if controlsVisible && playing && !voiceOverEnabled {
            withAnimation { controlsVisible = false }
            interaction = UUID()
        } else { showControls() }
    }
    private func skip(_ seconds: Double) {
        guard playback.skip(seconds: seconds) else { return }
        seekFeedback = seconds
        seekInteraction = UUID()
        interaction = UUID()
    }
}

struct VLCVideoPlayer: UIViewRepresentable {
    let playback: PlaybackController
    func makeUIView(context: Context) -> UIView { playback.vlcVideoView }
    func updateUIView(_ view: UIView, context: Context) {}
}

struct VLCPlaybackControls: View {
    @ObservedObject var playback: PlaybackController
    let onEditingChanged: (Bool) -> Void
    @State private var scrubbing = false
    @State private var position: Float = 0
    var body: some View {
        VStack(spacing: 12) {
            Slider(value: Binding(get: { scrubbing ? position : playback.vlcPosition }, set: { position = $0 }), in: 0...1) { editing in
                if editing { position = playback.vlcPosition }
                scrubbing = editing
                if !editing { playback.seekVLC(to: position) }
                onEditingChanged(editing)
            }
            .disabled(!playback.vlcSeekable)
            .accessibilityLabel("Playback position")
            HStack {
                Text(time(playback.vlcTime)).font(.caption).monospacedDigit().foregroundStyle(.secondary)
                Spacer()
                if playback.paths.count > 1 {
                    Button { playback.previous(); onEditingChanged(false) } label: { Label("Previous", systemImage: "backward.end.fill") }
                        .labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44).disabled(playback.index == 0)
                }
                Button(action: playback.toggleVLCPlayback) {
                    Label(playback.vlcIsPlaying ? "Pause" : "Play", systemImage: playback.vlcIsPlaying ? "pause.fill" : "play.fill")
                }.labelStyle(.iconOnly).font(.title2).frame(minWidth: 44, minHeight: 44).accessibilityIdentifier("vlcPlayPause")
                if playback.paths.count > 1 {
                    Button { playback.next(); onEditingChanged(false) } label: { Label("Next", systemImage: "forward.end.fill") }
                        .labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44).disabled(playback.index + 1 >= playback.paths.count)
                }
                Spacer()
                // VLC formats can send audio to AirPlay speakers; video needs Screen Mirroring.
                AirPlayButton().frame(width: 44, height: 44).accessibilityLabel("AirPlay audio")
                Text(time(playback.vlcDuration)).font(.caption).monospacedDigit().foregroundStyle(.secondary)
            }
        }.padding(.horizontal, 24).padding(.vertical, 12)
    }
    private func time(_ seconds: Double) -> String {
        let value = Int(seconds)
        return value >= 3600
            ? String(format: "%d:%02d:%02d", value / 3600, value / 60 % 60, value % 60)
            : String(format: "%d:%02d", value / 60, value % 60)
    }
}

struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.tintColor = .secondaryLabel
        picker.activeTintColor = .tintColor
        return picker
    }
    func updateUIView(_ view: AVRoutePickerView, context: Context) {}
}

/// Audio language, subtitles, repeat, shuffle, and sharing for the playing video.
struct PlayerOptionsPanel: View {
    @ObservedObject var playback: PlaybackController
    var body: some View {
        List {
            if !playback.audioOptions.isEmpty {
                Section("Audio") {
                    ForEach(playback.audioOptions) { option in
                        row(option.name, selected: playback.selectedAudio == option.id) { playback.selectAudio(option.id) }
                    }
                }
            }
            if !playback.subtitleOptions.isEmpty {
                Section("Subtitles") {
                    ForEach(playback.subtitleOptions) { option in
                        row(option.name, selected: playback.selectedSubtitle == option.id) { playback.selectSubtitle(option.id) }
                    }
                }
            }
            if playback.paths.count > 1 || playback.repeatMode != .off {
                Section("Queue") {
                    Picker("Repeat", selection: Binding(get: { playback.repeatMode }, set: playback.setRepeatMode)) {
                        Text("Off").tag(RepeatMode.off)
                        Text("All").tag(RepeatMode.all)
                        Text("One").tag(RepeatMode.one)
                    }.pickerStyle(.segmented).accessibilityIdentifier("repeatMode")
                    if playback.paths.count > 1 {
                        Toggle(isOn: Binding(get: { playback.isShuffled }, set: playback.setShuffled)) {
                            Label("Shuffle", systemImage: "shuffle")
                        }.accessibilityIdentifier("shuffle")
                    }
                }
            }
            if let url = playback.currentFileURL {
                Section { ShareLink(item: url) { Label("Share Video", systemImage: "square.and.arrow.up") } }
            }
        }
        .listStyle(.insetGrouped)
        .frame(minWidth: 300, idealWidth: 340, minHeight: 280, idealHeight: 440)
        .presentationCompactAdaptation(.popover)
    }

    private func row(_ name: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(name).foregroundStyle(.primary)
                Spacer()
                if selected { Image(systemName: "checkmark").foregroundStyle(.tint) }
            }
        }
        .accessibilityLabel(name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
