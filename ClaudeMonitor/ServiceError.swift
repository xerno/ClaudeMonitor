import Foundation

enum ServiceError: LocalizedError, Sendable {
    case unauthorized
    case rateLimited
    case unexpectedStatus(Int)

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "Session expired – update cookie in Preferences"
        case .rateLimited:
            return "Rate limited – too many requests"
        case .unexpectedStatus(let code):
            return "Unexpected HTTP \(code)"
        }
    }
}

enum RetryCategory: Sendable {
    case transient
    case rateLimited
    case authFailure
    case permanent

    init(classifying error: Error) {
        if let serviceError = error as? ServiceError {
            switch serviceError {
            case .unauthorized: self = .authFailure
            case .rateLimited: self = .rateLimited
            case .unexpectedStatus(let code):
                self = (500...599).contains(code) ? .transient : .permanent
            }
            return
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut, .networkConnectionLost, .notConnectedToInternet,
                 .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
                self = .transient
            default:
                self = .permanent
            }
            return
        }
        self = .transient
    }
}
