import Foundation
import NoHandsCore

/// Pure text helpers for the voice pipeline (HUD messages and the per-utterance log summary).
public enum PipelineText {
    public static let didntCatch = "didn't catch that"
    public static let llmOff = "LLM off: set ANTHROPIC_API_KEY"

    /// HUD text for a failed intent resolution; nil means show nothing (the request was cancelled).
    public static func hud(for error: IntentError) -> String? {
        switch error {
        case .cancelled: nil
        case .noAPIKey: llmOff
        case .network: "no network"
        case .timeout: "timed out"
        case .http(let code, _): "LLM error (\(code))"
        case .decode: didntCatch
        }
    }

    /// Short description of a routing decision for the one-line log.
    public static func summary(_ routing: Routing) -> String {
        switch routing {
        case .execute(let actions): "execute \(describe(actions))"
        case .resolveWithLLM: "llm"
        case .ignore(let reason): "ignore(\(reason))"
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
