import Foundation
import SwiftData

var checks = 0
@MainActor
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
    checks += 1
}

@MainActor
func run() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let schema = Schema([TaskItem.self, Tag.self, SubtaskItem.self])
    let config = ModelConfiguration(
        schema: schema, url: directory.appendingPathComponent("test.store"), cloudKitDatabase: .none)
    func seed() throws {
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)
        let tag = Tag(name: "Work", scheduledDays: [Weekday.current])
        let otherTag = Tag(name: "Personal")
        context.insert(tag)
        context.insert(otherTag)
        let task = TaskItem(title: "Persisted", notes: "Notes", isHighPriorityToday: true, tags: [tag])
        context.insert(task)
        let first = SubtaskItem(title: "First", isCompleted: true, sortOrder: 0)
        let second = SubtaskItem(title: "Second", sortOrder: 1)
        context.insert(first)
        context.insert(second)
        task.subtasks = [first, second]
        try context.save()
    }
    try seed()
    let container = try ModelContainer(for: schema, configurations: [config])
    let context = ModelContext(container)
    let task = try context.fetch(FetchDescriptor<TaskItem>()).first!
    let tags = try context.fetch(FetchDescriptor<Tag>())
    let work = tags.first { $0.name == "Work" }!
    let personal = tags.first { $0.name == "Personal" }!
    check(task.title == "Persisted" && task.notes == "Notes", "Title and notes survive reopening a disk store")
    check(
        task.tags.first?.id == work.id && work.tasks.contains { $0.id == task.id },
        "Category inverse relationship survives reopening")
    check(task.sortedSubtasks.map(\.title) == ["First", "Second"], "Subtask order survives reopening")
    check(task.subtasksProgress == 0.5, "Subtask completion survives reopening")
    check(work.scheduledDays == [Weekday.current], "Category schedule survives reopening")
    task.bucket = .done
    check(task.isDone && task.completedAt != nil, "Completing a task records its completion date")
    try context.save()
    let reloaded = ModelContext(container)
    let completed = try reloaded.fetch(FetchDescriptor<TaskItem>()).first!
    check(completed.isDone && completed.completedAt != nil, "Completion is persisted")
    task.bucket = .inbox
    check(
        !task.isDone && task.completedAt == nil && task.isPendingOfflineSync,
        "Undoing completion clears the date and queues synchronization")
    let untagged = TaskItem(title: "Untagged")
    let other = TaskItem(title: "Other", tags: [personal])
    context.insert(untagged)
    context.insert(other)
    let all = [task, untagged, other]
    check(
        Set(TaskScope.focus.filter(all, scheduledTags: [work]).map(\.id)) == Set([task.id, untagged.id]),
        "Focus includes scheduled and untagged tasks")
    check(TaskScope.focus.filter(all, scheduledTags: []).count == 3, "Focus without a schedule falls back to all tasks")
    check(
        TaskScope.highPriority.filter(all, scheduledTags: []).map(\.id) == [task.id],
        "Priority filter preserves only flagged tasks")
    check(
        TaskScope.tag(personal.id).filter(all, scheduledTags: []).map(\.id) == [other.id],
        "Category filter excludes unrelated tasks")
    check(TaskScope.tag(UUID()).validated(tags: tags) == .all, "Missing category falls back to all tasks")
    check(
        TaskScope.all.defaultTag(tags: tags, scheduledTags: [work]) == nil,
        "Adding to all tasks does not silently assign a category")
    check(
        FocusService.shared.currentFocusTags(allTags: tags, override: personal).first?.id == personal.id,
        "Manual focus override takes precedence")
    check(task.priority == .high, "Legacy priority flags remain high")
    for level in Priority.allCases {
        task.priority = level
        try context.save()
        let saved = try ModelContext(container).fetch(FetchDescriptor<TaskItem>()).first { $0.id == task.id }!
        check(saved.priority == level, "Priority survives disk reload: \(level.rawValue)")
        check(saved.isHighPriorityToday == (level == .high), "Priority and legacy flag agree")
    }
    task.priority = .none
    check(!task.isHighPriorityToday, "Removing priority clears legacy flag")
    check(TaskItem(title: "High", priority: .high).isHighPriorityToday, "High priority initializer sets flag")
    let medium = TaskItem(title: "Medium", priority: .medium)
    let high = TaskItem(title: "High", priority: .high)
    let secondMedium = TaskItem(title: "Second medium", priority: .medium)
    let low = TaskItem(title: "Legacy low", priority: .low)
    let priorityTasks = [medium, untagged, high, secondMedium, low]
    check(
        TaskScope.highPriority.filter(priorityTasks, scheduledTags: []).map(\.id)
            == [high.id, medium.id, secondMedium.id],
        "Both priority levels are included, high precedes medium, and equal levels keep their order")
    context.insert(medium)
    try context.save()
    let savedMedium = try ModelContext(container).fetch(FetchDescriptor<TaskItem>()).first { $0.id == medium.id }!
    check(savedMedium.isPriority && savedMedium.priority == .medium, "Medium stays prioritized after disk reload")
    medium.priority = .high
    check(medium.isPriority, "Promoting medium keeps it in priority")
    medium.priority = .medium
    check(medium.isPriority, "Demoting high to medium keeps it in priority")
    medium.priority = .none
    check(!medium.isPriority, "Removing priority leaves the priority section")
    context.delete(medium)
    context.delete(task)
    try context.save()
    let subtasks = try context.fetch(FetchDescriptor<SubtaskItem>())
    check(subtasks.isEmpty, "Deleting a task cascades to its subtasks")
    let categoryCount = try context.fetchCount(FetchDescriptor<Tag>())
    check(categoryCount == 2, "Deleting a task keeps its categories")
    context.delete(personal)
    try context.save()
    check(other.tags.isEmpty, "Deleting a category unlinks tasks without deleting them")
    let taskCount = try context.fetchCount(FetchDescriptor<TaskItem>())
    check(taskCount == 2, "Tasks survive category deletion")
    print("Passed \(checks) model and disk persistence checks")
}
try run()
