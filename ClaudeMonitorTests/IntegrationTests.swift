import Testing
import Foundation
import CFNetwork
@testable import ClaudeMonitor

/// Integration tests that hit real APIs. These verify network connectivity,
/// DNS resolution, TLS, and response parsing against live endpoints.
struct IntegrationTests {

    // MARK: - Status API

    @Test func statusURLResolves() async throws {
        let url = Constants.API.statusURL
        let host = url.host!

        let hostRef = CFHostCreateWithName(nil, host as CFString).takeRetainedValue()
        var resolved = DarwinBoolean(false)
        CFHostStartInfoResolution(hostRef, .addresses, nil)
        guard let addresses = CFHostGetAddressing(hostRef, &resolved)?.takeUnretainedValue() as? [Data],
              !addresses.isEmpty else {
            Issue.record("DNS resolution failed for \(host). The hostname cannot be resolved from this network.")
            return
        }
        #expect(resolved.boolValue)
    }

    @Test func statusEndpointReturnsHTTP200() async throws {
        let url = Constants.API.statusURL
        let (_, response) = try await URLSession.shared.data(from: url)

        let http = try #require(response as? HTTPURLResponse)
        #expect(http.statusCode == 200)
    }

    @Test func statusEndpointReturnsValidJSON() async throws {
        let url = Constants.API.statusURL
        let (data, _) = try await URLSession.shared.data(from: url)

        #expect(!data.isEmpty)

        do {
            let summary = try JSONDecoder().decode(StatusSummary.self, from: data)
            #expect(!summary.components.isEmpty)
        } catch {
            let raw = String(data: data.prefix(500), encoding: .utf8) ?? "<binary>"
            Issue.record("Failed to decode StatusSummary: \(error)\nRaw response (first 500 bytes): \(raw)")
        }
    }

    @Test func statusServiceFetch() async throws {
        let service = StatusService()
        do {
            let summary = try await service.fetch()
            #expect(!summary.components.isEmpty)
        } catch {
            Issue.record("StatusService.fetch() failed: \(error)\nUnderlying: \(String(describing: (error as NSError).userInfo))")
        }
    }

    // MARK: - Network diagnostics

    @Test func outgoingConnectionAllowed() async throws {
        let url = URL(string: "https://www.apple.com")!
        do {
            let (_, response) = try await URLSession.shared.data(from: url)
            let http = try #require(response as? HTTPURLResponse)
            #expect(http.statusCode == 200)
        } catch {
            let nsError = error as NSError
            let msg = """
                Cannot make outgoing HTTPS connection.
                Error: \(error.localizedDescription)
                Domain: \(nsError.domain), Code: \(nsError.code)
                UserInfo: \(nsError.userInfo)
                This likely means the app sandbox blocks outgoing connections.
                Fix: set ENABLE_OUTGOING_NETWORK_CONNECTIONS = YES in build settings.
                """
            Issue.record(Comment(rawValue: msg))
        }
    }
}
