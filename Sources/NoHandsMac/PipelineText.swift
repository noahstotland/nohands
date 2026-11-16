import Foundation
import NoHandsCore

/// Pure text helpers for the voice pipeline (HUD messages and the per-utterance log summary).
public enum PipelineText {
    public static let didntCatch = "didn't catch that"
    public static let localNotRunning = "local model not running: start Ollama"
    public static let localNotDownloaded = "local model not downloaded: see the NoHands menu"
    public static let llmDisabled = "LLM off (intentBackend is off)"
    public static let llmOff = "LLM off: choose Set Claude API key… in the menu"
    public static let stopped = "stopped"
    public static let skippedBusy = "skipped (busy)"
    /// A held utterance discarded by a stop, or one that waited longer than the held-job limit.
    public static let dropped = "dropped"
    public static let cancelled = "cancelled"
    public static let stopping = "stopping the task"
    public static let rewriting = "rewriting…"

    /// The finish HUD for a task.
    public static func hud(for outcome: TaskOutcome) -> String {
        switch outcome {
        case .done(let intent): intent.isEmpty ? "done" : "done · \(intent)"
        case .stuck(let reason): "stuck: \(reason)"
        case .ignored: didntCatch
        case .stopped: stopped
        case .failed(let message): message
        }
    }

    /// HUD text for a failed intent resolution; nil means show nothing (the request was cancelled).
    public static func hud(for error: IntentError) -> String? {
        switch error {
        case .cancelled: nil
        case .noAPIKey: llmOff
        case .network: "no network"
        case .timeout: "timed out"
        case .http(let code, _): "LLM error (\(code))"
        case .decode: didntCatch
        case .localUnavailable: localNotRunning
        case .modelMissing: localNotDownloaded
        }
    }

    /// Short description of a routing decision for the one-line log.
    /// `detailed: false` (the default) is payload-free and safe for public logs; `true` includes payloads
    /// (typed text, element and app names) and belongs only in private log fields or a terminal.
    public static func summary(_ routing: Routing, detailed: Bool = false) -> String {
        switch routing {
        case .execute(let actions): "execute \(detailed ? describe(actions) : ActionSummary.kinds(actions))"
        case .resolveWithLLM: "llm"
        case .ignore(let reason): "ignore(\(reason))"
        case .reject(let message): detailed ? "reject(\(message))" : "reject"
        }
    }

    public static func describe(_ actions: [Action]) -> String {
        let text = actions.map { String(describing: $0) }.joined(separator: ", ")
        return "[\(text.count > 160 ? String(text.prefix(160)) + "…" : text)]"
    }

    /// The one-line latency record: `[asr=…ms total=…ms] <transcript> -> <summary>`.
    public static func logLine(trace: LatencyTrace, transcript: String, summary: String) -> String {
        "[\(trace.summary)] \(transcript) -> \(summary)"
    }

    /// Truncates for the menu: at most `limit` characters, with an ellipsis when cut.
    public static func truncated(_ text: String, limit: Int = 60) -> String {
        text.count <= limit ? text : String(text.prefix(limit - 1)) + "…"
    }
}
