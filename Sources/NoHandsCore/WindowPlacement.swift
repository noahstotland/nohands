import Foundation
import CoreGraphics

/// Where the frontmost window goes on its screen. Raw values are the model-facing names (`move_window`'s
/// `placement` field) and the grammar's vocabulary.
public enum WindowPlacement: String, Codable, CaseIterable, Sendable {
    case leftHalf = "left_half", rightHalf = "right_half", topHalf = "top_half", bottomHalf = "bottom_half"
    case topLeft = "top_left", topRight = "top_right", bottomLeft = "bottom_left", bottomRight = "bottom_right"
    case leftThird = "left_third", middleThird = "middle_third", rightThird = "right_third"
    case leftTwoThirds = "left_two_thirds", rightTwoThirds = "right_two_thirds"
    /// Fill the screen's visible area (not macOS full-screen mode).
    case maximize
    /// Keep the window's size and centre it.
    case center

    /// The window's new frame inside `visible` (the screen minus menu bar and Dock; any coordinate system, as
    /// long as `current` uses the same one). `current` is the window's present frame, used by `center`.
    public func frame(in visible: CGRect, current: CGRect) -> CGRect {
        let w = visible.width, h = visible.height
        func rounded(_ r: CGRect) -> CGRect {
            CGRect(x: r.minX.rounded(), y: r.minY.rounded(), width: r.width.rounded(), height: r.height.rounded())
        }
        func slice(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) -> CGRect {
            rounded(CGRect(x: visible.minX + x * w, y: visible.minY + y * h, width: width * w, height: height * h))
        }
        let third = CGFloat(1) / 3
        switch self {
        case .leftHalf: return slice(x: 0, y: 0, width: 0.5, height: 1)
        case .rightHalf: return slice(x: 0.5, y: 0, width: 0.5, height: 1)
        case .topHalf: return slice(x: 0, y: 0, width: 1, height: 0.5)
        case .bottomHalf: return slice(x: 0, y: 0.5, width: 1, height: 0.5)
        case .topLeft: return slice(x: 0, y: 0, width: 0.5, height: 0.5)
        case .topRight: return slice(x: 0.5, y: 0, width: 0.5, height: 0.5)
        case .bottomLeft: return slice(x: 0, y: 0.5, width: 0.5, height: 0.5)
        case .bottomRight: return slice(x: 0.5, y: 0.5, width: 0.5, height: 0.5)
        case .leftThird: return slice(x: 0, y: 0, width: third, height: 1)
        case .middleThird: return slice(x: third, y: 0, width: third, height: 1)
        case .rightThird: return slice(x: 2 * third, y: 0, width: third, height: 1)
        case .leftTwoThirds: return slice(x: 0, y: 0, width: 2 * third, height: 1)
        case .rightTwoThirds: return slice(x: third, y: 0, width: 2 * third, height: 1)
        case .maximize: return rounded(visible)
        case .center:
            let size = CGSize(width: min(current.width, w), height: min(current.height, h))
            return rounded(CGRect(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2,
                                  width: size.width, height: size.height))
        }
    }
}
