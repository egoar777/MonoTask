import SwiftUI
import SwiftData
import UserNotifications
import EventKit
#if os(iOS)
import UIKit
#endif

struct NotificationPreferencesView: View {
    var showsCalendars = true
    var showsNotifications = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @State private var notifications = NotificationService.shared
    @State private var calendarSync = CalendarSyncService.shared
    @State private var testing = false
    @State private var testSent = false

    private var permissionText: String {
        switch notifications.authorization {
        case .authorized: return "Разрешены в системе"
        case .provisional: return "Доставляются тихо"
        case .denied: return "Запрещены в системе"
        case .notDetermined: return "Нужно разрешение системы"
        default: return "Проверьте системные настройки"
        }
    }

    private var morningTime: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(
                    bySettingHour: notifications.preferences.morningHour,
                    minute: notifications.preferences.morningMinute, second: 0, of: .now) ?? .now
            },
            set: { date in
                notifications.preferences.morningHour = Calendar.current.component(.hour, from: date)
                notifications.preferences.morningMinute = Calendar.current.component(.minute, from: date)
            })
    }

    var body: some View {
        @Bindable var notifications = notifications
        VStack(alignment: .leading, spacing: 10) {
            if showsCalendars {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Apple Calendar и Google Calendar").font(.headline)
                    Text(
                        "Напоминания задач создают события с уведомлением в выбранных календарях. Изменения в MonoTask обновляют события; выполнение, удаление задачи или отключение календаря удаляют связанные события."
                    )
                    .font(Theme.Typography.caption).foregroundStyle(Theme.Colors.textSecondary)
                    if calendarSync.hasAccess {
                        ForEach(calendarSync.calendars, id: \.calendarIdentifier) { calendar in
                            Toggle(
                                isOn: Binding(
                                    get: { calendarSync.selectedIDs.contains(calendar.calendarIdentifier) },
                                    set: { calendarSync.select(calendar, enabled: $0, context: context) }
                                )
                            ) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(calendar.title)
                                    Text(calendar.source.title).font(.caption).foregroundStyle(
                                        Theme.Colors.textSecondary)
                                }
                            }
                        }
                        if calendarSync.calendars.isEmpty {
                            Text("Нет доступных календарей для записи.").font(.caption)
                        }
                    } else {
                        Button {
                            Task { await calendarSync.connect(context: context) }
                        } label: {
                            Text("Подключить календари")
                                .modifier(MonoBrandPill(selected: true))
                        }
                        .buttonStyle(MonoBrandPressStyle())
                        .accessibilityIdentifier("calendar-connect")
                    }
                    Text(
                        "Чтобы выбрать Google Calendar, добавьте аккаунт Google в системных настройках: Приложения → Календарь → Учётные записи → Добавить учётную запись. Включите «Календари»."
                    )
                    .font(Theme.Typography.caption).foregroundStyle(Theme.Colors.textSecondary)
                    if let error = calendarSync.errorMessage {
                        Text(error).font(.caption).foregroundStyle(Theme.Colors.warning)
                    }
                }
                .padding(16)
                .modifier(MonoBrandSurface())
            }
            if showsNotifications {
                VStack(alignment: .leading, spacing: 14) {
                    Toggle("Уведомления MonoTask", isOn: $notifications.preferences.enabled)
                        .onChange(of: notifications.preferences.enabled) { _, enabled in
                            if enabled {
                                Task {
                                    await notifications.checkAuthorization()
                                    if notifications.authorization == .notDetermined {
                                        _ = await notifications.requestAuthorization()
                                    }
                                }
                            }
                        }
                    Text(permissionText)
                        .font(Theme.Typography.caption)
                        .foregroundColor(
                            notifications.authorization == .denied ? Theme.Colors.priority : Theme.Colors.textMuted)
                    if notifications.authorization == .notDetermined {
                        Button {
                            Task { _ = await notifications.requestAuthorization() }
                        } label: {
                            Text("Разрешить")
                                .modifier(MonoBrandPill(selected: true))
                        }
                        .buttonStyle(MonoBrandPressStyle())
                    }
                    Button {
                        openSystemSettings()
                    } label: {
                        Text("Настройки системы")
                            .modifier(MonoBrandPill())
                    }
                    .buttonStyle(MonoBrandPressStyle())
                    if notifications.preferences.enabled {
                        Hairline()
                        Toggle("Напоминания задач", isOn: $notifications.preferences.taskReminders)
                        Text(
                            "Выберите дату и время в карточке задачи. Выполнение или удаление отменяет напоминание."
                        )
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textMuted)
                        Toggle("Утренний план", isOn: $notifications.preferences.morningPlan)
                        if notifications.preferences.morningPlan {
                            DatePicker("Время", selection: morningTime, displayedComponents: .hourAndMinute)
                            HStack(spacing: 6) {
                                ForEach(Weekday.orderedFromMonday) { day in
                                    let selected = notifications.preferences.weekdays.contains(day.rawValue)
                                    Button {
                                        if selected {
                                            notifications.preferences.weekdays.removeAll { $0 == day.rawValue }
                                        } else {
                                            notifications.preferences.weekdays.append(day.rawValue)
                                        }
                                    } label: {
                                        Text(day.shortName)
                                            .font(Theme.Typography.numeric(12))
                                            .frame(maxWidth: .infinity, minHeight: 36)
                                            .background(selected ? Theme.Colors.accent : MonoBrand.inset)
                                            .foregroundColor(
                                                selected ? Theme.Colors.background : Theme.Colors.textSecondary
                                            )
                                            .clipShape(.capsule)
                                    }
                                    .buttonStyle(MonoBrandPressStyle())
                                    .animation(reduceMotion ? nil : MonoBrandMotion.control, value: selected)
                                    .accessibilityLabel(day.fullName)
                                    .accessibilityValue(selected ? "Включён" : "Выключен")
                                }
                            }
                            if notifications.preferences.weekdays.isEmpty {
                                Text("Выберите хотя бы один день для утреннего плана.")
                                    .foregroundColor(Theme.Colors.priority)
                            }
                            HStack {
                                Text("Задачи в плане")
                                Spacer()
                                Picker("Задачи в плане", selection: $notifications.preferences.morningScope) {
                                    Text("Только приоритетные").tag("priority")
                                    Text("Все открытые").tag("all")
                                }
                                .labelsHidden()
                            }
                            Stepper(
                                "Названий задач: \(notifications.preferences.taskCount)",
                                value: $notifications.preferences.taskCount, in: 1...8)
                        }
                        Hairline()
                        Toggle("Звук", isOn: $notifications.preferences.sound)
                        Toggle(
                            "Показывать названия задач и папок", isOn: $notifications.preferences.showPreview
                        )
                        Text("Выключите названия, если хотите скрыть содержимое уведомлений на экране блокировки.")
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.textMuted)
                    }
                    Hairline()
                    Button(testing ? "Отправляем…" : "Тестовое уведомление через 5 секунд") {
                        testing = true
                        Task {
                            testSent = await notifications.sendTest()
                            testing = false
                        }
                    }
                    .disabled(testing)
                    if testSent {
                        Text("Проверка запланирована — можно свернуть приложение.").font(Theme.Typography.caption)
                    }
                    if let error = notifications.errorMessage {
                        Text(error).foregroundColor(Theme.Colors.priority)
                    }
                    if notifications.overflowCount > 0 {
                        Text(
                            "Запланированы ближайшие 60 уведомлений. Ещё \(notifications.overflowCount) будут добавлены при следующих открытиях приложения по мере освобождения очереди."
                        )
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.priority)
                    }
                    Text(
                        "Настройки сохраняются для этого аккаунта на этом устройстве. Утренний план подготовлен на 14 дней и обновляется при открытии приложения и синхронизации. Чтобы в нём были свежие задачи, открывайте MonoTask после изменений на другом устройстве."
                    )
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textMuted)
                }
                .animation(reduceMotion ? nil : MonoBrandMotion.disclosure, value: notifications.preferences.enabled)
                .animation(
                    reduceMotion ? nil : MonoBrandMotion.disclosure, value: notifications.preferences.morningPlan
                )
                .padding(16)
                .modifier(MonoBrandSurface())
            }
        }
        .font(Theme.Typography.callout)
        .foregroundStyle(Theme.Colors.textPrimary)
        .toggleStyle(.switch)
        .task {
            await notifications.checkAuthorization()
            calendarSync.reload()
        }
        .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in
            calendarSync.sync(context: context)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                notifications.refresh(context: context)
                calendarSync.reload()
            }
        }
    }

    private func openSystemSettings() {
        #if os(iOS)
        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
        #else
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
            openURL(url)
        }
        #endif
    }
}
