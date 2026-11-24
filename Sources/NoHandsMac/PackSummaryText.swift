import Foundation
import NoHandsCore

/// The text a person reads before saying yes to a pack. One formatter for `nohands-cli pack add|install|update` and the
/// app's confirm alert, so both show the same lines.
public enum PackSummaryText {
    public static func text(_ s: PackSummary, id: String, shadowed: [PackSet.Shadowed], replaces: PackStore.Entry?) -> String {
        let show = PackSummary.printable
        func list(_ items: [String]) -> String { items.map(show).joined(separator: ", ") }
        var lines = ["\(show(s.name)) \(show(s.version))" + (s.author.isEmpty ? "" : " by \(show(s.author))") + " (\(show(id)))",
                     "  Works in:    \(list(s.apps))",
                     "  Phrases:     \(s.phraseCount)"]
        if !s.urlHosts.isEmpty { lines.append("  Opens URLs on: \(list(s.urlHosts))") }
        if !s.openedApps.isEmpty { lines.append("  Opens apps:  \(list(s.openedApps))") }
        if !s.overriddenPhrases.isEmpty { lines.append("  Replaces these NoHands phrases in its apps: \(list(s.overriddenPhrases))") }
        if !shadowed.isEmpty {
            lines.append("  Will not work (an earlier pack has them): "
                         + shadowed.map { "\(PackSummary.quoted($0.phrase)) (\(show($0.winner)))" }.joined(separator: ", "))
        }
        if let replaces {
            lines.append("  Replaces " + (replaces.pack.map { "version \(show($0.version))" } ?? "an invalid pack") + ", already installed.")
        }
        lines.append("  Says and does:")
        lines += s.commandLines.map { "    " + $0 }
        return lines.joined(separator: "\n")
    }

    /// The summary of `pack` as it would sit among the `installed` packs: the pack replaces one with its id in place, and
    /// phrases an earlier pack already has are listed as not working. With `updating`, what changed since that version follows.
    public static func text(for pack: AppPack, installed: [PackStore.Entry], updating old: AppPack? = nil) -> String {
        var others = installed.compactMap { $0.enabled && $0.pack?.id != pack.id ? $0.pack : nil }
        if let at = installed.firstIndex(where: { $0.id == pack.id }) {
            others.insert(pack, at: installed[..<at].filter { $0.enabled && $0.pack != nil }.count)
        } else {
            others.append(pack)
        }
        let shadowed = PackSet(installed: others).shadowed.filter { $0.packID == pack.id }
        var out = text(PackSummary(pack), id: pack.id, shadowed: shadowed, replaces: installed.first { $0.id == pack.id })
        if let old {
            let changes = PackDiff.lines(old: old, new: pack)
            out += "\n  Changes since \(PackSummary.printable(old.version)):\n"
                + (changes.isEmpty ? ["none to what it says or does"] : changes).map { "    " + $0 }.joined(separator: "\n")
        }
        return out
    }
}
