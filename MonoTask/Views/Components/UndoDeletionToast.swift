import SwiftUI

/// Appears while a task deletion can still be cancelled.
struct UndoDeletionToast: View {
    @State private var deletion = TaskDeletionManager.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .bottom) {
            if deletion.pendingCount > 0 {
                HStack(spacing: 12) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Theme.Colors.accent)

                    Text(
                        deletion.pendingCount == 1
                            ? "Удалена: \(deletion.lastTaskTitle)" : "Удалено задач: \(deletion.pendingCount)"
                    )
                    .font(Theme.Typography.callout)
                    .foregroundColor(Theme.Colors.textPrimary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Button {
                        Haptics.selection()
                        withAnimation(reduceMotion ? nil : Theme.Motion.standard) {
                            deletion.undo()
                        }
                    } label: {
                        Text("Отменить")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Theme.Colors.accent)
                            .padding(.horizontal, 12)
                            .frame(minHeight: 44)
                            .background(Theme.Colors.accent.opacity(0.12))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Отменить удаление")
                }
                .padding(.leading, 16)
                .padding(.trailing, 8)
                .frame(maxWidth: 440, minHeight: 60)
                .modifier(FloatingGlass(shape: Capsule()))
                .accessibilityIdentifier("undo-deletion-toast")
                .padding(.horizontal, 16)
                .transition(reduceMotion ? .opacity : .scale(scale: 0.96, anchor: .bottom).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : Theme.Motion.standard, value: deletion.pendingCount > 0)
    }
}
