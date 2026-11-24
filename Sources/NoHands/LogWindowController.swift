import AppKit
import Foundation
import NoHandsCore
import NoHandsMac

/// The View Logs window: the recent commands on the left, the selected command's steps on the right. One window,
/// reused; it follows the store live. Nothing here is sent anywhere.
@MainActor
final class LogWindowController: NSObject, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate {
    private let store: CommandLogStore
    private let window: NSWindow
    private let table = NSTableView()
    private let text = NSTextView.scrollableTextView()
    private var detail: NSTextView { text.documentView as! NSTextView }
    private var selectedID: UUID?

    init(store: CommandLogStore) {
        self.store = store
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 880, height: 540),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        super.init()
        window.title = "NoHands Logs"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.setFrameAutosaveName("NoHandsLogs")

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("command"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = 22
        table.dataSource = self
        table.delegate = self
        let list = NSScrollView()
        list.documentView = table
        list.hasVerticalScroller = true

        detail.isEditable = false
        detail.isSelectable = true
        detail.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        detail.textContainerInset = NSSize(width: 10, height: 10)

        let split = NSSplitView()
        split.isVertical = true
        split.dividerStyle = .thin
        split.addArrangedSubview(list)
        split.addArrangedSubview(text)
        list.widthAnchor.constraint(greaterThanOrEqualToConstant: 240).isActive = true
        text.widthAnchor.constraint(greaterThanOrEqualToConstant: 320).isActive = true
        window.contentView = split
        split.setPosition(300, ofDividerAt: 0)
        reload()
    }

    /// Brings the window to the front (the app is a menu-bar app, so it activates first), on `id` when given.
    func show(selecting id: UUID? = nil) {
        if let id { selectedID = id }
        reload()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// Redraws from the store, keeping the selected command selected as new ones arrive.
    func reload() {
        let entries = store.log.entries
        let selectedBefore = table.selectedRow
        table.reloadData()
        if let id = selectedID, let row = entries.firstIndex(where: { $0.id == id }) {
            let changed = selectedBefore != row
            table.selectRowIndexes([row], byExtendingSelection: false)
            if changed { table.scrollRowToVisible(row) }
        } else if let first = entries.first {
            selectedID = first.id
            table.selectRowIndexes([0], byExtendingSelection: false)
        } else {
            selectedID = nil
        }
        showDetail()
    }

    private func showDetail() {
        if let id = selectedID, let entry = store.log.entries.first(where: { $0.id == id }) {
            detail.string = CommandLogText.detail(entry)
        } else {
            detail.string = "No commands yet"
        }
    }

    // MARK: table

    func numberOfRows(in tableView: NSTableView) -> Int { store.log.entries.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let field = NSTextField(labelWithString: CommandLogText.listLine(store.log.entries[row]))
        field.lineBreakMode = .byTruncatingTail
        return field
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = table.selectedRow
        guard row >= 0, row < store.log.entries.count else { return }
        selectedID = store.log.entries[row].id
        showDetail()
    }
}
