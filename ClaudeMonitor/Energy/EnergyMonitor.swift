import Foundation

/// Own loop rather than the usage poll, which backs off, pauses when the user is away and stops
/// when claude.ai is unreachable — none of which applies to local files.
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

    /// The only place the log path is built.
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

    /// Not started from `init`: a default-constructed instance, as tests create, must not read
    /// hundreds of megabytes.
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

    /// Scans off the main actor: a cold scan takes seconds and must not block the menu.
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
