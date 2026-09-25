import Foundation

protocol UsageFetching: Sendable {
    func fetch(organizationId: String, cookieString: String) async throws -> UsageResponse
}

struct UsageService: UsageFetching, Sendable {
    private static let decoder = JSONDecoder.iso8601WithFractionalSeconds

    static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }()

    func fetch(organizationId: String, cookieString: String) async throws -> UsageResponse {
        guard let url = Constants.API.usageURL(organizationId: organizationId) else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = Constants.Network.requestTimeout
        let sanitizedScalars = cookieString.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }
        let sanitizedCookie = String(String.UnicodeScalarView(sanitizedScalars))
        request.httpShouldHandleCookies = false
        request.setValue(sanitizedCookie, forHTTPHeaderField: "Cookie")
        request.setValue(Constants.API.referer, forHTTPHeaderField: "Referer")
        request.setValue(Constants.API.userAgent, forHTTPHeaderField: "User-Agent")

        let (data, response) = try await Self.session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        switch http.statusCode {
        case 200:
            return try Self.decoder.decode(UsageResponse.self, from: data)
        case 401, 403:
            throw ServiceError.unauthorized
        case 429:
            throw ServiceError.rateLimited
        default:
            throw ServiceError.unexpectedStatus(http.statusCode)
        }
    }
}
