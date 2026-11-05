import Foundation

/// Whether media is playing in the front window, as the task loop's observation reports it.
public enum MediaState: String, Codable, Sendable, CaseIterable { case playing, paused, none }

/// A player control read from one element: the button that would pause (so media is playing) or play.
public enum MediaControl: Equatable, Sendable { case play, pause }

/// Pure rules for telling from the screen and the audio hint whether a video or song is playing.
public enum MediaSignal {
    private static let controlRoles: Set<String> = ["button", "checkbox", "toggle", "switch"]
    private static let pauseNames: Set<String> = ["pause", "pause video", "pause button"]
    private static let playNames: Set<String> = ["play", "play video", "play button"]
    private static let toggleNames: Set<String> = ["play/pause", "play pause", "playpause", "play-pause"]
    /// A trailing shortcut hint: "Pause (k)", "Play (space)".
    private static let trailingParenthetical = try! NSRegularExpression(pattern: #"\s*\([^()]*\)\s*$"#)

    /// The player control this element is, or nil. Only button-like roles count, and the name must match exactly
    /// (after dropping a trailing "(k)" shortcut and surrounding punctuation), so "Play all" and "Playlist" are not
    /// controls. A play/pause toggle reads its value: `playing` is a pause control, `paused` a play control.
    public static func control(role: String, name: String, value: String? = nil) -> MediaControl? {
        var r = role.lowercased()
        if r.hasPrefix("ax") { r.removeFirst(2) }
        guard controlRoles.contains(r) else { return nil }
        var n = name.lowercased()
        n = trailingParenthetical.stringByReplacingMatches(
            in: n, range: NSRange(n.startIndex..., in: n), withTemplate: "")
        n = n.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        if pauseNames.contains(n) { return .pause }
        if playNames.contains(n) { return .play }
        guard toggleNames.contains(n) else { return nil }
        switch value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "playing": return .pause
        case "paused": return .play
        default: return nil
        }
    }

    /// Controls in the focused window speak for that window; audio speaks for the whole Mac, so it counts only
    /// when no control was found.
    public static func state(controls: [MediaControl], audioPlaying: Bool) -> MediaState {
        if controls.contains(.pause) { return .playing }
        if controls.contains(.play) { return .paused }
        return audioPlaying ? .playing : .none
    }

    /// The state for a window's elements. `audioPlaying` is asked only when no element is a player control.
    public static func state(elements: [UIElementInfo], audioPlaying: () -> Bool) -> MediaState {
        let controls = elements.compactMap { control(role: $0.role, name: $0.title, value: $0.value) }
        return state(controls: controls, audioPlaying: controls.isEmpty && audioPlaying())
    }

    private static let playWords: Set<String> = ["play", "watch", "listen"]

    /// Whether the goal asks for something to play: the words play, watch or listen, or "turn on" / "put on" with up
    /// to two words between ("turn the video on"). Whole words only: "display" and "replay" do not count.
    public static func wantsPlayback(goal: String) -> Bool {
        let words = goal.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        for (i, w) in words.enumerated() {
            if playWords.contains(w) { return true }
            if w == "turn" || w == "put", words[(i + 1)...].prefix(3).contains("on") { return true }
        }
        return false
    }
}
