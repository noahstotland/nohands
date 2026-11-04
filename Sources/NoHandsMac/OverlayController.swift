import AppKit
import NoHandsCore

@MainActor
public final class OverlayController {
    public private(set) var state: OverlayState = .none

    private var gridPanel: NSPanel?
    private var labelsPanels: [NSPanel] = []
    private var hudPanel: NSPanel?
    private var hudGeneration = 0
    private var hudTask: Task<Void, Never>?

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
    }

    public func showLabels(_ labels: [Int: UIElementInfo]) {
        removeGridPanel()
        removeLabelsPanels()
        let screensCG = Self.allScreensCG()
        let h = Self.primaryHeight
        var perScreen = [[Int: UIElementInfo]](repeating: [:], count: screensCG.count)
        for (n, e) in labels {
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
        state = .labels(labels)
    }

    public func hide() {
        removeGridPanel()
        removeLabelsPanels()
        state = .none
    }

    public func showHUD(_ text: String, duration: Duration = .seconds(1.5)) {
        hudTask?.cancel()
        hudGeneration += 1
        let generation = hudGeneration
        guard let shown = OverlayMath.hudText(text, maxChars: 80) else {
            hudPanel?.orderOut(nil)
            return
        }

        let font = NSFont.systemFont(ofSize: 18, weight: .medium)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
        let textSize = (shown as NSString).size(withAttributes: attrs)
        let size = CGSize(width: ceil(textSize.width) + 36, height: ceil(textSize.height) + 18)

        let screenCG = Self.visibleBoundsCG(containing: Self.pointerCG())
        let originCG = CGPoint(x: screenCG.midX - size.width / 2, y: screenCG.maxY - size.height - 40)
        let frame = CoordinateMapper.toAppKit(CGRect(origin: originCG, size: size),
                                              primaryScreenHeight: Self.primaryHeight)
        let panel = hudPanel ?? Self.makePanel()
        hudPanel = panel
        panel.setFrame(frame, display: false)
        panel.contentView = HUDView(frame: CGRect(origin: .zero, size: size), text: shown, attrs: attrs)
        panel.orderFrontRegardless()

        hudTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled, let self, self.hudGeneration == generation else { return }
            self.hudPanel?.orderOut(nil)
        }
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

private final class HUDView: NSView {
    let text: String
    let attrs: [NSAttributedString.Key: Any]
    init(frame: CGRect, text: String, attrs: [NSAttributedString.Key: Any]) {
        self.text = text; self.attrs = attrs; super.init(frame: frame)
    }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(white: 0.08, alpha: 0.88).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2).fill()
        let s = NSAttributedString(string: text, attributes: attrs)
        let sz = s.size()
        s.draw(at: CGPoint(x: bounds.midX - sz.width / 2, y: bounds.midY - sz.height / 2))
    }
}
