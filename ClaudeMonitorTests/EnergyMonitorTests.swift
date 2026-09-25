import Testing
import AppKit
@testable import ClaudeMonitor

/// The monitor and its route to the menu. These cover the wiring, not the arithmetic —
/// `EnergyModelTests` owns the numbers.
@MainActor
struct EnergyMonitorTests {

    /// The repo's per-run root: swept at the start of the NEXT run, never torn down by this one, so
    /// a failing assertion leaves its files behind for post-mortem. See TestHistoryRoot.
    private func makeTempDirectory() throws -> URL {
        TestHistoryRoot.makeSubdirectory()
    }

    private func writeLog(outputTokens: Int, id: String = "A", to directory: URL) throws {
        let line = """
        {"type":"assistant","requestId":"req_\(id)","uuid":"uuid-\(id)","message":{"id":"msg_\(id)",\
        "model":"claude-opus-5","usage":{"input_tokens":1,"cache_creation_input_tokens":0,\
        "cache_read_input_tokens":10,"output_tokens":\(outputTokens)}}}
        """
        try (line + "\n").data(using: .utf8)!.write(to: directory.appendingPathComponent("\(id).jsonl"))
    }

    private func makeMonitor(logs: URL, root: URL) -> EnergyMonitor {
        EnergyMonitor(logsDirectory: logs, stateFile: root.appendingPathComponent("state.json"))
    }

    // MARK: - Scanning

    @Test func refreshProducesAnEstimateFromTheLogs() async throws {
        let root = try makeTempDirectory()
        let logs = root.appendingPathComponent("logs")
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        try writeLog(outputTokens: 300, to: logs)

        let monitor = makeMonitor(logs: logs, root: root)
        #expect(monitor.estimate == nil, "nothing should be claimed before the first scan")

        await monitor.refresh()

        #expect(monitor.totals?.requests == 1)
        #expect(abs((monitor.estimate?.median ?? 0) - 0.31) < 1e-9)
    }

    @Test func refreshNotifiesSoTheMenuCanRedraw() async throws {
        let root = try makeTempDirectory()
        let logs = root.appendingPathComponent("logs")
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        try writeLog(outputTokens: 300, to: logs)

        let monitor = makeMonitor(logs: logs, root: root)
        var notifications = 0
        monitor.onUpdate = { notifications += 1 }
        await monitor.refresh()
        #expect(notifications == 1)
    }

    // MARK: - Persistence

    /// A restored monitor must show a number before it has scanned anything, otherwise every launch
    /// reads as "no data" for as long as a cold scan takes.
    @Test func persistedStateIsRestoredWithoutScanning() async throws {
        let root = try makeTempDirectory()
        let logs = root.appendingPathComponent("logs")
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        try writeLog(outputTokens: 300, to: logs)

        let first = makeMonitor(logs: logs, root: root)
        await first.refresh()
        first.persist()

        // Second monitor pointed at an empty log directory: anything it reports came from disk.
        let emptyLogs = root.appendingPathComponent("empty")
        try FileManager.default.createDirectory(at: emptyLogs, withIntermediateDirectories: true)
        let second = makeMonitor(logs: emptyLogs, root: root)
        second.restorePersistedState()

        #expect(second.totals?.requests == 1)
        #expect(abs((second.estimate?.median ?? 0) - 0.31) < 1e-9)
    }

    @Test func missingStateFileIsNotAnError() throws {
        let root = try makeTempDirectory()
        let monitor = makeMonitor(logs: root, root: root)
        monitor.restorePersistedState()
        #expect(monitor.estimate == nil)
        #expect(monitor.totals == nil)
    }

    // MARK: - Rendered text

    @Test func nothingIsShownBeforeThereIsAnEstimate() {
        #expect(UsageGraphView.energyText(for: nil) == "")
        #expect(UsageGraphView.energyText(for: .zero) == "")
    }

    @Test func estimateRendersAsIconPlusRange() {
        let text = UsageGraphView.energyText(for: EnergyModel.estimate(outputTokens: 16_023_921))
        #expect(text == "\u{26A1} ~17 kWh")
    }

    // MARK: - Route into the menu

    /// End to end through the value type the menu is built from: an estimate on `MonitorState` has
    /// to reach the label under the graph.
    @Test func estimateOnStateReachesTheGraphView() {
        let view = UsageGraphView()
        let menu = NSMenu()
        let item = NSMenuItem()
        item.tag = MenuBuilder.usageGraphTag
        item.view = view
        menu.addItem(item)

        MenuBuilder.refreshGraph(in: menu, analyses: [], energy: EnergyModel.estimate(outputTokens: 16_023_921))
        #expect(view.currentEnergyText == "\u{26A1} ~17 kWh")

        MenuBuilder.refreshGraph(in: menu, analyses: [], energy: nil)
        #expect(view.currentEnergyText == "")
    }

    @Test func monitorStateCarriesTheEstimate() {
        let estimate = EnergyModel.estimate(outputTokens: 300)
        #expect(MonitorState(energy: estimate).energy == estimate)
        #expect(MonitorState().energy == nil)
    }

    // MARK: - Layout

    /// The energy label must not sit on top of the stats text. Both live on one 20 pt row, so an
    /// overlap would render as two strings drawn over each other rather than as a visible error.
    @Test func statsAndEnergyLabelsDoNotOverlap() {
        let view = UsageGraphView()
        let labels = view.subviews.compactMap { $0 as? NSTextField }
        #expect(labels.count == 2)
        let stats = labels[0], energy = labels[1]
        #expect(stats.alignment == .left, "a centered stats label would drift under the energy label")
        #expect(energy.alignment == .right)
        #expect(stats.frame.maxX <= energy.frame.minX)
        #expect(energy.frame.maxX <= view.bounds.width - MenuBuilder.rowTrailingInset + 0.01)
        #expect(stats.frame.minY == energy.frame.minY, "both belong on the same row")
    }

    /// The reserved width has to fit the widest reading the formatter can produce.
    @Test func reservedWidthFitsTheWidestReading() {
        let widest = UsageGraphView.energyText(for: EnergyEstimate(low: 500_000, median: 1_500_000, high: 2_000_000))
        let measured = NSAttributedString(
            string: widest,
            attributes: [.font: NSFont.systemFont(ofSize: 12)]
        ).size().width
        #expect(measured <= GraphDrawer.Layout.energyLabelWidth, "\(widest) measures \(measured) pt")
    }
}
