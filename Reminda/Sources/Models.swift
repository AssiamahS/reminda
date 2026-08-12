import Foundation

struct Reminder: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var due: Date?
    var place: String?
    var latitude: Double?
    var longitude: Double?
    var done = false
    var created = Date()

    var hasPlace: Bool { latitude != nil && longitude != nil }
}
