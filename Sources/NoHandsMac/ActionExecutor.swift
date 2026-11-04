import Foundation
import CoreGraphics
import NoHandsCore

/// What the executor needs from the accessibility layer (AXQuery conforms).
public protocol ElementProviding: Sendable {
    func actionableElements() -> [UIElementInfo]
    func screenRectsCG() -> [CGRect]
    func activate(appNamed: String) -> Bool
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

    public init(input: any InputSynthesizing, ax: any ElementProviding, overlay: any OverlayPresenting, config: AppConfig) {
        self.input = input
        self.ax = ax
        self.overlay = overlay
        self.config = config
    }

    /// Executes in order; stops at the first failure and shows it in the HUD. Returns the failure message if any.
    @discardableResult
    public func execute(_ actions: [Action]) -> String? {
        for action in actions {
            if let message = run(action) {
                overlay.showHUD(message, duration: .seconds(1.5))
                return message
            }
        }
        return nil
    }

    private func run(_ action: Action) -> String? {
        do {
            switch action {
            case .typeText(let text):
                guard text.count <= Self.maxTypedCharacters else { return "text too long" }
                try input.type(text)
            case .pressKey(let chord):
                try input.press(chord)
            case .click(let target, let button, let count):
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
            case .releaseMouse(let b):
                try input.mouseUp(b, at: input.currentMouseLocation())
            case .moveCursor(let target):
                switch resolveMove(target) {
                case .failure(let m): return m
                case .point(let p): try input.moveMouse(to: p)
                }
            case .scroll(let direction, let amount):
                try input.scroll(direction, lines: amount)
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
            case .ignore:
                break
            }
            return nil
        } catch {
            return "\(error)"
        }
    }

    private func elementsIfNeeded(named: Bool) -> [UIElementInfo] { named ? ax.actionableElements() : [] }

    private func resolveClick(_ t: ClickTarget) -> TargetResolution {
        var needsElements = false
        if case .element = t { needsElements = true }
        return TargetResolver.resolveClick(t, overlay: overlay.state, cursor: input.currentMouseLocation(),
                                           elements: elementsIfNeeded(named: needsElements),
                                           screens: ax.screenRectsCG())
    }

    private func resolveMove(_ t: MoveTarget) -> TargetResolution {
        var needsElements = false
        if case .element = t { needsElements = true }
        return TargetResolver.resolveMove(t, overlay: overlay.state, cursor: input.currentMouseLocation(),
                                          elements: elementsIfNeeded(named: needsElements),
                                          screens: ax.screenRectsCG())
    }
}
