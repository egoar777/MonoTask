import XCTest

@MainActor
final class SettingsDesignTests: XCTestCase {
    private let app = XCUIApplication(bundleIdentifier: "com.egorkhmylkov.monotask")

    override func setUp() {
        continueAfterFailure = false
        app.launchArguments = ["--screenshots", "--settings"]
        app.launch()
        XCTAssertTrue(app.buttons["settings-account"].waitForExistence(timeout: 10))
    }

    private func open(_ identifier: String) {
        let button = app.buttons[identifier]
        if !button.isHittable { app.swipeUp() }
        XCTAssertTrue(button.isHittable)
        button.tap()
    }

    private func back() {
        app.navigationBars.buttons.firstMatch.tap()
    }

    func testSettingsDestinationsAndSeparateCalendars() {
        let folders = app.buttons["settings-folders"]
        let shared = app.buttons["settings-shared-lists"]
        let notifications = app.buttons["settings-notifications"]
        let calendars = app.buttons["settings-calendars"]
        XCTAssertEqual(folders.frame.minY, shared.frame.minY, accuracy: 2)
        XCTAssertEqual(notifications.frame.minY, calendars.frame.minY, accuracy: 2)
        XCTAssertLessThan(folders.frame.minX, shared.frame.minX)
        XCTAssertLessThan(folders.frame.maxY, notifications.frame.minY)
        let title = app.descendants(matching: .any).matching(identifier: "settings-title").firstMatch
        XCTAssertTrue(title.exists)
        XCTAssertEqual(title.label, "НАСТРОЙКИ")
        let account = app.buttons["settings-account"]
        XCTAssertLessThan(title.frame.maxY, account.frame.minY)
        XCTAssertLessThan(account.frame.maxY, folders.frame.minY)
        open("settings-folders")
        XCTAssertTrue(app.buttons["settings-edit-category-Учёба"].waitForExistence(timeout: 3))
        back()
        open("settings-account")
        XCTAssertTrue(app.staticTexts["Локальное пространство"].waitForExistence(timeout: 3))
        back()
        open("settings-notifications")
        XCTAssertTrue(app.switches["Уведомления MonoTask"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["calendar-connect"].exists)
        back()
        open("settings-calendars")
        XCTAssertTrue(app.buttons["calendar-connect"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Apple Calendar и Google Calendar"].exists)
        XCTAssertFalse(app.switches["Уведомления MonoTask"].exists)
        back()
        open("settings-shared-lists")
        XCTAssertTrue(app.staticTexts["Войдите в аккаунт"].waitForExistence(timeout: 5))
    }

    func testInlineAppearancePreviewReflectsPreferences() {
        let notes = app.switches["Показывать заметки в списке"]
        let compact = app.switches["Компактные строки задач"]
        XCTAssertTrue(notes.waitForExistence(timeout: 3))
        XCTAssertTrue(compact.exists)
        let originallyShowingNotes = notes.value as? String == "1"
        let originallyCompact = compact.value as? String == "1"
        let preview = app.buttons["settings-appearance"]
        let task = app.staticTexts["settings-preview-task"]
        let detail = app.staticTexts["settings-preview-notes"]
        XCTAssertEqual(preview.value as? String, "Свёрнуто")
        XCTAssertFalse(task.exists)

        open("settings-appearance")
        XCTAssertTrue(task.waitForExistence(timeout: 3))
        XCTAssertEqual(preview.value as? String, "Развёрнуто")
        XCTAssertEqual(detail.exists, originallyShowingNotes)

        notes.tap()
        compact.tap()
        XCTAssertEqual(detail.exists, !originallyShowingNotes)
        XCTAssertEqual(compact.value as? String == "1", !originallyCompact)
        notes.tap()
        compact.tap()

        open("settings-appearance")
        XCTAssertTrue(task.waitForNonExistence(timeout: 3))
        XCTAssertEqual(preview.value as? String, "Свёрнуто")
        XCTAssertEqual(notes.value as? String == "1", originallyShowingNotes)
        XCTAssertEqual(compact.value as? String == "1", originallyCompact)
    }

    func testOverviewOmitsFolderChipsAndFoldersStillOpenEditor() {
        let chip = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'settings-preview-'"))
            .firstMatch
        XCTAssertFalse(chip.exists)
        open("settings-folders")
        open("settings-edit-category-Учёба")
        XCTAssertTrue(app.textFields["Название"].waitForExistence(timeout: 3))
        app.buttons["Отмена"].tap()
        back()
        XCTAssertTrue(app.buttons["settings-account"].waitForExistence(timeout: 3))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "settings-tiles"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
