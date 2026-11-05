import Testing
import Foundation
@testable import NoHandsCore

@Test func decodesSuccessWithDispositionAndSurfaces() {
    let json = #"{"version":"2.6","ok":true,"command":"click","data":{"disposition":{"delivery":"delivered_verified","retry":"unsafe"},"surfaces":[{"type":"sheet"}]}}"#
    let e = DesktopEnvelope.decode(Data(json.utf8))!
    #expect(e.ok && e.command == "click" && e.disposition?.delivery == "delivered_verified" && e.surfaces == ["sheet"])
    #expect(e.error == nil)
}

@Test func decodesAmbiguousErrorWithCandidates() {
    let json = #"{"version":"2.6","ok":false,"command":"snapshot","error":{"code":"AMBIGUOUS_TARGET","message":"More than one window","details":{"kind":"x","candidates":[{"id":"w-1","is_focused":false,"title":"A","visible":true},{"id":"w-2","is_focused":true,"title":"B","visible":true}]},"disposition":{"delivery":"not_delivered","retry":"safe"}}}"#
    let e = DesktopEnvelope.decode(Data(json.utf8))!
    #expect(!e.ok && e.error?.code == "AMBIGUOUS_TARGET" && e.error?.notDelivered == true)
    #expect(e.error?.candidates.map(\.id) == ["w-1", "w-2"] && e.error?.candidates[1].isFocused == true)
    #expect(e.error?.detailsKind == "x" && e.surfaces.isEmpty && e.data == nil)
}

@Test func arrayDataIsKept() {
    let json = #"{"version":"2.6","ok":true,"command":"list-windows","data":[{"id":"w-1"},{"id":"w-2"}]}"#
    let e = DesktopEnvelope.decode(Data(json.utf8))!
    #expect(e.ok && e.data == nil && e.dataArray?.compactMap { $0["id"] as? String } == ["w-1", "w-2"])
}

@Test func surfacesAcceptPlainStrings() {
    let json = #"{"version":"2.6","ok":true,"command":"click","data":{"surfaces":["menu","sheet"]}}"#
    #expect(DesktopEnvelope.decode(Data(json.utf8))?.surfaces == ["menu", "sheet"])
}

@Test func malformedAndSyntheticEnvelopes() {
    #expect(DesktopEnvelope.decode(Data("nope".utf8)) == nil)
    #expect(DesktopEnvelope.decode(Data("[1]".utf8)) == nil)
    let t = DesktopEnvelope.timeout(command: "click", observation: false)
    #expect(t.ok == false && t.error?.code == "TIMEOUT" && t.error?.notDelivered == false)
    let o = DesktopEnvelope.timeout(command: "snapshot", observation: true)
    #expect(o.error?.notDelivered == true && o.error?.disposition?.retry == "safe")
    let p = DesktopEnvelope.processFailure(command: "snapshot", message: "m", observation: true)
    #expect(p.error?.code == "PROCESS_FAILED" && p.error?.message == "m" && p.error?.notDelivered == true)
    #expect(DesktopEnvelope.processFailure(command: "click", message: "m", observation: false).error?.notDelivered == false)
}
