import Testing
import Foundation
@testable import ClaudeMonitor

struct ServiceStateTests {

    @Test func initialState() {
        let state = ServiceState()
        #expect(state.consecutiveFailures == 0)
        #expect(state.lastError == nil)
        #expect(state.lastSuccess == nil)
        #expect(state.currentBackoff == Constants.Retry.initialBackoff)
    }

    @Test func recordSuccessResetsAll() {
        var state = ServiceState()
        state.recordFailure(category: .transient)
        state.recordFailure(category: .transient)

        state.recordSuccess()

        #expect(state.consecutiveFailures == 0)
        #expect(state.lastError == nil)
        #expect(state.lastSuccess != nil)
        #expect(state.currentBackoff == Constants.Retry.initialBackoff)
    }

    @Test func transientFailureDoublesBackoff() {
        var state = ServiceState()
        state.recordFailure(category: .transient)
        #expect(state.currentBackoff == Constants.Retry.initialBackoff * 2)
        #expect(state.consecutiveFailures == 1)
        #expect(state.lastError == .transient)
    }

    @Test func rateLimitedDoublesBackoff() {
        var state = ServiceState()
        state.recordFailure(category: .rateLimited)
        #expect(state.currentBackoff == Constants.Retry.initialBackoff * 2)
        #expect(state.lastError == .rateLimited)
    }

    @Test func authFailureDoesNotIncreaseBackoff() {
        var state = ServiceState()
        state.recordFailure(category: .authFailure)
        #expect(state.currentBackoff == Constants.Retry.initialBackoff)
        #expect(state.consecutiveFailures == 1)
        #expect(state.lastError == .authFailure)
    }

    @Test func permanentFailureDoesNotIncreaseBackoff() {
        var state = ServiceState()
        state.recordFailure(category: .permanent)
        #expect(state.currentBackoff == Constants.Retry.initialBackoff)
        #expect(state.consecutiveFailures == 1)
    }

    @Test func backoffExactProgression() {
        var state = ServiceState()
        // initial=10, doubles on transient: 20, 40, 80, 160, 300(capped), 300
        let expected: [TimeInterval] = [20, 40, 80, 160, 300, 300]
        for expectedBackoff in expected {
            state.recordFailure(category: .transient)
            #expect(state.currentBackoff == expectedBackoff,
                    "After \(state.consecutiveFailures) failures, expected \(expectedBackoff) got \(state.currentBackoff)")
        }
    }

    @Test func backoffCapsAtMax() {
        var state = ServiceState()
        for _ in 0..<20 {
            state.recordFailure(category: .transient)
        }
        #expect(state.currentBackoff == Constants.Retry.maxBackoff)
    }

    @Test func successAfterFailuresRestartsBackoff() {
        var state = ServiceState()
        state.recordFailure(category: .transient)  // 20
        state.recordFailure(category: .transient)  // 40

        state.recordSuccess()
        state.recordFailure(category: .transient)  // fresh: 10→20
        #expect(state.currentBackoff == Constants.Retry.initialBackoff * 2)
    }

    @Test func mixedFailureCategories() {
        var state = ServiceState()
        state.recordFailure(category: .transient)   // 10→20
        state.recordFailure(category: .authFailure)  // stays 20 (auth doesn't double)
        state.recordFailure(category: .transient)    // 20→40
        #expect(state.currentBackoff == 40)
        #expect(state.consecutiveFailures == 3)
    }

    @Test func consecutiveFailuresAccumulate() {
        var state = ServiceState()
        state.recordFailure(category: .permanent)
        state.recordFailure(category: .authFailure)
        state.recordFailure(category: .transient)
        #expect(state.consecutiveFailures == 3)
    }
}
