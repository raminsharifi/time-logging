#!/usr/bin/env swift
// generate_icons.swift — renders the TimeLogger precision-instrument icon.
//
// Mirrors the `buildIcon(...)` function from the HTML prototype. Produces
// AppIcon.appiconset folders for iOS, iPadOS (same target), macOS, and
// watchOS at every required size, with a correct Contents.json.
//
// Run: swift tools/generate_icons.swift

import AppKit
import CoreGraphics
import Foundation

// MARK: - Colors

struct P { let r: Double; let g: Double; let b: Double
    var cg: CGColor { CGColor(red: r, green: g, blue: b, alpha: 1) }
    func cg(_ alpha: Double) -> CGColor { CGColor(red: r, green: g, blue: b, alpha: alpha) }
}

// Warm-paper field (top → bottom)
let field1 = P(r: 0.925, g: 0.906, b: 0.863) // #ECE7DC
let field2 = P(r: 0.851, g: 0.827, b: 0.769) // #D9D3C4

// Ink / rule
let rule   = P(r: 0.102, g: 0.102, b: 0.110) // #1A1A1C
let mute   = P(r: 0.604, g: 0.580, b: 0.529) // #9A9487

// Precision marker (oklch ~0.52 0.16 152 → muted green)
let accent = P(r: 0.231, g: 0.533, b: 0.349)   // #3B8859
// Forward-motion (oklch ~0.68 0.19 45 → orange)
let forward = P(r: 0.847, g: 0.486, b: 0.227)  // #D87C3A

enum Shape { case squircle, rounded, circle, macos }

struct IconOpts {
    var size: Int
    var shape: Shape = .squircle
    var fill: Double = 0.42
    var showCorner: Bool = true
    var showMarker: Bool = true
    var showTicks: Bool = true
}

// MARK: - Squircle path

