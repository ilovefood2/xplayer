// SPDX-License-Identifier: MIT
import AVKit
import SwiftUI
import MobileVLCKit

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
    @Published var isPresented = false
    @Published private(set) var paths: [String] = []
    @Published private(set) var index = 0
    @Published var error: String?
    private var root: URL?
    private var remoteURL: URL?
    private var endObserver: NSObjectProtocol?
    private var failureObserver: NSKeyValueObservation?
    var title: String {
        if let remoteURL { return remoteURL.lastPathComponent.isEmpty ? "Network Video" : remoteURL.lastPathComponent }
        return paths.indices.contains(index) ? (paths[index] as NSString).lastPathComponent : "xplayer"
    }

    func play(_ paths: [String], startingAt path: String? = nil, library: LibraryStore) {
        self.paths = paths.filter(library.exists)
        guard !self.paths.isEmpty else { library.notice = "No playable files were found. Import videos into the library first."; return }
        remoteURL = nil
        root = library.root
        index = path.flatMap { self.paths.firstIndex(of: $0) } ?? 0
        isPresented = true
        loadCurrent()
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
        do { remoteURL = try Self.networkURL(url.absoluteString) }
        catch { self.error = error.localizedDescription; return }
        root = nil
        paths = [url.absoluteString]
        index = 0
        isPresented = true
        loadCurrent()
    }

    func next() {
        guard index + 1 < paths.count else { return }
        index += 1
        loadCurrent()
    }

    func previous() {
        guard index > 0 else { return }
        index -= 1
        loadCurrent()
    }

    private func loadCurrent() {
        removeObservers()
        player.pause()
        player.replaceCurrentItem(with: nil)
        stopVLC()
        error = nil
        guard paths.indices.contains(index) else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try AVAudioSession.sharedInstance().setActive(true)
            let url: URL
            if let remoteURL { url = remoteURL }
            else if let root { url = try LibraryFiles.url(paths[index], root: root) }
            else { return }
            if url.pathExtension.lowercased() == "mkv" {
                startVLC(url)
                return
            }
            let item = AVPlayerItem(url: url)
            failureObserver = item.observe(\.status, options: [.new]) { [weak self] item, _ in
                guard item.status == .failed else { return }
                let detail = item.error?.localizedDescription ?? "This video codec is not supported by iOS."
                Task { @MainActor [weak self] in
                    guard self?.player.currentItem === item else { return }
                    if let self, self.remoteURL != nil {
                        // Extensionless network endpoints can serve Matroska too.
                        self.player.pause()
                        self.player.replaceCurrentItem(with: nil)
                        self.removeObservers()
                        self.startVLC(url)
                        return
                    }
                    self?.error = self?.remoteURL == nil
                        ? "Unable to play this video. \(detail) Try an H.264 or HEVC video in MP4, M4V, or MOV format."
                        : "Unable to play this network video. Check the direct link, server access, connection, and supported format. If it is on your local network, allow access in Settings."
                }
            }
            endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard self?.player.currentItem === item else { return }
                    self?.next()
                }
            }
            player.replaceCurrentItem(with: item)
            player.play()
        } catch { self.error = error.localizedDescription }
    }

    private func removeObservers() {
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        failureObserver = nil
    }

    private func startVLC(_ url: URL) {
        let vlc = VLCMediaPlayer(options: ["--no-video-title-show", "--quiet", "--no-metadata-network-access"])
        vlc.drawable = vlcVideoView
        vlc.delegate = self
        vlc.media = VLCMedia(url: url)
        vlcPlayer = vlc
        vlcIsPlaying = true
        vlc.play()
    }

    private func stopVLC() {
        let previous = vlcPlayer
        vlcPlayer = nil
        previous?.delegate = nil
        previous?.stop()
        previous?.drawable = nil
        vlcIsPlaying = false
        vlcPosition = 0
        vlcTime = 0
        vlcDuration = 0
        vlcSeekable = false
    }

    nonisolated func mediaPlayerStateChanged(_ notification: Notification) {
        guard let vlc = notification.object as? VLCMediaPlayer else { return }
        let state = vlc.state
        Task { @MainActor [weak self] in
            guard let self, self.vlcPlayer === vlc else { return }
            self.updateVLCProgress(vlc)
            if state == .error {
                self.error = "Unable to play this video. Check that the file or network link is accessible and is not damaged or DRM-protected."
            } else if state == .ended { self.next() }
        }
    }

    nonisolated func mediaPlayerTimeChanged(_ notification: Notification) {
        guard let vlc = notification.object as? VLCMediaPlayer else { return }
        Task { @MainActor [weak self] in
            guard let self, self.vlcPlayer === vlc else { return }
            self.updateVLCProgress(vlc)
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
        if vlcPlayer.isPlaying { vlcPlayer.pause() } else { vlcPlayer.play() }
    }

    func seekVLC(to position: Float) {
        guard let vlcPlayer, vlcPlayer.isSeekable, position.isFinite else { return }
        vlcPlayer.position = max(0, min(1, position))
    }

    func pause() { player.pause(); vlcPlayer?.pause() }

    func stop() {
        stopVLC()
        player.pause()
        player.replaceCurrentItem(with: nil)
        removeObservers()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

struct NativeVideoPlayer: UIViewControllerRepresentable {
    let player: AVPlayer
    let onInteraction: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onInteraction: onInteraction) }
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.view.accessibilityIdentifier = "nativeVideo"
        controller.allowsPictureInPicturePlayback = false
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped))
        tap.cancelsTouchesInView = false
        tap.delegate = context.coordinator
        controller.view.addGestureRecognizer(tap)
        return controller
    }
    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        context.coordinator.onInteraction = onInteraction
    }
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onInteraction: () -> Void
        init(onInteraction: @escaping () -> Void) { self.onInteraction = onInteraction }
        @objc func tapped() { onInteraction() }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }
    }
}

