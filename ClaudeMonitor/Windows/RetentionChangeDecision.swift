import Foundation

/// AppKit-free so the confirmation rule is unit-testable.
enum RetentionChangeDecision {
    enum Outcome: Equatable {
        case noChange
        /// An increase, or a decrease that would delete nothing.
        case applyImmediately(newValue: Int)
        case needsConfirmation(newValue: Int, deletingCount: Int)
    }

    /// The count is async and disk-touching, so it is computed only for a decrease, the one case
    /// that can delete anything.
    static func requiresArchivedWindowCount(currentValue: Int, newValue: Int) -> Bool {
        newValue != currentValue && newValue < currentValue
    }

    /// `archivedWindowCount` must be computed against the same `now` later passed to the prune;
    /// pass `0` when `requiresArchivedWindowCount` is false.
    static func evaluate(
        currentValue: Int,
        newValue: Int,
        archivedWindowCount: Int
    ) -> Outcome {
        guard newValue != currentValue else { return .noChange }
        guard newValue < currentValue else { return .applyImmediately(newValue: newValue) }

        guard archivedWindowCount > 0 else { return .applyImmediately(newValue: newValue) }
        return .needsConfirmation(newValue: newValue, deletingCount: archivedWindowCount)
    }
}
