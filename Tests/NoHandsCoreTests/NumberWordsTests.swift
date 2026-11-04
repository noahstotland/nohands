import Testing
import Foundation
@testable import NoHandsCore

@Test func digitsAndWords() {
    #expect(NumberWords.parse(["42"]) == 42)
    #expect(NumberWords.parse(["forty", "two"]) == 42)
    #expect(NumberWords.parse(["forty-two"]) == 42)
    #expect(NumberWords.parse(["one", "hundred", "five"]) == 105)
    #expect(NumberWords.parse(["zero"]) == 0)
    #expect(NumberWords.parse(["twelve"]) == 12)
}

@Test func homophonesInNumberSlot() {
    #expect(NumberWords.parse(["to"]) == 2)
    #expect(NumberWords.parse(["too"]) == 2)
    #expect(NumberWords.parse(["for"]) == 4)
    #expect(NumberWords.parse(["twenty", "to"]) == 22)
}

@Test func nonNumbers() {
    #expect(NumberWords.parse(["save"]) == nil)
    #expect(NumberWords.parse([]) == nil)
    #expect(NumberWords.parse(["forty", "save"]) == nil)
}

@Test func leadingNumberSplitsRest() {
    let r = NumberWords.leadingNumber(in: ["thirty", "five", "pixels"])
    #expect(r?.value == 35)
    #expect(r?.rest == ["pixels"])
    #expect(NumberWords.leadingNumber(in: ["pixels"]) == nil)
}
