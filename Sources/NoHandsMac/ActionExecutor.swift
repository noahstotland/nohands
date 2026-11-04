import Foundation
import CoreGraphics
import NoHandsCore

/// What the executor needs from the accessibility layer (AXQuery conforms).
public protocol ElementProviding: Sendable {
    func actionableElements() -> [UIElementInfo]
    func screenRectsCG() -> [CGRect]
    func activate(appNamed: String) -> Bool
    func frontmostAppName() -> String?
}

extension AXQuery: ElementProviding {
    public func screenRectsCG() -> [CGRect] { AXQuery.screenRectsCG() }
}

/// What the executor needs from the overlay (OverlayController conforms).
@MainActor public protocol OverlayPresenting: AnyObject {
    var state: OverlayState { get }
    func showGrid(_ grid: GridModel)
    func showLabels(_ labels: [Int: UIElementInfo])
    func hide()
    func showHUD(_ text: String, duration: Duration)
    func screenBoundsCG(containing point: CGPoint) -> CGRect
}

extension OverlayController: OverlayPresenting {
    public func screenBoundsCG(containing point: CGPoint) -> CGRect { OverlayController.screenBoundsCG(containing: point) }
}

@MainActor public final class ActionExecutor {
    /// Guards against runaway LLM output being typed into the focused app.
    public static let maxTypedCharacters = 2000

    private let input: any InputSynthesizing
    private let ax: any ElementProviding
    private let overlay: any OverlayPresenting
    private let config: AppConfig
    public var onModeChange: ((Mode) -> Void)?
    private let frontTimeout: Duration
    private var pressed: Set<MouseButton> = []

    public init(input: any InputSynthesizing, ax: any ElementProviding, overlay: any OverlayPresenting,
                config: AppConfig, frontTimeout: Duration = .seconds(1.5)) {
        self.frontTimeout = frontTimeout
        self.input = input
        self.ax = ax
        self.overlay = overlay
        self.config = config
    }

    /// Executes in order; stops at the first failure and shows it in the HUD. Returns the failure message if any.
    /// Any mouse button pressed by this call is released before a failure is returned.
    @discardableResult
    public func execute(_ actions: [Action]) async -> String? {
        pressed = []
        for (i, action) in actions.enumerated() {
            if let message = await run(action, isLast: i == actions.count - 1) {
                for b in pressed.sorted(by: { $0.rawValue < $1.rawValue }) {
                    try? input.mouseUp(b, at: input.currentMouseLocation())
                }
                pressed = []
                overlay.showHUD(message, duration: .seconds(1.5))
                return message
            }
        }
        return nil
    }

    private func run(_ action: Action, isLast: Bool) async -> String? {
        do {
            switch action {
            case .typeText(let text):
                guard text.count <= Self.maxTypedCharacters else { return "text too long" }
                try input.type(text)
                hideStaleOverlay()
            case .pressKey(let chord):
                try input.press(chord)
                hideStaleOverlay()
            case .click(let target, let button, let count):
                guard (1...3).contains(count) else { return "bad click count" }
                let usedOverlay: Bool
                if case .numbered = target { usedOverlay = overlay.state != .none } else { usedOverlay = false }
                switch resolveClick(target) {
                case .failure(let m): return m
                case .point(let p):
                    try input.click(at: p, button: button, count: count)
                    if usedOverlay { overlay.hide() }
                }
            case .pressMouse(let b):
                try input.mouseDown(b, at: input.currentMouseLocation())
                pressed.insert(b)
            case .releaseMouse(let b):
                try input.mouseUp(b, at: input.currentMouseLocation())
                pressed.remove(b)
            case .moveCursor(let target):
                switch resolveMove(target) {
                case .failure(let m): return m
                case .point(let p): try input.moveMouse(to: p)
                }
            case .scroll(let direction, let amount):
                guard (1...100).contains(amount) else { return "bad scroll amount" }
                try input.scroll(direction, lines: amount)
                hideStaleOverlay()
            case .showGrid:
                let bounds = overlay.screenBoundsCG(containing: input.currentMouseLocation())
                overlay.showGrid(GridModel(bounds: bounds, columns: config.gridColumns, rows: config.gridRows))
            case .zoomGrid(let n):
                guard case .grid(let g) = overlay.state else { return "no grid shown" }
                guard let zoomed = g.zoomed(into: n) else { return "no cell \(n)" }
                overlay.showGrid(zoomed)
            case .showLabels:
                overlay.showLabels(LabelAssigner.assign(ax.actionableElements()))
            case .hideOverlay:
                overlay.hide()
            case .setMode(let mode):
                onModeChange?(mode)
            case .openApp(let name):
                guard ax.activate(appNamed: name) else { return "no app named \(name)" }
                hideStaleOverlay()
                let arrived = await waitForFront(name)
                if !arrived && !isLast { return "app did not come to front" }
            case .ignore:
                break
            }
            return nil
        } catch {
            return "couldn't post input event"
        }
    }

    private func hideStaleOverlay() { if overlay.state != .none { overlay.hide() } }

    private func waitForFront(_ name: String) async -> Bool {
        let want = name.lowercased()
        func isFront() -> Bool {
            guard let f = ax.frontmostAppName()?.lowercased(), !f.isEmpty else { return false }
            return f == want || f.contains(want) || want.contains(f)
        }
        let deadline = ContinuousClock.now.advanced(by: frontTimeout)
        while !isFront() {
            if ContinuousClock.now >= deadline { return false }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return true
    }

    /// Rejects points outside every screen (skipped when no screens are known).
    private func checkOnScreen(_ r: TargetResolution, checked: Bool) -> TargetResolution {
        guard checked, case .point(let p) = r else { return r }
        let screens = ax.screenRectsCG()
        if screens.isEmpty || screens.contains(where: { $0.contains(p) }) { return r }
        return .failure("point off screen")
    }

    private func elementsIfNeeded(named: Bool) -> [UIElementInfo] { named ? ax.actionableElements() : [] }

    private func resolveClick(_ t: ClickTarget) -> TargetResolution {
        var needsElements = false, direct = false
        if case .element = t { needsElements = true }
        if case .point = t { direct = true }
        return checkOnScreen(TargetResolver.resolveClick(t, overlay: overlay.state, cursor: input.currentMouseLocation(),
                                           elements: elementsIfNeeded(named: needsElements),
                                           screens: ax.screenRectsCG()), checked: direct)
    }

    private func resolveMove(_ t: MoveTarget) -> TargetResolution {
        var needsElements = false, direct = false
        if case .element = t { needsElements = true }
        switch t { case .point, .relative: direct = true; default: break }
        return checkOnScreen(TargetResolver.resolveMove(t, overlay: overlay.state, cursor: input.currentMouseLocation(),
                                          elements: elementsIfNeeded(named: needsElements),
                                          screens: ax.screenRectsCG()), checked: direct)
    }
}
