import EventKit
import Foundation
import Observation
import SwiftData

/// One-way export of MonoTask reminders to calendars configured on this device.
/// Preferences and identifiers are scoped to the signed-in account, never synced to another device.
@Observable @MainActor
final class CalendarSyncService {
    static let shared = CalendarSyncService()
    private let store = EKEventStore()
    private(set) var calendars: [EKCalendar] = []
    private(set) var selectedIDs: Set<String> = []
    private(set) var errorMessage: String?
    private(set) var hasAccess = false
    private var accountID: UUID?
    private var links: [String: Link] = [:]

    private struct Link: Codable {
        let eventID: String
        let signature: String
        let date: Date
        let marker: URL
    }

    private func key(_ suffix: String) -> String {
        "monotask.calendar.\(accountID?.uuidString ?? "signed-out").\(suffix)"
    }

    private func loadAccount() {
        let id = AuthManager.shared.userID
        guard accountID != id else { return }
        accountID = id
        selectedIDs = Set(UserDefaults.standard.stringArray(forKey: key("selected")) ?? [])
        links =
            UserDefaults.standard.data(forKey: key("links")).flatMap {
                try? JSONDecoder().decode([String: Link].self, from: $0)
            } ?? [:]
        errorMessage = nil
    }

    func reload() {
        loadAccount()
        hasAccess = EKEventStore.authorizationStatus(for: .event) == .fullAccess
        calendars =
            hasAccess
            ? store.calendars(for: .event).filter(\.allowsContentModifications).sorted {
                ($0.source.title, $0.title) < ($1.source.title, $1.title)
            } : []
    }

    func connect(context: ModelContext) async {
        do {
            guard try await store.requestFullAccessToEvents() else {
                reload()
                errorMessage = "Разрешите доступ к календарям в настройках системы."
                return
            }
            reload()
            sync(context: context)
        } catch { errorMessage = error.localizedDescription }
    }

    func select(_ calendar: EKCalendar, enabled: Bool, context: ModelContext) {
        loadAccount()
        if enabled {
            selectedIDs.insert(calendar.calendarIdentifier)
        } else {
            selectedIDs.remove(calendar.calendarIdentifier)
        }
        UserDefaults.standard.set(Array(selectedIDs), forKey: key("selected"))
        sync(context: context)
    }

    func sync(context: ModelContext) {
        guard context === AuthManager.shared.activeContainer?.mainContext,
            AuthManager.shared.userID != nil
        else { return }
        reload()
        guard hasAccess else { return }
        do {
            let tasks = try context.fetch(FetchDescriptor<TaskItem>()).filter {
                !$0.isDone && $0.dueDate != nil && !TaskDeletionManager.shared.isPending($0)
            }
            var activeKeys = Set<String>()
            let availableIDs = Set(calendars.map(\.calendarIdentifier))
            errorMessage = nil
            for task in tasks {
                guard let date = task.dueDate else { continue }
                for calendar in calendars where selectedIDs.contains(calendar.calendarIdentifier) {
                    let linkKey = task.id.uuidString + "|" + calendar.calendarIdentifier
                    activeKeys.insert(linkKey)
                    let marker = URL(string: "monotask://calendar/\(accountID!.uuidString)/\(task.id.uuidString)")!
                    let signature = [
                        task.title, task.notes, String(date.timeIntervalSince1970), String(task.repeatsReminderDaily),
                    ].joined(separator: "\u{1F}")
                    let oldLink = links[linkKey]
                    var existing = oldLink.flatMap { store.event(withIdentifier: $0.eventID) }
                    if existing?.url != marker { existing = nil }
                    if existing == nil {
                        // Event identifiers may change after a server sync. Recover only our own marked event.
                        let originalDate = oldLink?.date ?? date
                        let predicate = store.predicateForEvents(
                            withStart: originalDate.addingTimeInterval(-86400),
                            end: originalDate.addingTimeInterval(86400), calendars: [calendar])
                        existing = store.events(matching: predicate).first { $0.url == marker }
                    }
                    if let existing, oldLink?.signature == signature {
                        links[linkKey] = Link(
                            eventID: existing.eventIdentifier, signature: signature, date: date, marker: marker)
                        continue
                    }
                    let event = existing ?? EKEvent(eventStore: store)
                    event.calendar = calendar
                    event.title = task.title
                    event.notes = task.notes
                    event.url = marker
                    event.startDate = date
                    event.endDate = date.addingTimeInterval(15 * 60)
                    event.isAllDay = false
                    event.alarms = [EKAlarm(relativeOffset: 0)]
                    event.recurrenceRules =
                        task.repeatsReminderDaily
                        ? [EKRecurrenceRule(recurrenceWith: .daily, interval: 1, end: nil)] : nil
                    try store.save(event, span: .futureEvents, commit: true)
                    links[linkKey] = Link(
                        eventID: event.eventIdentifier, signature: signature, date: date, marker: marker)
                }
            }
            for (linkKey, link) in Array(links) where !activeKeys.contains(linkKey) {
                let calendarID = String(linkKey.split(separator: "|", maxSplits: 1).last ?? "")
                // Keep links to unavailable accounts so reconnecting cannot duplicate their events.
                guard availableIDs.contains(calendarID) else { continue }
                var event = store.event(withIdentifier: link.eventID)
                if event?.url != link.marker { event = nil }
                if event == nil, let calendar = calendars.first(where: { $0.calendarIdentifier == calendarID }) {
                    let predicate = store.predicateForEvents(
                        withStart: link.date.addingTimeInterval(-86400), end: link.date.addingTimeInterval(86400),
                        calendars: [calendar])
                    event = store.events(matching: predicate).first { $0.url == link.marker }
                }
                if let event { try store.remove(event, span: .futureEvents, commit: true) }
                links.removeValue(forKey: linkKey)
            }
        } catch { errorMessage = "Не удалось обновить календарь: \(error.localizedDescription)" }
        if let data = try? JSONEncoder().encode(links) {
            UserDefaults.standard.set(data, forKey: key("links"))
        }
    }
}
