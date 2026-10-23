import Foundation
import SwiftData
import Observation

/// Keeps deleted tasks out of the UI during the undo window. The cloud tombstone
/// is created only after that window, so an undo never races an in-flight sync.
@Observable
@MainActor
final class TaskDeletionManager {
    static let shared = TaskDeletionManager()

    private(set) var pendingTaskIDs: Set<UUID> = []
    private(set) var lastTaskTitle = ""
    @ObservationIgnored private var pendingContext: ModelContext?
    @ObservationIgnored private var commitTask: Task<Void, Never>?

    var pendingCount: Int { pendingTaskIDs.count }

    func isPending(_ task: TaskItem) -> Bool { pendingTaskIDs.contains(task.id) }

    func requestDelete(_ task: TaskItem, context: ModelContext) {
        requestDelete([task], context: context)
    }

    func requestDelete(_ tasks: [TaskItem], context: ModelContext) {
        guard context === AuthManager.shared.activeContainer?.mainContext else { return }
        if let pendingContext, pendingContext !== context { reset() }
        let newTasks = tasks.filter { !pendingTaskIDs.contains($0.id) }
        guard !newTasks.isEmpty else { return }
        pendingContext = context
        lastTaskTitle = newTasks.last?.title ?? ""
        pendingTaskIDs.formUnion(newTasks.map(\.id))
        NotificationService.shared.refresh(context: context)
        commitTask?.cancel()
        commitTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            commitPending()
        }
    }

    func undo() {
        guard !pendingTaskIDs.isEmpty else { return }
        let context = pendingContext
        reset()
        NotificationService.shared.refresh(context: context)
    }

    func reset() {
        commitTask?.cancel()
        commitTask = nil
        pendingTaskIDs.removeAll()
        pendingContext = nil
        lastTaskTitle = ""
    }

    func commitPending() {
        guard let context = pendingContext,
            context === AuthManager.shared.activeContainer?.mainContext
        else {
            reset()
            return
        }
        let ids = pendingTaskIDs
        if let tasks = try? context.fetch(FetchDescriptor<TaskItem>()) {
            for task in tasks where ids.contains(task.id) {
                context.deleteWithSync(task)
            }
            context.saveAndSync(delaySeconds: 0.1)
        }
        reset()
    }
}
