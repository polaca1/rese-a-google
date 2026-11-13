import Foundation
@main struct PlacesTransportTests {
    static func main() async throws {
        var calls: [String] = []
        var request = URLRequest(url: URL(string: "https://places.googleapis.com/v1/places:searchText")!)
        request.setValue("primary", forHTTPHeaderField: "X-Goog-Api-Key")
        func response(_ code: Int) -> (Data, URLResponse) {
            (Data("{}".utf8), HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: nil)!)
        }
        let result = try await PlacesTransport.execute(request, fallback: "secondary") { req in
            calls.append(req.value(forHTTPHeaderField: "X-Goog-Api-Key")!)
            return response(calls.count == 1 ? 429 : 200)
        }
        precondition(calls == ["primary", "secondary"] && (result.1 as! HTTPURLResponse).statusCode == 200)
        calls = []
        do {
            _ = try await PlacesTransport.execute(request, fallback: "secondary") { req in
                calls.append(req.value(forHTTPHeaderField: "X-Goog-Api-Key")!)
                if calls.count == 1 { return response(503) }
                throw URLError(.timedOut)
            }
            preconditionFailure("Secondary failure must be returned")
        } catch { precondition(calls == ["primary", "secondary"], "Only one fallback attempt") }
        for code in [200, 400, 404] {
            calls = []
            _ = try await PlacesTransport.execute(request, fallback: "secondary") { _ in calls.append("call"); return response(code) }
            precondition(calls.count == 1, "No fallback for success or invalid input")
        }
        calls = []
        _ = try await PlacesTransport.execute(request, fallback: "secondary") { req in
            calls.append(req.value(forHTTPHeaderField: "X-Goog-Api-Key")!)
            if calls.count == 1 { throw URLError(.timedOut) }
            return response(200)
        }
        precondition(calls == ["primary", "secondary"])
        print("Places fallback: HTTP errors, timeouts and bounded retries passed")
    }
}
