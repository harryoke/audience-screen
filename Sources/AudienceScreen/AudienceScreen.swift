import AppKit
import SwiftUI
import AVFoundation
import UniformTypeIdentifiers
import PlaybackCore

struct MediaFile: Identifiable {
    let id = UUID()
    let url: URL
    let video: Bool
    var seconds: Double = 0
    var name: String { url.lastPathComponent }
}

enum Transition: String, CaseIterable {
    case cut = "Cut", fade = "Dissolve", push = "Slide", reveal = "Reveal", move = "Move in", random = "Random"
}

final class StageView: NSView {
    private var mediaLayer: CALayer?
    private let blackoutLayer = CALayer()
    var fill = false { didSet { updateGravity() } }
    var blackedOut = false { didSet { blackoutLayer.isHidden = !blackedOut } }
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.masksToBounds = true
        blackoutLayer.backgroundColor = NSColor.black.cgColor
        blackoutLayer.zPosition = 100
        blackoutLayer.isHidden = true
        layer?.addSublayer(blackoutLayer)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        mediaLayer?.frame = bounds
        blackoutLayer.frame = bounds
        CATransaction.commit()
    }
    private func updateGravity() {
        if let video = mediaLayer as? AVPlayerLayer {
            video.videoGravity = fill ? .resizeAspectFill : .resizeAspect
        } else { mediaLayer?.contentsGravity = fill ? .resizeAspectFill : .resizeAspect }
    }
    func display(image: NSImage? = nil, player: AVPlayer? = nil, transition: Transition, duration: Double) {
        guard let root = layer else { return }
        let next: CALayer
        if let player { next = AVPlayerLayer(player: player) }
        else {
            next = CALayer()
            var rect = NSRect(origin: .zero, size: image?.size ?? .zero)
            next.contents = image?.cgImage(forProposedRect: &rect, context: nil, hints: nil)
        }
        next.frame = bounds
        next.backgroundColor = NSColor.black.cgColor
        let effect = transition == .random ? [Transition.fade, .push, .reveal, .move].randomElement()! : transition
        CATransaction.begin(); CATransaction.setDisableActions(true)
        mediaLayer?.removeFromSuperlayer()
        root.addSublayer(next)
        mediaLayer = next
        updateGravity()
        CATransaction.commit()
        if effect != .cut {
            let animation = CATransition()
            animation.duration = duration
            animation.type = effect == .push ? .push : effect == .reveal ? .reveal : effect == .move ? .moveIn : .fade
            animation.subtype = .fromRight
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            root.add(animation, forKey: "mediaTransition")
        }
    }
    func clear() { mediaLayer?.removeFromSuperlayer(); mediaLayer = nil; layer?.removeAllAnimations() }
}

final class AudienceWindow: NSWindow {
    var onKey: ((UInt16) -> Void)?
    override var canBecomeKey: Bool { true }
    override func keyDown(with event: NSEvent) { onKey?(event.keyCode) }
}

