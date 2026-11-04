import Testing
@testable import NoHandsCore

@Test func pullLinesParse() {
    #expect(PullEvent.parse(line: #"{"status":"pulling manifest"}"#) == .progress(nil))
    #expect(PullEvent.parse(line: #"{"status":"downloading","total":200,"completed":50}"#) == .progress(0.25))
    #expect(PullEvent.parse(line: #"{"status":"success"}"#) == .success)
    #expect(PullEvent.parse(line: #"{"error":"no space left on device"}"#) == .error("no space left on device"))
    #expect(PullEvent.parse(line: "") == nil)
    #expect(PullEvent.parse(line: "not json") == nil)
    #expect(PullEvent.parse(line: #"{"total":0,"completed":0,"status":"x"}"#) == .progress(nil))
}

@Test func menuTextForEveryState() {
    let m = "qwen2.5:7b-instruct"
    #expect(LocalModelMenu.text(.notRunning, model: m, ollamaInstalled: true) == "Start Ollama")
    #expect(LocalModelMenu.text(.notRunning, model: m, ollamaInstalled: false) == "Install Ollama…")
    #expect(LocalModelMenu.text(.modelMissing, model: m, ollamaInstalled: true) == "Download local model (≈ 4.7 GB)")
    #expect(LocalModelMenu.text(.downloading(0.42), model: m, ollamaInstalled: true) == "Downloading local model… 42%")
    #expect(LocalModelMenu.text(.downloading(nil), model: m, ollamaInstalled: true) == "Downloading local model…")
    #expect(LocalModelMenu.text(.downloadFailed, model: m, ollamaInstalled: true) == "Download failed: retry")
    #expect(LocalModelMenu.text(.ready, model: m, ollamaInstalled: true) == "Local model: ready (qwen2.5:7b-instruct)")
    #expect(!LocalModelMenu.actionable(.ready) && !LocalModelMenu.actionable(.downloading(nil)))
    #expect(LocalModelMenu.actionable(.notRunning) && LocalModelMenu.actionable(.modelMissing) && LocalModelMenu.actionable(.downloadFailed))
}

@Test func approxDownloadSizes() {
    #expect(LocalModelMenu.approxDownloadGB(model: "qwen2.5:7b-instruct") == "4.7")
    #expect(LocalModelMenu.approxDownloadGB(model: "qwen2.5:3b-instruct") == "1.9")
    #expect(LocalModelMenu.approxDownloadGB(model: "other") == "?")
}
