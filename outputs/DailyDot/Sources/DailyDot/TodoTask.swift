import Foundation

struct TodoTask: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var isCompleted = false
}

struct TaskArchive: Codable {
    var days: [String: [TodoTask]] = [:]
    var latestDay: String?
}
