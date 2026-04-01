import Foundation

struct UsageService: Sendable {
    func fetch(organizationId: String, cookieString: String) async throws -> UsageResponse {
        guard let url = Constants.API.usageURL(organizationId: organizationId) else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = Constants.Network.requestTimeout
        let sanitizedCookie = cookieString.filter { $0 != "\r" && $0 != "\n" }
        request.setValue(sanitizedCookie, forHTTPHeaderField: "Cookie")
        request.setValue(Constants.API.referer, forHTTPHeaderField: "Referer")
        request.setValue(Constants.API.userAgent, forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        switch http.statusCode {
        case 200:
            return try JSONDecoder.iso8601WithFractionalSeconds.decode(UsageResponse.self, from: data)
        case 401, 403:
            throw ServiceError.unauthorized
        case 429:
            throw ServiceError.rateLimited
        default:
            throw ServiceError.unexpectedStatus(http.statusCode)
        }
    }
}
