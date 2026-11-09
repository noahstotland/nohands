import AppKit
import NoHandsCore

@MainActor
public final class OverlayController {
    public private(set) var state: OverlayState = .none

    private var gridPanel: NSPanel?
    private var labelsPanels: [NSPanel] = []
    /// The prompts and notices at the top of the screen (see `PromptBoard`).
    private var board = PromptBoard()
    private var boardPanel: NSPanel?
    /// Redraws the board when its next row is due to leave.
    private var boardTask: Task<Void, Never>?
    /// The always-on status bar (see `StatusBarText`): app state and mode come from `setAppState`, the rest from the board.
    private var statusPanel: NSPanel?
    private var statusMenu: MenuState = .loading
    private var statusMode: Mode = .command
    private var shownStatus: (line: StatusLine, size: CGSize)?

    /// Where the status bar sits; changing it redraws at once.
    public var statusBarPosition: StatusBarPosition = .top {
        didSet { if statusBarPosition != oldValue { renderBoard() } }
    }

    public init() {}

    // MARK: Public API

    public func showGrid(_ grid: GridModel) {
        removeLabelsPanels()
        let panel = gridPanel ?? Self.makePanel()
        gridPanel = panel
        let h = Self.primaryHeight
        let frame = CoordinateMapper.toAppKit(grid.bounds, primaryScreenHeight: h)
        panel.setFrame(frame, display: false)
        panel.contentView = GridView(frame: CGRect(origin: .zero, size: frame.size), grid: grid)
        panel.orderFrontRegardless()
        state = .grid(grid)
        renderBoard()
    }

    public func showLabels(_ labels: [Int: UIElementInfo]) {
        removeGridPanel()
        removeLabelsPanels()
        let screensCG = Self.allScreensCG()
        let h = Self.primaryHeight
        let drawn = OverlayMath.drawnLabels(labels, screens: screensCG)
        var perScreen = [[Int: UIElementInfo]](repeating: [:], count: screensCG.count)
        for (n, e) in drawn {
            if let i = OverlayMath.screenIndex(for: e.frame, in: screensCG) { perScreen[i][n] = e }
        }
        for (i, screen) in screensCG.enumerated() where !perScreen[i].isEmpty {
            let panel = Self.makePanel()
            let frame = CoordinateMapper.toAppKit(screen, primaryScreenHeight: h)
            panel.setFrame(frame, display: false)
            panel.contentView = LabelsView(frame: CGRect(origin: .zero, size: frame.size),
                                           labels: perScreen[i], screenCG: screen)
            panel.orderFrontRegardless()
            labelsPanels.append(panel)
        }
        state = .labels(drawn)
        renderBoard()
    }

    public func hide() {
        removeGridPanel()
        removeLabelsPanels()
        state = .none
        renderBoard()
    }

    /// The app state and mode the status bar shows when no prompt is live (called from the menu refresh).
    public func setAppState(_ menu: MenuState, mode: Mode) {
        let changed = menu != statusMenu || mode != statusMode
        statusMenu = menu
        statusMode = mode
        if changed { renderBoard() } else { renderStatusBar() }
    }

    /// A transient notice line on the board (loading, listening, an error).
    public func showHUD(_ text: String, duration: Duration = .seconds(1.5)) {
        guard let shown = OverlayMath.hudText(text, maxChars: 80) else { return }
        board.notice(shown, for: duration, now: .now)
        renderBoard()
    }

    /// The prompt's row: its words on the left, how far it has got on the right.
    public func report(_ id: Int, text: String, status: PromptStatus) {
        board.report(id: id, text: OverlayMath.hudText(text, maxChars: 80) ?? "…", status: status, now: .now)
        renderBoard()
    }

    /// A running task's step trail, kept on the prompt's row.
    public func report(_ id: Int, trail: TaskTrail) {
        board.report(id: id, trail: trail, now: .now)
        renderBoard()
    }

    static let boardWidth: CGFloat = 720
    static let boardRowHeight: CGFloat = 30
    static let boardPadding: CGFloat = 8

