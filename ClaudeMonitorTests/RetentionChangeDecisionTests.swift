import Testing
@testable import ClaudeMonitor

@Suite struct RetentionChangeDecisionTests {
    @Test func noChangeWhenValuesAreEqual() {
        let outcome = RetentionChangeDecision.evaluate(
            currentValue: 2,
            newValue: 2,
            archivedWindowCount: 5
        )
        #expect(outcome == .noChange)
    }

    @Test func increaseNeverRequiresAnArchivedWindowCount() {
        #expect(!RetentionChangeDecision.requiresArchivedWindowCount(currentValue: 2, newValue: 5))
    }

    @Test func noChangeNeverRequiresAnArchivedWindowCount() {
        #expect(!RetentionChangeDecision.requiresArchivedWindowCount(currentValue: 2, newValue: 2))
    }

    @Test func decreaseRequiresAnArchivedWindowCount() {
        #expect(RetentionChangeDecision.requiresArchivedWindowCount(currentValue: 5, newValue: 2))
    }

    @Test func increaseAppliesImmediately() {
        let outcome = RetentionChangeDecision.evaluate(
            currentValue: 2,
            newValue: 5,
            archivedWindowCount: 0
        )
        #expect(outcome == .applyImmediately(newValue: 5))
    }

    @Test func decreaseWithNothingToDeleteAppliesImmediately() {
        let outcome = RetentionChangeDecision.evaluate(
            currentValue: 5,
            newValue: 2,
            archivedWindowCount: 0
        )
        #expect(outcome == .applyImmediately(newValue: 2))
    }

    @Test func decreaseThatWouldDeleteSomethingNeedsConfirmation() {
        let outcome = RetentionChangeDecision.evaluate(
            currentValue: 5,
            newValue: 1,
            archivedWindowCount: 3
        )
        #expect(outcome == .needsConfirmation(newValue: 1, deletingCount: 3))
    }

    @Test func decreaseAtTheMinimumBoundaryStillEvaluatesNormally() {
        let outcome = RetentionChangeDecision.evaluate(
            currentValue: Constants.History.maxRetentionYears,
            newValue: Constants.History.minRetentionYears,
            archivedWindowCount: 42
        )
        #expect(outcome == .needsConfirmation(newValue: Constants.History.minRetentionYears, deletingCount: 42))
    }
}
