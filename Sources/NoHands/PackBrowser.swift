import AppKit
import Foundation
import NoHandsCore
import NoHandsMac

/// The Browse window for the pack registry (NH-85). It fetches the registry's signed list when it opens and when Reload
/// is pressed, never otherwise. Install and Update download and check the pack, show what it does in an alert whose
/// default button is Cancel, and write it only on the other button. Nothing is fetched after that choice.
@MainActor
final class PackBrowserController: NSObject, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate {
    enum Mode { case browse, updates }

    private struct Row {
        let entry: RegistryEntry
        var decision: PackFetcher.Decision
        /// What to show instead of the state: progress, or why this pack failed.
        var note: String?
        var failed = false
    }

    private let store: PackStore
    /// Runs an alert with listening paused, so a spoken "press return" can't answer it.
    private let runAlert: (NSAlert) -> NSApplication.ModalResponse
    private let window: NSWindow
    private let table = NSTableView()
    private let status = NSTextField(labelWithString: "")
    private let reloadButton = NSButton(title: "Reload", target: nil, action: nil)

    private var config = AppConfig()
    private var mode = Mode.browse
    private var rows: [Row] = []
    private var fetcher: PackFetcher?
    /// Bumped on every load and on close, so an answer that arrives for an older one is dropped.
    private var generation = 0
    private var busy = false

    private static let columns: [(id: String, title: String, width: CGFloat)] = [
        ("pack", "Pack", 190), ("about", "What it does", 330), ("state", "State", 170), ("action", "", 90)]

    init(store: PackStore, runAlert: @escaping (NSAlert) -> NSApplication.ModalResponse) {
        self.store = store
        self.runAlert = runAlert
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 420),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        super.init()
        window.title = "NoHands Packs"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.setFrameAutosaveName("NoHandsPacks")

