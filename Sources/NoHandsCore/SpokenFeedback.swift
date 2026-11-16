import Foundation

/// How much NoHands says out loud: nothing, a task's finish line, or also questions and readings.
public enum SpeakLevel: String, Codable, Sendable, CaseIterable { case off, outcomes, all }

/// Logic behind the Speak Feedback submenu: the config patch.
public enum SpeakMenu {
    /// `existing` (nil means no file, treated as `{}`) with `speakFeedback` set to `level` and nothing else changed.
    public static func merged(existing: Data?, level: SpeakLevel) throws -> Data {
        try ConfigPatch.merged(existing: existing, key: "speakFeedback", value: level.rawValue)
    }
}

/// What the pipeline asks NoHands to say. Questions and confirms are `.running` strings on the board, and whether a
/// line holds private text is not in the status, so the speech function takes this instead of a bare `PromptStatus`.
public enum FeedbackCue: Equatable, Sendable {
    /// A task-slot row (model task, macro, rewrite) reported this status. `carriesPrivateText`: the detail may hold
    /// text the user did not say: the task read something, or it is a rewrite.
    case status(PromptStatus, carriesPrivateText: Bool)
    /// The board's question text.
    case question(String)
    case confirm(verb: String)
}

/// The words NoHands says for a cue at a level, or nil for silence.
public enum SpokenFeedback {
    public static let maxSpoken = 300

    public static func line(for cue: FeedbackCue, level: SpeakLevel) -> String? {
        guard level != .off else { return nil }
        switch cue {
        case let .status(status, carriesPrivateText):
            switch status {
            case let .done(detail):
                if carriesPrivateText && level != .all { return "Done." }
                return speakable(detail, terminator: ".")
            case let .failed(detail):
                if carriesPrivateText && level != .all {
                    return detail.lowercased().hasPrefix("stuck") ? "Stuck." : "Failed."
                }
                return speakable(detail, terminator: ".")
            case .listening, .heard, .running, .held, .stopped, .dropped, .ignored:
                return nil
            }
        case let .question(text):
            return level == .all ? speakable(text, terminator: "?") : nil
        case let .confirm(verb):
            guard level == .all else { return nil }
            return speakable("say yes to \(verb)", terminator: ".")
        }
    }

    /// The board's wording made speakable: step counts removed, " · " read as ": ", "…" dropped, whitespace
    /// collapsed, first letter capitalized, a terminator added, cut on a word boundary. Empty is nil.
    static func speakable(_ text: String, terminator: Character) -> String? {
        var s = text
            .replacingOccurrences(of: #"\s*\(\d+ steps?\)\s*$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s*·\s*\d+ steps?\s*$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: " · ", with: ": ")
            .replacingOccurrences(of: "…", with: "")
        s = s.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        if s.count >= maxSpoken {
            // Leave room for the terminator, and never end in the middle of a word.
            let cut = s.prefix(maxSpoken - 1)
            let midWord = !s[cut.endIndex].isWhitespace
            s = String(cut)
            if midWord, let space = s.lastIndex(of: " ") { s = String(s[..<space]) }
            s = s.trimmingCharacters(in: CharacterSet(charactersIn: " ,;:"))
        }
        guard let first = s.first else { return nil }
        s = first.uppercased() + s.dropFirst()
        if let last = s.last, !".!?".contains(last) { s.append(terminator) }
        return s
    }
}
