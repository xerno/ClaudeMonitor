import Foundation

struct Profile: Codable, Equatable, Identifiable, Sendable {
    let id: String
    var name: String
    var organizationId: String

    init(id: String = UUID().uuidString, name: String, organizationId: String) {
        self.id = id
        self.name = name
        self.organizationId = organizationId
    }
}
