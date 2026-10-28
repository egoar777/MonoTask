import Foundation
#if DEBUG && (targetEnvironment(simulator) || os(macOS))
enum SharedPreviewFixtures {
    static let ownerID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    static let memberID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    static var snapshot: SharedSnapshot {
        let list = SharedList(
            id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!, title: "Общий проект", ownerID: ownerID,
            createdAt: .now)
        let members = [
            SharedMember(listID: list.id, userID: ownerID, displayName: "Вы"),
            SharedMember(listID: list.id, userID: memberID, displayName: "Саша"),
        ]
        var task = SharedTask(
            listID: list.id, title: "Подготовить общий план", notes: "Согласовать этапы проекта", assigneeID: memberID,
            subtasks: [SharedSubtask(title: "Собрать идеи")], revision: 1)
        task.id = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
        return SharedSnapshot(lists: [list], members: members, tasks: [task])
    }
}
#endif
