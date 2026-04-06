import AppKit
import Foundation

enum IconGenerationError: Error {
    case missingOutputDirectory
    case pngEncodingFailed
}

let arguments = CommandLine.arguments
do {
    guard arguments.count == 2 || arguments.count == 3 else {
        throw IconGenerationError.missingOutputDirectory
    }

    let outputURL = URL(fileURLWithPath: arguments[1], isDirectory: true)
    let sourceImage = arguments.count == 3
        ? NSImage(contentsOf: URL(fileURLWithPath: arguments[2]))
        : nil
    let fileManager = FileManager.default

    if fileManager.fileExists(atPath: outputURL.path) {
        try fileManager.removeItem(at: outputURL)
    }
    try fileManager.createDirectory(at: outputURL, withIntermediateDirectories: true)

    let baseSizes = [16, 32, 128, 256, 512]

    for baseSize in baseSizes {
        for scale in [1, 2] {
            let pixelSize = CGFloat(baseSize * scale)
            let fileName = scale == 1
                ? "icon_\(baseSize)x\(baseSize).png"
                : "icon_\(baseSize)x\(baseSize)@2x.png"
            let destinationURL = outputURL.appendingPathComponent(fileName)
            let image = sourceImage.map { renderSourceIcon($0, size: pixelSize) } ?? renderIcon(size: pixelSize)
            try savePNG(image: image, to: destinationURL)
        }
    }
} catch {
    fputs("Failed to generate icon assets: \(error)\n", stderr)
    exit(1)
}

private func renderSourceIcon(_ sourceImage: NSImage, size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    NSGraphicsContext.current?.imageInterpolation = .high

    let destinationRect = CGRect(origin: .zero, size: CGSize(width: size, height: size))
    let sourceRect = centeredSquareRect(in: CGRect(origin: .zero, size: sourceImage.size))
    sourceImage.draw(in: destinationRect, from: sourceRect, operation: .copy, fraction: 1.0)

    image.unlockFocus()
    return image
}

private func renderIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    let rect = CGRect(origin: .zero, size: CGSize(width: size, height: size))
    let inset = size * 0.06
    let tileRect = rect.insetBy(dx: inset, dy: inset)
    let cornerRadius = size * 0.23

    let tilePath = NSBezierPath(roundedRect: tileRect, xRadius: cornerRadius, yRadius: cornerRadius)
    let gradient = NSGradient(
        colors: [
            NSColor(calibratedRed: 0.12, green: 0.43, blue: 0.97, alpha: 1.0),
            NSColor(calibratedRed: 0.37, green: 0.78, blue: 0.98, alpha: 1.0)
        ]
    )!
    gradient.draw(in: tilePath, angle: -45)

    NSColor.white.withAlphaComponent(0.22).setStroke()
    tilePath.lineWidth = max(2, size * 0.015)
    tilePath.stroke()

    let highlightRect = CGRect(
        x: tileRect.minX + size * 0.07,
        y: tileRect.midY + size * 0.10,
        width: tileRect.width - size * 0.14,
        height: size * 0.16
    )
    let highlightPath = NSBezierPath(
        roundedRect: highlightRect,
        xRadius: size * 0.08,
        yRadius: size * 0.08
    )
    NSColor.white.withAlphaComponent(0.11).setFill()
    highlightPath.fill()

    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.18)
    shadow.shadowBlurRadius = size * 0.035
    shadow.shadowOffset = NSSize(width: 0, height: -(size * 0.02))

    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.alignment = .center

    let fontSize = size * 0.34
    let baseFont = NSFont.systemFont(ofSize: fontSize, weight: .black)
    let roundedDescriptor = baseFont.fontDescriptor.withDesign(.rounded) ?? baseFont.fontDescriptor
    let roundedFont = NSFont(descriptor: roundedDescriptor, size: fontSize) ?? baseFont

    let attributes: [NSAttributedString.Key: Any] = [
        .font: roundedFont,
        .foregroundColor: NSColor.white,
        .paragraphStyle: paragraphStyle,
        .shadow: shadow
    ]
    let monogram = NSAttributedString(string: "YC", attributes: attributes)
    let textSize = monogram.size()
    let textRect = CGRect(
        x: rect.midX - textSize.width / 2,
        y: rect.midY - textSize.height / 2 - size * 0.035,
        width: textSize.width,
        height: textSize.height
    )
    monogram.draw(in: textRect)

    image.unlockFocus()
    return image
}

private func centeredSquareRect(in rect: CGRect) -> CGRect {
    let squareSide = min(rect.width, rect.height)
    let originX = rect.midX - squareSide / 2
    let originY = rect.midY - squareSide / 2
    return CGRect(x: originX, y: originY, width: squareSide, height: squareSide)
}

private func savePNG(image: NSImage, to url: URL) throws {
    guard
        let tiffData = image.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiffData),
        let pngData = bitmap.representation(using: .png, properties: [:])
    else {
        throw IconGenerationError.pngEncodingFailed
    }

    try pngData.write(to: url)
}
