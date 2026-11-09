#!/usr/bin/env swift
// Renders assets/menubar-icon.svg to Resources/MenuBarIcon.png (18 px) and Resources/MenuBarIcon@2x.png (36 px),
// keeping the alpha channel. Run by hand when the art changes: swift scripts/render-menubar-icon.swift
import AppKit

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let svgURL = root.appendingPathComponent("assets/menubar-icon.svg")

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("render-menubar-icon: \(message)\n".utf8))
    exit(1)
}

guard let svg = NSImage(contentsOf: svgURL), svg.isValid else {
    fail("could not load \(svgURL.path)")
}

func render(pixels: Int, to name: String) {
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
    svg.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels), from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    guard let png = rep.representation(using: .png, properties: [:]) else { fail("could not encode \(name)") }
    let out = root.appendingPathComponent("Resources/\(name)")
    do { try png.write(to: out) } catch { fail("could not write \(out.path): \(error)") }
    print("wrote \(out.path) (\(pixels) px)")
}

render(pixels: 18, to: "MenuBarIcon.png")
render(pixels: 36, to: "MenuBarIcon@2x.png")
