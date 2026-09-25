import Testing
import Foundation
@testable import ClaudeMonitor

struct UsageServiceSessionTests {

    @Test func sessionNeverStoresOrSendsServerCookies() {
        let configuration = UsageService.session.configuration
        #expect(configuration.httpCookieStorage == nil)
        #expect(configuration.httpShouldSetCookies == false)
        #expect(configuration.httpCookieAcceptPolicy == .never)
        #expect(configuration.urlCache == nil)
    }
}
