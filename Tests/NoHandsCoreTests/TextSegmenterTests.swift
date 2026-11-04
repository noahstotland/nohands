import Testing
@testable import NoHandsCore

@Test func segmentsMixedText() {
    #expect(TextSegmenter.segments("a\tb\nc") == [.text("a"), .key(.tab), .text("b"), .key(.return), .text("c")])
}
@Test func segmentsConsecutiveNewlines() {
    #expect(TextSegmenter.segments("\n\nx") == [.key(.return), .key(.return), .text("x")])
}
@Test func segmentsCRLFAsOneReturn() {
    #expect(TextSegmenter.segments("a\r\nb") == [.text("a"), .key(.return), .text("b")])
    #expect(TextSegmenter.segments("a\r\n\r\nb").filter { $0 == .key(.return) }.count == 2)
}
@Test func segmentsEmpty() {
    #expect(TextSegmenter.segments("") == [])
}
