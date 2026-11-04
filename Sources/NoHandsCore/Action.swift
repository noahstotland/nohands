import Foundation
import CoreGraphics

public enum Mode: String, Codable, Sendable { case command, dictation, sleep }
public enum MouseButton: String, Codable, Sendable { case left, right, middle }
public enum Direction: String, Codable, Sendable { case up, down, left, right }

public enum ClickTarget: Equatable, Codable, Sendable {
    case cursor
    case numbered(Int)                       // grid cell or label; executor decides
    case element(named: String)
    case point(CGPoint)
}

public enum MoveTarget: Equatable, Codable, Sendable {
    case numbered(Int)
    case element(named: String)
    case point(CGPoint)
    case relative(dx: Int, dy: Int)
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
    case ignore
}