    /// Draws the board below the menu bar of the screen the pointer is on, and schedules the next redraw for when
    /// a row is due to leave. An empty board hides the panel.
    private func renderBoard() {
        boardTask?.cancel()
        boardTask = nil
        let now = ContinuousClock.now
        board.prune(now: now)
        let rows = board.visibleRows(now: now)
        let notice = board.visibleNotice(now: now)
        renderStatusBar()
        guard !rows.isEmpty || notice != nil else {
            boardPanel?.orderOut(nil)
            return
        }
        let screenCG = Self.visibleBoundsCG(containing: Self.pointerCG())
        let width = min(Self.boardWidth, max(200, screenCG.width - 32))
        let lines = rows.count + (notice == nil ? 0 : 1)
        let size = CGSize(width: width, height: CGFloat(lines) * Self.boardRowHeight + Self.boardPadding * 2)
        let originCG = CGPoint(x: screenCG.midX - size.width / 2, y: screenCG.minY + 8 + (statusBarShown && statusBarPosition == .top ? Self.statusBarHeight + 6 : 0))
        let frame = CoordinateMapper.toAppKit(CGRect(origin: originCG, size: size), primaryScreenHeight: Self.primaryHeight)
        let panel = boardPanel ?? Self.makePanel()
        boardPanel = panel
        panel.setFrame(frame, display: false)
        panel.contentView = BoardView(frame: CGRect(origin: .zero, size: size), rows: rows, notice: notice)
        panel.orderFrontRegardless()
        if let next = board.nextChange(now: now) {
            boardTask = Task { [weak self] in
                try? await Task.sleep(until: next.advanced(by: .milliseconds(20)), clock: .continuous)
                guard !Task.isCancelled, let self else { return }
                self.renderBoard()
            }
        }
    }

    static let statusBarHeight: CGFloat = 28

    /// Hidden while the grid or number badges are up, so it never covers a badge or a grid number.
    private var statusBarShown: Bool { statusBarPosition != .off && state == .none }

    /// Draws the bar centred on the screen the pointer is on, 8 pt below the menu bar or above the Dock.
    private func renderStatusBar() {
        guard statusBarShown else {
            statusPanel?.orderOut(nil)
            shownStatus = nil
            return
        }
        let line = StatusBarText.line(menu: statusMenu, mode: statusMode, rows: board.visibleRows(now: .now))
        let screenCG = Self.visibleBoundsCG(containing: Self.pointerCG())
        let textW = StatusBarView.textWidth(line.text)
        let width = min(max(160, textW + 44), min(520, max(160, screenCG.width - 32)))
        let size = CGSize(width: width, height: Self.statusBarHeight)
        let y = statusBarPosition == .bottom ? screenCG.maxY - 8 - size.height : screenCG.minY + 8
        let originCG = CGPoint(x: screenCG.midX - size.width / 2, y: y)
        let frame = CoordinateMapper.toAppKit(CGRect(origin: originCG, size: size), primaryScreenHeight: Self.primaryHeight)
        let panel = statusPanel ?? Self.makePanel()
        statusPanel = panel
        if panel.frame != frame { panel.setFrame(frame, display: false) }
        if shownStatus?.line != line || shownStatus?.size != size {
            panel.contentView = StatusBarView(frame: CGRect(origin: .zero, size: size), line: line)
            shownStatus = (line, size)
        }
        panel.orderFrontRegardless()
    }

    /// CG-space (top-left origin) bounds of the screen containing `point`; primary screen if none does.
    public static func screenBoundsCG(containing point: CGPoint) -> CGRect {
        let rects = allScreensCG()
        return rects.first(where: { $0.contains(point) }) ?? rects.first ?? .zero
    }

    /// Like `screenBoundsCG` but excludes the menu bar and Dock.
    private static func visibleBoundsCG(containing point: CGPoint) -> CGRect {
        let h = primaryHeight
        let screens = NSScreen.screens
        let screen = screens.first(where: { CoordinateMapper.toAppKit($0.frame, primaryScreenHeight: h).contains(point) }) ?? screens.first
        guard let screen else { return .zero }
        return CoordinateMapper.toAppKit(screen.visibleFrame, primaryScreenHeight: h)
    }

    // MARK: Helpers

    private static var primaryHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

