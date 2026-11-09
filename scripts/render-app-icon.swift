#!/usr/bin/env swift
// Renders assets/app-icon.svg (and assets/app-icon-small.svg for 16 px) into a temporary .iconset of the 10 standard
// sizes, then runs iconutil to write Resources/AppIcon.icns. Every size but 16 px gets a soft drop shadow.
// Run by hand when the art changes: swift scripts/render-app-icon.swift
import AppKit

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let mainURL = root.appendingPathComponent("assets/app-icon.svg")
let smallURL = root.appendingPathComponent("assets/app-icon-small.svg")
let icnsURL = root.appendingPathComponent("Resources/AppIcon.icns")

struct Failure: Error { let message: String }

func load(_ url: URL) throws -> NSImage {
    guard let image = NSImage(contentsOf: url), image.isValid else { throw Failure(message: "could not load \(url.path)") }
    return image
}

func render(pixels: Int, art: NSImage, shadow: Bool, to url: URL) throws {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { throw Failure(message: "could not create a \(pixels) px bitmap") }
    rep.size = NSSize(width: pixels, height: pixels)
    guard let context = NSGraphicsContext(bitmapImageRep: rep) else { throw Failure(message: "no graphics context for \(pixels) px") }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    NSColor.clear.set()
    let rect = NSRect(x: 0, y: 0, width: pixels, height: pixels)
    rect.fill(using: .copy)
    if shadow {
        // One shadow for the whole tile: draw the art inside a transparency layer so the shadow is cast by the
        // composite, not by each shape. Blur 28, offset 12 down, 30% black, scaled from the 1024 px canvas.
        let scale = CGFloat(pixels) / 1024
        let cg = context.cgContext
        cg.setShadow(offset: CGSize(width: 0, height: -12 * scale), blur: 28 * scale,
                     color: NSColor.black.withAlphaComponent(0.3).cgColor)
        cg.beginTransparencyLayer(auxiliaryInfo: nil)
        art.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
        cg.endTransparencyLayer()
    } else {
        art.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
    }
    NSGraphicsContext.restoreGraphicsState()
    guard let png = rep.representation(using: .png, properties: [:]) else { throw Failure(message: "could not encode \(url.lastPathComponent)") }
    do { try png.write(to: url) } catch { throw Failure(message: "could not write \(url.path): \(error)") }
}

func build(into temp: URL) throws {
    let mainArt = try load(mainURL)
    let smallArt = try load(smallURL)
    let iconset = temp.appendingPathComponent("AppIcon.iconset")
    do { try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true) } catch {
        throw Failure(message: "could not create \(iconset.path): \(error)")
    }
    for point in [16, 32, 128, 256, 512] {
        for (pixels, suffix) in [(point, ""), (point * 2, "@2x")] {
            // The 16 px image is the one size that uses the thicker small cut, with no shadow.
            let small = pixels == 16
            try render(pixels: pixels, art: small ? smallArt : mainArt, shadow: !small,
                       to: iconset.appendingPathComponent("icon_\(point)x\(point)\(suffix).png"))
        }
    }
    // iconutil writes into the temp folder first, so a failure never leaves a partial Resources/AppIcon.icns.
    let builtURL = temp.appendingPathComponent("AppIcon.icns")
    let iconutil = Process()
    iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    iconutil.arguments = ["-c", "icns", iconset.path, "-o", builtURL.path]
    do { try iconutil.run() } catch { throw Failure(message: "could not run iconutil: \(error)") }
    iconutil.waitUntilExit()
    guard iconutil.terminationStatus == 0 else { throw Failure(message: "iconutil exited with status \(iconutil.terminationStatus)") }
    do { _ = try FileManager.default.replaceItemAt(icnsURL, withItemAt: builtURL) } catch {
        throw Failure(message: "could not write \(icnsURL.path): \(error)")
    }
}

let temp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("nohands-appicon-\(UUID().uuidString)")
var failure: Failure?
do { try build(into: temp) } catch let error as Failure { failure = error } catch { failure = Failure(message: "\(error)") }
try? FileManager.default.removeItem(at: temp)
if let failure {
    FileHandle.standardError.write(Data("render-app-icon: \(failure.message)\n".utf8))
    exit(1)
}
print("wrote \(icnsURL.path)")
