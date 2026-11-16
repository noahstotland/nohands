import Testing
@testable import NoHandsCore

@Test func mediaCommandsRouteByWhatIsInFront() {
    let k = KeyChord(.k), f = KeyChord(.f)
    // (command, YouTube in a browser, another site in a browser, not a browser)
    let table: [(MediaCommand, MediaRoute.Step, MediaRoute.Step, MediaRoute.Step)] = [
        (.play, .siteKeys([k]), .systemKey(.playPause), .systemKey(.playPause)),
        (.pause, .siteKeys([k]), .systemKey(.playPause), .systemKey(.playPause)),
        (.next, .siteKeys([KeyChord(.n, [.shift])]), .systemKey(.next), .systemKey(.next)),
        (.previous, .siteKeys([KeyChord(.p, [.shift])]), .systemKey(.previous), .systemKey(.previous)),
        (.skip(seconds: 30), .siteKeys(Array(repeating: KeyChord(.l), count: 3)), .unsupported("skip works on YouTube only"),
         .unsupported("skip works on YouTube only")),
        (.skip(seconds: -25), .siteKeys(Array(repeating: KeyChord(.j), count: 3)), .unsupported("skip works on YouTube only"),
         .unsupported("skip works on YouTube only")),
        (.skip(seconds: 3), .siteKeys([KeyChord(.l)]), .unsupported("skip works on YouTube only"),
         .unsupported("skip works on YouTube only")),
        (.fullScreen, .siteKeys([f]), .windowFullScreen, .windowFullScreen),
        (.exitFullScreen, .exitFullScreen(siteEscape: true), .exitFullScreen(siteEscape: false), .exitFullScreen(siteEscape: false)),
    ]
    for (command, youTube, other, native) in table {
        #expect(MediaRoute.step(for: command, isBrowser: true, host: "www.youtube.com") == youTube, "\(command) on YouTube")
        #expect(MediaRoute.step(for: command, isBrowser: true, host: "example.com") == other, "\(command) elsewhere")
        #expect(MediaRoute.step(for: command, isBrowser: false, host: nil) == native, "\(command) outside a browser")
    }
    // A YouTube address in a non-browser app (a stale URL) is not a player; an unknown page host is not YouTube.
    #expect(MediaRoute.step(for: .play, isBrowser: false, host: "youtube.com") == .systemKey(.playPause))
    #expect(MediaRoute.step(for: .play, isBrowser: true, host: "notyoutube.com") == .systemKey(.playPause))
}
