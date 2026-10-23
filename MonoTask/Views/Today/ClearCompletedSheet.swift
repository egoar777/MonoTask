import SwiftUI
import SwiftData

/// Confirmation before deleting the completed tasks of the current list.
private struct ClearCompletedAlert: ViewModifier {
    @Environment(\.modelContext) private var modelContext
    @Binding var isPresented: Bool
    let tasks: [TaskItem]

    func body(content: Content) -> some View {
        content
            .alert("Очистить выполненные?", isPresented: $isPresented) {
                Button("Очистить", role: .destructive) {
                    Haptics.warning()
                    withAnimation(.easeInOut(duration: 0.2)) {
                        modelContext.clearCompleted(tasks)
                    }
                }
                Button("Отмена", role: .cancel) {}
            } message: {
                Text(message)
            }
    }

    private var message: String {
        let count = tasks.filter(\.isDone).count
        return "Будет удалено задач: \(count). История в аналитике сохранится."
    }
}

extension View {
    func clearCompletedAlert(isPresented: Binding<Bool>, tasks: [TaskItem]) -> some View {
        modifier(ClearCompletedAlert(isPresented: isPresented, tasks: tasks))
    }
}
