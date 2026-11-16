import Foundation
import NoHandsCore

/// What a finished rewrite leaves for the board row and the command log: counts and a short preview, never the text.
struct RewriteReport: Equatable, Sendable {
    var from: Int
    var to: Int
    /// The first words of the answer, for the row; "no change" when the answer was the text itself.
    var preview: String
}

extension ActionExecutor {
    static let rewriteNeedsModel = "rewrite needs a model: add a Claude key or set up the local model"
    static let rewriteOff = "rewrite is off: intentBackend is off"
    static let rewriteUnreadable = "can't read the text here: rewrite needs a field NoHands can read"
    static let rewriteChanged = "the text changed: say it again"
    static let rewriteNoChange = "no change"
    static let previewWords = 6

    /// Rewrites the selection (else the last sentence before the caret) of the focused field with the model and types
    /// the answer over it, so the app's own undo takes it back. The field is read off the main actor; the text goes only
    /// to the rewriter. Before anything is typed the field is read again and must be unchanged, and a cancelled task
    /// (a spoken stop) types nothing. The text and the answer are never logged; failure messages never carry them.
    func rewriteText(_ how: RewriteInstruction) async throws -> String? {
        rewriteReport = nil
        guard let rewriter else { return rewriteUnavailable }
        let ax = self.ax
        let first = await Task.detached { ax.isTextFocused() ? (true, ax.focusedText()) : (false, nil) }.value
        if Task.isCancelled { return Self.cancelled }
        guard first.0 else { return Self.noTextField }
        guard let field = first.1, field.rangeSettable else { return Self.rewriteUnreadable }
        let subject: RewriteSubject
        do { subject = try RewriteSubject.pick(in: field.value, selection: field.selection) } catch { return error.message }

        onRewriteStart?()
        let answer: String
        do { answer = try await rewriter.rewrite(subject.text, how) } catch { return Self.rewriteFailure(error) }
        if Task.isCancelled { return Self.cancelled }
        let cleaned: String
        do { cleaned = try RewriteResult.clean(answer, source: subject.text) } catch { return error.message }

        // The user may have typed or clicked elsewhere while the model worked.
        let again = await Task.detached { ax.isTextFocused() ? ax.focusedText() : nil }.value
        if Task.isCancelled { return Self.cancelled }
        guard let again, again.value == field.value, again.selection == field.selection else { return Self.rewriteChanged }
        if cleaned == subject.text {
            rewriteReport = RewriteReport(from: subject.text.count, to: cleaned.count, preview: Self.rewriteNoChange)
            return nil
        }
        let span = subject.span
        let took = await Task.detached { ax.setSelection(span) }.value
        if Task.isCancelled { return Self.cancelled }
        guard took else { return Self.rewriteUnreadable }
        try input.type(cleaned)
        hideStaleOverlay()
        let words = cleaned.split(whereSeparator: \.isWhitespace)
        rewriteReport = RewriteReport(from: subject.text.count, to: cleaned.count,
                                      preview: words.prefix(Self.previewWords).joined(separator: " ") + (words.count > Self.previewWords ? "…" : ""))
        return nil
    }

    /// The row's text for a rewrite that failed: what the task loop says for the backend's own errors.
    private static func rewriteFailure(_ error: Error) -> String {
        switch error {
        case let e as RewriteError: e.message
        case let e as IntentError: PipelineText.hud(for: e) ?? cancelled
        case is CancellationError: cancelled
        default: "rewrite failed"
        }
    }

    /// The last rewrite's counts and preview, once; nil when there was none.
    func takeRewrite() -> RewriteReport? {
        defer { rewriteReport = nil }
        return rewriteReport
    }

    /// Uses the rewriter for the backend in `config` from the next rewrite on.
    public func useRewriter(config: AppConfig) {
        rewriter = TextRewriters.make(config: config)
        rewriteUnavailable = config.intentBackend == .off ? Self.rewriteOff : Self.rewriteNeedsModel
    }
}
