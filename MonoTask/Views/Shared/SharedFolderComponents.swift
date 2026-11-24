import SwiftUI

struct SharedMemberAvatar: View {
    let member: SharedMember
    var size: CGFloat = 28

    var body: some View {
        Text(member.initials)
            .font(.system(size: size * 0.34, weight: .bold, design: .rounded))
            .foregroundStyle(Theme.Colors.onAccent)
            .frame(width: size, height: size)
            .background(
                [Theme.Colors.accent, Theme.Colors.tagColor(Theme.Colors.tagColors[1]), Theme.Colors.priority][
                    member.avatarColorIndex],
                in: Circle()
            )
            .overlay(Circle().strokeBorder(Theme.Colors.surface, lineWidth: 2))
            .accessibilityLabel(member.displayName)
    }
}

struct SharedMemberAvatars: View {
    let members: [SharedMember]
    var size: CGFloat = 28
    var limit = 3

    var body: some View {
        HStack(spacing: -size * 0.26) {
            ForEach(Array(members.prefix(limit).enumerated()), id: \.element.id) { index, member in
                SharedMemberAvatar(member: member, size: size).zIndex(Double(limit - index))
            }
            if members.count > limit {
                Text("+\(members.count - limit)")
                    .font(.system(size: size * 0.32, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .frame(width: size, height: size)
                    .background(Theme.Colors.fillStrong, in: Circle())
                    .overlay(Circle().strokeBorder(Theme.Colors.surface, lineWidth: 2))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Участники: " + members.map(\.displayName).joined(separator: ", "))
    }
}

struct SoftPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(
                reduceMotion ? nil : Theme.Motion.quick, value: configuration.isPressed)
    }
}
