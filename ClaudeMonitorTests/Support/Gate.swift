/// A single-waiter, single-signaller rendezvous used to deterministically suspend a
/// mock fetch until the test explicitly releases it, and to let the test wait until the
/// fetch has genuinely started (and is suspended inside it) before proceeding. No
/// `Task.sleep`/`Task.yield` polling anywhere — both transitions are driven by
/// `CheckedContinuation`, so the test is deterministic under load.
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
