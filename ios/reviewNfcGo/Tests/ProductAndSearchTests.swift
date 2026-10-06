import Foundation
@main struct ProductAndSearchTests {
    static func main() {
        var checks = 0
        func check(_ value: @autoclosure () -> Bool, _ title: String) { precondition(value(), title); checks += 1 }
        let url = URL(string: "https://shop.example/products/card")!
        let json = """
        <script type="application/ld+json">{"@context":"https://schema.org","@graph":[{"@type":"Product","name":"Tarjeta NFC negra","image":["/card.jpg"],"offers":{"price":"3.50","priceCurrency":"EUR"}}]}</script>
        """
        let product = ProductMetadataService.parse(json, baseURL: url)
        check(product.name == "Tarjeta NFC negra" && product.euroPrice == 3.5, "JSON LD product name and EUR price")
        check(product.imageURL == "https://shop.example/card.jpg", "Relative image URL")
        let tags = "<meta content='Stand &amp; NFC' property='og:title'><meta property='og:image' content='/stand.png'><meta property='product:price:amount' content='12,99'><meta content='EUR' property='product:price:currency'>"
        let og = ProductMetadataService.parse(tags, baseURL: url)
        check(og.name == "Stand & NFC" && og.euroPrice == 12.99, "Open Graph order, entities and localized price")
        let usd = ProductMetadataService.parse(json.replacingOccurrences(of: "EUR", with: "USD"), baseURL: url)
        check(usd.euroPrice == nil && usd.currency == "USD", "Foreign currency never silently becomes EUR")
        check(ProductMetadataService.parse("<html>blocked</html>", baseURL: url).euroPrice == nil, "Manual fallback for unavailable data")
        check(ProductMetadataService.purchaseURL("javascript:alert(1)") == nil && ProductMetadataService.purchaseURL("file:///etc/passwd") == nil, "Reject nonweb source links")
        check(ProductMetadataService.purchaseURL("https://a:b@example.org") == nil, "Reject credentials in link")
        let a = PlaceResult(id: "a", name: "Café Plaza", address: "Madrid", latitude: 40, longitude: -3)
        let b = PlaceResult(id: "b", name: "Restaurante Café", address: "Madrid", latitude: 40, longitude: -3)
        let c = PlaceResult(id: "c", name: "Café", address: "Sevilla", latitude: 37, longitude: -5)
        check(SearchSuggestions.savedMatches("cafe", places: [a,b,c]).map(\.id) == ["c","a","b"], "Accent insensitive relevance ranking")
        check(SearchSuggestions.savedMatches("cafe madrid", places: [a,b,c]).count == 2, "All query words match name or address")
        check(SearchSuggestions.savedMatches("c", places: [a]).isEmpty, "Avoid single-character network queries")
        check(SearchSuggestions.merge(local: [a], remote: [a,b,c]).map(\.id) == ["a","b","c"], "Recommendations deduplicate place IDs")
        print("Product import and search: \(checks) checks passed")
    }
}
