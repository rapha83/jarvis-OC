#!/usr/bin/env swift

import AppKit
import Foundation

guard CommandLine.arguments.count == 3 || CommandLine.arguments.count == 4 else {
    FileHandle.standardError.write(Data("usage: generate_app_icon.swift <resources-dir> <app-icon-png> [status-icon-png]\n".utf8))
    exit(2)
}

let resourcesURL = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let sourceURL = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: false)
let statusSourceURL = URL(fileURLWithPath: CommandLine.arguments.count == 4 ? CommandLine.arguments[3] : CommandLine.arguments[2], isDirectory: false)
let iconsetURL = resourcesURL.appendingPathComponent("JARVIS.iconset", isDirectory: true)
let icnsURL = resourcesURL.appendingPathComponent("JARVIS.icns")
let appPreviewURL = resourcesURL.appendingPathComponent("JARVISAppIcon.png")
let statusIconURL = resourcesURL.appendingPathComponent("JARVISStatusIcon.png")
let fileManager = FileManager.default

guard let sourceImage = NSImage(contentsOf: sourceURL) else {
    FileHandle.standardError.write(Data("unable to read source icon: \(sourceURL.path)\n".utf8))
    exit(1)
}

guard let statusSourceImage = NSImage(contentsOf: statusSourceURL) else {
    FileHandle.standardError.write(Data("unable to read status icon: \(statusSourceURL.path)\n".utf8))
    exit(1)
}

try fileManager.createDirectory(at: resourcesURL, withIntermediateDirectories: true)
try? fileManager.removeItem(at: iconsetURL)
try? fileManager.removeItem(at: icnsURL)
try? fileManager.removeItem(at: appPreviewURL)
try? fileManager.removeItem(at: statusIconURL)
try fileManager.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

let iconFiles: [(points: Int, scale: Int, name: String)] = [
    (16, 1, "icon_16x16.png"),
    (16, 2, "icon_16x16@2x.png"),
    (32, 1, "icon_32x32.png"),
    (32, 2, "icon_32x32@2x.png"),
    (128, 1, "icon_128x128.png"),
    (128, 2, "icon_128x128@2x.png"),
    (256, 1, "icon_256x256.png"),
    (256, 2, "icon_256x256@2x.png"),
    (512, 1, "icon_512x512.png"),
    (512, 2, "icon_512x512@2x.png"),
]

var pngByPixelSize: [Int: Data] = [:]
for icon in iconFiles {
    let pixelSize = icon.points * icon.scale
    let image = renderIcon(sourceImage: sourceImage, size: pixelSize, insetRatio: 0.03)
    let png = try writePNG(image: image, to: iconsetURL.appendingPathComponent(icon.name))
    pngByPixelSize[pixelSize] = png
}

let statusImage = renderStatusIcon(sourceImage: statusSourceImage, size: 160)
let appPreviewImage = renderIcon(sourceImage: sourceImage, size: 256, insetRatio: 0.03)
_ = try writePNG(image: appPreviewImage, to: appPreviewURL)
_ = try writePNG(image: statusImage, to: statusIconURL)
try writeICNS(pngByPixelSize: pngByPixelSize, to: icnsURL)

func renderIcon(sourceImage: NSImage, size: Int, insetRatio: CGFloat) -> NSImage {
    let side = CGFloat(size)
    let image = NSImage(size: NSSize(width: side, height: side))

    image.lockFocus()
    defer { image.unlockFocus() }

    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: side, height: side).fill()

    let inset = side * insetRatio
    let targetRect = NSRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2)
    sourceImage.draw(
        in: targetRect,
        from: .zero,
        operation: .sourceOver,
        fraction: 1.0,
        respectFlipped: true,
        hints: [.interpolation: NSImageInterpolation.high]
    )
    return image
}

func renderStatusIcon(sourceImage: NSImage, size: Int) -> NSImage {
    let masked = makeTemplateMask(from: sourceImage)
    let sourceRect = nonTransparentBounds(of: masked) ?? NSRect(origin: .zero, size: masked.size)
    let side = CGFloat(size)
    let image = NSImage(size: NSSize(width: side, height: side))

    image.lockFocus()
    defer { image.unlockFocus() }

    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: side, height: side).fill()

    let inset: CGFloat = side * 0.14
    let maxSide = side - inset * 2
    let ratio = min(maxSide / max(sourceRect.width, 1), maxSide / max(sourceRect.height, 1))
    let targetSize = NSSize(width: sourceRect.width * ratio, height: sourceRect.height * ratio)
    let targetRect = NSRect(
        x: (side - targetSize.width) / 2,
        y: ((side - targetSize.height) / 2) - (side * 0.025),
        width: targetSize.width,
        height: targetSize.height
    )

    masked.draw(
        in: targetRect,
        from: sourceRect,
        operation: .sourceOver,
        fraction: 1.0,
        respectFlipped: true,
        hints: [.interpolation: NSImageInterpolation.high]
    )
    return image
}

