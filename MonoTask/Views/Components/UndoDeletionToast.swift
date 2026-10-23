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
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                            deletion.undo()
                        }
                    } label: {
                        Text("ОТМЕНИТЬ")
                            .font(Theme.Typography.numeric(11, weight: .bold))
                            .foregroundColor(Theme.Colors.onAccent)
                            .padding(.horizontal, 12)
                            .frame(height: 36)
                            .background(Theme.Colors.accent)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Отменить удаление")
                }
                .padding(.leading, 16)
                .padding(.trailing, 8)
                .frame(maxWidth: 440, minHeight: 54)
                .background(Theme.Colors.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                        .strokeBorder(Theme.Colors.ruleStrong, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.45), radius: 14, y: 6)
                .padding(.horizontal, 16)
                .transition(reduceMotion ? .opacity : .offset(y: 8).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.22), value: deletion.pendingCount > 0)
    }
}
