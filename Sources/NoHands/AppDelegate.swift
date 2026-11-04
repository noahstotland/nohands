import AppKit
import Foundation
import NoHandsCore
import NoHandsMac

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let stateItem = NSMenuItem(title: MenuState.loading.text, action: nil, keyEquivalent: "")
    private let configItem = NSMenuItem(title: "config.json invalid: using defaults", action: nil, keyEquivalent: "")
    private let transcriptItem = NSMenuItem(title: "No speech yet", action: nil, keyEquivalent: "")
    private let pauseItem = NSMenuItem(title: "Pause Listening", action: #selector(togglePause), keyEquivalent: "")
    private let retryItem = NSMenuItem(title: "Retry", action: #selector(retry), keyEquivalent: "")
    private let accessibilityItem = NSMenuItem(title: "Grant Accessibility…", action: #selector(grantAccessibility), keyEquivalent: "")
    private let micItem = NSMenuItem(title: "Microphone denied — open Settings", action: #selector(openMicrophoneSettings), keyEquivalent: "")

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
        statusItem.button?.image = NSImage(systemSymbolName: "mic", accessibilityDescription: "NoHands")
        statusItem.button?.imagePosition = .imageLeading

        let menu = NSMenu()
        stateItem.isEnabled = false
        configItem.isEnabled = false
        transcriptItem.isEnabled = false
        for item in [pauseItem, retryItem, accessibilityItem, micItem] { item.target = self }
        let title = NSMutableAttributedString(string: "● ", attributes: [.foregroundColor: NSColor.systemRed])
        title.append(NSAttributedString(string: "Grant Accessibility…"))
        accessibilityItem.attributedTitle = title
        let quit = NSMenuItem(title: "Quit NoHands", action: #selector(quit), keyEquivalent: "q")
        quit.target = self

        for item in [stateItem, configItem, NSMenuItem.separator(), transcriptItem, NSMenuItem.separator(),
                     pauseItem, retryItem, accessibilityItem, micItem, NSMenuItem.separator(), quit] {
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
        micItem.isHidden = !micDenied
        pauseItem.isHidden = pipeline == nil
        pauseItem.title = userPaused ? "Resume Listening" : "Pause Listening"
        statusItem.button?.title = " " + MenuState.title(mode: mode, paused: state == .paused)
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
                    PipelineLog.error("resume failed: \(error)")
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
                    PipelineLog.error("retry failed: \(error)")
                    errorText = "microphone failed"
                }
                refresh()
            }
        } else {
            startPipelineIfReady()
        }
        refresh()
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
                            PipelineLog.error("resume after Accessibility grant failed: \(error)")
                            errorText = "microphone failed"
                        }
                        refresh()
                    }
                }
            }
        } else {
            startPipelineIfReady()
        }
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
                let key = config.anthropicAPIKey ?? ""
                let resolver: (any IntentResolving)? = key.isEmpty ? nil : ClaudeIntentResolver(config: config)
                let ax = AXQuery()
                let executor = ActionExecutor(input: CGEventInputSynthesizer(), ax: ax, overlay: overlay, config: config)
                let p = VoicePipeline(config: config, transcriber: transcriber, resolver: resolver,
                                      executor: executor, overlay: overlay, ax: ax)
                p.onStatus = { [weak self] mode, transcript in self?.apply(mode: mode, transcript: transcript) }
                p.onNotice = { PipelineLog.info("notice: \($0)") }
                p.onError = { [weak self] message in self?.errorText = message; self?.refresh() }
                try await p.start()
                pipeline = p
                schedulePoll(every: 5)
                overlay.showHUD("NoHands is listening", duration: .seconds(2))
            } catch {
                PipelineLog.error("failed to start pipeline: \(error)")
                errorText = "start failed"
                overlay.showHUD("failed to start: \(error.localizedDescription)", duration: .seconds(5))
            }
        }
    }
}
