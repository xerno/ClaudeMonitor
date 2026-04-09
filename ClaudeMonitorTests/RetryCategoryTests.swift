import Testing
import Foundation
@testable import ClaudeMonitor

struct RetryCategoryTests {

    // MARK: - ServiceError classification

    @Test func unauthorizedClassifiesAsAuthFailure() {
        #expect(RetryCategory(classifying: ServiceError.unauthorized) == .authFailure)
    }

    @Test func rateLimitedClassifiesAsRateLimited() {
        #expect(RetryCategory(classifying: ServiceError.rateLimited) == .rateLimited)
    }

    @Test func serverErrorsClassifyAsTransient() {
        for code in [500, 502, 503, 504, 599] {
            #expect(RetryCategory(classifying: ServiceError.unexpectedStatus(code)) == .transient,
                    "HTTP \(code) should be transient")
        }
    }

    @Test func clientErrorsClassifyAsPermanent() {
        for code in [400, 404, 405, 422, 499] {
            #expect(RetryCategory(classifying: ServiceError.unexpectedStatus(code)) == .permanent,
                    "HTTP \(code) should be permanent")
        }
    }

    @Test func boundaryBetween4xxAnd5xx() {
        #expect(RetryCategory(classifying: ServiceError.unexpectedStatus(499)) == .permanent)
        #expect(RetryCategory(classifying: ServiceError.unexpectedStatus(500)) == .transient)
    }

    // MARK: - URLError classification

    @Test func transientURLErrors() {
        let transientCodes: [URLError.Code] = [
            .timedOut, .networkConnectionLost, .notConnectedToInternet,
            .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed,
        ]
        for code in transientCodes {
            #expect(RetryCategory(classifying: URLError(code)) == .transient,
                    "\(code) should be transient")
        }
    }

    @Test func permanentURLErrors() {
        let permanentCodes: [URLError.Code] = [
            .badURL, .unsupportedURL, .badServerResponse, .userCancelledAuthentication,
        ]
        for code in permanentCodes {
            #expect(RetryCategory(classifying: URLError(code)) == .permanent,
                    "\(code) should be permanent")
        }
    }

    // MARK: - Unknown errors

    @Test func unknownErrorClassifiesAsPermanent() {
        struct CustomError: Error {}
        #expect(RetryCategory(classifying: CustomError()) == .permanent)
    }

    @Test func nsErrorClassifiesAsPermanent() {
        let error = NSError(domain: "test", code: 42)
        #expect(RetryCategory(classifying: error) == .permanent)
    }
}
