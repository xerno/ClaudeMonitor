import Foundation
import IOKit

protocol SystemIdleProviding: Sendable {
    func idleTime() -> TimeInterval
}

struct SystemIdleService: SystemIdleProviding, Sendable {
    func idleTime() -> TimeInterval {
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOHIDSystem"), &iter) == KERN_SUCCESS else { return 0 }
        defer { IOObjectRelease(iter) }

        let entry = IOIteratorNext(iter)
        guard entry != 0 else { return 0 }
        defer { IOObjectRelease(entry) }

        guard let property = IORegistryEntryCreateCFProperty(entry, "HIDIdleTime" as CFString, kCFAllocatorDefault, 0) else { return 0 }
        let nanoseconds = (property.takeRetainedValue() as? NSNumber)?.int64Value ?? 0
        return TimeInterval(nanoseconds) / 1_000_000_000
    }
}