/// Approximates the iOS 7+ squircle (superellipse) with a continuous curve.
/// Uses UIKit-style continuous rounded rect — close enough for icon masking.
func iosSquirclePath(rect: CGRect, radius: CGFloat) -> CGPath {
    // CGPath.init(roundedRect: ... cornerWidth/cornerHeight: ...) is circular
    // arc, not continuous. The difference is subtle at icon sizes; we use it.
    return CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

// MARK: - Renderer

func render(_ opts: IconOpts) -> CGImage {
    let S = CGFloat(opts.size)
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil,
                        width: opts.size, height: opts.size,
                        bitsPerComponent: 8, bytesPerRow: 0,
                        space: cs,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    // Flip Y so our math matches the HTML version (y=0 top).
    ctx.translateBy(x: 0, y: S)
    ctx.scaleBy(x: 1, y: -1)

    // Corner radius per shape
    let r: CGFloat = {
        switch opts.shape {
        case .squircle: return S * 0.2237
        case .rounded:  return S * 0.18
        case .macos:    return S * 0.234
        case .circle:   return S / 2
        }
    }()

    // Clip to shape so content never leaks past the silhouette.
    let outer = CGRect(x: 0, y: 0, width: S, height: S)
    let path: CGPath = (opts.shape == .circle)
        ? CGPath(ellipseIn: outer, transform: nil)
        : iosSquirclePath(rect: outer, radius: r)
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()

    // Background gradient (warm paper, top → bottom)
    let grad = CGGradient(colorsSpace: cs,
                          colors: [field1.cg, field2.cg] as CFArray,
                          locations: [0, 1])!
    ctx.drawLinearGradient(grad,
                           start: CGPoint(x: S/2, y: 0),
                           end: CGPoint(x: S/2, y: S),
                           options: [])

    // Subtle concentric rings at large sizes
    if opts.size >= 180 {
        ctx.setStrokeColor(rule.cg(0.04))
        ctx.setLineWidth(S * 0.003)
        for i in 1...3 {
            let rad = S * 0.18 * CGFloat(i)
            ctx.strokeEllipse(in: CGRect(
                x: S/2 - rad, y: S/2 - rad,
                width: rad * 2, height: rad * 2
            ))
        }
    }

    let pad: CGFloat = S * 0.14
    let baseY: CGFloat = S * 0.64
    let baseH: CGFloat = S * 0.028

    // Corner registration crosshairs
    if opts.showCorner {
        let cornerL = S * 0.075
        let cornerT = S * 0.012
        ctx.setFillColor(rule.cg(0.55))
        ctx.fill(CGRect(x: pad, y: pad, width: cornerL, height: cornerT))
        ctx.fill(CGRect(x: pad, y: pad, width: cornerT, height: cornerL))
        ctx.setFillColor(rule.cg(0.35))
        ctx.fill(CGRect(x: S - pad - cornerL, y: S - pad - cornerT,
                        width: cornerL, height: cornerT))
        ctx.fill(CGRect(x: S - pad - cornerT, y: S - pad - cornerL,
                        width: cornerT, height: cornerL))
    }

    // Baseline rule — split past (orange) / future (muted)
    let splitX = pad + (S - pad * 2) * CGFloat(opts.fill)
    ctx.setFillColor(forward.cg)
    ctx.fill(CGRect(x: pad, y: baseY, width: splitX - pad, height: baseH))
    ctx.setFillColor(rule.cg(0.35))
    ctx.fill(CGRect(x: splitX, y: baseY, width: S - pad - splitX, height: baseH))

    // Forward-motion arrow head (points right)
    let arrowW = S * 0.055
    let arrowH = S * 0.08
    let arrowX = S - pad
    let arrowCY = baseY + baseH / 2
    ctx.setFillColor(forward.cg)
    ctx.beginPath()
    ctx.move(to: CGPoint(x: arrowX, y: arrowCY))
    ctx.addLine(to: CGPoint(x: arrowX - arrowW, y: arrowCY - arrowH/2))
    ctx.addLine(to: CGPoint(x: arrowX - arrowW, y: arrowCY + arrowH/2))
    ctx.closePath()
    ctx.fillPath()

    // 24 ticks along baseline
    if opts.showTicks && opts.size >= 60 {
        for i in 0...24 {
            let tx = pad + ((S - pad * 2) / 24) * CGFloat(i)
            let major = i % 6 == 0
            let tH = major ? S * 0.048 : S * 0.022
            let tW = S * 0.0075
            ctx.setFillColor(major ? rule.cg(0.95) : mute.cg(0.75))
            ctx.fill(CGRect(x: tx - tW/2, y: baseY + baseH, width: tW, height: tH))
        }
        // Major ticks above the rule too (large sizes)
        if opts.size >= 180 {
            for i in 0...24 where i % 6 == 0 {
                let tx = pad + ((S - pad * 2) / 24) * CGFloat(i)
                let tH = S * 0.022
                let tW = S * 0.0075
                ctx.setFillColor(rule.cg(0.6))
                ctx.fill(CGRect(x: tx - tW/2, y: baseY - tH, width: tW, height: tH))
            }
        }
    }

    // Precision marker at split position
    if opts.showMarker {
        let markerH = S * 0.50
        let markerW = S * 0.022
        let topY = baseY - markerH * 0.78
        ctx.setFillColor(accent.cg)
        ctx.fill(CGRect(x: splitX - markerW/2, y: topY,
                        width: markerW, height: markerH + baseH))
        // Diamond at top of marker
        let dS = S * 0.038
        ctx.beginPath()
        ctx.move(to: CGPoint(x: splitX,              y: topY - dS))
        ctx.addLine(to: CGPoint(x: splitX + dS*0.7,  y: topY))
        ctx.addLine(to: CGPoint(x: splitX,           y: topY + dS*0.6))
        ctx.addLine(to: CGPoint(x: splitX - dS*0.7,  y: topY))
        ctx.closePath()
        ctx.fillPath()
        // Dot at the intersection of marker and rule
        let dotR = S * 0.028
        ctx.setFillColor(forward.cg)
        ctx.fillEllipse(in: CGRect(
            x: splitX - dotR, y: baseY + baseH/2 - dotR,
            width: dotR * 2, height: dotR * 2
        ))
        let innerR = S * 0.014
        ctx.setFillColor(field2.cg)
        ctx.fillEllipse(in: CGRect(
            x: splitX - innerR, y: baseY + baseH/2 - innerR,
            width: innerR * 2, height: innerR * 2
        ))
    }

    ctx.restoreGState()

    // Hairline edge
    ctx.saveGState()
    ctx.addPath(path)
    ctx.setStrokeColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.35))
    ctx.setLineWidth(1.5)
    ctx.strokePath()
    ctx.restoreGState()

    return ctx.makeImage()!
}

