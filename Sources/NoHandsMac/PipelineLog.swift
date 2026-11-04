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

    public static func warning(_ message: String) {
        logger.warning("\(message, privacy: .public)")
        if tty { print("WARNING: \(message)") }
    }

    public static func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
        if tty { print("ERROR: \(message)") }
    }

    /// `[asr=…ms total=…ms] <transcript> -> <outcome>`
    public static func utterance(trace: LatencyTrace, transcript: String, outcome: String) {
        logger.info("[\(trace.summary, privacy: .public)] \(transcript, privacy: .private) -> \(outcome, privacy: .public)")
        if tty { print(PipelineText.logLine(trace: trace, transcript: transcript, summary: outcome)) }
    }
}
