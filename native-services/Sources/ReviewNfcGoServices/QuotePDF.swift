import Foundation
import CoreText
import CoreGraphics
private func suiteEuro(_ cents: Int64) -> String { (Double(cents) / 100).formatted(.currency(code: "EUR").locale(Locale(identifier: "es_ES"))) }
@MainActor enum QuotePDF {
    static func create(_ quote: BusinessQuote, owner: String) throws -> URL {
        try quote.validate()
        let lines = quote.items.map { "\($0.quantity) × \($0.title)\nPrecio unidad: \(suiteEuro($0.unitPriceCents))    Importe: \(suiteEuro($0.totalCents))" }.joined(separator: "\n\n")
        let text = "PRESUPUESTO \(quote.number)\nreviewNfcGo · \(owner)\n\nCliente: \(quote.businessName)\nFecha: \(quote.createdAt.formatted(date: .abbreviated, time: .omitted))\nVálido hasta: \(quote.expiresAt.formatted(date: .abbreviated, time: .omitted))\n\n\(lines)\n\nSubtotal: \(suiteEuro(quote.subtotalCents))\nDescuento: \(quote.discountPercent)% (\(suiteEuro(quote.discountCents)))\nTOTAL: \(suiteEuro(quote.totalCents))\n\n\(quote.notes)\n\nPresupuesto comercial. No es una factura ni un justificante de pago."
        let font = CTFontCreateWithName("Helvetica" as CFString, 12, nil)
        let attributes: [NSAttributedString.Key: Any] = [NSAttributedString.Key(kCTFontAttributeName as String): font]
        let content = NSAttributedString(string: text, attributes: attributes)
        let framesetter = CTFramesetterCreateWithAttributedString(content as CFAttributedString)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(quote.number + "-" + UUID().uuidString + ".pdf")
        var page = CGRect(x: 0, y: 0, width: 595, height: 842)
        guard let context = CGContext(url as CFURL, mediaBox: &page, nil) else { throw CocoaError(.fileWriteUnknown) }
        var offset = 0
        while offset < content.length {
            context.beginPDFPage(nil)
            let path = CGPath(rect: CGRect(x: 40, y: 50, width: 515, height: 742), transform: nil)
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: offset, length: 0), path, nil)
            CTFrameDraw(frame, context)
            let visible = CTFrameGetVisibleStringRange(frame)
            context.endPDFPage()
            guard visible.length > 0 else { context.closePDF(); throw CocoaError(.fileWriteUnknown) }
            offset += visible.length
        }
        context.closePDF()
        return url
    }
}
