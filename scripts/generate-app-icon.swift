import AppKit
import ImageIO
import UniformTypeIdentifiers

// Normalize the transparent rounded tile to an 80.5% footprint on Apple's 1024px canvas.
// The source artwork is preserved; only its placement and scale change for packaging.
let source = CommandLine.arguments[1]
let destination = CommandLine.arguments[2]
guard let image = NSImage(contentsOfFile: source),
      let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { fatalError("Logo transparente ausente") }
let width = cgImage.width, height = cgImage.height
var pixels = [UInt8](repeating: 0, count: width * height * 4)
let bounds: CGRect = pixels.withUnsafeMutableBytes { data in
    let context = CGContext(data: data.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
    var minX = width, minY = height, maxX = 0, maxY = 0
    for y in 0..<height {
        for x in 0..<width where data[(y * width + x) * 4 + 3] > 32 {
            minX = min(minX, x); maxX = max(maxX, x)
            minY = min(minY, y); maxY = max(maxY, y)
        }
    }
    precondition(minX < maxX && minY < maxY, "O logo está vazio")
    return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
}
guard let tile = cgImage.cropping(to: bounds) else { fatalError("Não foi possível normalizar o ícone") }
let canvas = 1024
let context = CGContext(data: nil, width: canvas, height: canvas, bitsPerComponent: 8, bytesPerRow: canvas * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
context.clear(CGRect(x: 0, y: 0, width: canvas, height: canvas))
context.interpolationQuality = .high
let scale = 824.0 / max(bounds.width, bounds.height)
let tileWidth = bounds.width * scale, tileHeight = bounds.height * scale
context.draw(tile, in: CGRect(x: (1024 - tileWidth)/2, y: (1024 - tileHeight)/2, width: tileWidth, height: tileHeight))
let output = context.makeImage()!
let url = URL(fileURLWithPath: destination)
let writer = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(writer, output, nil)
precondition(CGImageDestinationFinalize(writer), "Não foi possível salvar o ícone")
print("Ícone transparente: \(destination)")
