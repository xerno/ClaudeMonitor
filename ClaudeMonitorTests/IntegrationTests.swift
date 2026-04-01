import XCTest
@testable import ClaudeMonitor

/// Integration tests that hit real APIs. These verify network connectivity,
/// DNS resolution, TLS, and response parsing against live endpoints.
final class IntegrationTests: XCTestCase {

    // MARK: - Status API

    func testStatusURLResolves() async throws {
        let url = Constants.API.statusURL
        let host = url.host!

        let hostRef = CFHostCreateWithName(nil, host as CFString).takeRetainedValue()
        var resolved = DarwinBoolean(false)
        CFHostStartInfoResolution(hostRef, .addresses, nil)
        guard let addresses = CFHostGetAddressing(hostRef, &resolved)?.takeUnretainedValue() as? [Data],
              !addresses.isEmpty else {
            XCTFail("DNS resolution failed for \(host). The hostname cannot be resolved from this network.")
            return
        }
        XCTAssertTrue(resolved.boolValue, "DNS resolved but flag is false")
    }

    func testStatusEndpointReturnsHTTP200() async throws {
        let url = Constants.API.statusURL
        let (_, response) = try await URLSession.shared.data(from: url)

        let http = try XCTUnwrap(response as? HTTPURLResponse, "Response is not HTTPURLResponse")
        XCTAssertEqual(http.statusCode, 200, "Expected HTTP 200, got \(http.statusCode)")
    }

    func testStatusEndpointReturnsValidJSON() async throws {
        let url = Constants.API.statusURL
        let (data, _) = try await URLSession.shared.data(from: url)

        XCTAssertFalse(data.isEmpty, "Response body is empty")

        do {
            let summary = try JSONDecoder().decode(StatusSummary.self, from: data)
            XCTAssertFalse(summary.components.isEmpty, "Expected at least one component")
        } catch {
            let raw = String(data: data.prefix(500), encoding: .utf8) ?? "<binary>"
            XCTFail("Failed to decode StatusSummary: \(error)\nRaw response (first 500 bytes): \(raw)")
        }
    }

    func testStatusServiceFetch() async throws {
        let service = StatusService()
        do {
            let summary = try await service.fetch()
            XCTAssertFalse(summary.components.isEmpty, "Expected at least one component from StatusService")
        } catch {
            XCTFail("StatusService.fetch() failed: \(error)\nUnderlying: \(String(describing: (error as NSError).userInfo))")
        }
    }

    // MARK: - Network diagnostics

    func testOutgoingConnectionAllowed() async throws {
        // Minimal test: can the app make ANY outgoing HTTPS connection?
        let url = URL(string: "https://www.apple.com")!
        do {
            let (_, response) = try await URLSession.shared.data(from: url)
            let http = try XCTUnwrap(response as? HTTPURLResponse)
            XCTAssertEqual(http.statusCode, 200, "apple.com returned \(http.statusCode)")
        } catch {
            let nsError = error as NSError
            XCTFail("""
                Cannot make outgoing HTTPS connection.
                Error: \(error.localizedDescription)
                Domain: \(nsError.domain), Code: \(nsError.code)
                UserInfo: \(nsError.userInfo)
                This likely means the app sandbox blocks outgoing connections.
                Fix: set ENABLE_OUTGOING_NETWORK_CONNECTIONS = YES in build settings.
                """)
        }
    }
}
