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
