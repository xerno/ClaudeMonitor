import Foundation
import Network

protocol PathMonitoring: Sendable {
    @MainActor var isSatisfied: Bool { get }
    @MainActor func setOnPathChange(_ handler: @escaping @MainActor (Bool) -> Void)
    func start()
    func cancel()
}

final class PathMonitor: PathMonitoring {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: Constants.Network.pathMonitorQueueLabel)

    @MainActor private(set) var isSatisfied: Bool = true
    @MainActor private var onPathChange: (@MainActor (Bool) -> Void)?

    @MainActor func setOnPathChange(_ handler: @escaping @MainActor (Bool) -> Void) {
        onPathChange = handler
    }

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let satisfied = path.status == .satisfied
            Task { @MainActor in
                guard satisfied != self.isSatisfied else { return }
                self.isSatisfied = satisfied
                self.onPathChange?(satisfied)
            }
        }
        monitor.start(queue: queue)
    }

    func cancel() {
        monitor.cancel()
    }
}
