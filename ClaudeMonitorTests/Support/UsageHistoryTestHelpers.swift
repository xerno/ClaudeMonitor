import Foundation
import Testing
@testable import ClaudeMonitor

func makeEntry(key: String, utilization: Int, resetsAt: Date?) -> WindowEntry {
    WindowEntry.make(key: key, utilization: utilization, resetsAt: resetsAt)!
}

func makeSamples(count: Int, startUtilization: Int, endUtilization: Int, span: TimeInterval, endDate: Date) -> [UtilizationSample] {
    guard count >= 2 else { return [] }
    var samples: [UtilizationSample] = []
    for i in 0..<count {
        let fraction = Double(i) / Double(count - 1)
        let util = startUtilization + Int(Double(endUtilization - startUtilization) * fraction)
        let timestamp = endDate.addingTimeInterval(-span + span * fraction)
        samples.append(UtilizationSample(utilization: util, timestamp: timestamp))
    }
    return samples
}

let archiveTestIdentity = "18000"

func archiveTestDirectory(baseDirectory: URL, orgId: String) -> URL {
    baseDirectory
        .appendingPathComponent("\(orgId)/archive")
        .appendingPathComponent(archiveTestIdentity)
}

func archiveDateFormatterForTests() -> DateFormatter {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd'T'HHmm'Z'"
    f.timeZone = TimeZone(identifier: "UTC")
    return f
}
