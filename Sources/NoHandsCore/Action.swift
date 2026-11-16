import Foundation
import CoreGraphics

public enum Mode: String, Codable, Sendable { case command, dictation, sleep }
public enum MouseButton: String, Codable, Sendable { case left, right, middle }
public enum Direction: String, Codable, Sendable { case up, down, left, right }

public enum ClickTarget: Equatable, Codable, Sendable {
    case cursor
    case numbered(Int)                       // grid cell, or label of the overlay currently shown; executor decides
    case label(Int)                          // label from an LLM request's element snapshot (never a grid cell)
    case element(named: String)
    case point(CGPoint)
}

public enum MoveTarget: Equatable, Codable, Sendable {
    case numbered(Int)
    case label(Int)
    case element(named: String)
    case point(CGPoint)
    case relative(dx: Int, dy: Int)
}

/// An element the harness acts on: a number from the request's element list, or a name looked up live.
public enum ElementTarget: Equatable, Codable, Sendable { case label(Int), named(String) }

/// What an agent-desktop `wait` blocks on.
public enum WaitCondition: Equatable, Codable, Sendable {
    case text(String), window(String), event(DesktopEvent), menu, menuClosed
    case element(ElementTarget, predicate: String)
    /// Media plays in the front window; polled by NoHands, not by agent-desktop.
    case mediaPlaying
}

/// Which tab "tab 3", "last tab" and "switch to the YouTube tab" mean: a position in the strip, the last tab, or words
/// of its title. Grammar only; positions here are the speaker's, not the model's `Tabs:` listing numbers.
public enum TabTarget: Equatable, Codable, Sendable { case number(Int), last, named(String) }

/// A media command by voice ("pause", "next track", "skip ahead 30 seconds"). Grammar only; the model has no kind for it.
public enum MediaCommand: Equatable, Codable, Sendable {
    case play, pause, playPause, next, previous, fullScreen, exitFullScreen
    /// Seconds to seek; negative goes back.
    case skip(seconds: Int)
}

/// A change to the system output volume ("volume 30 percent", "volume up", "mute"). Grammar only.
public enum VolumeChange: Equatable, Codable, Sendable {
    /// An absolute level, 0 to 100.
    case set(Int)
    /// A step in points, positive or negative.
    case by(Int)
    case mute(Bool)
}

public enum Action: Equatable, Codable, Sendable {
    case typeText(String)
    case pressKey(KeyChord)
    case click(ClickTarget, button: MouseButton, count: Int)
    case pressMouse(MouseButton)
    case releaseMouse(MouseButton)
    case moveCursor(MoveTarget)
    case scroll(Direction, amount: Int)
    case showGrid
    case zoomGrid(Int)
    case showLabels
    case hideOverlay
    case setMode(Mode)
    case openApp(String)
    /// Open a standard folder, a file or folder found by name, or the newest file of a kind (see `FileRequest`).
    case openFile(FileRequest)
    /// Open a web address in the default browser (`app` nil) or in the named browser.
    case openURL(URL, app: String?)
    /// Move and resize the frontmost app's focused window on its screen.
    case moveWindow(WindowPlacement)
    /// Search in the frontmost app or site: its own search box when it shows one, else the site's search
    /// page, else a browser's address bar.
    case search(String)
    /// Search for words on a named site: inside that site when it is the page in front, else its results page in
    /// the default browser. `site` is a `SiteSearch.templates` key ("youtube.com"), never free text.
    case searchSite(String, site: String)
    /// Scroll the focused window until text or an element with these words is on screen. `movePointer` leaves the
    /// pointer on the match (the voice command, so a bare "click" follows); the model's find never moves it.
    case findOnPage(String, movePointer: Bool)
    case wait(ms: Int)
    /// Report whether media is playing in the front window as a reading. Grammar only ("is it playing"); the
    /// model has no kind for it.
    case checkMedia
    case ignore

    // Harness actions (agent-desktop semantics; each has a native fallback or fails with "needs agent-desktop").
    case setValue(ElementTarget, String)
    case typeInto(ElementTarget, String)
    case clearField(ElementTarget)
    case selectOption(ElementTarget, String)
    /// nil toggles.
    case setChecked(ElementTarget, Bool?)
    case setExpanded(ElementTarget, Bool)
    case focusElement(ElementTarget)
    case scrollTo(ElementTarget)
    case scrollIn(ElementTarget, Direction, amount: Int)
    case drag(from: MoveTarget, to: MoveTarget)
    /// Click a named item in a surface (menubar, dock, sheet, …).
    case clickIn(DesktopSurface, name: String)
    /// Run a menu bar command by name ("Save As…" or "File > Save As…").
    case menuItem(String)
    case closeApp(String)
    case windowAction(DesktopWindowOp, app: String?, title: String?)
    case clipboardSet(String)
    case readClipboard
    /// Read the visible text of the focused window's page as a reading (`page: …`), for choosing between controls
    /// whose titles alone don't say which is the target. Native walk under either harness.
    case readPage
    case readValue(ElementTarget)
    case readNotifications
    case dismissNotifications(app: String?)
    case waitFor(WaitCondition, timeoutMs: Int)

    // Browser tabs and windows, by number from the request's `Tabs:` list (the task loop's pop-up cleanup).
    case closeTab(Int)
    case closeWindow(Int)
    case selectTab(Int)

    // Voice commands on the front browser's tabs. Grammar only ("tab 3", "close the other tabs", "list tabs"); the
    // model has no kind for them.
    case goToTab(TabTarget)
    case closeOtherTabs
    case listTabs

    /// Edit the focused text field by voice ("select the last sentence", "replace meeting with call"). Grammar only,
    /// like the tab commands: the model has no kind for it. `otherwise` is dictation's own words, typed when the edit
    /// names a phrase that is not in the field ("Delete the old files." still dictates); nil in command mode.
    case editText(TextEdit, otherwise: String?)
    /// Rewrite the selected text (else the last sentence before the caret) with the model and type the answer over it
    /// ("make that shorter", "translate that to French"). Grammar only: the model has no kind for it.
    case rewriteText(RewriteInstruction)
    // Voice commands for what is playing and the system volume. Grammar only; the model has no kind for them.
    case media(MediaCommand)
    case volume(VolumeChange)
    /// A system chore ("lock screen", "next space", "open bluetooth settings"). Grammar only; the model has no kind for it.
    case system(SystemCommand)

    /// Ask for a picture of the focused window on the next step. Only the task loop gives it meaning; anywhere
    /// else the executor runs it as a successful no-op.
    case look
}