    private static func allScreensCG() -> [CGRect] {
        let h = primaryHeight
        return NSScreen.screens.map { CoordinateMapper.toAppKit($0.frame, primaryScreenHeight: h) }
    }

    private static func pointerCG() -> CGPoint {
        CoordinateMapper.toCG(NSEvent.mouseLocation, primaryScreenHeight: primaryHeight)
    }

    private func removeGridPanel() { gridPanel?.orderOut(nil); gridPanel = nil }
    private func removeLabelsPanels() { labelsPanels.forEach { $0.orderOut(nil) }; labelsPanels = [] }

    private static func makePanel() -> NSPanel {
        let p = OverlayPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered, defer: false)
        p.level = .screenSaver
        p.ignoresMouseEvents = true
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = false
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        return p
    }
}

private final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - Views (flipped: origin top-left, matching CG space)

private final class GridView: NSView {
    let grid: GridModel
    init(frame: CGRect, grid: GridModel) { self.grid = grid; super.init(frame: frame) }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let cw = grid.bounds.width / CGFloat(grid.columns)
        let ch = grid.bounds.height / CGFloat(grid.rows)
        let font = NSFont.monospacedSystemFont(ofSize: OverlayMath.fontSize(forCell: CGSize(width: cw, height: ch)), weight: .bold)
        let shadow = NSShadow()
        shadow.shadowColor = .black
        shadow.shadowBlurRadius = 2
        shadow.shadowOffset = .zero
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: NSColor.white, .shadow: shadow,
            .strokeColor: NSColor.black, .strokeWidth: -2.0,
        ]
        let lines = NSBezierPath()
        let w = grid.bounds.width, hgt = grid.bounds.height
        for c in 0...grid.columns {
            let x = min(CGFloat(c) * cw, w - 0.5) + (c == 0 ? 0.5 : 0)
            lines.move(to: CGPoint(x: x, y: 0)); lines.line(to: CGPoint(x: x, y: hgt))
        }
        for r in 0...grid.rows {
            let y = min(CGFloat(r) * ch, hgt - 0.5) + (r == 0 ? 0.5 : 0)
            lines.move(to: CGPoint(x: 0, y: y)); lines.line(to: CGPoint(x: w, y: y))
        }
        NSColor(white: 0, alpha: 0.35).setStroke()
        lines.lineWidth = 2; lines.stroke()
        NSColor(white: 1, alpha: 0.25).setStroke()
        lines.lineWidth = 1; lines.stroke()
        for n in 1...grid.cellCount {
            guard let f = grid.frame(of: n) else { continue }
            let r = CGRect(x: f.minX - grid.bounds.minX, y: f.minY - grid.bounds.minY, width: f.width, height: f.height)
            let s = NSAttributedString(string: String(n), attributes: attrs)
            let sz = s.size()
            s.draw(at: CGPoint(x: r.midX - sz.width / 2, y: r.midY - sz.height / 2))
        }
    }
}

private final class LabelsView: NSView {
    let labels: [Int: UIElementInfo]
    let screenCG: CGRect
    init(frame: CGRect, labels: [Int: UIElementInfo], screenCG: CGRect) {
        self.labels = labels; self.screenCG = screenCG
        super.init(frame: frame)
    }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .bold)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor(white: 0.1, alpha: 1)]
        let bg = NSColor(calibratedRed: 1, green: 0.88, blue: 0.3, alpha: 0.95)
        let border = NSColor(white: 0, alpha: 0.6)
        for n in labels.keys.sorted() {
            guard let e = labels[n] else { continue }
            let s = NSAttributedString(string: String(n), attributes: attrs)
            let ts = s.size()
            let size = CGSize(width: ceil(ts.width) + 8, height: ceil(ts.height) + 2)
            let o = OverlayMath.badgeOrigin(for: e.frame, badgeSize: size, in: screenCG)
            let r = CGRect(x: o.x - screenCG.minX, y: o.y - screenCG.minY, width: size.width, height: size.height)
            let path = NSBezierPath(roundedRect: r, xRadius: 4, yRadius: 4)
            bg.setFill(); path.fill()
            border.setStroke(); path.lineWidth = 1; path.stroke()
            s.draw(at: CGPoint(x: r.minX + 4, y: r.minY + 1))
        }
    }
}

