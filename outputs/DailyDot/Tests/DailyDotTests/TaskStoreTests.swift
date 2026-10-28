import XCTest
@testable import DailyDot

final class TaskStoreTests: XCTestCase {
    var defaults: UserDefaults!
    var suite: String!
    override func setUp() {
        suite = "DailyDotTests.\(UUID())"
        defaults = UserDefaults(suiteName: suite)!
    }
    override func tearDown() { defaults.removePersistentDomain(forName: suite) }

    func testDailyRolloverAndPersistence() throws {
        let now = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now)!
        let oldKey = TaskStore.dateKey(yesterday)
        let oldTasks = [TodoTask(title: "pending"), TodoTask(title: "done", isCompleted: true)]
        let archive = TaskArchive(days: [oldKey: oldTasks], latestDay: oldKey)
        defaults.set(try JSONEncoder().encode(archive), forKey: "DailyDot.archive.v1")
        let store = TaskStore(defaults: defaults, now: yesterday)
        store.refreshDay(now: now)
        XCTAssertEqual(store.tasks.map(\.title), ["pending"])
        XCTAssertEqual(store.archive.days[oldKey], oldTasks)
        XCTAssertNotEqual(store.tasks.first?.id, oldTasks.first?.id)
        store.refreshDay(now: now)
        XCTAssertEqual(store.tasks.count, 1)
        XCTAssertEqual(TaskStore(defaults: defaults, now: now).tasks, store.tasks)
    }

    func testAddCompleteDeleteAndReload() {
        let store = TaskStore(defaults: defaults)
        store.add("   ")
        XCTAssertTrue(store.tasks.isEmpty)
        store.add("  First task  ")
        let id = store.tasks[0].id
        store.toggle(id)
        XCTAssertEqual(store.tasks.count, 1)
        XCTAssertTrue(store.tasks[0].isCompleted)
        let loaded = TaskStore(defaults: defaults)
        XCTAssertEqual(loaded.tasks[0].title, "First task")
        XCTAssertTrue(loaded.tasks[0].isCompleted)
        loaded.delete(id)
        XCTAssertTrue(TaskStore(defaults: defaults).tasks.isEmpty)
    }

    func testSingleCompletedTaskCanBeUncheckedAndPersists() {
        let store = TaskStore(defaults: defaults)
        store.add("Only task")
        let id = store.tasks[0].id
        store.toggle(id)
        XCTAssertTrue(store.tasks[0].isCompleted)
        store.toggle(id)
        XCTAssertFalse(store.tasks[0].isCompleted)
        XCTAssertEqual(store.tasks.count, 1)
        XCTAssertFalse(TaskStore(defaults: defaults).tasks[0].isCompleted)
    }

    func testOfflineGapCarriesOnlyPendingAndKeepsHistory() throws {
        let now = Date()
        let older = Calendar.current.date(byAdding: .day, value: -5, to: now)!
        let key = TaskStore.dateKey(older)
        defaults.set(try JSONEncoder().encode(TaskArchive(days: [key: [TodoTask(title: "unfinished"), TodoTask(title: "finished", isCompleted: true)]], latestDay: key)), forKey: "DailyDot.archive.v1")
        let store = TaskStore(defaults: defaults, now: now)
        XCTAssertEqual(store.tasks.map(\.title), ["unfinished"])
        XCTAssertEqual(store.archive.days[key]?.count, 2)
    }
}
