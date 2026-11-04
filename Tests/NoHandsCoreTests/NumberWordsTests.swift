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

@Test func homophoneBarePrefixInNumberSlot() {
    let a = NumberWords.leadingNumber(in: ["to", "fit"])
    #expect(a?.value == 2)
    #expect(a?.rest == ["fit"])
    let b = NumberWords.leadingNumber(in: ["twenty", "to", "save"])
    #expect(b?.value == 22)
    #expect(b?.rest == ["save"])
    let c = NumberWords.leadingNumber(in: ["for"])
    #expect(c?.value == 4)
    #expect(c?.rest == [])
}

@Test func trailingAndNotConsumed() {
    #expect(NumberWords.parse(["one", "hundred", "and"]) == nil)
    #expect(NumberWords.parse(["one", "hundred", "and", "five"]) == 105)
    let r = NumberWords.leadingNumber(in: ["one", "hundred", "and", "save"])
    #expect(r?.value == 100)
    #expect(r?.rest == ["and", "save"])
}

@Test func zeroOnlyStandalone() {
    #expect(NumberWords.parse(["forty", "zero"]) == nil)
    #expect(NumberWords.parse(["one", "hundred", "zero"]) == nil)
    #expect(NumberWords.parse(["zero"]) == 0)
}

@Test func digitTokensAreAllDigits() {
    #expect(NumberWords.parse(["-5"]) == nil)
    #expect(NumberWords.parse(["+5"]) == nil)
    #expect(NumberWords.parse(["007"]) == 7)
}
