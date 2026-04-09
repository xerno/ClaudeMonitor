import Testing
import Foundation
@testable import ClaudeMonitor

struct FormatIntervalTests {

    @Test func seconds() {
        #expect(Formatting.formatInterval(0) == "0s")
        #expect(Formatting.formatInterval(1) == "1s")
        #expect(Formatting.formatInterval(30) == "30s")
        #expect(Formatting.formatInterval(59) == "59s")
    }

    @Test func exactMinutes() {
        #expect(Formatting.formatInterval(60) == "1m")
        #expect(Formatting.formatInterval(120) == "2m")
        #expect(Formatting.formatInterval(300) == "5m")
        #expect(Formatting.formatInterval(3540) == "59m")
    }

    @Test func minutesWithSeconds() {
        #expect(Formatting.formatInterval(90) == "1m 30s")
        #expect(Formatting.formatInterval(150) == "2m 30s")
        #expect(Formatting.formatInterval(3599) == "59m 59s")
    }

    @Test func exactHours() {
        #expect(Formatting.formatInterval(3600) == "1h")
        #expect(Formatting.formatInterval(7200) == "2h")
    }

    @Test func hoursWithMinutes() {
        #expect(Formatting.formatInterval(3660) == "1h 1m")
        #expect(Formatting.formatInterval(5400) == "1h 30m")
    }

    @Test func negativeClampedToZero() {
        #expect(Formatting.formatInterval(-10) == "0s")
        #expect(Formatting.formatInterval(-0.5) == "0s")
    }

    @Test func fractionalSecondsRounded() {
        // Int(max(30.7, 0)) = 30
        #expect(Formatting.formatInterval(30.7) == "30s")
        #expect(Formatting.formatInterval(59.9) == "59s")
    }

    @Test func commonPollingIntervals() {
        // These are the actual intervals the app uses
        #expect(Formatting.formatInterval(Constants.Polling.minInterval) == "24s")
        #expect(Formatting.formatInterval(Constants.Polling.baseInterval) == "1m")
        #expect(Formatting.formatInterval(Constants.Polling.criticalFloor) == "2m")
        #expect(Formatting.formatInterval(Constants.Polling.maxInterval) == "10m")
    }
}