/// The board: one line per prompt (a tone dot, the words, the status on the right) and an optional notice line.
private final class BoardView: NSView {
    let rows: [PromptRow]
    let notice: PromptNotice?
    init(frame: CGRect, rows: [PromptRow], notice: PromptNotice?) {
        self.rows = rows; self.notice = notice; super.init(frame: frame)
    }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }

    static func color(_ tone: PromptStatus.Tone) -> NSColor {
        switch tone {
        case .active: NSColor(calibratedRed: 0.45, green: 0.72, blue: 1, alpha: 1)
        case .waiting: NSColor(calibratedRed: 1, green: 0.8, blue: 0.3, alpha: 1)
        case .good: NSColor(calibratedRed: 0.45, green: 0.85, blue: 0.5, alpha: 1)
        case .bad: NSColor(calibratedRed: 1, green: 0.45, blue: 0.45, alpha: 1)
        case .muted: NSColor(white: 0.7, alpha: 1)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(white: 0.08, alpha: 0.88).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 12, yRadius: 12).fill()
        let rowH = OverlayController.boardRowHeight, pad = OverlayController.boardPadding
        let tail = NSMutableParagraphStyle()
        tail.lineBreakMode = .byTruncatingTail
        let promptAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .medium), .foregroundColor: NSColor.white, .paragraphStyle: tail,
        ]
        var y = pad
        if let notice {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 14, weight: .regular), .foregroundColor: NSColor(white: 0.85, alpha: 1),
                .paragraphStyle: tail,
            ]
            let s = NSAttributedString(string: notice.text, attributes: attrs)
            let h = s.size().height
            s.draw(with: CGRect(x: 16, y: y + (rowH - h) / 2, width: bounds.width - 32, height: h),
                   options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
            y += rowH
        }
        for row in rows {
            let color = Self.color(row.status.tone)
            color.setFill()
            NSBezierPath(ovalIn: CGRect(x: 14, y: y + rowH / 2 - 4, width: 8, height: 8)).fill()
            let statusAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 13, weight: .regular), .foregroundColor: color, .paragraphStyle: tail,
            ]
            let status = NSAttributedString(string: row.status.text, attributes: statusAttrs)
            let prompt = NSAttributedString(string: row.text, attributes: promptAttrs)
            let inner = bounds.width - 30 - 16
            // The words get what they need up to half the line; the status takes the rest.
            let promptW = min(ceil(prompt.size().width), inner * 0.5)
            let statusW = inner - promptW - 12
            let ph = prompt.size().height, sh = status.size().height
            prompt.draw(with: CGRect(x: 30, y: y + (rowH - ph) / 2, width: promptW, height: ph),
                        options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
            let sw = min(ceil(status.size().width), statusW)
            status.draw(with: CGRect(x: bounds.width - 16 - sw, y: y + (rowH - sh) / 2, width: sw, height: sh),
                        options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
            y += rowH
        }
    }
}

/// The status bar: a tone dot and one line of text on the board's dark capsule.
private final class StatusBarView: NSView {
    let line: StatusLine
    init(frame: CGRect, line: StatusLine) { self.line = line; super.init(frame: frame) }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }

    static let font = NSFont.systemFont(ofSize: 13, weight: .medium)

    static func textWidth(_ text: String) -> CGFloat {
        ceil(NSAttributedString(string: text, attributes: [.font: font]).size().width)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(white: 0.08, alpha: 0.88).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2).fill()
        BoardView.color(line.tone).setFill()
        NSBezierPath(ovalIn: CGRect(x: 14, y: bounds.height / 2 - 4, width: 8, height: 8)).fill()
        let tail = NSMutableParagraphStyle()
        tail.lineBreakMode = .byTruncatingTail
        let s = NSAttributedString(string: line.text, attributes: [
            .font: Self.font, .foregroundColor: NSColor.white, .paragraphStyle: tail,
        ])
        let h = s.size().height
        s.draw(with: CGRect(x: 30, y: (bounds.height - h) / 2, width: bounds.width - 44, height: h),
               options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }
}
