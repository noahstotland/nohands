import Foundation
import NoHandsCore

/// What a text edit does once Core has found its range.
private enum EditPlan {
    case select(TextSpan), caret(TextSpan), delete(TextSpan), replace(TextSpan, with: String)

    var span: TextSpan {
        switch self {
        case .select(let s), .caret(let s), .delete(let s), .replace(let s, _): s
        }
    }
}

private enum EditResolution {
    case plan(EditPlan)
    /// The words the speaker named are not in the field.
    case notFound(String)
    case failed(String)
}

extension ActionExecutor {
    static let noTextField = "no text field: click into one first"
    static let unreadableField = "can't read the text here: select it by hand or say \"select line\""

    /// Edits the focused text field by voice. The field is read off the main actor; Core finds the range; the field
    /// selects it (checked by reading it back) and the change is typed or deleted, which keeps the app's own undo. A
    /// field that cannot be read or will not take the range falls back to keyboard chords where one exists. Field
    /// text stays in this function and Core: it is never logged, and failure messages carry only the speaker's words.
    func editText(_ edit: TextEdit, otherwise: String?) async throws -> String? {
        editTypedOtherwise = false
        let ax = self.ax
        let readsText: Bool
        if case .caret = edit { readsText = false } else { readsText = true }
        let read = await Task.detached { () -> (focused: Bool, text: FocusedText?) in
            guard ax.isTextFocused() else { return (false, nil) }
            return (true, readsText ? ax.focusedText() : nil)
        }.value
        // A spoken stop during the read must win: nothing below acts once the task is cancelled.
        if Task.isCancelled { return Self.cancelled }
        guard read.focused else { return Self.noTextField }
        if case .caret(let place) = edit {
            try input.press(TextEditChords.caret(place))
            hideStaleOverlay()
            return nil
        }
        guard let text = read.text, text.rangeSettable else {
            PipelineLog.info("edit: field not readable or range not settable, using keys")
            return try await editWithKeys(edit, otherwise: otherwise)
        }
        let plan: EditPlan
        switch Self.resolve(edit, in: text) {
        case .plan(let p): plan = p
        case .failed(let message): return message
        case .notFound(let words):
            if let otherwise { return try typeInstead(otherwise) }
            return "no \"\(words)\" in the text"
        }
        let span = plan.span
        let took = await Task.detached { ax.setSelection(span) }.value
        if Task.isCancelled { return Self.cancelled }
        guard took else {
            PipelineLog.info("edit: the field did not take the selection, using keys")
            return try await editWithKeys(edit, otherwise: otherwise)
        }
        switch plan {
        case .select, .caret: break
        case .delete: try input.press(KeyChord(.delete))
        case .replace(_, let typed):
            guard typed.count <= Self.maxTypedCharacters else { return "text too long" }
            try input.type(typed)
        }
        hideStaleOverlay()
        return nil
    }

    /// The same edit by keyboard chords, for a field that cannot be read or will not take a range. Sentences, phrases
    /// and case changes have no chord: they fail with the next step, except that dictation types its own words.
    private func editWithKeys(_ edit: TextEdit, otherwise: String?) async throws -> String? {
        if Task.isCancelled { return Self.cancelled }
        switch edit {
        case .select(let unit, let last), .delete(let unit, let last):
            guard let chords = TextEditChords.select(unit, last: last) else { break }
            for chord in chords { try input.press(chord) }
            if case .delete = edit { try input.press(KeyChord(.delete)) }
            hideStaleOverlay()
            return nil
        default: break
        }
        if let otherwise { return try typeInstead(otherwise) }
        return Self.unreadableField
    }

    /// Dictation's phrase edit with no phrase to act on: the words are typed as ordinary dictation.
    private func typeInstead(_ words: String) throws -> String? {
        guard words.count <= Self.maxTypedCharacters else { return "text too long" }
        try input.type(words)
        editTypedOtherwise = true
        hideStaleOverlay()
        return nil
    }

    private static func slice(_ value: String, _ span: TextSpan) -> String {
        (value as NSString).substring(with: NSRange(location: span.location, length: span.length))
    }

    private static func resolve(_ edit: TextEdit, in text: FocusedText) -> EditResolution {
        let value = text.value, caret = text.selection.location, selected = text.selection.length
        func unit(_ u: TextUnit, _ last: Bool) -> TextSpan? {
            TextRanges.unit(u, last: last, in: value, caret: caret, line: text.line)
        }
        func find(_ words: String) -> TextSpan? {
            TextRanges.find(words, in: value, caret: caret, selectionLength: selected)
        }
        switch edit {
        case .select(let u, let last):
            guard let span = unit(u, last) else { return .failed("no \(last ? "last " : "")\(u.rawValue) to select") }
            return .plan(.select(span))
        case .delete(let u, let last):
            guard let span = unit(u, last) else { return .failed("no \(last ? "last " : "")\(u.rawValue) to delete") }
            return .plan(.delete(TextRanges.deletion(of: span, unit: u, in: value)))
        case .selectPhrase(let words):
            guard let span = find(words) else { return .notFound(words) }
            return .plan(.select(span))
        case .deletePhrase(let words):
            guard let span = find(words) else { return .notFound(words) }
            return .plan(.delete(TextRanges.deletion(of: span, unit: nil, in: value)))
        case .replace(let words, let new):
            guard let span = find(words) else { return .notFound(words) }
            return .plan(.replace(span, with: TextRanges.replacement(new, replacing: slice(value, span))))
        case .caretBefore(let words):
            guard let span = find(words) else { return .notFound(words) }
            return .plan(.caret(TextSpan(location: span.location, length: 0)))
        case .caretAfter(let words):
            guard let span = find(words) else { return .notFound(words) }
            return .plan(.caret(TextSpan(location: span.end, length: 0)))
        case .caret:
            return .failed("no text to move in")   // never read: caret moves are keys
        case .changeCase(let change):
            guard let span = TextRanges.caseTarget(in: value, selection: text.selection) else { return .failed("no word to change") }
            return .plan(.replace(span, with: TextRanges.changeCase(change, of: slice(value, span))))
        }
    }
}
