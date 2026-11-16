import Foundation
import AppKit
import CoreGraphics
import NoHandsCore
import os

public enum InputSynthesisError: Error, CustomStringConvertible {
    case eventCreationFailed(String)
    case invalidArgument(String)
    public var description: String {
        switch self {
        case .eventCreationFailed(let what): "Could not create CGEvent: \(what)"
        case .invalidArgument(let what): "Invalid argument: \(what)"
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
    /// The system play, next or previous key (a system-defined event, not a key code).
    func pressMediaKey(_ key: SystemMediaKey) throws
    /// nil when the pointer position cannot be read.
    func currentMouseLocation() -> CGPoint?
    /// Releases any mouse button this synthesizer is still holding down (safety net on pause/quit).
    func releaseAll()
}

public struct CGEventInputSynthesizer: InputSynthesizing {
    public init() {}

    private let buttons = OSAllocatedUnfairLock(initialState: MouseButtonState())

    private func postKeyPair(virtualKey: CGKeyCode, flags: CGEventFlags = [], unicode: [UniChar]? = nil, what: String) throws {
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: virtualKey, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: virtualKey, keyDown: false) else {
            throw InputSynthesisError.eventCreationFailed(what)
        }
        for e in [down, up] {
            if let unicode { e.keyboardSetUnicodeString(stringLength: unicode.count, unicodeString: unicode) }
            e.flags = flags
        }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    public func type(_ text: String) throws {
        var needsPause = false
        for segment in TextSegmenter.segments(text) {
            switch segment {
            case .key(let key):
                if needsPause { Thread.sleep(forTimeInterval: 0.001) }
                try postKeyPair(virtualKey: key.keyCode, what: "key event for \(key)")
                needsPause = true
            case .text(let str):
                for chunk in TextChunker.deliveryChunks(str) {
                    if needsPause { Thread.sleep(forTimeInterval: 0.001) }
                    try postKeyPair(virtualKey: 0, unicode: Array(chunk.utf16), what: "keyboard event for text chunk")
                    needsPause = true
                }
            }
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
        try postKeyPair(virtualKey: chord.key.keyCode, flags: flags, what: "key event for \(chord.key)")
    }

    public func pressMediaKey(_ key: SystemMediaKey) throws {
        // NX_KEYTYPE_PLAY 16, NEXT 17, PREVIOUS 18; subtype 8 is a media key; 0xA00 is key down, 0xB00 key up.
        let code: Int
        switch key {
        case .playPause: code = 16
        case .next: code = 17
        case .previous: code = 18
        }
        for down in [true, false] {
            let state = down ? 0xA00 : 0xB00
            guard let event = NSEvent.otherEvent(with: .systemDefined, location: .zero,
                                                 modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(state)), timestamp: 0,
                                                 windowNumber: 0, context: nil, subtype: 8,
                                                 data1: (code << 16) | state, data2: -1),
                  let cgEvent = event.cgEvent else {
                throw InputSynthesisError.eventCreationFailed("media key \(key)")
            }
            cgEvent.post(tap: .cghidEventTap)
        }
    }

    public func moveMouse(to point: CGPoint) throws {
        let type: CGEventType
        let button: CGMouseButton
        switch buttons.withLock({ $0.moveKind }) {
        case .moved: type = .mouseMoved; button = .left
        case .dragged(.left): type = .leftMouseDragged; button = .left
        case .dragged(.right): type = .rightMouseDragged; button = .right
        case .dragged(.middle): type = .otherMouseDragged; button = .center
        }
        guard let e = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: button) else {
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
        buttons.withLock { $0.down(button) }
    }

    public func mouseUp(_ button: MouseButton, at point: CGPoint) throws {
        // Clear held state first so a failed event creation can never leave a stale drag.
        buttons.withLock { $0.up(button) }
        try post(button, down: false, at: point, clickState: 1)
    }

    public func scroll(_ direction: Direction, lines: Int) throws {
        guard lines >= 0 else { throw InputSynthesisError.invalidArgument("negative scroll amount \(lines)") }
        guard lines > 0 else { return }
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

    public func currentMouseLocation() -> CGPoint? {
        CGEvent(source: nil)?.location
    }

    public func releaseAll() {
        guard let held = buttons.withLock({ state -> MouseButton? in
            let h = state.heldButton
            state = MouseButtonState()
            return h
        }) else { return }
        try? post(held, down: false, at: currentMouseLocation() ?? .zero, clickState: 1)
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