        for column in Self.columns {
            let c = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(column.id))
            c.title = column.title
            c.width = column.width
            table.addTableColumn(c)
        }
        table.rowHeight = 44
        table.dataSource = self
        table.delegate = self
        table.allowsEmptySelection = true
        let list = NSScrollView()
        list.documentView = table
        list.hasVerticalScroller = true

        status.lineBreakMode = .byTruncatingTail
        reloadButton.target = self
        reloadButton.action = #selector(reloadClicked)
        let top = NSStackView(views: [status, reloadButton])
        top.orientation = .horizontal
        status.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let root = NSStackView(views: [top, list])
        root.orientation = .vertical
        root.alignment = .leading
        root.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        root.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = NSView()
        window.contentView?.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor),
            root.topAnchor.constraint(equalTo: window.contentView!.topAnchor),
            root.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor),
            top.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -24),
            list.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -24),
        ])
    }

    /// Opens the window and loads the registry's list once.
    func show(_ mode: Mode, config: AppConfig) {
        self.mode = mode
        self.config = config
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        reload()
    }

    func windowWillClose(_ notification: Notification) { generation += 1 }

    @objc private func reloadClicked() { reload() }

    // MARK: Loading

    private func reload() {
        guard !busy else { return }
        generation += 1
        let mine = generation
        rows = []
        table.reloadData()
        let url: URL, keys: [PackRegistry.TrustedKey]
        switch RegistryStatus(config: config) {
        case .unavailable(_, let reason):
            status.stringValue = reason
            fetcher = nil
            return
        case .ready(let u, let k): (url, keys) = (u, k)
        }
        let fetcher = PackFetcher(registry: url, trusting: keys, session: PackFetcher.session(), state: RegistryState())
        self.fetcher = fetcher
        status.stringValue = "Loading…"
        reloadButton.isEnabled = false
        Task { [weak self] in
            let result = await Self.loadIndex(fetcher)
            self?.loaded(result, generation: mine)
        }
    }

    private nonisolated static func loadIndex(_ fetcher: PackFetcher) async -> Result<RegistryIndex, FetchError> {
        do throws(FetchError) { return .success(try await fetcher.fetchIndex()) } catch { return .failure(error) }
    }

    private nonisolated static func download(_ fetcher: PackFetcher, _ entry: RegistryEntry) async -> Result<(data: Data, pack: AppPack), FetchError> {
        do throws(FetchError) { return .success(try await fetcher.fetchVerifiedPack(entry)) } catch { return .failure(error) }
    }

    private func loaded(_ result: Result<RegistryIndex, FetchError>, generation mine: Int) {
        guard mine == generation else { return }
        reloadButton.isEnabled = true
        switch result {
        case .failure(let error):
            status.stringValue = error.userMessage
        case .success(let index):
            let installed = (try? store.list()) ?? []
            rows = index.packs.map { entry in
                Row(entry: entry, decision: PackFetcher.decision(entry: entry, installedVersion: version(of: entry.id, in: installed)))
            }
            if mode == .updates { rows.sort { ($0.decision == .update ? 0 : 1) < ($1.decision == .update ? 0 : 1) } }
            updateStatus()
            table.reloadData()
        }
    }

    private func version(of id: String, in installed: [PackStore.Entry]) -> String? { installed.first { $0.id == id }?.pack?.version }

    private func updateStatus() {
        let updates = rows.filter { $0.decision == .update }.count
        switch mode {
        case .updates: status.stringValue = updates == 0 ? "All packs up to date" : "\(updates) \(updates == 1 ? "update" : "updates")"
        case .browse: status.stringValue = rows.isEmpty ? "The registry lists no packs" : "\(rows.count) \(rows.count == 1 ? "pack" : "packs")"
        }
    }

    // MARK: Install and update

    @objc private func actionClicked(_ sender: NSButton) {
        let index = table.row(for: sender)
        guard !busy, rows.indices.contains(index), let fetcher, [.install, .update].contains(rows[index].decision) else { return }
        let entry = rows[index].entry
        busy = true
        reloadButton.isEnabled = false
        setNote(entry.id, "Downloading…")
        Task { [weak self] in
            let result = await Self.download(fetcher, entry)
            self?.downloaded(result, for: entry)
        }
    }

    private func setNote(_ id: String, _ note: String?, failed: Bool = false) {
        guard let at = rows.firstIndex(where: { $0.entry.id == id }) else { return }
        rows[at].note = note
        rows[at].failed = failed
        table.reloadData(forRowIndexes: [at], columnIndexes: IndexSet(0..<Self.columns.count))
    }

    private func downloaded(_ result: Result<(data: Data, pack: AppPack), FetchError>, for entry: RegistryEntry) {
        defer { busy = false; reloadButton.isEnabled = true }
        switch result {
        case .failure(let error): setNote(entry.id, error.userMessage, failed: true)
        case .success(let (data, pack)): confirmAndInstall(data: data, pack: pack, entry: entry)
        }
    }

    /// The summary alert: Cancel is the default button (Return), so a stray key never installs. The pack is written only
    /// on the second button, from the bytes that were just checked.
    private func confirmAndInstall(data: Data, pack: AppPack, entry: RegistryEntry) {
        let installed = (try? store.list()) ?? []
        let old = installed.first { $0.id == pack.id }?.pack
        // From what is on disk now, not the row: the pack may have changed since the list loaded.
        let fresh = PackFetcher.decision(entry: entry, installedVersion: old?.version)
        guard fresh == .install || fresh == .update else { setNote(entry.id, fresh.userMessage, failed: true); refreshDecisions(); return }
        let isUpdate = fresh == .update
        let verb = isUpdate ? "Update" : "Install"
        let alert = NSAlert()
        alert.messageText = "\(verb) \(PackSummary.printable(pack.name)) \(PackSummary.printable(pack.version))?"
        alert.informativeText = "From the pack registry. Nothing is installed until you choose \(verb)."
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: verb)
        let text = NSTextView.scrollableTextView()
        text.frame = NSRect(x: 0, y: 0, width: 520, height: 260)
        if let view = text.documentView as? NSTextView {
            view.isEditable = false
            view.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
            view.string = PackSummaryText.text(for: pack, installed: installed, updating: isUpdate ? old : nil)
        }
        alert.accessoryView = text
        guard runAlert(alert) == .alertSecondButtonReturn else { setNote(entry.id, nil); return }
        // The alert can stay open a while: check again that this is still not a downgrade.
        let again = PackFetcher.decision(entry: entry, installedVersion: ((try? store.list()) ?? []).first { $0.id == pack.id }?.pack?.version)
        guard again == fresh else { setNote(entry.id, again.userMessage ?? "Changed while you were looking, try again", failed: true); refreshDecisions(); return }
        do {
            try store.install(data)
            setNote(entry.id, nil)
            refreshDecisions()
        } catch {
            setNote(entry.id, PackStore.message(for: error), failed: true)
        }
    }

    /// After an install, each row's state from what is on disk now. No fetch.
    private func refreshDecisions() {
        let installed = (try? store.list()) ?? []
        for at in rows.indices {
            rows[at].decision = PackFetcher.decision(entry: rows[at].entry, installedVersion: version(of: rows[at].entry.id, in: installed))
        }
        updateStatus()
        table.reloadData()
    }

    // MARK: Table

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard rows.indices.contains(row), let id = tableColumn?.identifier.rawValue else { return nil }
        let r = rows[row], e = r.entry
        let show = PackSummary.printable
        switch id {
        case "pack":
            return label(show(e.name) + " " + show(e.version) + (e.author.isEmpty ? "" : "\nby " + show(e.author)))
        case "about":
            return label((e.description.isEmpty ? "" : show(e.description) + "\n") + "Works in: " + e.bundleIDs.map(show).joined(separator: ", "))
        case "state":
            let text = r.note ?? PackFetcher.stateLabel(r.decision, entry: e)
            let view = label(text.isEmpty ? (r.decision.userMessage ?? "") : text)
            view.textColor = r.failed ? .systemRed : .secondaryLabelColor
            return view
        default:
            guard r.note == nil || r.failed, [.install, .update].contains(r.decision) else { return nil }
            let button = NSButton(title: r.decision == .update ? "Update" : "Install", target: self, action: #selector(actionClicked(_:)))
            button.bezelStyle = .rounded
            return button
        }
    }

    private func label(_ text: String) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        field.maximumNumberOfLines = 2
        field.lineBreakMode = .byTruncatingTail
        field.font = .systemFont(ofSize: 12)
        return field
    }
}
