#!/usr/bin/env swift
// Renders assets/app-icon.svg (and assets/app-icon-small.svg for 16 px) into a temporary .iconset of the 10 standard
// sizes, then runs iconutil to write Resources/AppIcon.icns. Every size but 16 px gets a soft drop shadow.
// Run by hand when the art changes: swift scripts/render-app-icon.swift
import AppKit

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let mainURL = root.appendingPathComponent("assets/app-icon.svg")
let smallURL = root.appendingPathComponent("assets/app-icon-small.svg")
let icnsURL = root.appendingPathComponent("Resources/AppIcon.icns")

nonisolated(unsafe) var tempDir: URL?

func fail(_ message: String) -> Never {
    if let tempDir { try? FileManager.default.removeItem(at: tempDir) }
    FileHandle.standardError.write(Data("render-app-icon: \(message)\n".utf8))
    exit(1)
}

func load(_ url: URL) -> NSImage {
    guard let image = NSImage(contentsOf: url), image.isValid else { fail("could not load \(url.path)") }
    return image
}

let mainArt = load(mainURL)
let smallArt = load(smallURL)

func render(pixels: Int, to url: URL) {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { fail("could not create a \(pixels) px bitmap") }
    rep.size = NSSize(width: pixels, height: pixels)
    guard let context = NSGraphicsContext(bitmapImageRep: rep) else { fail("no graphics context for \(pixels) px") }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    NSColor.clear.set()
    NSRect(x: 0, y: 0, width: pixels, height: pixels).fill(using: .copy)
    let rect = NSRect(x: 0, y: 0, width: pixels, height: pixels)
    if pixels == 16 {
        smallArt.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
    } else {
        // One shadow for the whole tile: draw the art inside a transparency layer so the shadow is cast by the
        // composite, not by each shape. Blur 28, offset 12 down, 30% black, scaled from the 1024 px canvas.
        let scale = CGFloat(pixels) / 1024
        let cg = context.cgContext
        cg.setShadow(offset: CGSize(width: 0, height: -12 * scale), blur: 28 * scale,
                     color: NSColor.black.withAlphaComponent(0.3).cgColor)
        cg.beginTransparencyLayer(auxiliaryInfo: nil)
        mainArt.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
        cg.endTransparencyLayer()
    }
    NSGraphicsContext.restoreGraphicsState()
    guard let png = rep.representation(using: .png, properties: [:]) else { fail("could not encode \(url.lastPathComponent)") }
    do { try png.write(to: url) } catch { fail("could not write \(url.path): \(error)") }
}

let temp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("nohands-appicon-\(UUID().uuidString)")
let iconset = temp.appendingPathComponent("AppIcon.iconset")
tempDir = temp
do { try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true) } catch {
    fail("could not create \(iconset.path): \(error)")
}
defer { try? FileManager.default.removeItem(at: temp) }

for point in [16, 32, 128, 256, 512] {
    render(pixels: point, to: iconset.appendingPathComponent("icon_\(point)x\(point).png"))
    render(pixels: point * 2, to: iconset.appendingPathComponent("icon_\(point)x\(point)@2x.png"))
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", icnsURL.path]
do { try iconutil.run() } catch { fail("could not run iconutil: \(error)") }
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { fail("iconutil exited with status \(iconutil.terminationStatus)") }
print("wrote \(icnsURL.path)")
