import Foundation

/// What an update changes, in words: phrases added, removed or re-pointed, apps, `open_url` hosts and `open_app` names.
/// Every line goes through `PackSummary`'s quoting and `printable`, so a pack cannot inject terminal escapes.
public enum PackDiff {
    /// Empty when the two packs do the same thing.
    public static func lines(old: AppPack, new: AppPack) -> [String] {
        func actions(_ pack: AppPack, _ phrase: String) -> String {
            (pack.phrases[phrase] ?? []).map(PackSummary.describe).joined(separator: ", ")
        }
        var out: [String] = []
        let oldPhrases = Set(old.phrases.keys), newPhrases = Set(new.phrases.keys)
        for phrase in newPhrases.subtracting(oldPhrases).sorted() {
            out.append("added phrase \(PackSummary.quoted(phrase)) -> \(actions(new, phrase))")
        }
        for phrase in oldPhrases.subtracting(newPhrases).sorted() {
            out.append("removed phrase \(PackSummary.quoted(phrase)) -> \(actions(old, phrase))")
        }
        for phrase in oldPhrases.intersection(newPhrases).sorted() where old.phrases[phrase] != new.phrases[phrase] {
            out.append("changed phrase \(PackSummary.quoted(phrase)): was \(actions(old, phrase)), now \(actions(new, phrase))")
        }
        for phrase in oldPhrases.intersection(newPhrases).sorted() where old.confirms.contains(phrase) != new.confirms.contains(phrase) {
            out.append("phrase \(PackSummary.quoted(phrase)) " + (new.confirms.contains(phrase) ? "now asks first" : "no longer asks first"))
        }
        let (a, b) = (PackSummary(old), PackSummary(new))
        for (label, before, after) in [("app", a.apps, b.apps), ("url host", a.urlHosts, b.urlHosts), ("opened app", a.openedApps, b.openedApps)] {
            out += Set(after).subtracting(before).sorted().map { "added \(label) \(PackSummary.printable($0))" }
            out += Set(before).subtracting(after).sorted().map { "removed \(label) \(PackSummary.printable($0))" }
        }
        return out
    }
}