// MARK: - PNG writer

func writePNG(_ image: CGImage, to url: URL) throws {
    let rep = NSBitmapImageRep(cgImage: image)
    rep.size = NSSize(width: image.width, height: image.height)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "icon", code: 1, userInfo: [NSLocalizedDescriptionKey: "PNG encode failed"])
    }
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true
    )
    try data.write(to: url)
}

// MARK: - Icon-set specs

struct Spec {
    let filename: String
    let size: Int          // pixels on the long edge (already @scale applied)
    let idiom: String
    let pointSize: String
    let scale: String
}

/// iOS + iPadOS App Icon specs (universal).
let iosSpecs: [Spec] = [
    .init(filename: "icon-20@2x.png",   size: 40,   idiom: "iphone",     pointSize: "20x20",     scale: "2x"),
    .init(filename: "icon-20@3x.png",   size: 60,   idiom: "iphone",     pointSize: "20x20",     scale: "3x"),
    .init(filename: "icon-29@2x.png",   size: 58,   idiom: "iphone",     pointSize: "29x29",     scale: "2x"),
    .init(filename: "icon-29@3x.png",   size: 87,   idiom: "iphone",     pointSize: "29x29",     scale: "3x"),
    .init(filename: "icon-40@2x.png",   size: 80,   idiom: "iphone",     pointSize: "40x40",     scale: "2x"),
    .init(filename: "icon-40@3x.png",   size: 120,  idiom: "iphone",     pointSize: "40x40",     scale: "3x"),
    .init(filename: "icon-60@2x.png",   size: 120,  idiom: "iphone",     pointSize: "60x60",     scale: "2x"),
    .init(filename: "icon-60@3x.png",   size: 180,  idiom: "iphone",     pointSize: "60x60",     scale: "3x"),
    // iPad
    .init(filename: "icon-20.png",      size: 20,   idiom: "ipad",       pointSize: "20x20",     scale: "1x"),
    .init(filename: "ipad-icon-20@2x.png", size: 40, idiom: "ipad",     pointSize: "20x20",     scale: "2x"),
    .init(filename: "icon-29.png",      size: 29,   idiom: "ipad",       pointSize: "29x29",     scale: "1x"),
    .init(filename: "ipad-icon-29@2x.png", size: 58, idiom: "ipad",     pointSize: "29x29",     scale: "2x"),
    .init(filename: "icon-40.png",      size: 40,   idiom: "ipad",       pointSize: "40x40",     scale: "1x"),
    .init(filename: "ipad-icon-40@2x.png", size: 80, idiom: "ipad",     pointSize: "40x40",     scale: "2x"),
    .init(filename: "icon-76.png",      size: 76,   idiom: "ipad",       pointSize: "76x76",     scale: "1x"),
    .init(filename: "icon-76@2x.png",   size: 152,  idiom: "ipad",       pointSize: "76x76",     scale: "2x"),
    .init(filename: "icon-83.5@2x.png", size: 167,  idiom: "ipad",       pointSize: "83.5x83.5", scale: "2x"),
    // Marketing
    .init(filename: "icon-1024.png",    size: 1024, idiom: "ios-marketing", pointSize: "1024x1024", scale: "1x"),
]

let macosSpecs: [Spec] = [
    .init(filename: "icon-16.png",    size: 16,   idiom: "mac", pointSize: "16x16",   scale: "1x"),
    .init(filename: "icon-16@2x.png", size: 32,   idiom: "mac", pointSize: "16x16",   scale: "2x"),
    .init(filename: "icon-32.png",    size: 32,   idiom: "mac", pointSize: "32x32",   scale: "1x"),
    .init(filename: "icon-32@2x.png", size: 64,   idiom: "mac", pointSize: "32x32",   scale: "2x"),
    .init(filename: "icon-128.png",   size: 128,  idiom: "mac", pointSize: "128x128", scale: "1x"),
    .init(filename: "icon-128@2x.png",size: 256,  idiom: "mac", pointSize: "128x128", scale: "2x"),
    .init(filename: "icon-256.png",   size: 256,  idiom: "mac", pointSize: "256x256", scale: "1x"),
    .init(filename: "icon-256@2x.png",size: 512,  idiom: "mac", pointSize: "256x256", scale: "2x"),
    .init(filename: "icon-512.png",   size: 512,  idiom: "mac", pointSize: "512x512", scale: "1x"),
    .init(filename: "icon-512@2x.png",size: 1024, idiom: "mac", pointSize: "512x512", scale: "2x"),
]

