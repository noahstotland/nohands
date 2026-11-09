import AppKit
import Foundation
import NoHandsCore
import NoHandsMac

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let stateItem = NSMenuItem(title: MenuState.loading.text, action: nil, keyEquivalent: "")
    private let configItem = NSMenuItem(title: "config.json invalid: using defaults", action: nil, keyEquivalent: "")
    private let transcriptItem = NSMenuItem(title: "No speech yet", action: nil, keyEquivalent: "")
    private let localModelItem = NSMenuItem(title: "", action: #selector(localModelClicked), keyEquivalent: "")
    private let pauseItem = NSMenuItem(title: "Pause Listening", action: #selector(togglePause), keyEquivalent: "")
    private let retryItem = NSMenuItem(title: "Retry", action: #selector(retry), keyEquivalent: "")
    private let accessibilityItem = NSMenuItem(title: "Grant Accessibility…", action: #selector(grantAccessibility), keyEquivalent: "")
    private let screenRecordingItem = NSMenuItem(title: "Grant Screen Recording…", action: #selector(grantScreenRecording), keyEquivalent: "")
    private let micItem = NSMenuItem(title: "Microphone denied — open Settings", action: #selector(openMicrophoneSettings), keyEquivalent: "")
    private let harnessItem = NSMenuItem(title: "Harness: checking…", action: nil, keyEquivalent: "")
    private let claudeItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let checkClaudeItem = NSMenuItem(title: "Check Claude connection", action: #selector(checkClaude), keyEquivalent: "")
    private let loginItem = NSMenuItem(title: "Start at Login", action: #selector(loginItemClicked), keyEquivalent: "")
    private let statusBarItem = NSMenuItem(title: "Status Bar", action: nil, keyEquivalent: "")
    private let statusBarMenu = NSMenu(title: "Status Bar")
    private static let statusBarDefaultsKey = "statusBarPosition"
    private let openConfigItem = NSMenuItem(title: "Open config.json…", action: #selector(openConfig), keyEquivalent: "")
    /// agent-desktop, when found and permitted (see `HarnessStatus`); re-probed when the menu opens.
    private var harnessStatus: HarnessStatus?
    private var harnessProbeInFlight = false
    /// The harness the running pipeline was built with (built once at pipeline start); nil before it starts.
    private var pipelineHarnessKind: HarnessKind?
    /// The last Claude check (kept in memory only) and whether one is running.
    private var lastClaudeCheck: (result: ClaudeCheckResult, time: String)?
    private var claudeChecking = false

    private let overlay = OverlayController()
    private var config = AppConfig()
    private var configInvalid = false
    private var pipeline: VoicePipeline?
    private var pipelineStarting = false
    private var userPaused = false
    private var axPaused = false          // paused because Accessibility was revoked
    private var micGranted = false
    private var errorText: String?        // shown as "Error: …" with a Retry item
    private var mode: Mode = .command
    private var pollTimer: Timer?
    private var localStatus: LocalModelStatus = .notRunning
    private var pullTask: Task<Void, Never>?
    private var pullFailed = false
    private var statusInFlight = false
    private var launchedOllama = false
    private var lastWarm: ContinuousClock.Instant?
    private var warming = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        overlay.statusBarPosition = StatusBarPosition.stored(UserDefaults.standard.string(forKey: Self.statusBarDefaultsKey))
        buildMenu()
        Task { await bootstrap() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        pipeline?.stop()
    }

    // MARK: - menu

    /// The bundled winking-face glyph as a template image, or the `mic` symbol when the PNGs are missing (an unbundled `swift run`).
    private func menuBarImage() -> NSImage {
        guard let image = NSImage(named: "MenuBarIcon") else {
            return NSImage(systemSymbolName: "mic", accessibilityDescription: "NoHands") ?? NSImage()
        }
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        image.accessibilityDescription = "NoHands"
        return image
    }

    private func buildMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = menuBarImage()
        statusItem.button?.imagePosition = .imageLeading

        let menu = NSMenu()
        menu.delegate = self
        stateItem.isEnabled = false
        configItem.isEnabled = false
        transcriptItem.isEnabled = false
        harnessItem.isEnabled = false
        claudeItem.isEnabled = false
        for item in [checkClaudeItem, localModelItem, pauseItem, retryItem, accessibilityItem, screenRecordingItem, micItem, loginItem, openConfigItem] { item.target = self }
        let title = NSMutableAttributedString(string: "● ", attributes: [.foregroundColor: NSColor.systemRed])
        title.append(NSAttributedString(string: "Grant Accessibility…"))
        accessibilityItem.attributedTitle = title
        let recordingTitle = NSMutableAttributedString(string: "● ", attributes: [.foregroundColor: NSColor.systemRed])
        recordingTitle.append(NSAttributedString(string: "Grant Screen Recording…"))
        screenRecordingItem.attributedTitle = recordingTitle
        for position in StatusBarPosition.allCases {
            let item = NSMenuItem(title: position.rawValue.capitalized, action: #selector(statusBarChosen(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = position.rawValue
            statusBarMenu.addItem(item)
        }
        statusBarItem.submenu = statusBarMenu
        refreshStatusBarMenu()
        let quit = NSMenuItem(title: "Quit NoHands", action: #selector(quit), keyEquivalent: "q")
        quit.target = self

        for item in [stateItem, configItem, NSMenuItem.separator(), transcriptItem, localModelItem, harnessItem, claudeItem, checkClaudeItem, NSMenuItem.separator(),
                     pauseItem, retryItem, accessibilityItem, screenRecordingItem, micItem, NSMenuItem.separator(), loginItem, statusBarItem, openConfigItem,
                     NSMenuItem.separator(), quit] {
            menu.addItem(item)
        }
        statusItem.menu = menu
        refresh()
    }

    /// Recomputes the status line, title and item visibility from current state.
    private func refresh() {
        let axGranted = Permissions.accessibilityGranted(prompt: false)
        let micDenied = Permissions.microphoneStatus() == .denied
        let state = MenuState.resolve(micDenied: micDenied, accessibilityGranted: axGranted, error: errorText,
                                      pipelineReady: pipeline != nil, paused: userPaused || axPaused)
        stateItem.title = state.text
        retryItem.isHidden = !state.showsRetry
        configItem.isHidden = !configInvalid
        accessibilityItem.isHidden = axGranted
        screenRecordingItem.isHidden = !config.visionEnabled || Permissions.screenRecordingGranted()
        micItem.isHidden = !micDenied
        pauseItem.isHidden = pipeline == nil
        let isLocal = config.effectiveBackend == .local
        localModelItem.isHidden = !isLocal
        if isLocal {
            localModelItem.title = LocalModelMenu.text(localStatus, model: config.resolvedLocalModel,
                                                       ollamaInstalled: OllamaClient.installedAppURL() != nil)
            localModelItem.isEnabled = LocalModelMenu.actionable(localStatus)
        }
        refreshClaudeItems()
        refreshLoginItem()
        pauseItem.title = userPaused ? "Resume Listening" : "Pause Listening"
        if let harnessStatus { harnessItem.title = harnessStatus.menuText(inUse: pipelineHarnessKind) }
        statusItem.button?.title = " " + MenuState.title(mode: mode, paused: state == .paused)
        overlay.setAppState(state, mode: mode)
    }

    // MARK: - Claude status

    /// The Claude line (config and last check only, no network) and the check item. The menu autoenables items that
    /// have a target and action, so the item is disabled by removing its action, not by `isEnabled`.
    private func refreshClaudeItems() {
        claudeItem.title = ClaudeStatus.menuLine(config: config, checking: claudeChecking, last: lastClaudeCheck)
        checkClaudeItem.action = claudeChecking || !ClaudeStatus.hasKey(config) ? nil : #selector(checkClaude)
    }

    @objc private func checkClaude() {
        guard !claudeChecking, ClaudeStatus.hasKey(config) else { return }
        claudeChecking = true
        refresh()
        let check = ClaudeConnectionCheck(config: config)
        Task { @MainActor in
            let result = await check.run()
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            lastClaudeCheck = (result, formatter.string(from: Date()))
            claudeChecking = false
            refresh()
        }
    }

    // MARK: - status bar setting

    private func refreshStatusBarMenu() {
        for item in statusBarMenu.items {
            item.state = (item.representedObject as? String) == overlay.statusBarPosition.rawValue ? .on : .off
        }
    }

    @objc private func statusBarChosen(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let position = StatusBarPosition(rawValue: raw) else { return }
        UserDefaults.standard.set(position.rawValue, forKey: Self.statusBarDefaultsKey)
        overlay.statusBarPosition = position
        refreshStatusBarMenu()
    }

    // MARK: - login item and config file

    /// Re-reads the system's registration state; it is never cached, so it is right after a relaunch and after
    /// the user removes the item in System Settings.
    private func refreshLoginItem() {
        let item = LoginItemMenu.item(for: LoginItem.state)
        loginItem.title = item.title
        loginItem.isEnabled = item.isEnabled
        switch item.checkmark {
        case .on: loginItem.state = .on
        case .off: loginItem.state = .off
        case .mixed: loginItem.state = .mixed
        }
    }

    @objc private func loginItemClicked() {
        do {
            switch LoginItemMenu.item(for: LoginItem.state).action {
            case .register: try LoginItem.register()
            case .unregister: try LoginItem.unregister()
            case .openSettings: LoginItem.openSettings()
            case .none: break
            }
        } catch {
            PipelineLog.warning("couldn't change Start at Login", detail: "\(error)")
            overlay.showHUD("couldn't change Start at Login: allow NoHands in Login Items", duration: .seconds(4))
        }
        refreshLoginItem()
    }

    @objc private func openConfig() {
        let url = ConfigFile.defaultURL
        do { _ = try ConfigFile.ensureExists(at: url) } catch {
            PipelineLog.warning("couldn't create config.json", detail: "\(url.path): \(error)")
            overlay.showHUD("couldn't create config.json: check ~/.config/nohands", duration: .seconds(4))
            return
        }
        let workspace = NSWorkspace.shared
        if workspace.urlForApplication(toOpen: url) == nil,
           let textEdit = workspace.urlForApplication(withBundleIdentifier: "com.apple.TextEdit") {
            workspace.open([url], withApplicationAt: textEdit, configuration: NSWorkspace.OpenConfiguration())
        } else {
            workspace.open(url)
        }
        overlay.showHUD("restart NoHands to apply config changes", duration: .seconds(4))
    }

    // MARK: - desktop harness

    /// The harness kind the pipeline runs with (native until it starts): what the local model is warmed for.
    private var harnessKind: HarnessKind { pipelineHarnessKind ?? .native }

    /// Re-reads the agent-desktop status (binary, version, Accessibility); the menu says when a restart is needed.
    private func probeHarness() async -> HarnessStatus {
        harnessProbeInFlight = true
        defer { harnessProbeInFlight = false }
        let status = await HarnessStatus.probe(config: config)
        harnessStatus = status
        refresh()
        return status
    }

    func menuWillOpen(_ menu: NSMenu) {
        refreshLoginItem()
        guard !harnessProbeInFlight else { return }
        Task { _ = await probeHarness() }
    }

    private func apply(mode: Mode, transcript: String) {
        self.mode = mode
        if !transcript.isEmpty { transcriptItem.title = PipelineText.truncated(transcript) }
        refresh()
    }

    @objc private func togglePause() {
        guard let pipeline else { return }
        if userPaused {
            Task {
                do {
                    try await pipeline.resume()
                    userPaused = false
                } catch {
                    PipelineLog.error("resume failed", detail: "\(error)")
                    overlay.showHUD("microphone error")
                    errorText = "microphone failed"
                }
                refresh()
            }
        } else {
            pipeline.pause()
            userPaused = true
            refresh()
        }
    }

    @objc private func retry() {
        errorText = nil
        if let pipeline {
            pipeline.stop()
            Task {
                do { try await pipeline.start(); userPaused = false } catch {
                    PipelineLog.error("retry failed", detail: "\(error)")
                    errorText = "microphone failed"
                }
                refresh()
            }
        } else {
            startPipelineIfReady()
        }
        refresh()
    }

    // MARK: - local model

    private var ollama: OllamaClient { OllamaClient(baseURL: config.ollamaBaseURL) }

    /// Re-checks Ollama (never while a pull runs), launches it once if installed, and keeps the model warm.
    private func refreshLocalModel() {
        guard config.effectiveBackend == .local, pullTask == nil, !statusInFlight else { return }
        statusInFlight = true
        let model = config.resolvedLocalModel
        Task {
            let status = await ollama.status(model: model)
            statusInFlight = false
            guard pullTask == nil else { return }
            // A failed download stays visible until the user retries or the model turns up.
            localStatus = (pullFailed && status == .modelMissing) ? .downloadFailed : status
            if status == .ready { pullFailed = false }
            if status == .notRunning, !launchedOllama, let app = OllamaClient.installedAppURL() {
                launchedOllama = true
                NSWorkspace.shared.open(app)
            }
            warmIfDue(model: model)
            refresh()
        }
    }

    private func warmIfDue(model: String) {
        let listening = pipeline != nil && !userPaused && !axPaused
        let now = ContinuousClock.now
        guard !warming, WarmPolicy.shouldWarm(now: now, last: lastWarm, listening: listening, status: localStatus) else { return }
        warming = true
        lastWarm = now
        Task {
            defer { warming = false }
            do { try await ollama.warm(model: model, harness: harnessKind) } catch {
                PipelineLog.warning("local model warm-up failed")
            }
        }
    }

    @objc private func localModelClicked() {
        switch localStatus {
        case .notRunning:
            if let app = OllamaClient.installedAppURL() {
                NSWorkspace.shared.open(app)
            } else if let url = URL(string: "https://ollama.com/download") {
                NSWorkspace.shared.open(url)
            }
        case .modelMissing, .downloadFailed:
            startPull()
        case .downloading, .ready:
            break
        }
    }

    private func startPull() {
        guard pullTask == nil else { return }
        let model = config.resolvedLocalModel
        pullFailed = false
        localStatus = .downloading(nil)
        refresh()
        pullTask = Task {
            let client = ollama
            let last = PercentThrottle()
            do {
                try await client.pull(model: model) { [weak self] p in
                    guard last.shouldReport(p) else { return }
                    Task { @MainActor in
                        guard let self, self.pullTask != nil else { return }
                        self.localStatus = .downloading(p)
                        self.refresh()
                    }
                }
                pullTask = nil
                localStatus = await client.status(model: model)
            } catch {
                pullTask = nil
                pullFailed = true
                localStatus = .downloadFailed
                PipelineLog.warning("local model download failed")
            }
            refresh()
        }
    }

    @objc private func grantAccessibility() { Permissions.openAccessibilitySettings() }

    @objc private func grantScreenRecording() {
        Permissions.requestScreenRecording()
        Permissions.openScreenRecordingSettings()
    }

    @objc private func openMicrophoneSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func quit() {
        pipeline?.stop()
        NSApp.terminate(nil)
    }

    // MARK: - startup

    private func loadConfig() {
        let url = ConfigFile.defaultURL
        let env = ProcessInfo.processInfo.environment
        let data = try? Data(contentsOf: url)   // missing file -> defaults
        do {
            config = try AppConfig.load(from: data, environment: env)
            if let data, (try? AppConfig.load(from: data, environment: [:]))?.anthropicAPIKey?.isEmpty == false,
               let perms = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.posixPermissions] as? Int,
               ConfigFileSecurity.isTooOpen(posixPermissions: perms) {
                PipelineLog.warning("config.json contains an API key but is readable by other users; run: chmod 600 \(url.path)")
            }
        } catch {
            // Never log file contents (they may hold the API key).
            PipelineLog.error("config.json is not valid JSON (\(url.path)); using defaults")
            config = (try? AppConfig.load(from: nil, environment: env)) ?? AppConfig()
            configInvalid = true
        }
    }

    private func bootstrap() async {
        loadConfig()
        micGranted = await Permissions.requestMicrophone()
        _ = Permissions.accessibilityGranted(prompt: true)
        // Shown after the permission prompts so it is not buried; it also stays in the menu.
        if configInvalid { overlay.showHUD("config.json invalid: using defaults", duration: .seconds(4)) }
        refresh()
        refreshLocalModel()
        startPipelineIfReady()
        schedulePoll(every: 2)
    }

    private func schedulePoll(every seconds: TimeInterval) {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollPermissions() }
        }
    }

    /// Runs every 2 s until the pipeline is up, then every 5 s for the app's lifetime.
    private func pollPermissions() {
        if !micGranted { micGranted = Permissions.microphoneStatus() == .granted }
        let axGranted = Permissions.accessibilityGranted(prompt: false)
        if let pipeline {
            if !axGranted, !axPaused {
                pipeline.pause()
                axPaused = true
            } else if axGranted, axPaused {
                axPaused = false
                if !userPaused {
                    Task {
                        do { try await pipeline.resume() } catch {
                            PipelineLog.error("resume after Accessibility grant failed", detail: "\(error)")
                            errorText = "microphone failed"
                        }
                        refresh()
                    }
                }
            }
        } else {
            startPipelineIfReady()
        }
        refreshLocalModel()
        refresh()
    }

    private func startPipelineIfReady() {
        guard pipeline == nil, !pipelineStarting, errorText == nil, micGranted,
              Permissions.accessibilityGranted(prompt: false) else { return }
        pipelineStarting = true
        overlay.showHUD("loading speech model…", duration: .seconds(3))
        Task {
            defer { pipelineStarting = false; refresh() }
            do {
                let transcriber = try await ParakeetTranscriber(version: config.asrModelVersion)
                let resolver: (any IntentResolving)?
                switch config.effectiveBackend {
                case .claude: resolver = ClaudeIntentResolver(config: config)
                case .local: resolver = OllamaIntentResolver(config: config)
                case .off: resolver = nil
                }
                let ax = AXQuery()
                // agent-desktop, when installed and permitted: the task loop observes and acts through it.
                let status = await probeHarness()
                let harness = status.makeHarness(config: config)
                pipelineHarnessKind = harness == nil ? .native : .agentDesktop
                PipelineLog.info("harness: \(status.text)")
                // Tasks observe, and the executor looks for a media player, with their own, larger AX budget:
                // Chrome's toolbar alone exhausts the default one.
                let taskAX = AXQuery(budget: .milliseconds(1000), maxNodes: 6000)
                let executor = ActionExecutor(input: CGEventInputSynthesizer(), ax: ax, overlay: overlay, config: config,
                                              harness: harness, mediaAX: taskAX)
                let observer = ScreenObserver(ax: taskAX,
                                              maxElements: config.observedElementCap, harness: harness,
                                              snapshotTimeoutMs: config.agentDesktopSnapshotMs)
                let p = VoicePipeline(config: config, transcriber: transcriber, resolver: resolver,
                                      executor: executor, overlay: overlay, ax: ax, observer: observer, harness: harness)
                p.onStatus = { [weak self] mode, transcript in self?.apply(mode: mode, transcript: transcript) }
                p.onNotice = { PipelineLog.info("notice: \($0)") }
                p.onError = { [weak self] message in self?.errorText = message; self?.refresh() }
                try await p.start()
                pipeline = p
                schedulePoll(every: 5)
                overlay.showHUD("NoHands is listening", duration: .seconds(2))
            } catch {
                PipelineLog.error("failed to start pipeline", detail: "\(error)")
                errorText = "start failed"
                overlay.showHUD("failed to start: \(error.localizedDescription)", duration: .seconds(5))
            }
        }
    }
}

/// Reports a pull progress value only when the whole percent changes.
private final class PercentThrottle: @unchecked Sendable {
    private let lock = NSLock()
    private var lastPercent = -1
    func shouldReport(_ p: Double?) -> Bool {
        let pct = p.map { Int(($0 * 100).rounded()) } ?? -1
        lock.lock(); defer { lock.unlock() }
        guard pct != lastPercent else { return false }
        lastPercent = pct
        return true
    }
}
