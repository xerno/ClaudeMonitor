/// Single-waiter, single-signaller rendezvous, driven by `CheckedContinuation` rather than
/// `Task.sleep`/`Task.yield` polling so tests stay deterministic under load.
actor Gate {
    private var isOpen = false
    private var waiter: CheckedContinuation<Void, Never>?

    func open() {
        isOpen = true
        waiter?.resume()
        waiter = nil
    }

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { continuation in
            waiter = continuation
        }
    }
}
