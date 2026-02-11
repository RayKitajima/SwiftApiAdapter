import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Deterministic network stubs for unit tests.
///
/// These tests previously hit https://jsonplaceholder.typicode.com which is brittle in CI
/// (network may be unavailable; upstream may change). This URLProtocol intercepts those
/// requests and returns a known fixture response.
final class JsonPlaceholderURLProtocol: URLProtocol {

    /// Register this URLProtocol globally.
    ///
    /// Safe to call multiple times.
    static func register() {
        _ = URLProtocol.registerClass(JsonPlaceholderURLProtocol.self)
    }

    // Only intercept jsonplaceholder requests. Everything else should go through the normal stack.
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "jsonplaceholder.typicode.com"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        let (statusCode, data): (Int, Data)

        switch url.path {
        case "/posts/1":
            statusCode = 200
            data = Data(Self.post1JSON.utf8)
        default:
            statusCode = 404
            data = Data("{\"error\":\"not found\"}".utf8)
        }

        let response = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json; charset=utf-8"]
        )!

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {
        // No-op
    }

    // MARK: - Fixtures

    /// Fixture matching jsonplaceholder's `/posts/1` payload.
    private static let post1JSON = """
    {
      \"userId\": 1,
      \"id\": 1,
      \"title\": \"sunt aut facere repellat provident occaecati excepturi optio reprehenderit\",
      \"body\": \"quia et suscipit\\nsuscipit recusandae consequuntur expedita et cum\\nreprehenderit molestiae ut ut quas totam\\nnostrum rerum est autem sunt rem eveniet architecto\"
    }
    """
}
