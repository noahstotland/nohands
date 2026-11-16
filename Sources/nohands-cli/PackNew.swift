import AppKit
import Foundation
import NoHandsCore
import NoHandsMac

/// `nohands-cli pack new [--app <name|bundle id>] [--out <file>]`: writes a draft pack from the app's top-level menu
/// items and lists what it left out. The draft goes through the same validator and `pack add` question as any file;
/// this command never installs and never overwrites a file.
func newPack(_ args: [String]) {
    var app: String?, out: String?
    var rest = args[...]
    while let flag = rest.popFirst() {
        guard let value = rest.popFirst(), !value.isEmpty else { usage() }
        switch flag {
        case "--app" where app == nil: app = value
        case "--out" where out == nil: out = value
        default: usage()
        }
    }
    let show = PackSummary.printable
    if let out, exists(out) { fail("\(show(out)) exists; pass --out with a new name") }
    guard Permissions.accessibilityGranted(prompt: false) else {
        fail("Accessibility permission is not granted to this process (or its terminal).")
    }
    let target: NSRunningApplication
    if let app {
        let key = app.lowercased()
        let matches = NSWorkspace.shared.runningApplications.filter {
            $0.localizedName?.lowercased() == key || $0.bundleIdentifier?.lowercased() == key
        }
        guard let found = matches.first(where: { $0.activationPolicy == .regular }) ?? matches.first else {
            fail("no running app called \(show(app)); open it first")
        }
        target = found
    } else {
        Thread.sleep(forTimeInterval: 3)
        guard let front = NSWorkspace.shared.frontmostApplication else { fail("no app in front to read; bring one forward and try again") }
        target = front
    }
    let name = target.localizedName ?? target.bundleIdentifier ?? "the app"
    guard let bundleID = target.bundleIdentifier else { fail("\(show(name)) has no usable bundle ID; write its pack by hand") }
    let entries: [MenuEntry]
    var stoppedEarly = false
    do { (entries, stoppedEarly) = try MenuShortcutReader.read(pid: target.processIdentifier) } catch {
        fail("\(show(name)) has no menu bar to read; open a window of it and try again")
    }
    let draft = PackDraft.make(appName: name, bundleID: bundleID, entries: entries)
    let leftOut = draft.leftOut.map { "  \(show($0.item)): \(show($0.reason))" }
    switch draft.problem {
    case .badBundleID: fail("\(show(name)) has no usable bundle ID; write its pack by hand")
    case .nothingToPut: fail("nothing to put in a pack: every menu item of \(show(name)) was left out\n" + leftOut.joined(separator: "\n"))
    case .invalid(let reason): fail("the draft did not pass the pack check, so nothing was written: \(show(reason))")
    case nil: break
    }
    guard let pack = draft.pack, let data = draft.data else { return }
    let path = out ?? "\(pack.id).json"
    writeNew(data, to: path)
    print("wrote \(show(path)): \(pack.phrases.count) commands for \(show(name)), \(leftOut.count) menu items left out")
    if !leftOut.isEmpty {
        print("Left out:")
        leftOut.forEach { print($0) }
    }
    if draft.leftOut.contains(where: { $0.reason == "disabled" }) {
        print("Disabled items depend on what is open; open a window with content and run again to catch more.")
    }
    if stoppedEarly { print("The read stopped at its time or item limit, so later menus may be missing. Run again, or add them by hand.") }
    print("Edit it, then install with: swift run nohands-cli pack add \(show(path))")
}

private func exists(_ path: String) -> Bool {
    var info = stat()
    return lstat(path, &info) == 0
}

/// Creates `path` (mode 0644) and writes `data`; an existing file, or a symlink in its place, stops the command.
private func writeNew(_ data: Data, to path: String) {
    let fd = open(path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o644)
    guard fd >= 0 else {
        fail(errno == EEXIST ? "\(PackSummary.printable(path)) exists; pass --out with a new name"
                             : "can't write \(PackSummary.printable(path)): \(String(cString: strerror(errno)))")
    }
    defer { close(fd) }
    fchmod(fd, 0o644)
    let written = data.withUnsafeBytes { buffer in
        var done = 0
        while done < buffer.count {
            let n = write(fd, buffer.baseAddress! + done, buffer.count - done)
            if n <= 0 { return false }
            done += n
        }
        return true
    }
    if !written {
        unlink(path)
        fail("can't write \(PackSummary.printable(path))")
    }
}
