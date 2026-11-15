import Foundation
import os
import NoHandsCore

/// Unified logging (visible with `log stream` even when launched via `open`). Transcripts are `.private`;
/// everything else is `.public`. When stdout is a terminal, lines are mirrored with `print` (unredacted).
public enum PipelineLog {
    private static let logger = Logger(subsystem: "dev.nohands.app", category: "pipeline")
    private static let tty = isatty(1) != 0

    public static func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
        if tty { print(message) }
    }

    /// `detail` (page text, which may hold anything on screen) is logged `.private`.
    public static func info(_ message: String, detail: String) {
        logger.info("\(message, privacy: .public) \(detail, privacy: .private)")
        if tty { print("\(message) \(detail)") }
    }

    /// `detail` (error descriptions, which may contain names or text) is logged `.private`.
    public static func warning(_ message: String, detail: String = "") {
        logger.warning("\(message, privacy: .public) \(detail, privacy: .private)")
        if tty { print("WARNING: \(message) \(detail)") }
    }

    public static func error(_ message: String, detail: String = "") {
        logger.error("\(message, privacy: .public) \(detail, privacy: .private)")
        if tty { print("ERROR: \(message) \(detail)") }
    }

    /// `[asr=…ms total=…ms] <transcript> -> <outcome>`. `outcome` is payload-free (public); `detail` carries
    /// the full human-readable outcome and is private. The terminal mirror prints the detailed line.
    public static func utterance(trace: LatencyTrace, transcript: String, outcome: String, detail: String) {
        logger.info("[\(trace.summary, privacy: .public)] \(transcript, privacy: .private) -> \(outcome, privacy: .public) | \(detail, privacy: .private)")
        if tty { print(PipelineText.logLine(trace: trace, transcript: transcript, summary: detail)) }
    }
}
