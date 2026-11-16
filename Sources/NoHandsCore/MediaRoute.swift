import Foundation

/// The system play, next and previous keys: system-defined events, not key codes.
public enum SystemMediaKey: Equatable, Sendable { case playPause, next, previous }

/// Which input a media command becomes, from what is in front. Pure: the executor reads the facts and runs the step.
public enum MediaRoute {
    public enum Step: Equatable, Sendable {
        /// Keys for the page's own player (YouTube); the page must have focus.
        case siteKeys([KeyChord])
        case systemKey(SystemMediaKey)
        /// The window's full screen chord.
        case windowFullScreen
        /// Leave full screen, only when the focused window is in it. `siteEscape` presses escape (YouTube) instead of the
        /// window chord.
        case exitFullScreen(siteEscape: Bool)
        case unsupported(String)
    }

    /// Seconds one `j` or `l` press moves YouTube.
    static let secondsPerPress = 10

    public static func step(for command: MediaCommand, isBrowser: Bool, host: String?) -> Step {
        let youTube = isBrowser && host.map { SitePlaybooks.youTubeHosts.contains($0.lowercased()) } == true
        switch command {
        case .play, .pause, .playPause: return youTube ? .siteKeys([KeyChord(.k)]) : .systemKey(.playPause)
        case .next: return youTube ? .siteKeys([KeyChord(.n, [.shift])]) : .systemKey(.next)
        case .previous: return youTube ? .siteKeys([KeyChord(.p, [.shift])]) : .systemKey(.previous)
        case .skip(let seconds):
            guard youTube else { return .unsupported("skip works on YouTube only") }
            let presses = max(1, Int((Double(abs(seconds)) / Double(secondsPerPress)).rounded()))
            return .siteKeys(Array(repeating: KeyChord(seconds < 0 ? .j : .l), count: presses))
        case .fullScreen: return youTube ? .siteKeys([KeyChord(.f)]) : .windowFullScreen
        case .exitFullScreen: return .exitFullScreen(siteEscape: youTube)
        }
    }
}