final class ShowController: NSObject, ObservableObject, NSWindowDelegate {
    @Published var files: [MediaFile] = []
    @Published var folder: URL?
    @Published var selection: UUID?
    @Published var currentID: UUID?
    @Published var running = false
    @Published var status = "Choose a folder to build your show."
    @Published var defaultSeconds = 8.0
    @Published var fullVideos = true
    @Published var shuffle = false { didSet { playlist.reset(files.map(\.id), shuffle: shuffle, keeping: currentID) } }
    @Published var loop = true
    @Published var recursive = false
    @Published var transition = Transition.fade
    @Published var transitionSeconds = 0.7
    @Published var fill = false { didSet { stage.fill = fill } }
    @Published var muted = false { didSet { player?.isMuted = muted || blackout } }
    @Published var blackout = false { didSet { stage.blackedOut = blackout; player?.isMuted = muted || blackout } }
    @Published var screens = NSScreen.screens
    @Published var screenIndex = NSScreen.screens.count > 1 ? 1 : 0
    @Published var elapsed = 0.0
    let stage = StageView(frame: NSRect(x: 0, y: 0, width: 1280, height: 720))
    private var audience: AudienceWindow?
    private var playlist = Playlist()
    private var player: AVPlayer?
    private var observation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var screenObserver: NSObjectProtocol?
    private var timer: Timer?
    private var lastTick = ProcessInfo.processInfo.systemUptime
    private var loadingSince: Double?
    private var limit: Double?
    private var ready = false
    private var failed = Set<UUID>()
    private var generation = UUID()
    private var activity: NSObjectProtocol?
    private let defaultsKey = "AudienceScreen.fileDurations"
    private var savedDurations: [String: Double] {
        get { UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: Double] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: defaultsKey) }
    }

    override init() {
        super.init()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in self?.tick() }
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.screens = NSScreen.screens
            self.screenIndex = min(self.screenIndex, max(0, self.screens.count - 1))
        }
    }
    var currentName: String { files.first(where: { $0.id == currentID })?.name ?? "Ready when you are" }
    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.allowsMultipleSelection = false; panel.prompt = "Use folder"
        if panel.runModal() == .OK, let url = panel.url { folder = url; reload() }
    }
    func reload() {
        guard let folder else { return }
        stop()
        var urls: [URL] = []
        do {
            if recursive {
                var scanError: Error?
                let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey, .contentTypeKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) { _, error in scanError = error; return true }
                urls = enumerator?.allObjects as? [URL] ?? []
                if let scanError { throw scanError }
            } else { urls = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isRegularFileKey, .contentTypeKey], options: [.skipsHiddenFiles]) }
            let saved = savedDurations
            files = urls.compactMap { url in
                guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .contentTypeKey]), values.isRegularFile == true,
                      let type = values.contentType else { return nil }
                let video = type.conforms(to: .movie)
                guard video || type.conforms(to: .image) else { return nil }
                return MediaFile(url: url, video: video, seconds: saved[url.path] ?? 0)
            }.sorted { $0.url.path.localizedStandardCompare($1.url.path) == .orderedAscending }
            playlist.reset(files.map(\.id), shuffle: shuffle)
            selection = files.first?.id
            status = files.isEmpty ? "No supported images or videos in this folder." : "\(files.count) files ready."
        } catch { files = []; status = "Could not read folder: \(error.localizedDescription)" }
    }
    func setDuration(_ id: UUID, seconds: Double) {
        guard let index = files.firstIndex(where: { $0.id == id }) else { return }
        let value = seconds.isFinite ? min(86400, max(0, seconds)) : 0
        files[index].seconds = value
        var saved = savedDurations; saved[files[index].url.path] = value; savedDurations = saved
    }
    func openAudience(fullscreen: Bool = false) {
        if audience == nil {
            let window = AudienceWindow(contentRect: stage.frame, styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "Audience Screen — Output"
            window.backgroundColor = .black; window.contentView = stage
            window.isReleasedWhenClosed = false; window.delegate = self
            window.collectionBehavior = [.fullScreenPrimary]
            window.onKey = { [weak self] code in
                guard let self else { return }
                switch code {
                case 49: self.togglePlay()
                case 124: self.next()
                case 123: self.previous()
                case 11: self.blackout.toggle()
                case 53: if self.audience?.styleMask.contains(.fullScreen) == true { self.audience?.toggleFullScreen(nil) }
                default: break
                }
            }
            audience = window
        }
        guard let window = audience else { return }
        if !window.styleMask.contains(.fullScreen), screens.indices.contains(screenIndex) {
            let frame = screens[screenIndex].visibleFrame
            window.setFrame(NSRect(x: frame.minX + frame.width * 0.08, y: frame.minY + frame.height * 0.08, width: frame.width * 0.84, height: frame.height * 0.84), display: true)
        }
        window.makeKeyAndOrderFront(nil)
        if fullscreen && !window.styleMask.contains(.fullScreen) { window.toggleFullScreen(nil) }
    }
    func windowWillClose(_ notification: Notification) { stop() }
    func togglePlay() {
        guard !files.isEmpty else { return }
        if running { pause(); return }
        if audience?.isVisible != true { openAudience() }
        running = true; lastTick = ProcessInfo.processInfo.systemUptime
        activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleDisplaySleepDisabled], reason: "Presenting audience slideshow")
        if currentID == nil {
            failed.removeAll()
            if let id = playlist.current { load(id) }
        } else if ready { player?.play(); status = "Playing" }
    }
    func pause() {
        running = false; player?.pause(); status = "Paused"
        if let activity { ProcessInfo.processInfo.endActivity(activity); self.activity = nil }
    }
    func stop() {
        pause(); cleanup(); currentID = nil; elapsed = 0; stage.clear(); failed.removeAll()
        playlist.reset(files.map(\.id), shuffle: shuffle)
        status = "Stopped"
    }
    func next() {
        guard !files.isEmpty else { return }
        if let id = playlist.advance(loop: loop, shuffle: shuffle) { load(id) }
        else { pause(); status = "Show complete" }
    }
    func previous() { if let id = playlist.previous() { load(id) } }
    func playSelected() {
        guard let selection else { return }
        playlist.select(selection)
        load(selection)
        if !running { togglePlay() }
    }
    private func cleanup() {
        generation = UUID(); observation = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver); self.endObserver = nil }
        player?.pause(); player = nil; ready = false; loadingSince = nil
    }
    private func load(_ id: UUID) {
        guard let file = files.first(where: { $0.id == id }) else { return }
        cleanup(); currentID = id; elapsed = 0
        limit = file.seconds > 0 ? file.seconds : (file.video && fullVideos ? nil : max(0.5, defaultSeconds))
        if file.video {
            status = "Loading \(file.name)…"
            let item = AVPlayerItem(url: file.url)
            let nextPlayer = AVPlayer(playerItem: item)
            player = nextPlayer; nextPlayer.isMuted = muted || blackout
            loadingSince = ProcessInfo.processInfo.systemUptime
            let token = generation
            observation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
                DispatchQueue.main.async {
                    guard let self, self.generation == token else { return }
                    if item.status == .readyToPlay {
                        self.ready = true; self.loadingSince = nil
                        self.stage.display(player: nextPlayer, transition: self.transition, duration: self.transitionSeconds)
                        if self.running { nextPlayer.play() }
                        self.status = self.running ? "Playing" : "Paused"
                    } else if item.status == .failed { self.skipFailed(file, reason: item.error?.localizedDescription ?? "Unsupported video") }
                }
            }
            endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
                guard let self, self.generation == token else { return }
                if self.limit != nil, self.elapsed + 0.15 < self.limit! {
                    nextPlayer.seek(to: .zero) { _ in DispatchQueue.main.async {
                        if self.generation == token && self.running { nextPlayer.play() }
                    } }
                } else if self.running { self.next() }
            }
        } else if let image = NSImage(contentsOf: file.url), image.isValid {
            stage.display(image: image, transition: transition, duration: transitionSeconds)
            ready = true; status = running ? "Playing" : "Paused"
        } else { skipFailed(file, reason: "Unreadable image") }
    }
    private func skipFailed(_ file: MediaFile, reason: String) {
        failed.insert(file.id)
        status = "Skipped \(file.name): \(reason)"
        guard failed.count < files.count else { pause(); cleanup(); stage.clear(); currentID = nil; status = "No playable media. Check the files and video codecs."; return }
        let token = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self, self.generation == token else { return }
            self.next()
        }
    }
    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        let delta = now - lastTick; lastTick = now
        if let loadingSince, now - loadingSince > 20,
           let file = files.first(where: { $0.id == currentID }) { self.loadingSince = nil; skipFailed(file, reason: "Video load timed out"); return }
        guard running, ready else { return }
        elapsed += delta
        if let limit, elapsed >= limit { next() }
        if player?.currentItem?.status == .failed, let file = files.first(where: { $0.id == currentID }) { skipFailed(file, reason: "Playback failed") }
    }
}

