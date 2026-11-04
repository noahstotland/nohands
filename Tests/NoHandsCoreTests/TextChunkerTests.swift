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

@Test func deliveryChunksSplitsOversizeClusterOnScalars() {
    let text = "x" + String(repeating: "👨\u{200D}", count: 12) + "👩"
    #expect(text.count == 2)   // "x" + one giant cluster
    let big = text.dropFirst()
    #expect(big.utf16.count > 20)
    #expect(TextChunker.chunks(text).contains { $0.utf16.count > 20 })
    let d = TextChunker.deliveryChunks(text)
    #expect(d.joined() == text)
    for c in d { #expect(c.utf16.count <= 20); #expect(!c.isEmpty) }
    #expect(TextChunker.deliveryChunks("") == [])
    #expect(TextChunker.deliveryChunks("abc") == ["abc"])
}
