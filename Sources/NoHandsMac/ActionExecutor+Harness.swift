import Foundation
import AppKit
import CoreGraphics
import NoHandsCore

/// The system clipboard (`NSPasteboard`), injectable for tests.
public protocol ClipboardAccess: Sendable {
    func readText() -> String?
    func write(_ text: String)
}

public struct PasteboardClipboard: ClipboardAccess {
    public init() {}
    public func readText() -> String? { NSPasteboard.general.string(forType: .string) }
    public func write(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

/// The harness actions: agent-desktop when a harness is present and the element has a ref; the native fallback
/// from the design's table otherwise.
extension ActionExecutor {
    /// A resolved element: its ref (agent-desktop) and/or its frame (native).
    struct Resolved {
        var title: String
        var ref: String?
        var frame: CGRect
        var value: String?
        var centre: CGPoint? { frame == .zero ? nil : CGPoint(x: frame.midX, y: frame.midY) }
    }

    /// `.label(n)` from the request's snapshot; `.named` through `find` when a harness is present, else the
    /// native element list. Returns the failure message instead of an element when neither resolves.
    func resolve(_ target: ElementTarget, surface: DesktopSurface? = nil) async -> Result<Resolved, Unresolved> {
        switch target {
        case .label(let n):
            guard let e = labelSnapshot?[n] else { return .failure(Unresolved(message: "no label \(n)")) }
            return .success(Resolved(title: e.title, ref: e.ref, frame: e.frame, value: e.value))
        case .named(let name):
            if let harness, let m = await harness.find(app: ax.frontmostAppName(), surface: surface, name: name) {
                return .success(Resolved(title: m.name, ref: m.ref, frame: .zero, value: nil))
            }
            guard let e = LabelAssigner.find(named: name, in: ax.actionableElements()) else {
                return .failure(Unresolved(message: "no element named '\(name)'"))
            }
            return .success(Resolved(title: e.title, ref: e.ref, frame: e.frame, value: e.value))
        }
    }

    /// Runs a ref command through the harness. nil: done. A string: the failure. `.notDelivered` → the native
    /// fallback when the element has a frame, else the message.
    private func act(_ command: DesktopCommand, on r: Resolved,
                     fallback: (CGPoint) throws -> Void) async throws -> String? {
        if let harness, r.ref != nil {
            switch await harness.act(command) {
            case .delivered: return nil
            case .failed(let m): return m
            case .elementChanged: return Self.elementChanged
            case .notDelivered(let m):
                guard let c = r.centre else { return m }
                try fallback(c)
                return nil
            }
        }
        guard let c = r.centre else { return r.ref == nil ? Self.needsHarness : "no label on screen" }
        try fallback(c)
        return nil
    }

    private func clickCentre(_ p: CGPoint) throws { try input.click(at: p, button: .left, count: 1) }
    private func selectAll() throws { try input.press(KeyChord(.a, [.command])) }

    enum MenuPress { case pressed, disabled(String), refused(String), noMatch }

    /// The frontmost app's own menu, pressed through Accessibility (the menu does not open on screen). `noMatch`
    /// when no item is named so; `refused` when the app ignored the press. Either way the caller tries agent-desktop.
    func pressMenuItem(_ spoken: String, exactOnly: Bool = false) -> MenuPress {
        let entries = menus.entries()
        guard let i = MenuMatch.firstMatch(spoken, in: entries, exactOnly: exactOnly) else { return .noMatch }
        guard entries[i].enabled else { return .disabled(entries[i].title) }
        return menus.press(i) ? .pressed : .refused(entries[i].title)
    }

    func runHarnessAction(_ action: Action) async throws -> String? {
        switch action {
        case .setValue(let t, let text):
            guard text.count <= Self.maxTypedCharacters else { return "text too long" }
            let r = try await element(t)
            if r.centre == nil, harness == nil || r.ref == nil { return "no label \(label(t)) on screen" }
            return try await act(.setValue(ref: r.ref ?? "", text: text), on: r) { p in
                try clickCentre(p); try selectAll(); try input.type(text)
            }
        case .typeInto(let t, let text):
            guard text.count <= Self.maxTypedCharacters else { return "text too long" }
            let r = try await element(t)
            return try await act(.type(ref: r.ref ?? "", text: text), on: r) { p in try clickCentre(p); try input.type(text) }
        case .clearField(let t):
            let r = try await element(t)
            return try await act(.clear(ref: r.ref ?? ""), on: r) { p in
                try clickCentre(p); try selectAll(); try input.press(KeyChord(.delete, []))
            }
        case .selectOption(let t, let option):
            let r = try await element(t)
            guard let ref = r.ref else { return Self.needsHarness }
            return try await act(.select(ref: ref, option: option), on: r) { _ in throw HarnessOnly() }
        case .setChecked(let t, let on):
            let r = try await element(t)
            let command: DesktopCommand = on.map { .check(ref: r.ref ?? "", $0) } ?? .toggle(ref: r.ref ?? "")
            return try await act(command, on: r, fallback: clickCentre)
        case .setExpanded(let t, let open):
            let r = try await element(t)
            return try await act(.expand(ref: r.ref ?? "", open), on: r, fallback: clickCentre)
        case .focusElement(let t):
            let r = try await element(t)
            return try await act(.focus(ref: r.ref ?? ""), on: r, fallback: clickCentre)
        case .scrollTo(let t):
            let r = try await element(t)
            guard let ref = r.ref else { return Self.needsHarness }
            return try await act(.scrollTo(ref: ref), on: r) { _ in throw HarnessOnly() }
        case .scrollIn(let t, let direction, let amount):
            guard (1...100).contains(amount) else { return "bad scroll amount" }
            let r = try await element(t)
            return try await act(.scroll(ref: r.ref ?? "", direction, amount: amount), on: r) { p in
                try input.moveMouse(to: p); try input.scroll(direction, lines: amount)
            }
        case .drag(let from, let to):
            return try await drag(from: from, to: to)
        case .clickIn(let surface, let name):
            guard let harness else { return Self.needsHarness }
            let app: String? = [.dock, .menuBarExtras].contains(surface) ? nil : ax.frontmostAppName()
            guard let m = await harness.find(app: app, surface: surface, name: name) else { return "no '\(name)' in \(surface.rawValue)" }
            // The guards checked the name the step sent; `find` may fall back to a contains match ("Safari" finding
            // "Quit Safari"), so on the menu bar a model step presses only that title, and never an Apple menu item.
            if surface == .menubar,
               MenuMatch.isAppleMenuTitle(m.name) || MenuMatch.isLookalike(m.name)
                || (labelSnapshot != nil && MenuMatch.plain(m.name) != MenuMatch.plain(MenuMatch.leaf(of: name) ?? name)) {
                return "no '\(name)' in menubar"
            }
            if m.disabled { return "'\(name)' is disabled" }
            if let refusal = pressRefusal(title: m.name) { return refusal }
            return outcome(await harness.act(.click(ref: m.ref, button: .left, count: 1)))
        case .menuItem(let name, let exact):
            guard let last = MenuMatch.leaf(of: name) else { return "no menu item called \(name)" }
            // agent-desktop looks a title up in the whole menu bar and cannot keep to a submenu path, so a path of three or more
            // parts never falls back to it ("Mailbox > Go to Favorite Mailbox > Sent" must not find "Use This Mailbox For > Sent").
            let canFallBack = harness != nil && name.split(separator: ">").count < 3
            // A model step (the task loop passes labels) and an installed pack's step (`exact`) press only the exact title,
            // natively or through agent-desktop; the user's own "menu <words>" and built-in packs may be closest.
            let exactOnly = exact || labelSnapshot != nil
            switch pressMenuItem(name, exactOnly: exactOnly) {
            case .pressed: return nil
            case .disabled(let title): return "menu item \(title) is disabled"
            case .refused(let title):
                guard canFallBack else { return "couldn't press menu item \(title)" }
            case .noMatch: break
            }
            guard canFallBack, let harness, !MenuMatch.isAppleMenuTitle(last) else { return "no menu item called \(last)" }
            guard let m = await harness.find(app: ax.frontmostAppName(), surface: .menubar, name: last) else {
                return "no menu item called \(last)"
            }
            if MenuMatch.isAppleMenuTitle(m.name) || MenuMatch.isLookalike(m.name) { return "no menu item called \(last)" }
            // agent-desktop falls back to a contains match; an exact step may press only the title it named.
            if exactOnly, MenuMatch.plain(m.name) != MenuMatch.plain(last) { return "no menu item called \(last)" }
            if m.disabled { return "menu item \(last) is disabled" }
            if let refusal = pressRefusal(title: m.name) { return refusal }
            return outcome(await harness.act(.click(ref: m.ref, button: .left, count: 1)))
        case .closeApp(let app):
            if let harness { return outcome(await harness.act(.closeApp(app))) }
            guard ax.activate(appNamed: app) else { return "no app named \(app)" }
            _ = await waitForFront(app)
            try input.press(KeyChord(.q, [.command]))
            return nil
        case .windowAction(let op, let app, let title):
            if let harness { return outcome(await harness.act(.window(op, app: app, title: title))) }
            if let app, !ax.activate(appNamed: app) { return "no app named \(app)" }
            switch op {
            case .focus: return nil
            case .minimize:
                if let app { _ = await waitForFront(app) }
                try input.press(KeyChord(.m, [.command]))
                return nil
            case .maximize, .restore: return Self.needsHarness
            }
        case .clipboardSet(let text):
            if let harness { return outcome(await harness.act(.clipboardSet(text: text))) }
            clipboard.write(text)
            return nil
        case .readClipboard:
            let text: String?
            if let harness { text = await harness.read(.clipboardGet) } else { text = clipboard.readText() ?? "" }
            guard let text else { return "couldn't read" }
            addReading("clipboard", text)
            return nil
        case .readValue(let t):
            let r = try await element(t)
            let text: String?
            if let harness, let ref = r.ref { text = await harness.read(.get(ref: ref, property: "value")) } else { text = r.value ?? "" }
            guard let text else { return "couldn't read" }
            addReading(r.title.isEmpty ? "value" : r.title, text)
            return nil
        case .readNotifications:
            guard let harness else { return Self.needsHarness }
            guard let text = await harness.read(.listNotifications) else { return "couldn't read" }
            addReading("notifications", text)
            return nil
        case .dismissNotifications(let app):
            guard let harness else { return Self.needsHarness }
            return outcome(await harness.act(.dismissAllNotifications(app: app)))
        case .waitFor(.mediaPlaying, let timeoutMs):
            return await waitForMediaPlaying(timeoutMs: timeoutMs)
        case .waitFor(let condition, let timeoutMs):
            guard let harness else {
                try? await Task.sleep(for: .milliseconds(min(timeoutMs, 5000)))
                return nil
            }
            let command: DesktopCommand
            let app = ax.frontmostAppName()
            switch condition {
            case .text(let s): command = .wait(.text, value: s, app: app, ref: nil, timeoutMs: timeoutMs)
            case .window(let s): command = .wait(.window, value: s, app: app, ref: nil, timeoutMs: timeoutMs)
            case .event(let e): command = .wait(.event, value: e.rawValue, app: app, ref: nil, timeoutMs: timeoutMs)
            case .menu: command = .wait(.menu, value: nil, app: app, ref: nil, timeoutMs: timeoutMs)
            case .menuClosed: command = .wait(.menuClosed, value: nil, app: app, ref: nil, timeoutMs: timeoutMs)
            case .element(let t, let predicate):
                let r = try await element(t)
                guard let ref = r.ref else { return Self.needsHarness }
                command = .wait(.element, value: predicate, app: nil, ref: ref, timeoutMs: timeoutMs)
            case .mediaPlaying: return nil   // handled above
            }
            switch await harness.act(command) {
            case .delivered: return nil
            case .elementChanged: return Self.elementChanged
            case .failed, .notDelivered: return "wait timed out"
            }
        default:
            return nil
        }
    }

    /// Pauses that a spoken stop does not cut short: a drag runs to its release, so it never stops with the button down.
    private static func pause(_ interval: Duration) async {
        await Task.detached { try? await Task.sleep(for: interval) }.value
    }

    private static let dragSteps = 10

    private func drag(from: MoveTarget, to: MoveTarget) async throws -> String? {
        // The labels or grid are stale once something has moved ("click 12" hides them the same way).
        var usedOverlay = false
        for case .numbered in [from, to] where overlayShown { usedOverlay = true }
        if let harness {
            func endpoint(_ t: MoveTarget) -> (ref: String?, xy: CGPoint?, failure: String?) {
                if case .label(let n) = t, let e = labelSnapshot?[n], let ref = e.ref { return (ref, nil, nil) }
                switch resolveMove(t) {
                case .point(let p): return (nil, p, nil)
                case .failure(let m): return (nil, nil, m)
                }
            }
            let a = endpoint(from), b = endpoint(to)
            if let m = a.failure ?? b.failure { return m }
            // A release on a guarded button presses it: checked before anything moves.
            if let xy = b.xy {
                if let refusal = pressRefusal(at: xy) { return refusal }
            } else if let ref = b.ref, let refusal = pressRefusal(title: labelSnapshot?.values.first(where: { $0.ref == ref })?.title) {
                return refusal
            }
            let m = outcome(await harness.act(.drag(fromRef: a.ref, fromXY: a.xy, toRef: b.ref, toXY: b.xy)))
            if m == nil, usedOverlay { hideStaleOverlay() }
            return m
        }
        guard case .point(let p1) = resolveMove(from) else { return "can't resolve drag start" }
        guard case .point(let p2) = resolveMove(to) else { return "can't resolve drag end" }
        // Checked before the button goes down: a release on a guarded button presses it.
        if let refusal = pressRefusal(at: p2) { return refusal }
        // Finder and most apps ignore a drag that arrives in one jump: press, wait, move in steps, wait, release.
        try input.moveMouse(to: p1)
        dragInFlight = true
        defer { dragInFlight = false }
        try input.mouseDown(.left, at: p1)
        do {
            await Self.pause(.milliseconds(100))
            for i in 1...Self.dragSteps {
                let t = CGFloat(i) / CGFloat(Self.dragSteps)
                try input.moveMouse(to: CGPoint(x: p1.x + (p2.x - p1.x) * t, y: p1.y + (p2.y - p1.y) * t))
                await Self.pause(.milliseconds(15))
            }
            await Self.pause(.milliseconds(50))
            try input.mouseUp(.left, at: p2)
        } catch {
            input.releaseAll()   // a drag that fails half way must not leave the button down
            throw error
        }
        if usedOverlay { hideStaleOverlay() }
        return nil
    }

    private func outcome(_ r: HarnessActionResult) -> String? {
        switch r {
        case .delivered: nil
        case .failed(let m), .notDelivered(let m): m
        case .elementChanged: Self.elementChanged
        }
    }

    private func element(_ t: ElementTarget) async throws -> Resolved {
        try await resolve(t).get()
    }

    private func label(_ t: ElementTarget) -> String {
        if case .label(let n) = t { return String(n) }
        return "?"
    }

    struct Unresolved: Error { var message: String }
    struct HarnessOnly: Error {}
}
