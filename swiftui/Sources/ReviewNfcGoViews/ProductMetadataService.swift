import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct ProductMetadata: Equatable {
    var name = ""
    var imageURL = ""
    var euroPrice: Double?
    var currency = ""
}
enum ProductMetadataService {
    static func purchaseURL(_ text: String) -> URL? {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil,
              url.user == nil, url.password == nil else { return nil }
        return url
    }
    static func fetch(_ url: URL) async throws -> ProductMetadata {
        var request = URLRequest(url: url, timeoutInterval: 18)
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode), data.count <= 2_000_000,
              let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw NSError(domain: "ProductMetadata", code: 1, userInfo: [NSLocalizedDescriptionKey: "La tienda no facilita datos. Puedes rellenarlos manualmente."])
        }
        return parse(html, baseURL: response.url ?? url)
    }
    static func parse(_ html: String, baseURL: URL) -> ProductMetadata {
        var result = ProductMetadata()
        func matches(_ pattern: String, _ text: String) -> [[String]] {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return [] }
            let source = text as NSString
            return regex.matches(in: text, range: NSRange(location: 0, length: source.length)).map { match in
                (0..<match.numberOfRanges).map { match.range(at: $0).location == NSNotFound ? "" : source.substring(with: match.range(at: $0)) }
            }
        }
        var meta: [String: String] = [:]
        for tag in matches("<meta\\b[^>]*>", html) {
            var attrs: [String: String] = [:]
            for attribute in matches("([\\w:-]+)\\s*=\\s*([\"'])(.*?)\\2", tag[0]) { attrs[attribute[1].lowercased()] = unescape(attribute[3]) }
            if let key = attrs["property"] ?? attrs["name"], let value = attrs["content"] { meta[key.lowercased()] = value }
        }
        result.name = meta["og:title"] ?? matches("<title[^>]*>(.*?)</title>", html).first?[1] ?? ""
        result.imageURL = meta["og:image"] ?? ""
        result.currency = meta["product:price:currency"] ?? meta["og:price:currency"] ?? ""
        let ogPrice = meta["product:price:amount"] ?? meta["og:price:amount"]
        if result.currency.uppercased() == "EUR", let price = ogPrice { result.euroPrice = SaleAmountFormatting.parse(price) }
        func inspect(_ node: Any) {
            if let nodes = node as? [Any] { nodes.forEach(inspect); return }
            guard let object = node as? [String: Any] else { return }
            if let graph = object["@graph"] { inspect(graph) }
            let type = object["@type"] as? String ?? (object["@type"] as? [String])?.first ?? ""
            guard type.lowercased() == "product" else { return }
            if let name = object["name"] as? String { result.name = name }
            if let image = object["image"] as? String { result.imageURL = image }
            else if let images = object["image"] as? [String], let first = images.first { result.imageURL = first }
            else if let image = object["image"] as? [String: Any], let url = image["url"] as? String { result.imageURL = url }
            let offer = object["offers"] as? [String: Any] ?? (object["offers"] as? [[String: Any]])?.first
            if let currency = offer?["priceCurrency"] as? String {
                result.currency = currency
                if currency.uppercased() == "EUR" {
                    let price = offer?["price"] ?? offer?["lowPrice"]
                    if let amount = price as? NSNumber { result.euroPrice = amount.doubleValue }
                    else if let amount = price as? String { result.euroPrice = SaleAmountFormatting.parse(amount) }
                } else { result.euroPrice = nil }
            }
        }
        for script in matches("<script\\b[^>]*type\\s*=\\s*[\"']application/ld\\+json[\"'][^>]*>(.*?)</script>", html) {
            if let data = script[1].data(using: .utf8), let json = try? JSONSerialization.jsonObject(with: data) { inspect(json) }
        }
        result.name = String(unescape(result.name).trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
        if let image = URL(string: unescape(result.imageURL), relativeTo: baseURL)?.absoluteURL, purchaseURL(image.absoluteString) != nil { result.imageURL = image.absoluteString } else { result.imageURL = "" }
        if let price = result.euroPrice, price <= 0 || MoneyLedger.cents(price) == nil { result.euroPrice = nil }
        return result
    }
    private static func unescape(_ text: String) -> String {
        var value = text
        for (from, to) in [("&amp;", "&"), ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"), ("&lt;", "<"), ("&gt;", ">"), ("&nbsp;", " ")] { value = value.replacingOccurrences(of: from, with: to) }
        return value
    }
}
