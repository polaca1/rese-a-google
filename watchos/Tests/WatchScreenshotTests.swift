import Foundation
import ImageIO
import CoreGraphics
import Vision

@main struct WatchScreenshotTests {
    static func main() throws {
        let args = CommandLine.arguments
        guard args.count == 3, let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: args[1]) as CFURL, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { fatalError("Missing Watch capture") }
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { fatalError("Cannot inspect Watch capture") }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var visible = 0
        for y in 60..<max(61, height - 30) { for x in 0..<width {
            let i = (y * width + x) * 4
            if max(pixels[i], pixels[i+1], pixels[i+2]) > 24 { visible += 1 }
        } }
        precondition(visible > 2000, "The Watch screen only shows the clock or is blank")
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["es-ES", "en-US"]
        request.usesLanguageCorrection = false
        try VNImageRequestHandler(cgImage: image).perform([request])
        let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ").lowercased()
        if args[2] == "money" { precondition(text.contains("30"), "Balance must be visible on the Watch") }
        else { precondition(text.contains("centro"), "The actual customer must be visible on the Watch") }
        print("Watch \(args[2]): rendered content verified; \(text)")
    }
}
