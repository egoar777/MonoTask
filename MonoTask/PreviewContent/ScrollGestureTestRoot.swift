import SwiftUI
import SwiftData

#if DEBUG && (targetEnvironment(simulator) || os(macOS))
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
/// In-memory sample data for repository screenshots.
struct ScreenshotPreviewRoot: View {
    @State private var container: ModelContainer
    private let initialTab: AppTab

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
        let study = Tag(name: "Учёба", colorHex: "#5AA9FF", scheduledDays: Weekday.orderedFromMonday, sortOrder: 0)
        let projects = Tag(
            name: "Проекты", colorHex: "#B48CFF", scheduledDays: [.monday, .wednesday, .friday], sortOrder: 1)
        let personal = Tag(name: "Личное", colorHex: "#3DDC97", scheduledDays: [.saturday, .sunday], sortOrder: 2)
        for tag in [study, projects, personal] { opened.mainContext.insert(tag) }
        let samples: [(String, String, Tag, Bool)] = [
            ("Подготовить проект к защите", "Презентация, демо и ответы на вопросы", study, true),
            ("Закончить макет приложения", "Проверить типографику и состояния", projects, true),
            ("Разобрать конспект по сетям", "Повторить маршрутизацию и подсети", study, false),
            ("Прочитать главу книги", "20 минут без уведомлений", personal, false),
            ("Запланировать следующую неделю", "Выбрать главное и оставить время на отдых", personal, false),
            ("Проверить синхронизацию", "iPhone и Mac", projects, false),
        ]
        for (index, item) in samples.enumerated() {
            let task = TaskItem(
                title: item.0, notes: item.1, bucket: .todo, isHighPriorityToday: item.3, tags: [item.2])
            task.sortOrder = index
            opened.mainContext.insert(task)
        }
        for day in 0..<210 where day % 7 != 3 && day % 11 != 0 {
            let date = Calendar.current.date(byAdding: .day, value: -day, to: Date.now.startOfDay)!
            for index in 0..<(1 + (day * 7 + day / 3) % 5) {
                let tag = [study, projects, personal][(day + index) % 3]
                opened.mainContext.insert(CompletedHistoryEntry(taskId: UUID(), tagId: tag.id, completedAt: date))
            }
        }
        try! opened.mainContext.save()
        _container = State(initialValue: opened)
        initialTab =
            ProcessInfo.processInfo.arguments.contains("--activity")
            ? .activity : ProcessInfo.processInfo.arguments.contains("--settings") ? .settings : .today
    }

    var body: some View {
        ContentView(initialTab: initialTab)
            .modelContainer(container)
            .onAppear { AuthManager.shared.activeContainer = container }
            .onDisappear {
                TaskDeletionManager.shared.reset()
                AuthManager.shared.activeContainer = nil
            }
    }
}
#endif