struct PlayerScreen: View {
    @ObservedObject var playback: PlaybackController
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @State private var controlsVisible = true
    @State private var nativePlaying = false
    @State private var scrubbing = false
    @State private var interaction = UUID()
    private var playing: Bool { playback.vlcPlayer != nil ? playback.vlcIsPlaying : nativePlaying }
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if playback.vlcPlayer != nil {
                    ZStack(alignment: .bottom) {
                        VLCVideoPlayer(playback: playback)
                            .overlay {
                                Button {
                                    if controlsVisible && playing && !voiceOverEnabled {
                                        withAnimation { controlsVisible = false }
                                        interaction = UUID()
                                    } else { showControls() }
                                } label: { Color.clear.contentShape(Rectangle()) }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("playerVideo")
                                .accessibilityLabel(controlsVisible && playing && !voiceOverEnabled ? "Hide playback controls" : "Show playback controls")
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
                    NativeVideoPlayer(player: playback.player, onInteraction: showControls)
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
            .ignoresSafeArea(edges: controlsVisible ? [] : .all)
            .background(.black)
            .navigationTitle(playback.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(controlsVisible ? .visible : .hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Done", systemImage: "xmark") { playback.isPresented = false }.labelStyle(.iconOnly) }
            }
        }
        .statusBarHidden(!controlsVisible)
        .onReceive(playback.player.publisher(for: \.timeControlStatus)) { nativePlaying = $0 == .playing }
        .onChange(of: playing) { _, _ in showControls() }
        .onChange(of: playback.index) { _, _ in showControls() }
        .onChange(of: playback.error) { _, _ in showControls() }
        .onChange(of: voiceOverEnabled) { _, _ in showControls() }
        .task(id: interaction) {
            guard controlsVisible, playing, !scrubbing, !voiceOverEnabled, playback.error == nil else { return }
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
