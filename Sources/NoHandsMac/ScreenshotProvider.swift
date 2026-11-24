import Foundation
import AppKit
import CoreGraphics
import CoreText
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers
import NoHandsCore

public enum ScreenshotResult: Sendable {
    case image(StepScreenshot)
    case notGranted
    case failed
}

/// Takes a picture of the focused window for the task loop's vision fallback. Nothing is written to disk or logged.
public protocol ScreenshotProviding: Sendable {
    /// `badges` are the numbered elements the screen is showing now (empty when none); they are drawn into the picture.
    func capture(badges: [Int: UIElementInfo]) async -> ScreenshotResult
}

/// ScreenCaptureKit capture of the frontmost app's focused window. Every ScreenCaptureKit call is made inside
/// `capture`, in one task, so no ScreenCaptureKit value crosses an isolation boundary.
public struct WindowScreenshotter: ScreenshotProviding {
    static let jpegQuality = 0.7
    private let ax: any ElementProviding

    public init(ax: any ElementProviding) { self.ax = ax }

    public func capture(badges: [Int: UIElementInfo]) async -> ScreenshotResult {
        // Preflight never prompts; only the menu item asks for the grant.
        guard Permissions.screenRecordingGranted() else { return .notGranted }
        guard let app = NSWorkspace.shared.frontmostApplication, let focused = ax.focusedWindowFrame() else { return .failed }
        let pid = app.processIdentifier
        let appName = ax.frontmostAppName() ?? app.localizedName ?? ""
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
            // Never falls back to another window: no match means no picture.
            guard let window = content.windows.first(where: {
                $0.owningApplication?.processID == pid && $0.windowLayer == 0
                    && ScreenshotGeometry.sameFrame($0.frame, focused)
            }) else { return .failed }
            let filter = SCContentFilter(desktopIndependentWindow: window)
            let size = ScreenshotGeometry.imageSize(window: window.frame.size, backingScale: CGFloat(filter.pointPixelScale))
            let config = SCStreamConfiguration()
            config.width = Int(size.width)
            config.height = Int(size.height)
            config.showsCursor = false
            config.ignoreShadowsSingleWindow = true
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            // The picture's own size is what the model's coordinates are in.
            let actual = CGSize(width: image.width, height: image.height)
            let shot = StepScreenshot(jpeg: Data(), imageSize: actual, windowFrame: window.frame, app: appName)
            guard let jpeg = Self.encode(image, badges: badges, shot: shot) else { return .failed }
            return .image(StepScreenshot(jpeg: jpeg, imageSize: actual, windowFrame: window.frame, app: appName))
        } catch {
            return .failed
        }
    }

    /// Draws the number badges whose elements are inside the window, then encodes JPEG in memory.
    static func encode(_ image: CGImage, badges: [Int: UIElementInfo], shot: StepScreenshot) -> Data? {
        let w = image.width, h = image.height
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        // Top-left origin from here on, like the picture's coordinates.
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: 1, y: -1)
        ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        let bounds = CGRect(x: 0, y: 0, width: w, height: h)
        let font = CTFontCreateWithName("Menlo-Bold" as CFString, 12, nil)
        let attrs: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true,
        ]
        for n in badges.keys.sorted() {
            guard let e = badges[n], shot.windowFrame.intersects(e.frame) else { continue }
            let topLeft = ScreenshotGeometry.imagePoint(fromScreen: e.frame.origin, shot: shot)
            let bottomRight = ScreenshotGeometry.imagePoint(fromScreen: CGPoint(x: e.frame.maxX, y: e.frame.maxY), shot: shot)
            let frame = CGRect(x: topLeft.x, y: topLeft.y, width: bottomRight.x - topLeft.x, height: bottomRight.y - topLeft.y)
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: String(n), attributes: attrs))
            var ascent: CGFloat = 0, descent: CGFloat = 0
            let textWidth = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, nil))
            let size = CGSize(width: ceil(textWidth) + 8, height: ceil(ascent + descent) + 2)
            let o = OverlayMath.badgeOrigin(for: frame, badgeSize: size, in: bounds)
            let box = CGRect(origin: o, size: size)
            ctx.setFillColor(CGColor(red: 1, green: 0.88, blue: 0.3, alpha: 1))
            ctx.addPath(CGPath(roundedRect: box, cornerWidth: 4, cornerHeight: 4, transform: nil))
            ctx.fillPath()
            ctx.setFillColor(CGColor(gray: 0.1, alpha: 1))
            ctx.textPosition = CGPoint(x: box.minX + 4, y: box.minY + 1 + ascent)
            CTLineDraw(line, ctx)
        }
        guard let drawn = ctx.makeImage() else { return nil }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, drawn, [kCGImageDestinationLossyCompressionQuality: jpegQuality] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return out as Data
    }
}
