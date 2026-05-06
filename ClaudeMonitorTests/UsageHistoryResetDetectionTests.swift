import Foundation
import Testing
@testable import ClaudeMonitor

@Suite struct ResetDetectionTests {

    @Test @MainActor func resetClearsHistory() async throws {
        let fixture = UsageHistoryTestFixture()
        let history = fixture.history
        history.switchOrganization(UUID().uuidString)

        let now = Date()
        let entry = makeEntry(key: "five_hour", utilization: 42, resetsAt: now.addingTimeInterval(3600))
        history.record(entries: [entry], at: now)
        #expect(history.samples(for: entry).count == 1)

        let duration: TimeInterval = 18000
        let previousResetsAt = now.addingTimeInterval(3600)
        let newResetsAt = previousResetsAt.addingTimeInterval(duration * 0.6)
        await history.detectAndHandleReset(
            entry: makeEntry(key: "five_hour", utilization: 0, resetsAt: newResetsAt),
            newResetsAt: newResetsAt,
            previousResetsAt: previousResetsAt
        )
        #expect(history.samples(for: makeEntry(key: "five_hour", utilization: 0, resetsAt: newResetsAt)).count == 0)
        await fixture.cleanup()
    }

    @Test @MainActor func smallResetsAtChangeDoesNotClear() async {
        let fixture = UsageHistoryTestFixture()
        let history = fixture.history
        let now = Date()
        let entry = makeEntry(key: "five_hour", utilization: 42, resetsAt: now.addingTimeInterval(3600))
        history.record(entries: [entry], at: now)

        let duration: TimeInterval = 18000
        let previousResetsAt = now.addingTimeInterval(3600)
        let newResetsAt = previousResetsAt.addingTimeInterval(duration * 0.3)
        await history.detectAndHandleReset(
            entry: makeEntry(key: "five_hour", utilization: 0, resetsAt: newResetsAt),
            newResetsAt: newResetsAt,
            previousResetsAt: previousResetsAt
        )
        #expect(history.samples(for: entry).count == 1)
        await fixture.cleanup()
    }

    @Test @MainActor func nilResetsAtDoesNotClear() async {
        let fixture = UsageHistoryTestFixture()
        let history = fixture.history
        let now = Date()
        let entry = makeEntry(key: "five_hour", utilization: 42, resetsAt: nil)
        history.record(entries: [entry], at: now)

        await history.detectAndHandleReset(
            entry: makeEntry(key: "five_hour", utilization: 0, resetsAt: nil),
            newResetsAt: nil,
            previousResetsAt: nil
        )
        #expect(history.samples(for: entry).count == 1)
        await fixture.cleanup()
    }
}
