import Foundation
import Combine

final class TaskStore: ObservableObject {
    @Published private(set) var archive: TaskArchive
    @Published private(set) var day: String = ""
    private let defaults: UserDefaults
    private let key = "DailyDot.archive.v1"
    var tasks: [TodoTask] { archive.days[day] ?? [] }

    init(defaults: UserDefaults = .standard, now: Date = Date()) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key), let saved = try? JSONDecoder().decode(TaskArchive.self, from: data) {
            archive = saved
        } else {
            archive = TaskArchive()
        }
        refreshDay(now: now)
    }

    static func dateKey(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    func refreshDay(now: Date = Date()) {
        let today = Self.dateKey(now)
        guard today != day else { return }
        if archive.days[today] == nil {
            // Carry the last recorded day's pending work across offline days too.
            let previous = archive.days.keys.filter { $0 < today }.max()
            let pending = previous.flatMap { archive.days[$0] } ?? []
            archive.days[today] = pending.filter { !$0.isCompleted }.map { TodoTask(title: $0.title) }
        }
        day = today
        archive.latestDay = today
        save()
    }

    func add(_ title: String) {
        refreshDay()
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        archive.days[day, default: []].append(TodoTask(title: clean))
        save()
    }

    func toggle(_ id: UUID) {
        refreshDay()
        guard let index = archive.days[day]?.firstIndex(where: { $0.id == id }) else { return }
        archive.days[day]![index].isCompleted.toggle()
        save()
    }

    func delete(_ id: UUID) {
        refreshDay()
        archive.days[day]?.removeAll { $0.id == id }
        save()
    }

    func rename(_ id: UUID, title: String) {
        refreshDay()
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty,
              let index = archive.days[day]?.firstIndex(where: { $0.id == id }) else { return }
        archive.days[day]![index].title = clean
        save()
    }

    // The slot is an insertion boundary in the original, unmodified array.
    func move(_ id: UUID, toInsertionIndex slot: Int) {
        refreshDay()
        guard var tasks = archive.days[day], (0...tasks.count).contains(slot),
              let source = tasks.firstIndex(where: { $0.id == id }) else { return }
        let task = tasks.remove(at: source)
        let destination = slot > source ? slot - 1 : slot
        tasks.insert(task, at: destination)
        archive.days[day] = tasks
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(archive) { defaults.set(data, forKey: key) }
    }
}
