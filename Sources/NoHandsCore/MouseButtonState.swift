import Foundation

public enum MouseMoveKind: Equatable, Sendable {
    case moved
    case dragged(MouseButton)
}

/// Tracks which mouse button is held so moves can be posted as drags.
public struct MouseButtonState: Equatable, Sendable {
    public private(set) var heldButton: MouseButton?
    public init() {}

    public mutating func down(_ button: MouseButton) { heldButton = button }

    /// Releasing a button other than the held one is ignored.
    public mutating func up(_ button: MouseButton) {
        if heldButton == button { heldButton = nil }
    }

    public var moveKind: MouseMoveKind {
        heldButton.map { .dragged($0) } ?? .moved
    }
}
