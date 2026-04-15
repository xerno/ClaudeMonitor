import Foundation
import IOKit

protocol SystemIdleProviding: Sendable {
    func idleTime() -> TimeInterval
}

final class SystemIdleService: SystemIdleProviding, @unchecked Sendable {
    // Safe: hidEntry is write-once in init, read-only in idleTime
    private let hidEntry: io_registry_entry_t

    init() {
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOHIDSystem"), &iter) == KERN_SUCCESS else {
            hidEntry = 0
            return
        }
        defer { IOObjectRelease(iter) }

        let entry = IOIteratorNext(iter)
        hidEntry = entry != 0 ? entry : 0
    }

    deinit {
        if hidEntry != 0 { IOObjectRelease(hidEntry) }
    }

    func idleTime() -> TimeInterval {
        guard hidEntry != 0 else { return 0 }
        guard let property = IORegistryEntryCreateCFProperty(hidEntry, "HIDIdleTime" as CFString, kCFAllocatorDefault, 0) else { return 0 }
        let nanoseconds = (property.takeRetainedValue() as? NSNumber)?.int64Value ?? 0
        return TimeInterval(nanoseconds) / 1_000_000_000
    }
}