struct ControlView: View {
    @ObservedObject var show: ShowController
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Image(systemName: "play.rectangle.fill").font(.system(size: 32)).foregroundStyle(.cyan)
                    VStack(alignment: .leading) {
                        Text("Audience Screen").font(.title2.bold())
                        Text("Your media. Their screen.").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Choose folder…", action: show.chooseFolder).keyboardShortcut("o")
                }
                HStack {
                    Image(systemName: "folder")
                    Text(show.folder?.path ?? "No folder selected").lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button(action: show.reload) { Image(systemName: "arrow.clockwise") }.disabled(show.folder == nil).help("Rescan folder")
                }.font(.callout).foregroundStyle(.secondary)
                if show.files.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "photo.on.rectangle.angled").font(.system(size: 56)).foregroundStyle(.secondary)
                        Text("Fill the screen with something great").font(.title3.bold())
                        Text("Choose a folder of images and videos to get started.").foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(selection: $show.selection) {
                        ForEach(show.files) { file in
                            HStack(spacing: 12) {
                                Image(systemName: file.video ? "film" : "photo").foregroundStyle(file.id == show.currentID ? .cyan : .secondary)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(file.name).lineLimit(1)
                                    Text(file.seconds > 0 ? "\(file.seconds, specifier: "%.1f") seconds" : file.video && show.fullVideos ? "Full video" : "Default duration").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if file.id == show.currentID { Image(systemName: "speaker.wave.2.fill").foregroundStyle(.cyan) }
                            }.padding(.vertical, 5).tag(file.id)
                        }
                    }.listStyle(.inset(alternatesRowBackgrounds: true))
                    HStack {
                        Text("\(show.files.count) files").foregroundStyle(.secondary)
                        Spacer()
                        Button("Play selected", action: show.playSelected).disabled(show.selection == nil)
                    }
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text(show.currentName).font(.headline).lineLimit(1)
                    HStack {
                        Text(show.status).lineLimit(2).foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(show.elapsed))s").monospacedDigit().foregroundStyle(.secondary)
                    }.font(.caption)
                    HStack(spacing: 16) {
                        Button(action: show.previous) { Image(systemName: "backward.end.fill") }.help("Previous file")
                        Button(action: show.togglePlay) { Label(show.running ? "Pause" : "Play", systemImage: show.running ? "pause.fill" : "play.fill").frame(width: 70) }.buttonStyle(.borderedProminent)
                        Button(action: show.next) { Image(systemName: "forward.end.fill") }.help("Next file")
                        Button(action: show.stop) { Image(systemName: "stop.fill") }.help("Stop")
                        Spacer()
                        Toggle("Blackout", isOn: $show.blackout).toggleStyle(.button).help("Hide output and mute audio while the show continues")
                    }.disabled(show.files.isEmpty)
                }.padding(16).background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            }.padding(24).frame(minWidth: 490)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("SHOW SETTINGS").font(.caption.bold()).foregroundStyle(.secondary)
                    GroupBox("Audience display") {
                        VStack(alignment: .leading, spacing: 10) {
                            Picker("Display", selection: $show.screenIndex) {
                                ForEach(Array(show.screens.enumerated()), id: \.offset) { index, screen in Text(screen.localizedName).tag(index) }
                            }.labelsHidden()
                            HStack {
                                Button("Open window") { show.openAudience() }
                                Button("Full screen") { show.openAudience(fullscreen: true) }
                            }
                            Toggle("Fill screen (crop edges)", isOn: $show.fill)
                            Toggle("Mute video audio", isOn: $show.muted)
                        }.padding(6)
                    }
                    GroupBox("Playback") {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Default seconds")
                                TextField("Seconds", value: $show.defaultSeconds, formatter: Self.secondsFormatter).frame(width: 65)
                            }
                            Toggle("Play videos to the end", isOn: $show.fullVideos)
                            Toggle("Shuffle order", isOn: $show.shuffle)
                            Toggle("Loop show", isOn: $show.loop)
                            Toggle("Include subfolders", isOn: $show.recursive).onChange(of: show.recursive) { _ in show.reload() }
                            Text("Timing changes apply when the next file starts.").font(.caption).foregroundStyle(.secondary)
                        }.padding(6)
                    }
                    GroupBox("Transitions") {
                        VStack(alignment: .leading, spacing: 10) {
                            Picker("Effect", selection: $show.transition) { ForEach(Transition.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                            HStack { Text("Speed"); Slider(value: $show.transitionSeconds, in: 0.1...2); Text("\(show.transitionSeconds, specifier: "%.1f")s").monospacedDigit() }
                        }.padding(6)
                    }
                    GroupBox("Selected file duration") {
                        VStack(alignment: .leading, spacing: 10) {
                            if let id = show.selection, let file = show.files.first(where: { $0.id == id }) {
                                Text(file.name).lineLimit(2).font(.callout)
                                HStack {
                                    TextField("Seconds", value: Binding(get: { show.files.first(where: { $0.id == id })?.seconds ?? 0 }, set: { show.setDuration(id, seconds: $0) }), formatter: Self.secondsFormatter).frame(width: 85)
                                    Text("seconds")
                                    Spacer()
                                    Button("Reset") { show.setDuration(id, seconds: 0) }
                                }
                                Text("0 uses the default. A video repeats or trims to fit a custom duration. Saved per file.").font(.caption).foregroundStyle(.secondary)
                            } else { Text("Select a file to set its duration.").foregroundStyle(.secondary) }
                        }.padding(6)
                    }
                    Text("Audience window shortcuts\nSpace  Play / Pause    ← →  Previous / Next\nB  Blackout    Esc  Leave full screen").font(.caption).foregroundStyle(.secondary)
                }.padding(22)
            }.frame(width: 345)
        }.frame(minWidth: 880, minHeight: 700).preferredColorScheme(.dark)
    }
    static var secondsFormatter: NumberFormatter {
        let formatter = NumberFormatter(); formatter.numberStyle = .decimal
        formatter.minimum = 0; formatter.maximum = 86400; formatter.maximumFractionDigits = 1
        return formatter
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var show: ShowController!
    func applicationDidFinishLaunching(_ notification: Notification) {
        show = ShowController()
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1040, height: 760), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Audience Screen"
        window.contentView = NSHostingView(rootView: ControlView(show: show))
        window.minSize = NSSize(width: 880, height: 700)
        window.isReleasedWhenClosed = false
        window.center(); window.makeKeyAndOrderFront(nil)
        let menu = NSMenu()
        let appItem = NSMenuItem(); menu.addItem(appItem)
        let appMenu = NSMenu(); appItem.submenu = appMenu
        appMenu.addItem(withTitle: "About Audience Screen", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Audience Screen", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let editItem = NSMenuItem(); menu.addItem(editItem)
        let editMenu = NSMenu(title: "Edit"); editItem.submenu = editMenu
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        NSApp.mainMenu = menu
        NSApp.activate(ignoringOtherApps: true)
        if CommandLine.arguments.contains("--smoke-test") {
            show.openAudience()
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                print("AUDIENCE_SCREEN_SMOKE_OK")
                NSApp.terminate(nil)
            }
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) { show.stop() }
}

@main
enum AudienceScreenApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { app.run() }
    }
}
