import Foundation
import Testing
@testable import ClaudeMonitor

@Suite @MainActor struct ProjectionTests {

    @Test func projectionBelowLimit() {
        let (projected, timeToLimit) = UsageHistory.project(
            currentUtilization: 40,
            rate: 0.005,
            timeRemaining: 3600
        )
        #expect(abs(projected - 58.0) < 0.01)
        #expect(timeToLimit == nil)
    }

    @Test func projectionExceedsLimit() {
        let (projected, timeToLimit) = UsageHistory.project(
            currentUtilization: 60,
            rate: 0.02,
            timeRemaining: 3600
        )
        #expect(abs(projected - 132.0) < 0.01)
        #expect(timeToLimit != nil)
        #expect(abs(timeToLimit! - 2000.0) < 0.01)
    }

    @Test func projectionWithZeroRate() {
        let (projected, timeToLimit) = UsageHistory.project(
            currentUtilization: 50,
            rate: 0,
            timeRemaining: 3600
        )
        #expect(abs(projected - 50.0) < 0.01)
        #expect(timeToLimit == nil)
    }

    @Test func projectionAtExactlyLimit() {
        let (projected, timeToLimit) = UsageHistory.project(
            currentUtilization: 100,
            rate: 0.01,
            timeRemaining: 3600
        )
        #expect(projected > 100.0)
        #expect(timeToLimit == nil)
    }
}