func makeTemplateMask(from sourceImage: NSImage) -> NSImage {
    var proposedRect = NSRect(origin: .zero, size: sourceImage.size)
    guard let cgImage = sourceImage.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) else {
        return sourceImage
    }

    let width = cgImage.width
    let height = cgImage.height
    let bytesPerRow = width * 4
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    var sourcePixels = [UInt8](repeating: 0, count: height * bytesPerRow)

    guard let context = CGContext(
        data: &sourcePixels,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        return sourceImage
    }

    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

    var outputPixels = [UInt8](repeating: 0, count: height * bytesPerRow)
    for y in 0..<height {
        for x in 0..<width {
            let index = (y * bytesPerRow) + (x * 4)
            let red = CGFloat(sourcePixels[index]) / 255.0
            let green = CGFloat(sourcePixels[index + 1]) / 255.0
            let blue = CGFloat(sourcePixels[index + 2]) / 255.0
            let sourceAlpha = CGFloat(sourcePixels[index + 3]) / 255.0
            let luma = (0.299 * red) + (0.587 * green) + (0.114 * blue)
            let darkness = 1.0 - luma

            var alpha = smoothstep(edge0: 0.08, edge1: 0.30, value: darkness) * sourceAlpha
            alpha = min(1, pow(alpha, 0.34) * 1.85)
            if alpha < 0.025 {
                alpha = 0
            }

            outputPixels[index] = 0
            outputPixels[index + 1] = 0
            outputPixels[index + 2] = 0
            outputPixels[index + 3] = UInt8((min(1, alpha) * 255).rounded())
        }
    }

    let data = Data(outputPixels)
    guard
        let provider = CGDataProvider(data: data as CFData),
        let outputImage = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    else {
        return sourceImage
    }

    let image = NSImage(cgImage: outputImage, size: NSSize(width: width, height: height))
    image.isTemplate = true
    return image
}

func smoothstep(edge0: CGFloat, edge1: CGFloat, value: CGFloat) -> CGFloat {
    let x = min(1, max(0, (value - edge0) / (edge1 - edge0)))
    return x * x * (3 - (2 * x))
}

func nonTransparentBounds(of image: NSImage, alphaThreshold: CGFloat = 0.12) -> NSRect? {
    guard
        let tiff = image.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiff)
    else {
        return nil
    }

    var minX = bitmap.pixelsWide
    var minY = bitmap.pixelsHigh
    var maxX = 0
    var maxY = 0

    for y in 0..<bitmap.pixelsHigh {
        for x in 0..<bitmap.pixelsWide {
            let alpha = bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0
            guard alpha > alphaThreshold else {
                continue
            }
            minX = min(minX, x)
            minY = min(minY, y)
            maxX = max(maxX, x)
            maxY = max(maxY, y)
        }
    }

    guard minX <= maxX, minY <= maxY else {
        return nil
    }

    return NSRect(
        x: CGFloat(minX),
        y: CGFloat(minY),
        width: CGFloat(maxX - minX + 1),
        height: CGFloat(maxY - minY + 1)
    )
}

func writePNG(image: NSImage, to url: URL) throws -> Data {
    guard
        let tiff = image.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiff),
        let data = bitmap.representation(using: .png, properties: [:])
    else {
        throw NSError(domain: "JarvisIcon", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to encode PNG"])
    }
    try data.write(to: url)
    return data
}

func writeICNS(pngByPixelSize: [Int: Data], to url: URL) throws {
    let chunks: [(type: String, size: Int)] = [
        ("icp4", 16),
        ("icp5", 32),
        ("icp6", 64),
        ("ic07", 128),
        ("ic08", 256),
        ("ic09", 512),
        ("ic10", 1024),
    ]

    var body = Data()
    for chunk in chunks {
        guard let png = pngByPixelSize[chunk.size] else {
            continue
        }
        body.append(Data(chunk.type.utf8))
        body.appendUInt32BE(UInt32(png.count + 8))
        body.append(png)
    }

    var output = Data("icns".utf8)
    output.appendUInt32BE(UInt32(body.count + 8))
    output.append(body)
    try output.write(to: url)
}

extension Data {
    mutating func appendUInt32BE(_ value: UInt32) {
        var bigEndian = value.bigEndian
        Swift.withUnsafeBytes(of: &bigEndian) { bytes in
            append(contentsOf: bytes)
        }
    }
}
