import Foundation
import NoHandsCore

/// Who asked for a file. Only a spoken command may show a list of several hits; a macro step or a model task fails
/// with a message that names no files, and the model is told what happened in words that name none either.
public enum FileContext: Sendable { case spoken, macro, model }

extension ActionExecutor {
    /// The ranked hits a spoken command found when several matched; the pipeline shows them as a list. Clears them.
    public func takeFileOffer() -> [FileHit]? {
        defer { fileOffer = nil }
        return fileOffer
    }

    /// Opens a hit the speaker picked from the list. The guard runs again: the list may be old.
    public func openPicked(_ hit: FileHit) async -> String? {
        fileContext = .spoken
        return await open(hit)
    }

    func openFile(_ request: FileRequest) async -> String? {
        switch request {
        case .folder(let folder):
            guard await fileOpener.open(path: folder.path(home: fileOpener.home), inFinder: true) else { return "couldn't open that folder" }
            noteOpened(folder: true)
            return nil
        case .named(let name, let kind):
            let query = FileQuery(words: FileRequest.words(name), kind: kind)
            let (allowed, refusal) = await candidates(query)
            if Task.isCancelled { return Self.cancelled }
            switch allowed.count {
            case 0:
                if let refusal { return refusal }
                guard fileContext != .model else { return "no file matched" }
                return "no \(kind == .folder ? "folder" : "file") called \"\(name)\""
            case 1:
                return await open(allowed[0])
            default:
                let say = kind == .folder ? "open the \(name) folder" : "open file \(name)"
                switch fileContext {
                case .spoken: fileOffer = allowed; return nil
                case .macro: return "several files match: say \(say)"
                case .model: return "several files match: ask the user to say \(say)"
                }
            }
        case .recent(let kind):
            let (allowed, _) = await candidates(FileQuery(words: [], kind: kind, newestFirst: true))
            if Task.isCancelled { return Self.cancelled }
            guard let newest = allowed.first else { return fileContext == .model ? "no file matched" : "no recent \(kind.rawValue)" }
            return await open(newest)
        }
    }

    /// Every hit that matches the words, in rank order, that the guard allows; and the first refusal, for when none does.
    private func candidates(_ query: FileQuery) async -> (allowed: [FileHit], refusal: String?) {
        let found = await files.search(query).filter { FileRank.matches($0.name, words: query.words) }
        var allowed: [FileHit] = [], refusal: String?
        for hit in FileRank.order(found, words: query.words) {
            switch FileOpenGuard.decide(fileOpener.facts(forPath: hit.path)) {
            case .allow: allowed.append(hit)
            case .refuse(let why): refusal = refusal ?? why.message(name: refusalName(hit))
            }
        }
        return (allowed, refusal)
    }

    private func open(_ hit: FileHit) async -> String? {
        let facts = fileOpener.facts(forPath: hit.path)
        if case .refuse(let why) = FileOpenGuard.decide(facts) { return why.message(name: refusalName(hit)) }
        let folder = facts.isDirectory && !facts.isPackage
        // The path the guard checked, not the spelling the search found.
        guard await fileOpener.open(path: facts.resolved, inFinder: folder) else { return "couldn't open that file" }
        noteOpened(folder: folder)
        return nil
    }

    /// A spoken refusal names the hit (it was on screen); a macro or the model gets no file name, which would reach the
    /// model and the logs.
    private func refusalName(_ hit: FileHit) -> String { fileContext == .spoken ? hit.name : "a file" }

    /// The model is told what happened, in words that name nothing; a spoken command's row says "opened" itself.
    private func noteOpened(folder: Bool) {
        if fileContext == .model { addResult(folder ? "opened a folder" : "opened a file") }
    }
}
