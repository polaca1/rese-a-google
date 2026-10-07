import Foundation
import Vision
import ImageIO

@main struct WatchScreenshots {
    static func main() throws {
        let arguments = CommandLine.arguments
        guard arguments.count == 3 else { throw NSError(domain: "WatchUI", code: 1) }
        let url = URL(fileURLWithPath: arguments[1]), screen = arguments[2]
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["es-ES", "en-US"]
        request.usesLanguageCorrection = false
        try VNImageRequestHandler(url: url).perform([request])
        let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
        let expected: [String]
        switch screen {
        case "next": expected = ["Próxima visita", "Café"]
        case "business": expected = ["Visita", "Café"]
        case "summary": expected = ["Resumen", "Ingresos"]
        case "sale": expected = ["Vendido", "tarjeta"]
        default: throw NSError(domain: "WatchUI", code: 2)
        }
        let passed = expected.allSatisfy { text.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        let report: [String: Any] = ["screen": screen, "passed": passed, "visibleText": text]
        let data = try JSONSerialization.data(withJSONObject: report, options: .prettyPrinted)
        FileHandle.standardOutput.write(data); print()
        if !passed { throw NSError(domain: "WatchUI", code: 3, userInfo: [NSLocalizedDescriptionKey: "La captura no muestra la pantalla " + screen]) }
    }
}