let watchSpecs: [Spec] = [
    .init(filename: "icon-24@2x.png",   size: 48,  idiom: "watch", pointSize: "24x24",   scale: "2x"),
    .init(filename: "icon-27.5@2x.png", size: 55,  idiom: "watch", pointSize: "27.5x27.5", scale: "2x"),
    .init(filename: "icon-29@2x.png",   size: 58,  idiom: "watch", pointSize: "29x29",   scale: "2x"),
    .init(filename: "icon-29@3x.png",   size: 87,  idiom: "watch", pointSize: "29x29",   scale: "3x"),
    .init(filename: "icon-40@2x.png",   size: 80,  idiom: "watch", pointSize: "40x40",   scale: "2x"),
    .init(filename: "icon-44@2x.png",   size: 88,  idiom: "watch", pointSize: "44x44",   scale: "2x"),
    .init(filename: "icon-50@2x.png",   size: 100, idiom: "watch", pointSize: "50x50",   scale: "2x"),
    .init(filename: "icon-86@2x.png",   size: 172, idiom: "watch", pointSize: "86x86",   scale: "2x"),
    .init(filename: "icon-98@2x.png",   size: 196, idiom: "watch", pointSize: "98x98",   scale: "2x"),
    .init(filename: "icon-108@2x.png",  size: 216, idiom: "watch", pointSize: "108x108", scale: "2x"),
    .init(filename: "icon-1024.png",    size: 1024, idiom: "watch-marketing", pointSize: "1024x1024", scale: "1x"),
]

// MARK: - Contents.json

struct ContentsImage: Codable {
    let size: String
    let idiom: String
    let filename: String
    let scale: String?
    let role: String?
    let subtype: String?
}

struct ContentsInfo: Codable { let version: Int; let author: String }
struct Contents: Codable { let images: [ContentsImage]; let info: ContentsInfo }

func contentsJSON(specs: [Spec]) -> Data {
    let images = specs.map { s in
        ContentsImage(
            size: s.pointSize,
            idiom: s.idiom,
            filename: s.filename,
            scale: s.scale == "1x" && s.idiom.hasSuffix("marketing") ? nil : s.scale,
            role: nil, subtype: nil
        )
    }
    let c = Contents(images: images, info: ContentsInfo(version: 1, author: "xcode"))
    let enc = JSONEncoder()
    enc.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try! enc.encode(c)
}

// MARK: - Platform drivers

let shapeFor: [String: Shape] = [
    "ios": .squircle, "macos": .macos, "watchos": .circle,
]

func generate(platform: String, specs: [Spec], outDir: String) throws {
    let shape = shapeFor[platform]!
    // watchOS uses `showCorner: sz >= 60` in the HTML; we carry that over.
    let dir = URL(fileURLWithPath: outDir)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

    for s in specs {
        let img = render(IconOpts(
            size: s.size,
            shape: shape,
            showCorner: s.size >= 60,
            showMarker: s.size >= 40,
            showTicks:  s.size >= 60
        ))
        try writePNG(img, to: dir.appendingPathComponent(s.filename))
        print("✓ \(platform) \(s.filename) (\(s.size)px)")
    }
    try contentsJSON(specs: specs)
        .write(to: dir.appendingPathComponent("Contents.json"))
}

// MARK: - Main

let repo = "/Users/raminsharifi/time-logging"
try generate(platform: "ios",
             specs: iosSpecs,
             outDir: "\(repo)/ios/TimeLogger/Assets.xcassets/AppIcon.appiconset")
try generate(platform: "macos",
             specs: macosSpecs,
             outDir: "\(repo)/macos/TimeLogger/Assets.xcassets/AppIcon.appiconset")
try generate(platform: "watchos",
             specs: watchSpecs,
             outDir: "\(repo)/watchos/TimeLogger Watch App/Assets.xcassets/AppIcon.appiconset")

print("Done.")
