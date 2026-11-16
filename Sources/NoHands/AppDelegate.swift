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
    private let recentItem = NSMenuItem(title: "Recent commands", action: nil, keyEquivalent: "")
    private let recentMenu = NSMenu(title: "Recent commands")
    private let viewLogsItem = NSMenuItem(title: "View Logs…", action: #selector(viewLogs), keyEquivalent: "")
    private let localModelItem = NSMenuItem(title: "", action: #selector(localModelClicked), keyEquivalent: "")
    private let pauseItem = NSMenuItem(title: "Pause Listening", action: #selector(togglePause), keyEquivalent: "")
    private let retryItem = NSMenuItem(title: "Retry", action: #selector(retry), keyEquivalent: "")
    private let accessibilityItem = NSMenuItem(title: "Grant Accessibility…", action: #selector(grantAccessibility), keyEquivalent: "")
    private let screenRecordingItem = NSMenuItem(title: "Grant Screen Recording…", action: #selector(grantScreenRecording), keyEquivalent: "")
    private let micItem = NSMenuItem(title: "Microphone denied — open Settings", action: #selector(openMicrophoneSettings), keyEquivalent: "")
    private let harnessItem = NSMenuItem(title: "Harness: checking…", action: nil, keyEquivalent: "")
    private let claudeItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let claudeUsageItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let checkClaudeItem = NSMenuItem(title: "Check Claude connection", action: #selector(checkClaude), keyEquivalent: "")
    private let loginItem = NSMenuItem(title: "Start at Login", action: #selector(loginItemClicked), keyEquivalent: "")
    private let statusBarItem = NSMenuItem(title: "Status Bar", action: nil, keyEquivalent: "")
    private let statusBarMenu = NSMenu(title: "Status Bar")
    private static let statusBarDefaultsKey = "statusBarPosition"
    private let backendItem = NSMenuItem(title: "Model", action: nil, keyEquivalent: "")
    private let backendMenu = NSMenu(title: "Model")
    private let packsItem = NSMenuItem(title: "Packs", action: nil, keyEquivalent: "")
    private let packsMenu = NSMenu(title: "Packs")
    private let packStore = PackStore()
    private let claudeKeyItem = NSMenuItem(title: "Set Claude API key…", action: #selector(setClaudeKey), keyEquivalent: "")
    private let openConfigItem = NSMenuItem(title: "Open config.json…", action: #selector(openConfig), keyEquivalent: "")
    /// agent-desktop, when found and permitted (see `HarnessStatus`); re-probed when the menu opens.
    private var harnessStatus: HarnessStatus?
    private var harnessProbeInFlight = false
    /// The harness the running pipeline was built with (built once at pipeline start); nil before it starts.
    private var pipelineHarnessKind: HarnessKind?
    /// What the running pipeline was built with, so a model switch can build a new observer and runner on the same AX query and harness.
    private var taskAX: AXQuery?
    private var pipelineHarness: (any DesktopHarness)?
    /// The last Claude check (kept in memory only) and whether one is running.
    private var lastClaudeCheck: (result: ClaudeCheckResult, time: String)?
    private var claudeChecking = false

    private let overlay = OverlayController()
    private let commandLog = CommandLogStore()
    /// Created on first show, so no command builds it unless the user opens the logs.
    private var logWindow: LogWindowController?
    private var config = AppConfig()
    private var configInvalid = false
    /// Whether config.json itself holds a key (the environment is ignored): as of launch, plus saves from the menu.
    private var fileHasKey = false
    /// A key was saved from the menu since launch. It applies after a restart, so the Claude row stays off and says so.
    private var keySavedThisSession = false
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
    private var packsObserver: (any NSObjectProtocol)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        overlay.statusBarPosition = StatusBarPosition.stored(UserDefaults.standard.string(forKey: Self.statusBarDefaultsKey))
        commandLog.onChange = { [weak self] in self?.logWindow?.reload() }
        buildMenu()
        // The CLI installs packs; it tells the app through this local notification (no payload), and the menu re-reads on open.
        packsObserver = DistributedNotificationCenter.default().addObserver(
            forName: PackStore.changedNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.packsChanged() }
        }
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
        claudeUsageItem.isEnabled = false
        claudeUsageItem.isHidden = true
        for item in [viewLogsItem, checkClaudeItem, localModelItem, pauseItem, retryItem, accessibilityItem, screenRecordingItem, micItem, loginItem, claudeKeyItem, openConfigItem] { item.target = self }
        let title = NSMutableAttributedString(string: "● ", attributes: [.foregroundColor: NSColor.systemRed])
        title.append(NSAttributedString(string: "Grant Accessibility…"))
        accessibilityItem.attributedTitle = title
        let recordingTitle = NSMutableAttributedString(string: "● ", attributes: [.foregroundColor: NSColor.systemRed])
        recordingTitle.append(NSAttributedString(string: "Grant Screen Recording…"))
        screenRecordingItem.attributedTitle = recordingTitle
        for choice in BackendChoice.allCases {
            let item = NSMenuItem(title: choice.rawValue, action: #selector(backendChosen(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = choice.rawValue
            backendMenu.addItem(item)
        }
        backendItem.submenu = backendMenu
        for position in StatusBarPosition.allCases {
            let item = NSMenuItem(title: Self.statusBarTitle(position), action: #selector(statusBarChosen(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = position.rawValue
            statusBarMenu.addItem(item)
        }
        statusBarItem.submenu = statusBarMenu
        packsItem.submenu = packsMenu
        reloadPacks()
        refreshStatusBarMenu()
        let quit = NSMenuItem(title: "Quit NoHands", action: #selector(quit), keyEquivalent: "q")
        quit.target = self

        recentItem.submenu = recentMenu
        rebuildRecentMenu()
        for item in [stateItem, configItem, NSMenuItem.separator(), transcriptItem, recentItem, viewLogsItem, localModelItem, harnessItem, claudeItem, claudeUsageItem, checkClaudeItem, NSMenuItem.separator(),
                     pauseItem, retryItem, accessibilityItem, screenRecordingItem, micItem, NSMenuItem.separator(), loginItem, statusBarItem, packsItem, backendItem, claudeKeyItem, openConfigItem,
                     NSMenuItem.separator(), quit] {
            menu.addItem(item)
        }
        statusItem.menu = menu
        installEditMenu()
        refresh()
    }

    /// An accessory app shows no main menu, but text fields get Cmd-V, Cmd-C, Cmd-X and Cmd-A only through one.
    /// This hidden Edit menu lets paste work in the API key field.
    private func installEditMenu() {
        let edit = NSMenu(title: "Edit")
        for (title, selector, key) in [("Cut", #selector(NSText.cut(_:)), "x"), ("Copy", #selector(NSText.copy(_:)), "c"),
                                       ("Paste", #selector(NSText.paste(_:)), "v"), ("Select All", #selector(NSText.selectAll(_:)), "a")] {
            edit.addItem(NSMenuItem(title: title, action: selector, keyEquivalent: key))
        }
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        editItem.submenu = edit
        let mainMenu = NSMenu()
        mainMenu.addItem(NSMenuItem(title: "NoHands", action: nil, keyEquivalent: ""))
        mainMenu.addItem(editItem)
        NSApp.mainMenu = mainMenu
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
        refreshBackendMenu()
        claudeKeyItem.title = fileHasKey ? "Change Claude API key…" : "Set Claude API key…"
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
        let line = ClaudeStatus.menuLine(config: config, checking: claudeChecking, last: lastClaudeCheck)
        claudeItem.title = line
        if ClaudeStatus.showsCheckmark(checking: claudeChecking, last: lastClaudeCheck?.result) {
            let title = NSMutableAttributedString(string: "✓ ", attributes: [.foregroundColor: NSColor.systemGreen])
            title.append(NSAttributedString(string: line))
            claudeItem.attributedTitle = title
        } else {
            claudeItem.attributedTitle = nil
        }
        // The session's token total: counts only, no network. Hidden until the first call (and with no key or LLM off).
        let usageLine = config.effectiveBackend == .claude ? ClaudeUsageMeter.shared.total.menuLine : nil
        claudeUsageItem.title = usageLine ?? ""
        claudeUsageItem.isHidden = usageLine == nil
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

    // MARK: - model setting

    /// The title follows the backend in use; each row's checkmark and enabled state come from `BackendMenu`. A disabled
    /// row has its action removed, since the menu autoenables items that have one.
    private func refreshBackendMenu() {
        backendItem.title = BackendMenu.title(config: config)
        let rows = BackendMenu.rows(config: config, keySavedThisSession: keySavedThisSession)
        for item in backendMenu.items {
            guard let raw = item.representedObject as? String, let row = rows.first(where: { $0.choice.rawValue == raw }) else { continue }
            item.title = row.title
            item.state = row.checked ? .on : .off
            item.action = row.enabled ? #selector(backendChosen(_:)) : nil
        }
    }

    /// One pick, applied from the next command with no restart. The file is written first; if that fails the app stays
    /// on the old backend. Only `intentBackend` is applied live: other edits to config.json still wait for a restart.
    @objc private func backendChosen(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let choice = BackendChoice(rawValue: raw) else { return }
        let target: EffectiveBackend = choice == .claude ? .claude : .local
        // The checked row does nothing, so `auto` stays `auto` until a real change.
        guard config.effectiveBackend != target else { return }
        guard choice != .claude || ClaudeStatus.hasKey(config) else { return }
        do {
            try ConfigFile.saveIntentBackend(choice, at: ConfigFile.defaultURL)
        } catch {
            let hud: String
            switch error as? ConfigFile.SaveError {
            case .invalidJSON:
                PipelineLog.warning("couldn't switch model: config.json is not valid JSON")
                hud = "couldn't switch model: fix config.json, then try again"
            case .symlink:
                PipelineLog.warning("couldn't switch model: config.json or its folder is a symlink")
                hud = "couldn't switch model: replace the config.json link with a file"
            case .writeFailed(let code):
                PipelineLog.warning("couldn't switch model: write failed (\(code))")
                hud = "couldn't switch model: check ~/.config/nohands"
            case nil:
                PipelineLog.warning("couldn't switch model")
                hud = "couldn't switch model: check ~/.config/nohands"
            }
            overlay.showHUD(hud, duration: .seconds(4))
            return
        }
        config.intentBackend = choice == .claude ? .claude : .local
        lastClaudeCheck = nil
        if target == .local { lastWarm = nil }
        if let pipeline { switchPipelineBackend(pipeline) }
        PipelineLog.info("intent backend: \(Self.backendName(config.effectiveBackend))")
        refresh()
        refreshLocalModel()
        overlay.showHUD(target == .claude ? "Using Claude from the next command" : "Using the local model from the next command",
                        duration: .seconds(3))
    }

    private static func backendName(_ backend: EffectiveBackend) -> String {
        switch backend {
        case .claude: "claude"
        case .local: "local"
        case .off: "off"
        }
    }

    /// The resolver for the backend in effect; nil when the model is off.
    private func makeResolver() -> (any IntentResolving)? {
        switch config.effectiveBackend {
        case .claude: ClaudeIntentResolver(config: config)
        case .local: OllamaIntentResolver(config: config)
        case .off: nil
        }
    }

    /// Hands the pipeline a runner for the backend now in `config`: the resolver, the element cap and vision all follow it.
    private func switchPipelineBackend(_ pipeline: VoicePipeline) {
        guard let resolver = makeResolver(), let taskAX else { return }
        let observer = ScreenObserver(ax: taskAX, maxElements: config.observedElementCap, harness: pipelineHarness,
                                      snapshotTimeoutMs: config.agentDesktopSnapshotMs)
        pipeline.switchBackend(config: config, resolver: resolver, observer: observer)
        pipeline.resolverKind = Self.logResolver(config.effectiveBackend)
    }

    // MARK: - status bar setting

    private static func statusBarTitle(_ position: StatusBarPosition) -> String {
        switch position {
        case .off: "Off"
        case .corner: "Bottom Right"
        }
    }

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

    /// Asks for the key in a masked field and saves it to config.json. The key never reaches the menu, the HUD or the
    /// log: only fixed text (and the errno name of a failed write) is logged. It applies after a restart.
    @objc private func setClaudeKey() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = fileHasKey ? "Change Claude API key" : "Set Claude API key"
        alert.informativeText = "Applies after you restart NoHands. ANTHROPIC_API_KEY, if set, overrides this."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        // Listening stays off while the alert is open, so dictation can't type into the field and a spoken
        // "press return" can't press Save. If the user had already paused, it stays paused.
        let pausedForAlert = pipeline != nil && !userPaused && !axPaused
        if pausedForAlert { togglePause() }
        let response = alert.runModal()
        if pausedForAlert { togglePause() }
        defer { field.stringValue = "" }
        guard response == .alertFirstButtonReturn else { return }
        guard let key = ClaudeKeyEntry.normalized(field.stringValue) else { return }
        do {
            try ConfigFile.saveAnthropicKey(key, at: ConfigFile.defaultURL)
            fileHasKey = true
            keySavedThisSession = true
            PipelineLog.info("Claude key saved to config.json; restart to apply")
            overlay.showHUD("Claude key saved: restart NoHands to apply", duration: .seconds(4))
            refresh()
        } catch let error as ConfigFile.SaveError {
            let hud: String
            switch error {
            case .invalidJSON:
                PipelineLog.warning("couldn't save Claude key: config.json is not valid JSON")
                hud = "couldn't save key: fix config.json, then try again"
            case .symlink:
                PipelineLog.warning("couldn't save Claude key: config.json or its folder is a symlink")
                hud = "couldn't save key: replace the config.json link with a file"
            case .writeFailed(let code):
                PipelineLog.warning("couldn't save Claude key: write failed (\(code))")
                hud = "couldn't save key: check ~/.config/nohands"
            }
            overlay.showHUD(hud, duration: .seconds(4))
        } catch {
            PipelineLog.warning("couldn't save Claude key")
            overlay.showHUD("couldn't save key: check ~/.config/nohands", duration: .seconds(4))
        }
    }

    // MARK: - app packs

    /// Built-in packs plus the enabled installed ones, as of the last reload.
    private var packSet = PackSet.builtIns

    private var packsReloadPending = false

    /// The CLI's notification: one reload per 500 ms however many arrive, so a flood of them cannot keep the app reading disk.
    private func packsChanged() {
        guard !packsReloadPending else { return }
        packsReloadPending = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            self?.packsReloadPending = false
            self?.reloadPacks()
        }
    }

    /// Re-reads the installed packs (on the CLI's notification, on menu open and after a toggle or remove), hands the
    /// pipeline the new set and rebuilds the Packs submenu. A pack that fails to load is shown as invalid and skipped.
    private func reloadPacks() {
        let entries: [PackStore.Entry]
        do { entries = try packStore.list() } catch {
            PipelineLog.warning("couldn't read installed packs", detail: "\(error)")
            entries = []
        }
        packSet = PackSet(installed: entries.compactMap { $0.enabled ? $0.pack : nil })
        pipeline?.setPacks(packSet)
        packsMenu.removeAllItems()
        guard !entries.isEmpty else {
            let none = NSMenuItem(title: "No packs installed", action: nil, keyEquivalent: "")
            none.isEnabled = false
            packsMenu.addItem(none)
            return
        }
        for entry in entries {
            let status = PackMenu.status(phrases: entry.pack?.phrases.count ?? 0,
                                         shadowed: packSet.shadowed.filter { $0.packID == entry.id }.count,
                                         invalidReason: entry.invalidReason)
            let line = NSMenuItem(title: status, action: nil, keyEquivalent: "")
            line.isEnabled = false
            let on = NSMenuItem(title: "On", action: #selector(packToggled(_:)), keyEquivalent: "")
            on.state = entry.enabled ? .on : .off
            let remove = NSMenuItem(title: "Remove…", action: #selector(packRemoveClicked(_:)), keyEquivalent: "")
            let submenu = NSMenu(title: entry.id)
            for item in [line, on, remove] {
                item.target = self
                item.representedObject = entry.id
                submenu.addItem(item)
            }
            let item = NSMenuItem(title: entry.pack.map { "\($0.name) \($0.version)" } ?? entry.id, action: nil, keyEquivalent: "")
            item.submenu = submenu
            packsMenu.addItem(item)
        }
    }

    @objc private func packToggled(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        do { try packStore.setEnabled(id, sender.state != .on) } catch {
            PipelineLog.warning("couldn't change pack", detail: "\(error)")
            overlay.showHUD("couldn't change the pack: check ~/.config/nohands/packs", duration: .seconds(4))
        }
        reloadPacks()
    }

    @objc private func packRemoveClicked(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Remove this pack?"
        alert.informativeText = "Its voice commands stop working. You can add the pack again with nohands-cli."
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Remove").hasDestructiveAction = true
        // Listening stays off while the alert is open, so a spoken "press return" can't answer it.
        let pausedForAlert = pipeline != nil && !userPaused && !axPaused
        if pausedForAlert { togglePause() }
        let response = alert.runModal()
        if pausedForAlert { togglePause() }
        guard response == .alertSecondButtonReturn else { return }
        do { try packStore.remove(id) } catch {
            PipelineLog.warning("couldn't remove pack", detail: "\(error)")
            overlay.showHUD("couldn't remove the pack: check ~/.config/nohands/packs", duration: .seconds(4))
        }
        reloadPacks()
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
        refreshClaudeItems()
        refreshLoginItem()
        rebuildRecentMenu()
        reloadPacks()
        guard !harnessProbeInFlight else { return }
        Task { _ = await probeHarness() }
    }

    /// Newest first, one line per command; choosing one opens the View Logs window on it.
    private func rebuildRecentMenu() {
        recentMenu.removeAllItems()
        let entries = commandLog.log.entries
        guard !entries.isEmpty else {
            let none = NSMenuItem(title: "No commands yet", action: nil, keyEquivalent: "")
            none.isEnabled = false
            recentMenu.addItem(none)
            return
        }
        for entry in entries {
            let item = NSMenuItem(title: CommandLogText.menuLine(entry), action: #selector(recentCommandChosen(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = entry.id.uuidString
            recentMenu.addItem(item)
        }
    }

    @objc private func recentCommandChosen(_ sender: NSMenuItem) {
        showLogs(selecting: (sender.representedObject as? String).flatMap(UUID.init(uuidString:)))
    }

    @objc private func viewLogs() { showLogs() }

    private func showLogs(selecting id: UUID? = nil) {
        let window = logWindow ?? LogWindowController(store: commandLog)
        logWindow = window
        window.show(selecting: id)
    }

    private static func logResolver(_ backend: EffectiveBackend) -> CommandLogEntry.Resolver {
        switch backend {
        case .claude: .claude
        case .local: .localModel
        case .off: .none
        }
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
        // A status check that lands after a switch away from the local model must not warm it.
        guard config.effectiveBackend == .local else { return }
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
            fileHasKey = (try? AppConfig.load(from: data, environment: [:]))?.anthropicAPIKey?.isEmpty == false
            // A count only: the words are never logged.
            if config.vocabulary.skipped > 0 {
                PipelineLog.warning("vocabulary: skipped \(config.vocabulary.skipped) entries (see docs/configuration.md)")
            }
            if fileHasKey,
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
                // The menu can switch backend while the speech model loads; remember which one the pipeline starts on.
                let builtBackend = config.effectiveBackend
                let resolver = makeResolver()
                let ax = AXQuery()
                // agent-desktop, when installed and permitted: the task loop observes and acts through it.
                let status = await probeHarness()
                let harness = status.makeHarness(config: config)
                pipelineHarnessKind = harness == nil ? .native : .agentDesktop
                PipelineLog.info("harness: \(status.text)")
                // Tasks observe, and the executor looks for a media player, with their own, larger AX budget:
                // Chrome's toolbar alone exhausts the default one.
                let taskAX = AXQuery(budget: .milliseconds(1000), maxNodes: 6000)
                self.taskAX = taskAX
                pipelineHarness = harness
                let executor = ActionExecutor(input: CGEventInputSynthesizer(), ax: ax, overlay: overlay, config: config,
                                              harness: harness, mediaAX: taskAX)
                let observer = ScreenObserver(ax: taskAX,
                                              maxElements: config.observedElementCap, harness: harness,
                                              snapshotTimeoutMs: config.agentDesktopSnapshotMs)
                let p = VoicePipeline(config: config, transcriber: transcriber, resolver: resolver,
                                      executor: executor, overlay: overlay, ax: ax, observer: observer, harness: harness,
                                      commandLog: commandLog)
                p.resolverKind = Self.logResolver(builtBackend)
                p.setPacks(packSet)
                p.onStatus = { [weak self] mode, transcript in self?.apply(mode: mode, transcript: transcript) }
                p.onNotice = { PipelineLog.info("notice: \($0)") }
                p.onError = { [weak self] message in self?.errorText = message; self?.refresh() }
                try await p.start()
                pipeline = p
                PipelineLog.info("intent backend: \(Self.backendName(builtBackend))")
                if config.effectiveBackend != builtBackend { switchPipelineBackend(p) }
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
