import Foundation

/// Keeps the token-derived energy estimate current.
///
/// Runs on its own timer rather than riding the usage poll. That poll is network-driven: it backs
/// off on failure, pauses when the user is away, and stops entirely when the API is unreachable.
/// None of that applies to reading local files, and an estimate that froze because claude.ai was
/// down would be wrong for no reason.
@MainActor
final class EnergyMonitor {
    private(set) var estimate: EnergyEstimate?
    private(set) var totals: TokenTotals?
    var onUpdate: (() -> Void)?

    private let logsDirectory: URL
    private let stateFile: URL
    private var state = TokenScanState()
    private var task: Task<Void, Never>?
    private var lastPersisted: Date?

    init(
        logsDirectory: URL = EnergyMonitor.productionLogsDirectory,
        stateFile: URL = EnergyMonitor.productionStateFile
    ) {
        self.logsDirectory = logsDirectory
        self.stateFile = stateFile
    }

    // MARK: - Production locations

    /// The single place the log location is constructed; callers must not build the path themselves.
    static var productionLogsDirectory: URL {
        URL(fileURLWithPath: NSString(string: Constants.Energy.logsDirectory).expandingTildeInPath)
    }

    static var productionStateFile: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport
            .appendingPathComponent(Constants.Energy.stateSubdirectory)
            .appendingPathComponent(Constants.Energy.stateFileName)
    }

    // MARK: - Lifecycle

    /// Begins scanning. Deliberately not called from `init`: a default-constructed coordinator must
    /// not start reading hundreds of megabytes, which is exactly what the test suite does.
    func start() {
        guard task == nil else { return }
        guardAgainstProductionUseUnderTest()
        restorePersistedState()
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(Constants.Energy.scanInterval))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        persist()
    }

    /// One scan. The file reading happens off the main actor — a cold scan of a full archive is
    /// seconds of work and must never block the menu.
    func refresh() async {
        let directory = logsDirectory
        let previous = state

        let scanned = await Task.detached(priority: .userInitiated) {
            TokenLogReader.scan(directory: directory, state: previous)
        }.value

        state = scanned
        totals = scanned.totals
        estimate = EnergyModel.estimate(totals: scanned.totals)
        persistIfDue()
        onUpdate?()
    }

    // MARK: - Persistence

    /// Not private: tests restore state without starting the scan loop.
    func restorePersistedState() {
        guard let data = try? Data(contentsOf: stateFile),
              let restored = try? JSONDecoder().decode(TokenScanState.self, from: data) else { return }
        state = restored
        totals = restored.totals
        estimate = EnergyModel.estimate(totals: restored.totals)
    }

    private func persistIfDue() {
        guard let last = lastPersisted else {
            persist()
            return
        }
        guard Date().timeIntervalSince(last) >= Constants.Energy.statePersistInterval else { return }
        persist()
    }

    func persist() {
        let directory = stateFile.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: stateFile, options: .atomic)
        lastPersisted = Date()
    }

    /// Mirrors the guard in `UsageHistory.init`: under the project's own test runner, touching the
    /// real logs or the real Application Support state is a bug, not a slow test.
    private func guardAgainstProductionUseUnderTest() {
        guard ProcessInfo.processInfo.environment[BuildInfo.underTestEnvVar] != nil else { return }
        if logsDirectory == Self.productionLogsDirectory || stateFile == Self.productionStateFile {
            preconditionFailure(
                "EnergyMonitor must not be started against the real logs or state file during"
                + " tests — inject temporary directories instead."
            )
        }
    }
}
