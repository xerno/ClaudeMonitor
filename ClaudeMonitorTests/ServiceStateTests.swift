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

    @Test func backoffDoublesUntilCapThenStaysCapped() {
        var state = ServiceState()
        state.recordFailure(category: .transient)
        #expect(state.currentBackoff == Constants.Retry.initialBackoff * 2,
                "the first failure must exactly double the initial backoff")

        var observed: [TimeInterval] = [state.currentBackoff]
        for _ in 0..<10 {
            state.recordFailure(category: .transient)
            observed.append(state.currentBackoff)
        }

        for value in observed {
            #expect(value <= Constants.Retry.maxBackoff, "backoff must never exceed the configured maximum")
        }

        for i in 1..<observed.count {
            let previous = observed[i - 1]
            let current = observed[i]
            if previous < Constants.Retry.maxBackoff {
                #expect(current == previous * 2 || current == Constants.Retry.maxBackoff,
                        "each step must either exactly double the previous value or clamp at the maximum")
            } else {
                #expect(current == Constants.Retry.maxBackoff,
                        "once capped, backoff must stay capped on further failures")
            }
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
        state.recordFailure(category: .transient)
        state.recordFailure(category: .transient)

        state.recordSuccess()
        state.recordFailure(category: .transient)
        #expect(state.currentBackoff == Constants.Retry.initialBackoff * 2)
    }

    @Test func mixedFailureCategories() {
        var state = ServiceState()
        state.recordFailure(category: .transient)   // 10→20
        state.recordFailure(category: .authFailure)  // stays 20 (auth doesn't double)
        state.recordFailure(category: .transient)
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
