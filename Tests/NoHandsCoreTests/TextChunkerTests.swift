import Testing
@testable import NoHandsCore

@Test func chunksByUTF16Budget() {
    let text = String(repeating: "a", count: 45)
    let c = TextChunker.chunks(text)
    #expect(c.map(\.utf16.count) == [20, 20, 5])
    #expect(c.joined() == text)
    #expect(TextChunker.chunks("") == [])
}

@Test func neverSplitsGraphemeClusters() {
    let flag = "🇺🇸"              // 4 UTF-16 units
    let family = "👨‍👩‍👧‍👦"          // 11 UTF-16 units
    let text = String(repeating: "x", count: 18) + flag + family + "é"
    let c = TextChunker.chunks(text)
    #expect(c.joined() == text)
    for chunk in c { #expect(chunk.utf16.count <= 20) }
    #expect(c[0] == String(repeating: "x", count: 18))
    #expect(c[1].hasPrefix(flag))
}
