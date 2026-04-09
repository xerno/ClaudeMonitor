import Foundation

enum ServiceError: LocalizedError, Sendable {
    case unauthorized
    case rateLimited
    case unexpectedStatus(Int)

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            return String(localized: "error.unauthorized", bundle: .module)
        case .rateLimited:
            return String(localized: "error.rate_limited", bundle: .module)
        case .unexpectedStatus(let code):
            return String(format: String(localized: "error.unexpected_status", bundle: .module), code)
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
        self = .permanent
    }
}
