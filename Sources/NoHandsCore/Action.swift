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
    /// Open a web address in the default browser (`app` nil) or in the named browser.
    case openURL(URL, app: String?)
    /// Move and resize the frontmost app's focused window on its screen.
    case moveWindow(WindowPlacement)
    /// Search in the frontmost app or site: its own search box when it shows one, else the site's search
    /// page, else a browser's address bar.
    case search(String)
    case wait(ms: Int)
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
    case readValue(ElementTarget)
    case readNotifications
    case dismissNotifications(app: String?)
    case waitFor(WaitCondition, timeoutMs: Int)
}
