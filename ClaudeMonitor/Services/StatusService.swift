import Foundation

protocol StatusFetching: Sendable {
    func fetch() async throws -> StatusSummary
}

struct StatusService: StatusFetching, Sendable {
    private static let decoder = JSONDecoder.iso8601WithFractionalSeconds

    func fetch() async throws -> StatusSummary {
        var request = URLRequest(url: Constants.API.statusURL)
        request.timeoutInterval = Constants.Network.requestTimeout
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        switch http.statusCode {
        case 200:
            return try Self.decoder.decode(StatusSummary.self, from: data)
        case 429:
            throw ServiceError.rateLimited
        default:
            throw ServiceError.unexpectedStatus(http.statusCode)
        }
    }
}
