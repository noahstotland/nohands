import Foundation
import AppKit
import ApplicationServices
import NoHandsCore

/// The focused text field as the text-editing commands need it. Offsets are UTF-16, the unit Accessibility uses.
/// The value is the user's own text: it goes to Core's range maths and nowhere else, never into a log line.
public struct FocusedText: Equatable, Sendable {
    public var value: String
    public var selection: TextSpan
    /// The line the caret is on, when the field reports it.
    public var line: TextSpan?
    /// Whether the field accepts a new selection range (some web editors do not).
    public var rangeSettable: Bool

    public init(value: String, selection: TextSpan, line: TextSpan? = nil, rangeSettable: Bool = true) {
        self.value = value
        self.selection = selection
        self.line = line
        self.rangeSettable = rangeSettable
    }
}

/// The keyboard chords that do a text edit when the field cannot be read or its range cannot be set. Only edits with a
/// plain keyboard equivalent have one: sentences, phrases and case changes do not.
enum TextEditChords {
    static let selectWord = [KeyChord(.left, [.option]), KeyChord(.right, [.option, .shift])]
    static let selectLastWord = [KeyChord(.left, [.option, .shift])]
    static let selectLine = [KeyChord(.left, [.command]), KeyChord(.right, [.command, .shift])]
    static let selectParagraph = [KeyChord(.up, [.option]), KeyChord(.down, [.option, .shift])]

    /// The chords that select `unit` (the last one before the caret with `last`); nil when there is no such chord.
    static func select(_ unit: TextUnit, last: Bool) -> [KeyChord]? {
        switch (unit, last) {
        case (.word, false): selectWord
        case (.word, true): selectLastWord
        case (.line, false): selectLine
        case (.paragraph, false): selectParagraph
        default: nil
        }
    }

    /// The chord that moves the caret to `place`.
    static func caret(_ place: CaretPlace) -> KeyChord {
        switch place {
        case .lineStart: KeyChord(.left, [.command])
        case .lineEnd: KeyChord(.right, [.command])
        case .documentStart: KeyChord(.up, [.command])
        case .documentEnd: KeyChord(.down, [.command])
        }
    }
}

extension AXQuery {
    /// A field longer than this (UTF-16 units) counts as unreadable: the maths and the read are not worth it.
    static let maxFieldUnits = 200_000
    /// How long reading the focused field may take in all.
    static let fieldReadBudget: Duration = .milliseconds(500)

    private static let textRoles: Set<String> = ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"]

    private func focusedElement(timeout: Float = 0.05) -> AXUIElement? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let appEl = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(appEl, timeout)
        guard let el = Self.element(appEl, kAXFocusedUIElementAttribute) else { return nil }
        AXUIElementSetMessagingTimeout(el, timeout)
        return el
    }

    /// True when the frontmost app's focused element takes typed text: a text field, text area, search field or combo
    /// box, or something inside an editable web region. A password field never counts.
    public func isTextFocused() -> Bool {
        guard let el = focusedElement() else { return false }
        if Self.string(el, kAXSubroleAttribute) == "AXSecureTextField" { return false }
        if let role = Self.string(el, kAXRoleAttribute), Self.textRoles.contains(role) { return true }
        return Self.attr(el, "AXEditableAncestor") != nil
    }

    private static func range(of value: CFTypeRef?) -> CFRange? {
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        guard AXValueGetValue(value as! AXValue, .cfRange, &range) else { return nil }
        return range
    }

    /// The focused field's text, selection and caret line. nil when there is no focused field, it is a password field,
    /// the value is not a string, it is over `maxFieldUnits`, or the read passes its `fieldReadBudget`.
    public func focusedText() -> FocusedText? {
        let deadline = ContinuousClock.now.advanced(by: Self.fieldReadBudget)
        func remaining() -> Float? {
            let left = ContinuousClock.now.duration(to: deadline)
            guard left > .zero else { return nil }
            let c = left.components
            return Float(Double(c.seconds) + Double(c.attoseconds) / 1e18)
        }
        guard let first = remaining(), let el = focusedElement(timeout: first),
              Self.string(el, kAXSubroleAttribute) != "AXSecureTextField" else { return nil }
        guard let t = remaining() else { return nil }
        AXUIElementSetMessagingTimeout(el, t)
        guard let value = Self.attr(el, kAXValueAttribute) as? String, (value as NSString).length <= Self.maxFieldUnits,
              let t2 = remaining() else { return nil }
        AXUIElementSetMessagingTimeout(el, t2)
        guard let sel = Self.range(of: Self.attr(el, kAXSelectedTextRangeAttribute)), sel.location >= 0, sel.length >= 0,
              sel.location + sel.length <= (value as NSString).length else { return nil }
        var line: TextSpan?
        if let t3 = remaining() {
            AXUIElementSetMessagingTimeout(el, t3)
            if let n = Self.attr(el, kAXInsertionPointLineNumberAttribute) as? Int {
                var out: CFTypeRef?
                if AXUIElementCopyParameterizedAttributeValue(el, kAXRangeForLineParameterizedAttribute as CFString, n as CFNumber, &out) == .success,
                   let r = Self.range(of: out), r.location >= 0, r.length >= 0 {
                    line = TextSpan(location: r.location, length: r.length)
                }
            }
        }
        var settable: DarwinBoolean = false
        let canSet = AXUIElementIsAttributeSettable(el, kAXSelectedTextRangeAttribute as CFString, &settable) == .success && settable.boolValue
        return FocusedText(value: value, selection: TextSpan(location: sel.location, length: sel.length), line: line, rangeSettable: canSet)
    }

    /// Selects `span` in the focused field and reads the selection back: true only when the field took it.
    public func setSelection(_ span: TextSpan) -> Bool {
        guard let el = focusedElement(timeout: 0.5) else { return false }
        var settable: DarwinBoolean = false
        guard AXUIElementIsAttributeSettable(el, kAXSelectedTextRangeAttribute as CFString, &settable) == .success,
              settable.boolValue else { return false }
        var range = CFRange(location: span.location, length: span.length)
        guard let value = AXValueCreate(.cfRange, &range),
              AXUIElementSetAttributeValue(el, kAXSelectedTextRangeAttribute as CFString, value) == .success,
              let now = Self.range(of: Self.attr(el, kAXSelectedTextRangeAttribute)) else { return false }
        return now.location == span.location && now.length == span.length
    }
}
