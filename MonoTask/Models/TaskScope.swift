import SwiftUI

/// Which slice of tasks a list shows. Shared by the iPhone context chips and the Mac sidebar.
enum TaskScope: Hashable {
    /// Tasks of the contexts scheduled for today, plus untagged tasks
    case focus
    case all
    case highPriority
    case tag(UUID)

    func filter(_ tasks: [TaskItem], scheduledTags: [Tag]) -> [TaskItem] {
        switch self {
        case .all:
            return tasks
        case .focus:
            guard !scheduledTags.isEmpty else { return tasks }
            let scheduledIds = Set(scheduledTags.map(\.id))
            return tasks.filter { task in
                task.tags.isEmpty || task.tags.contains { scheduledIds.contains($0.id) }
            }
        case .highPriority:
            return tasks.filter(\.isHighPriorityToday)
        case .tag(let id):
            return tasks.filter { task in task.tags.contains { $0.id == id } }
        }
    }

    func title(tags: [Tag]) -> String {
        switch self {
        case .focus: return "Фокус дня"
        case .all: return "Все задачи"
        case .highPriority: return "Приоритет"
        case .tag(let id): return tags.first { $0.id == id }?.name ?? "Категория"
        }
    }

    /// Context assigned to tasks created while this scope is active
    func defaultTag(tags: [Tag], scheduledTags: [Tag]) -> Tag? {
        switch self {
        case .focus: return scheduledTags.first
        case .tag(let id): return tags.first { $0.id == id }
        case .all, .highPriority: return nil
        }
    }

    /// Falls back to `.focus` when the scope points at a context that no longer exists
    func validated(tags: [Tag]) -> TaskScope {
        if case .tag(let id) = self, !tags.contains(where: { $0.id == id }) {
            return .focus
        }
        return self
    }
}
