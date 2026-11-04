import AppKit
import Foundation
import NoHandsCore
import NoHandsMac

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let transcriptItem = NSMenuItem(title: "No speech yet", action: nil, keyEquivalent: "")
    private let pauseItem = NSMenuItem(title: "Pause Listening", action: #selector(togglePause), keyEquivalent: "")
    private let accessibilityItem = NSMenuItem(title: "Grant Accessibility…", action: #selector(grantAccessibility), keyEquivalent: "")
    private let micItem = NSMenuItem(title: "Microphone denied — open Settings", action: #selector(openMicrophoneSettings), keyEquivalent: "")

    private let overlay = OverlayController()
    private var config = AppConfig()
    private var pipeline: VoicePipeline?
    private var pipelineStarting = false
    private var startFailed = false   // do not retry (and re-download) every poll after a failed start
    private var paused = false
    private var micGranted = false
    private var pollTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        Task { await bootstrap() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        pipeline?.stop()
    }

    // MARK: - menu

    private func buildMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "mic", accessibilityDescription: "NoHands")
            button.imagePosition = .imageLeading
            button.title = " CMD"
        }
        let menu = NSMenu()
        transcriptItem.isEnabled = false
        menu.addItem(transcriptItem)
        menu.addItem(.separator())
        pauseItem.target = self
        menu.addItem(pauseItem)
        accessibilityItem.target = self
        micItem.target = self
        menu.addItem(accessibilityItem)
        menu.addItem(micItem)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit NoHands", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        statusItem.menu = menu
        refreshPermissionItems()
    }

    private func refreshPermissionItems() {
        let axGranted = Permissions.accessibilityGranted(prompt: false)
        accessibilityItem.isHidden = axGranted
        // Red dot, normal text.
        let title = NSMutableAttributedString(string: "● ", attributes: [.foregroundColor: NSColor.systemRed])
        title.append(NSAttributedString(string: "Grant Accessibility…"))
        accessibilityItem.attributedTitle = title
        micItem.isHidden = Permissions.microphoneStatus() != .denied
        pauseItem.isHidden = pipeline == nil
    }

    private func apply(mode: Mode, transcript: String) {
        let label: String
        switch mode {
        case .command: label = "CMD"
        case .dictation: label = "DICT"
        case .sleep: label = "ZZZ"
        }
        statusItem.button?.title = " \(label)"
        if !transcript.isEmpty { transcriptItem.title = PipelineText.truncated(transcript) }
    }

    @objc private func togglePause() {
        guard let pipeline else { return }
        if paused {
            Task {
                do {
                    try await pipeline.resume()
                    paused = false
                    pauseItem.title = "Pause Listening"
                } catch {
                    print("resume failed: \(error)")
                    overlay.showHUD("microphone error")
                }
            }
        } else {
            pipeline.pause()
            paused = true
            pauseItem.title = "Resume Listening"
        }
    }

    @objc private func grantAccessibility() { Permissions.openAccessibilitySettings() }

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
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/nohands/config.json")
        let env = ProcessInfo.processInfo.environment
        let data = try? Data(contentsOf: url)   // missing file -> defaults
        do {
            config = try AppConfig.load(from: data, environment: env)
        } catch {
            // Never log file contents (they may hold the API key).
            print("config.json is not valid JSON (\(url.path)); using defaults")
            config = (try? AppConfig.load(from: nil, environment: env)) ?? AppConfig()
            overlay.showHUD("config.json invalid: using defaults", duration: .seconds(4))
        }
    }

    private func bootstrap() async {
        loadConfig()
        micGranted = await Permissions.requestMicrophone()
        _ = Permissions.accessibilityGranted(prompt: true)
        refreshPermissionItems()
        startPipelineIfReady()
        if pipeline == nil {
            pollTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.pollPermissions() }
            }
        }
    }

    private func pollPermissions() {
        if !micGranted { micGranted = Permissions.microphoneStatus() == .granted }
        refreshPermissionItems()
        startPipelineIfReady()
        if pipeline != nil || startFailed { pollTimer?.invalidate(); pollTimer = nil }
    }

    private func startPipelineIfReady() {
        guard pipeline == nil, !pipelineStarting, !startFailed, micGranted, Permissions.accessibilityGranted(prompt: false) else { return }
        pipelineStarting = true
        overlay.showHUD("loading speech model…", duration: .seconds(3))
        Task {
            defer { pipelineStarting = false }
            do {
                let transcriber = try await ParakeetTranscriber(version: config.asrModelVersion)
                let key = config.anthropicAPIKey ?? ""
                let resolver: (any IntentResolving)? = key.isEmpty ? nil : ClaudeIntentResolver(config: config)
                let ax = AXQuery()
                let executor = ActionExecutor(input: CGEventInputSynthesizer(), ax: ax, overlay: overlay, config: config)
                let p = VoicePipeline(config: config, transcriber: transcriber, resolver: resolver,
                                      executor: executor, overlay: overlay, ax: ax)
                p.onStatus = { [weak self] mode, transcript in self?.apply(mode: mode, transcript: transcript) }
                try await p.start()
                pipeline = p
                refreshPermissionItems()
                overlay.showHUD("NoHands is listening", duration: .seconds(2))
            } catch {
                startFailed = true
                print("failed to start pipeline: \(error)")
                overlay.showHUD("failed to start: \(error.localizedDescription)", duration: .seconds(5))
            }
        }
    }
}
