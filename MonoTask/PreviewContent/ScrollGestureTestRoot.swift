import SwiftUI
import SwiftData

#if DEBUG && targetEnvironment(simulator)
/// Disposable local fixtures for exercising real touch gestures without a cloud account.
struct ScrollGestureTestRoot: View {
    @State private var container: ModelContainer

    init() {
        let schema = Schema([
            TaskItem.self, SubtaskItem.self, Tag.self, DailyNote.self,
            WeeklyReview.self, FocusSchedule.self, ActivityEntry.self,
            CompletedHistoryEntry.self, SyncTombstone.self,
        ])
        let opened = try! ModelContainer(
            for: schema,
            configurations: [
                ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            ])
        for index in 1...40 {
            let task = TaskItem(
                title: "Тест прокрутки · \(index)",
                notes: index.isMultiple(of: 3) ? "Проверка строки с дополнительной информацией" : "")
            task.sortOrder = index
            opened.mainContext.insert(task)
        }
        try! opened.mainContext.save()
        _container = State(initialValue: opened)
    }

    var body: some View {
        ContentView()
            .modelContainer(container)
            .onAppear { AuthManager.shared.activeContainer = container }
            .onDisappear {
                TaskDeletionManager.shared.reset()
                AuthManager.shared.activeContainer = nil
            }
    }
}
#endif
