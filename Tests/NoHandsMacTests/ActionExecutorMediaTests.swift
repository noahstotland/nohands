import Testing
import CoreGraphics
import NoHandsCore
@testable import NoHandsMac

/// An executor with fakes for the media paths: `playing` is the sound hint, `youTube` puts a browser on YouTube.
@MainActor private func media(playing: Bool = false, youTube: Bool = false)
    -> (ActionExecutor, FakeInput, FakeElements, FakeOverlay, FakeVolume) {
    let i = FakeInput(), e = FakeElements(), o = FakeOverlay(), v = FakeVolume(), a = FakeAudio()
    a.playing = playing
    if youTube { e.isBrowser = true; e.url = "https://www.youtube.com/watch?v=abc" }
    let x = ActionExecutor(input: i, ax: e, overlay: o, config: AppConfig(), audio: a, volume: v, fullScreenSettle: .zero)
    return (x, i, e, o, v)
}

@MainActor @Test func playAndPauseNeverToggleToTheOpposite() async {
    // (command, sound playing, expected system keys, expected notice)
    let table: [(MediaCommand, Bool, [SystemMediaKey], String?)] = [
        (.pause, false, [], "nothing is playing"), (.pause, true, [.playPause], nil),
        (.play, true, [], "already playing"), (.play, false, [.playPause], nil),
        (.playPause, true, [.playPause], nil), (.playPause, false, [.playPause], nil),
    ]
    for (command, playing, keys, notice) in table {
        let (x, i, _, o, _) = media(playing: playing)
        #expect(await x.execute([.media(command)]) == nil, "\(command) \(playing)")
        #expect(i.mediaKeys == keys && i.chords.isEmpty, "\(command) \(playing)")
        #expect(o.huds == (notice.map { [$0] } ?? []), "\(command) \(playing)")
    }
}

@MainActor @Test func youTubeKeysNeedThePageFocusedNotATextBox() async {
    let (x, i, _, _, _) = media(youTube: true)
    #expect(await x.execute([.media(.playPause), .media(.skip(seconds: -20)), .media(.fullScreen)]) == nil)
    #expect(i.chords.map(\.key) == [.k, .j, .j, .f] && i.mediaKeys.isEmpty)

    // A search box has focus: play falls back to the system key, anything else fails and presses nothing.
    let (y, j, f, _, _) = media(youTube: true)
    f.textFocused = true
    #expect(await y.execute([.media(.playPause)]) == nil)
    #expect(j.mediaKeys == [.playPause] && j.chords.isEmpty)
    for command in [MediaCommand.fullScreen, .next, .skip(seconds: 10)] {
        #expect(await y.execute([.media(command)]) == "a text box has focus: click the video first")
    }
    #expect(j.chords.isEmpty)

    // Off YouTube a skip is refused; next goes to the system key.
    let (z, k, _, _, _) = media()
    #expect(await z.execute([.media(.skip(seconds: 10))]) == "skip works on YouTube only")
    #expect(await z.execute([.media(.next)]) == nil && k.mediaKeys == [.next] && k.chords.isEmpty)
}

@MainActor @Test func exitFullScreenPressesOnlyFromFullScreen() async {
    let escape = KeyChord(.escape), window = KeyChord(.f, [.command, .control])
    // (window full screen, on YouTube, full screen after Escape, expected chords)
    let table: [(Bool?, Bool, Bool?, [KeyChord])] = [
        (false, true, nil, []), (nil, false, nil, []), (true, true, false, [escape]),
        (true, true, nil, [escape, window]), (true, false, nil, [window]),
    ]
    for (fullScreen, youTube, after, chords) in table {
        let (x, i, e, o, _) = media(youTube: youTube)
        e.fullScreen = fullScreen; e.fullScreenAfterFirstRead = after
        #expect(await x.execute([.media(.exitFullScreen)]) == nil)
        #expect(i.chords == chords, "\(String(describing: fullScreen)) \(youTube)")
        #expect(o.huds == (chords.isEmpty ? ["not in full screen"] : []))
    }
    // Off YouTube, "full screen video" in a full screen window does nothing instead of leaving it.
    let (x, i, e, o, _) = media()
    e.fullScreen = true
    #expect(await x.execute([.media(.fullScreen)]) == nil && i.chords.isEmpty && o.huds == ["already full screen"])
    e.fullScreen = false
    #expect(await x.execute([.media(.fullScreen)]) == nil && i.chords == [window])
}

@MainActor @Test func volumeChangesClampUnmuteAndFailWithoutAControl() async {
    // (change, level before, level set, notice)
    let table: [(VolumeChange, Int, Int, String)] = [
        (.set(40), 90, 40, "volume 40%"), (.by(-30), 20, 0, "volume 0%"), (.by(10), 95, 100, "volume 100%"),
    ]
    for (change, before, after, notice) in table {
        let (x, _, _, o, v) = media()
        v.current = before; v.muted = true
        #expect(await x.execute([.volume(change)]) == nil)
        #expect(v.set == [after] && o.huds == [notice])
        #expect(v.muted == (after == 0), "a level above 0 unmutes")
    }
    let (x, _, _, o, v) = media()
    #expect(await x.execute([.volume(.mute(true))]) == nil && v.muted && v.set.isEmpty && o.huds == ["muted"])
    #expect(await x.execute([.volume(.mute(false))]) == nil && !v.muted && o.huds.last == "volume 50%")
    v.canMute = false
    #expect(await x.execute([.volume(.mute(true))]) == "this speaker can't be muted")
    v.current = nil
    #expect(await x.execute([.volume(.set(30))]) == "this speaker has no volume control")
}
