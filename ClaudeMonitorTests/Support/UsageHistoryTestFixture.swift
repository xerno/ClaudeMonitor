@testable import ClaudeMonitor
import Foundation
import Testing

struct UsageHistoryTestFixture {
    let history: UsageHistory
    let baseDirectory: URL

    @MainActor init() {
        self.baseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClaudeMonitorTests-\(UUID().uuidString)", isDirectory: true)
        self.history = UsageHistory(baseDirectory: baseDirectory)
    }

    func cleanup() async {
        await history.clearAll()
        try? FileManager.default.removeItem(at: baseDirectory)
    }
}
