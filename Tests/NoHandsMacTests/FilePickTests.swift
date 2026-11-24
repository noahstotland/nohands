import Testing
import Foundation
import NoHandsCore
@testable import NoHandsMac

private struct NullTranscriber: Transcribing { func transcribe(_ samples: [Float]) async throws -> String { "" } }

@MainActor private final class ListedFiles: FileSource, FileOpening {
    let home = "/Users/noah"
    var opened: [String] = []
    func search(_ query: FileQuery) async -> [FileHit] { ["a", "b", "c"].map { FileHit(path: "/Users/noah/Documents/\($0).pdf", name: "report \($0).pdf") } }
    func facts(forPath path: String) -> FileFacts { var f = FileFacts(home: home, found: path); f.isRegularFile = true; f.conformsToContent = true; return f }
    func open(path: String, inFinder: Bool) async -> Bool { opened.append(path); return true }
}

private func at() -> LatencyTrace { var t = LatencyTrace(); t.speechEnd = .now; t.asrDone = .now; return t }

/// Says "open file report" (three files match, after the attention word when there is one), then each reply in turn,
/// on a fresh pipeline.
@MainActor private func say(_ replies: [String], attention: String = "", timeout: Duration = .seconds(30)) async -> (files: ListedFiles, overlay: FakeOverlay, pipeline: VoicePipeline) {
    let files = ListedFiles(), overlay = FakeOverlay(), input = FakeInput(), ax = FakeElements()
    let executor = ActionExecutor(input: input, ax: ax, overlay: overlay, config: AppConfig(), files: files, fileOpener: files)
    var config = AppConfig()
    config.attentionWord = attention
    let pipeline = VoicePipeline(config: config, transcriber: NullTranscriber(), resolver: nil, executor: executor, overlay: overlay, ax: ax)
    pipeline.pickTimeout = timeout
    await pipeline.handle(transcript: (attention.isEmpty ? "" : attention + " ") + "open file report", trace: at())
    for reply in replies { await pipeline.handle(transcript: reply, trace: at()) }
    return (files, overlay, pipeline)
}

@MainActor @Test func aFileListWaitsForANumberAndAStopAlwaysClosesIt() async {
    // (the replies, what opened, the list row's last status)
    let table: [([String], [String], String)] = [
        ([], [], "say 1 to 3, or cancel"),
        (["two"], ["/Users/noah/Documents/b.pdf"], "opened"),
        (["seven", "open 1"], ["/Users/noah/Documents/a.pdf"], "opened"),
        (["seven"], [], "say 1 to 3, or cancel"),
        (["stop"], [], "cancelled"), (["cancel"], [], "cancelled"), (["number two", "two"], ["/Users/noah/Documents/b.pdf"], "opened"),
        (["scroll down", "two"], [], "dropped"),
    ]
    for (replies, opened, status) in table {
        let r = await say(replies)
        #expect(r.files.opened == opened, "\(replies)")
        #expect(r.overlay.reports.last { $0.id == 1 }?.status.text == status, "\(replies)")
    }
    // The rows are numbered under the prompt and cleared when it closes.
    let r = await say(["cancel"])
    #expect(r.overlay.trails.first?.trail.steps.map(\.intent) == ["1 report a.pdf · Documents", "2 report b.pdf · Documents", "3 report c.pdf · Documents"])
    #expect(r.overlay.trails.last?.trail.steps.isEmpty == true)
    // With the attention word on, stray speech leaves the list open, and an addressed number picks.
    let gated = await say(["the weather is nice", "computer two"], attention: "computer")
    #expect(gated.files.opened == ["/Users/noah/Documents/b.pdf"])
    // A list nobody answers closes by itself.
    let slow = await say([], timeout: .milliseconds(30))
    try? await Task.sleep(for: .milliseconds(150))
    #expect(slow.overlay.reports.last { $0.id == 1 }?.status.text == "no pick: say it again" && slow.files.opened.isEmpty)
}
