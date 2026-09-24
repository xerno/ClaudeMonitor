import Foundation

@MainActor
final class InMemorySecrets {
    var store: [String: String] = [:]
    var isSaveFailing = false

    func load(_ key: String) -> String? { store[key] }

    func save(_ key: String, _ value: String) -> Bool {
        guard !isSaveFailing else { return false }
        store[key] = value
        return true
    }

    func remove(_ key: String) { store[key] = nil }
}
