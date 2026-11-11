import Foundation

/// Private cookie-backed transport. No shared cookie jar, disk cache or redirects.
final class FlexSessionClient: Sendable {
    private let session: URLSession

    init(configuration: URLSessionConfiguration = .ephemeral) {
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 25
        session = URLSession(configuration: configuration, delegate: FlexRedirectBlocker(), delegateQueue: nil)
    }

    static func request(path: String, cookies: [HTTPCookie], deviceID: String) throws -> URLRequest {
        guard path.hasPrefix("/api/"), !path.hasPrefix("//"),
              let url = URL(string: "https://flex.team" + path),
              url.scheme == "https", url.host == "flex.team" else { throw Failure.invalidRequest }
        let relevant = cookies.filter {
            ["flex.team", ".flex.team"].contains($0.domain) &&
            url.path.hasPrefix($0.path) && ($0.expiresDate.map { $0 > Date() } ?? true)
        }
        guard let aid = relevant.first(where: { $0.name == "AID" && $0.path == "/" })?.value,
              !aid.isEmpty else { throw Failure.missingSession }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.allHTTPHeaderFields = HTTPCookie.requestHeaderFields(with: relevant)
        request.setValue(aid, forHTTPHeaderField: "x-flex-aid")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("https://flex.team", forHTTPHeaderField: "Origin")
        request.setValue("https://flex.team/home", forHTTPHeaderField: "Referer")
        request.setValue(relevant.first(where: { $0.name == "DEVICE_ID" })?.value ?? deviceID,
                         forHTTPHeaderField: "Flexteam-Deviceid")
        request.setValue("ko", forHTTPHeaderField: "Flexteam-Locale")
        request.setValue("FLEX", forHTTPHeaderField: "Flexteam-Productcode")
        request.setValue("base", forHTTPHeaderField: "X-Flex-Axios")
        request.setValue(ISO8601DateFormatter().string(from: Date()), forHTTPHeaderField: "X-Request-Time")
        return request
    }

    func get(path: String, cookies: [HTTPCookie], deviceID: String) async throws -> Data {
        let request = try Self.request(path: path, cookies: cookies, deviceID: deviceID)
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw Failure.invalidResponse }
        guard (200..<300).contains(response.statusCode) else { throw Failure.status(response.statusCode) }
        guard response.mimeType == "application/json" else { throw Failure.contentType }
        return data
    }

    enum Failure: Error { case invalidRequest, missingSession, invalidResponse, status(Int), contentType }
}

private final class FlexRedirectBlocker: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
