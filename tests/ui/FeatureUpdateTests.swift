import XCTest

@MainActor
final class FeatureUpdateTests: XCTestCase {
    let app = XCUIApplication(bundleIdentifier: "com.egorkhmylkov.monotask")

    override func setUp() {
        continueAfterFailure = false
    }

    func testFoldersReorderByDragging() {
        app.launchArguments = ["--screenshots"]
        app.launch()
        let study = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'classic-folder-' AND label CONTAINS 'Учёба'")).firstMatch
        let personal = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'classic-folder-' AND label CONTAINS 'Личное'")).firstMatch
        XCTAssertTrue(study.waitForExistence(timeout: 10))
        XCTAssertTrue(personal.exists)
        let initialStudy = study.frame
        let initialPersonal = personal.frame
        study.press(forDuration: 0.6, thenDragTo: personal, withVelocity: .slow, thenHoldForDuration: 2)
        XCTAssertTrue(waitUntil { study.frame.midY > personal.frame.midY ||
            (abs(study.frame.midY - personal.frame.midY) < 10 && study.frame.midX > personal.frame.midX) })
        XCTAssertNotEqual(study.frame, initialStudy)
        XCTAssertNotEqual(personal.frame, initialPersonal)
        saveScreenshot("folders-after-drag")
        let beforeCancel = study.frame
        let outside = app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.12))
        study.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.6, thenDragTo: outside, withVelocity: .slow, thenHoldForDuration: 1)
        XCTAssertTrue(waitUntil { study.frame == beforeCancel })
        XCTAssertLessThan(app.descendants(matching: .any)["classic-all-tasks-folder"].firstMatch.frame.midY, study.frame.midY)
    }

    func testFolderDragReordersInBothDirections() {
        app.launchArguments = ["--screenshots"]
        app.launch()
        let projects = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'classic-folder-' AND label CONTAINS 'Проекты'")).firstMatch
        let personal = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'classic-folder-' AND label CONTAINS 'Личное'")).firstMatch
        XCTAssertTrue(projects.waitForExistence(timeout: 10))
        let projectsOrigin = projects.frame
        let personalOrigin = personal.frame
        projects.press(forDuration: 0.6, thenDragTo: personal, withVelocity: .slow, thenHoldForDuration: 8)
        XCTAssertTrue(waitUntil { projects.frame.midX > personal.frame.midX })
        XCTAssertTrue(projects.label.contains("Проекты"))
        projects.press(forDuration: 0.6, thenDragTo: personal, withVelocity: .slow, thenHoldForDuration: 1)
        XCTAssertTrue(waitUntil { projects.frame == projectsOrigin && personal.frame == personalOrigin })
        saveScreenshot("folders-drag-restored-labels")
    }

    func testFolderReorderingAfterScrolling() {
        app.launchArguments = ["--screenshots", "--folder-drag-review"]
        app.launch()
        let projects = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'classic-folder-' AND label CONTAINS 'Проекты'")).firstMatch
        let personal = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'classic-folder-' AND label CONTAINS 'Личное'")).firstMatch
        XCTAssertTrue(projects.waitForExistence(timeout: 10))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8)).press(
            forDuration: 0.05,
            thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.65)))
        let before = projects.frame
        projects.press(forDuration: 0.6, thenDragTo: personal, withVelocity: .slow, thenHoldForDuration: 4)
        XCTAssertTrue(waitUntil { projects.frame.midX > personal.frame.midX })
        projects.press(forDuration: 0.6, thenDragTo: personal, withVelocity: .slow, thenHoldForDuration: 2)
        XCTAssertTrue(waitUntil { projects.frame.midX < personal.frame.midX })
        XCTAssertEqual(projects.frame.minX, before.minX, accuracy: 1)
        saveScreenshot("folder-reorder-scrolled")
    }

    func testFolderOrderSurvivesRelaunch() {
        app.launchArguments = ["--screenshots", "--folder-drag-persistence", "--reset-folder-drag-order"]
        app.launch()
        let projects = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'classic-folder-' AND label CONTAINS 'Проекты'")).firstMatch
        let personal = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'classic-folder-' AND label CONTAINS 'Личное'")).firstMatch
        XCTAssertTrue(projects.waitForExistence(timeout: 10))
        projects.press(forDuration: 0.6, thenDragTo: personal, withVelocity: .slow, thenHoldForDuration: 1)
        XCTAssertTrue(waitUntil { projects.frame.midX > personal.frame.midX })
        app.terminate()
        app.launchArguments = ["--screenshots", "--folder-drag-persistence"]
        app.launch()
        XCTAssertTrue(projects.waitForExistence(timeout: 10))
        XCTAssertGreaterThan(projects.frame.midX, personal.frame.midX)
    }

    func testFolderMovementScrollsAtBottomEdge() {
        app.launchArguments = ["--screenshots", "--folder-drag-review"]
        app.launch()
        let projects = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'classic-folder-' AND label CONTAINS 'Проекты'")).firstMatch
        let sport = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'classic-folder-' AND label CONTAINS 'Спорт'")).firstMatch
        XCTAssertTrue(projects.waitForExistence(timeout: 10))
        let lowerEdge = app.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.91))
        projects.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(
            forDuration: 0.6, thenDragTo: lowerEdge, withVelocity: .slow, thenHoldForDuration: 4)
        XCTAssertTrue(waitUntil {
            projects.frame.midY > sport.frame.midY ||
            (abs(projects.frame.midY - sport.frame.midY) < 10 && projects.frame.midX > sport.frame.midX)
        })
        saveScreenshot("folder-reorder-at-bottom-edge")
    }

    func testFolderMenuSelectsActionWithoutLiftingFinger() {
        app.launchArguments = ["--screenshots"]
        app.launch()
        let study = app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH 'classic-folder-' AND label CONTAINS 'Учёба'")).firstMatch
        XCTAssertTrue(study.waitForExistence(timeout: 10))
        study.press(forDuration: 1)
        let edit = app.buttons["Изменить папку"]
        XCTAssertTrue(edit.waitForExistence(timeout: 3))
        let target = app.coordinate(withNormalizedOffset: .zero).withOffset(
            CGVector(dx: edit.frame.midX, dy: edit.frame.midY))
        saveScreenshot("native-folder-menu")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8)).tap()
        XCTAssertTrue(waitUntil { !edit.exists })
        // One uninterrupted gesture must reveal the menu and choose its action.
        study.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(
            forDuration: 1, thenDragTo: target, withVelocity: .slow, thenHoldForDuration: 0.3)
        XCTAssertTrue(app.buttons["folder-save"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["personal-folder-name"].value as? String, "Учёба")
    }

    func testFolderMenuDoesNotCaptureNextTap() {
        app.launchArguments = ["--screenshots"]
        app.launch()
        let study = app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH 'classic-folder-' AND label CONTAINS 'Учёба'")).firstMatch
        XCTAssertTrue(study.waitForExistence(timeout: 10))
        study.press(forDuration: 0.6)
        XCTAssertTrue(app.buttons["Открыть папку"].waitForExistence(timeout: 3))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8)).tap()
        study.tap()
        XCTAssertTrue(app.staticTexts["classic-folder-title"].waitForExistence(timeout: 5))
    }

    func testFolderDeletionRequiresConfirmationAndKeepsTasks() {
        app.launchArguments = ["--screenshots"]
        app.launch()
        let study = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'classic-folder-' AND label CONTAINS 'Учёба'")).firstMatch
        XCTAssertTrue(study.waitForExistence(timeout: 10))
        study.press(forDuration: 0.6)
        app.buttons["Удалить папку"].tap()
        let confirmation = app.alerts.firstMatch
        XCTAssertTrue(confirmation.waitForExistence(timeout: 3))
        XCTAssertTrue(confirmation.staticTexts["Задачи сохранятся в «Все задачи» без этой папки."].exists)
        confirmation.buttons["Отмена"].tap()
        XCTAssertTrue(study.exists)
        study.press(forDuration: 0.6)
        app.buttons["Удалить папку"].tap()
        confirmation.buttons["Удалить"].tap()
        XCTAssertTrue(waitUntil { !study.exists })
        app.descendants(matching: .any)["classic-all-tasks-folder"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Разобрать конспект по сетям"].waitForExistence(timeout: 5))
    }

    private func waitUntil(_ condition: @escaping () -> Bool) -> Bool {
        let predicate = NSPredicate { _, _ in condition() }
        return XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: nil)], timeout: 5) == .completed
    }

    func testFoldersTabDoubleTapReturnsHome() {
        app.launchArguments = ["--screenshots"]
        app.launch()
        let folders = app.buttons["navigation-today"]
        let allTasks = app.descendants(matching: .any)["classic-all-tasks-folder"].firstMatch
        let folderTitle = app.staticTexts["classic-folder-title"]
        XCTAssertTrue(allTasks.waitForExistence(timeout: 10))
        XCTAssertEqual(folders.label, "Папки")

        // Keep the selected folder when switching tabs with a single tap.
        allTasks.tap()
        XCTAssertTrue(folderTitle.waitForExistence(timeout: 5))
        app.buttons["Закрыть ввод"].tap()
        app.buttons["navigation-activity"].tap()
        XCTAssertTrue(app.staticTexts["АНАЛИТИКА"].waitForExistence(timeout: 5))
        folders.tap()
        XCTAssertTrue(folderTitle.waitForExistence(timeout: 5))
        folders.doubleTap()
        XCTAssertTrue(allTasks.waitForExistence(timeout: 5))
        XCTAssertFalse(folderTitle.exists)

        // Reset the retained folder directly from each of the other tabs.
        for tab in ["navigation-activity", "navigation-settings"] {
            allTasks.tap()
            XCTAssertTrue(folderTitle.waitForExistence(timeout: 5))
            app.buttons["Закрыть ввод"].tap()
            app.buttons[tab].tap()
            XCTAssertTrue(folders.waitForExistence(timeout: 5))
            folders.doubleTap()
            XCTAssertTrue(allTasks.waitForExistence(timeout: 5))
            XCTAssertFalse(folderTitle.exists)
            XCTAssertFalse(app.textFields["task-capture-title"].exists)
        }
        saveScreenshot("folders-home-tab")
    }

    func testDefaultFolderAndPriorityPersistence() {
        app.launchArguments = ["--screenshots"]
        app.launch()
        let folder = app.descendants(matching: .any)["classic-all-tasks-folder"].firstMatch
        XCTAssertTrue(folder.waitForExistence(timeout: 10))
        folder.tap()
        XCTAssertTrue(app.staticTexts["classic-folder-title"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["classic-folder-focus"].exists)
        app.staticTexts["Разобрать конспект по сетям"].tap()
        let picker = app.descendants(matching: .any)["task-editor-priority"].firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        picker.tap()
        app.buttons["Средний"].tap()
        app.buttons["Готово"].tap()
        app.staticTexts["Разобрать конспект по сетям"].tap()
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        XCTAssertTrue(picker.label.contains("Средний") || (picker.value as? String)?.contains("Средний") == true)
        saveScreenshot("priority-editor")
        app.buttons["Готово"].tap()
        saveScreenshot("all-tasks")
    }

    func testExpandingAnalyticsFolderKeepsScrollPosition() {
        app.launchArguments = ["--screenshots", "--activity"]
        app.launch()
        let folder = app.buttons["analytics-folder-Учёба"]
        let section = app.staticTexts["По папкам"]
        XCTAssertTrue(folder.waitForExistence(timeout: 10))

        for period in ["Неделя", "Месяц", "Год"] {
            app.segmentedControls.buttons[period].tap()
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
            let heading = app.staticTexts["АНАЛИТИКА"]
            let initialHeadingY = heading.frame.minY
            let initialSectionY = section.frame.minY
            folder.tap()
            XCTAssertTrue(app.descendants(matching: .any)["analytics-folder-heatmap-\(period)"].firstMatch.waitForExistence(timeout: 5))
            XCTAssertEqual(folder.value as? String, "Развёрнуто")
            // Wait for the disclosure animation before comparing viewport coordinates.
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
            XCTAssertEqual(heading.frame.minY, initialHeadingY, accuracy: 1, period)
            XCTAssertEqual(section.frame.minY, initialSectionY, accuracy: 1, period)
            folder.tap()
            XCTAssertTrue(waitUntil { folder.value as? String == "Свёрнуто" })
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }
    }

    func testSummaryChartOpensDetailsForEachPeriod() throws {
        app.launchArguments = ["--screenshots", "--activity"]
        app.launch()
        XCTAssertTrue(app.staticTexts["АНАЛИТИКА"].waitForExistence(timeout: 10))

        let day = Calendar.current.component(.day, from: .now)
        let weekday = Calendar.current.component(.weekday, from: .now)
        let month = Calendar.current.component(.month, from: .now)
        let bucketIndexes = [(weekday + 5) % 7, ((day - 1) / 7) * 7, month - 1]
        for (period, index) in zip(["Неделя", "Месяц", "Год"], bucketIndexes) {
            app.segmentedControls.buttons[period].tap()
            let bucket = app.buttons["analytics-bucket-\(index)"]
            XCTAssertTrue(bucket.waitForExistence(timeout: 3))
            let count = try XCTUnwrap(bucket.label.split(separator: ":").last?.split(separator: " ").first.flatMap { Int($0) })
            XCTAssertGreaterThan(count, 0)
            if period == "Неделя" { XCTAssertEqual(count, 1) }
            bucket.tap()
            XCTAssertTrue(app.staticTexts["Выполнено: \(count)"].waitForExistence(timeout: 3))
            app.buttons["Готово"].tap()
        }
    }

    func testHeatmapsAndDayDetails() {
        app.launchArguments = ["--screenshots", "--activity"]
        app.launch()
        XCTAssertTrue(app.staticTexts["АНАЛИТИКА"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Выполнено за неделю"].exists)
        XCTAssertTrue(app.staticTexts["По папкам"].exists)
        let folder = app.buttons["analytics-folder-Учёба"]
        XCTAssertTrue(folder.exists)
        saveScreenshot("analytics")
        folder.tap()
        let week = app.descendants(matching: .any)["analytics-folder-heatmap-Неделя"].firstMatch
        XCTAssertTrue(week.waitForExistence(timeout: 5))
        XCTAssertEqual(folder.value as? String, "Развёрнуто")
        saveScreenshot("analytics-inline-week")
        let today = Calendar.current.component(.day, from: Date())
        let day = app.buttons["analytics-day-\(today)"]
        if !day.isHittable { app.swipeUp() }
        day.tap()
        XCTAssertTrue(app.staticTexts["Выполнено: 1"].waitForExistence(timeout: 5))
        saveScreenshot("analytics-folder-day")
        app.buttons["Готово"].tap()
        folder.tap()
        XCTAssertFalse(week.exists)
        XCTAssertEqual(folder.value as? String, "Свёрнуто")
        app.swipeDown()
        app.segmentedControls.buttons["Месяц"].tap()
        XCTAssertTrue(app.staticTexts["Выполнено за месяц"].exists)
        folder.tap()
        XCTAssertTrue(app.descendants(matching: .any)["analytics-folder-heatmap-Месяц"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["analytics-day-1"].exists)
        saveScreenshot("analytics-inline-month")
        app.swipeDown()
        app.swipeDown()
        app.segmentedControls.buttons["Год"].tap()
        XCTAssertTrue(app.staticTexts["Выполнено за год"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["analytics-folder-heatmap-Год"].firstMatch.exists)
        app.swipeUp()
        saveScreenshot("analytics-inline-year")
    }

    func testCapturePriorityAndCalendarSettings() {
        app.launchArguments = ["--screenshots"]
        app.launch()
        let add = app.buttons["navigation-add-task"]
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        add.tap()
        let input = app.descendants(matching: .any)["task-capture-title"].firstMatch
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["capture-priority"].value as? String, "Без приоритета")
        saveScreenshot("capture-no-priority-blue-circle")
        input.tap()
        XCTAssertFalse(app.buttons["capture-reminder"].exists)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        app.buttons["capture-priority"].tap()
        let medium = app.buttons["Средний"]
        if !medium.waitForExistence(timeout: 3) { app.buttons["capture-priority"].tap() }
        XCTAssertTrue(medium.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Низкий"].exists)
        medium.tap()
        XCTAssertEqual(app.buttons["capture-priority"].value as? String, "Средний")
        XCTAssertTrue(app.buttons["capture-reminder"].exists)
        input.typeText("Задача со средним приоритетом")
        app.buttons["Добавить задачу"].tap()
        app.buttons["Скрыть клавиатуру"].tap()
        app.buttons["Закрыть ввод"].tap()
        app.descendants(matching: .any)["classic-all-tasks-folder"].firstMatch.tap()
        let task = app.staticTexts["Задача со средним приоритетом"]
        if !task.isHittable { app.swipeUp() }
        XCTAssertTrue(task.waitForExistence(timeout: 5))
        task.tap()
        let picker = app.descendants(matching: .any)["task-editor-priority"].firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        XCTAssertTrue(picker.label.contains("Средний") || (picker.value as? String)?.contains("Средний") == true)
        app.terminate()
        app.launchArguments = ["--screenshots", "--settings", "--settings-calendars"]
        app.launch()
        XCTAssertTrue(app.buttons["calendar-connect"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Apple Calendar и Google Calendar"].exists)
        saveScreenshot("calendar-settings")
    }

    private func saveScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
