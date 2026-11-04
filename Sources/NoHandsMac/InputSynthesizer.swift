import Foundation
import CoreGraphics
import NoHandsCore

public enum InputSynthesisError: Error, CustomStringConvertible {
    case eventCreationFailed(String)
    public var description: String {
        switch self {
        case .eventCreationFailed(let what): "Could not create CGEvent: \(what)"
        }
    }
}

public protocol InputSynthesizing: Sendable {
    func type(_ text: String) throws
    func press(_ chord: KeyChord) throws
    func moveMouse(to point: CGPoint) throws
    func click(at point: CGPoint, button: MouseButton, count: Int) throws
    func mouseDown(_ button: MouseButton, at point: CGPoint) throws
    func mouseUp(_ button: MouseButton, at point: CGPoint) throws
    func scroll(_ direction: Direction, lines: Int) throws
    func currentMouseLocation() -> CGPoint
}

public struct CGEventInputSynthesizer: InputSynthesizing {
    public init() {}

    public func type(_ text: String) throws {
        let chunks = TextChunker.chunks(text)
        for (i, chunk) in chunks.enumerated() {
            let units = Array(chunk.utf16)
            for down in [true, false] {
                guard let e = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: down) else {
                    throw InputSynthesisError.eventCreationFailed("keyboard event for text chunk")
                }
                e.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
                e.post(tap: .cghidEventTap)
            }
            if i < chunks.count - 1 { Thread.sleep(forTimeInterval: 0.001) }
        }
    }

    public func press(_ chord: KeyChord) throws {
        var flags: CGEventFlags = []
        for m in chord.modifiers {
            switch m {
            case .command: flags.insert(.maskCommand)
            case .shift: flags.insert(.maskShift)
            case .option: flags.insert(.maskAlternate)
            case .control: flags.insert(.maskControl)
            case .function: flags.insert(.maskSecondaryFn)
            }
        }
        for down in [true, false] {
            guard let e = CGEvent(keyboardEventSource: nil, virtualKey: chord.key.keyCode, keyDown: down) else {
                throw InputSynthesisError.eventCreationFailed("key event for \(chord.key)")
            }
            e.flags = flags
            e.post(tap: .cghidEventTap)
        }
    }

    public func moveMouse(to point: CGPoint) throws {
        guard let e = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left) else {
            throw InputSynthesisError.eventCreationFailed("mouse move")
        }
        e.post(tap: .cghidEventTap)
    }

    public func click(at point: CGPoint, button: MouseButton, count: Int) throws {
        try moveMouse(to: point)
        for i in 1...max(1, count) {
            try post(button, down: true, at: point, clickState: i)
            try post(button, down: false, at: point, clickState: i)
        }
    }

    public func mouseDown(_ button: MouseButton, at point: CGPoint) throws {
        try post(button, down: true, at: point, clickState: 1)
    }

    public func mouseUp(_ button: MouseButton, at point: CGPoint) throws {
        try post(button, down: false, at: point, clickState: 1)
    }

    public func scroll(_ direction: Direction, lines: Int) throws {
        var v: Int32 = 0, h: Int32 = 0
        let n = Int32(clamping: lines)
        switch direction {
        case .up: v = n
        case .down: v = -n
        case .left: h = n
        case .right: h = -n
        }
        guard let e = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2, wheel1: v, wheel2: h, wheel3: 0) else {
            throw InputSynthesisError.eventCreationFailed("scroll wheel")
        }
        e.post(tap: .cghidEventTap)
    }

    public func currentMouseLocation() -> CGPoint {
        CGEvent(source: nil)?.location ?? .zero
    }

    private func post(_ button: MouseButton, down: Bool, at point: CGPoint, clickState: Int) throws {
        let type: CGEventType
        let cgButton: CGMouseButton
        switch button {
        case .left: type = down ? .leftMouseDown : .leftMouseUp; cgButton = .left
        case .right: type = down ? .rightMouseDown : .rightMouseUp; cgButton = .right
        case .middle: type = down ? .otherMouseDown : .otherMouseUp; cgButton = .center
        }
        guard let e = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: cgButton) else {
            throw InputSynthesisError.eventCreationFailed("mouse \(button) \(down ? "down" : "up")")
        }
        e.setIntegerValueField(.mouseEventClickState, value: Int64(clickState))
        e.post(tap: .cghidEventTap)
    }
}
