import XCTest

@MainActor
final class ClassicCaptureTests: XCTestCase {
    func testSketchStatesAndGrowingDraft() {
        continueAfterFailure = false
        do {
            let appearance = "Classic"
            let app = XCUIApplication(bundleIdentifier: "com.egorkhmylkov.monotask")
            app.launchArguments = ["--screenshots"]
            app.launch()
            let add = app.buttons["navigation-add-task"]
            XCTAssertTrue(add.waitForExistence(timeout: 10))
            add.tap()
            let input = app.descendants(matching: .any).matching(identifier: "task-capture-title").firstMatch
            XCTAssertTrue(input.waitForExistence(timeout: 4))
            XCTAssertFalse(app.keyboards.firstMatch.exists)
            XCTAssertFalse(app.buttons["capture-category-picker"].exists)
            XCTAssertFalse(app.buttons["Добавить задачу"].exists)
            waitForHittable(app.buttons["capture-priority"])
            selectPriority("Высокий", in: app)
            XCTAssertEqual(app.buttons["capture-priority"].value as? String, "Высокий")
            capture(app, "Classic compact \(appearance)")
            let compactLeading = input.frame.minX
            input.tap()
            XCTAssertTrue(app.buttons["Скрыть клавиатуру"].waitForExistence(timeout: 4))
            XCTAssertTrue(app.buttons["capture-category-picker"].isHittable)
            XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 4))
            XCTAssertLessThanOrEqual(input.frame.minX, compactLeading - 10)
            let submit = app.buttons["Добавить задачу"]
            XCTAssertGreaterThanOrEqual(app.keyboards.firstMatch.frame.minY - submit.frame.maxY, 15)
            input.typeText("Тест")
            input.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 4))
            capture(app, "Classic empty keyboard input")
            app.buttons["capture-category-picker"].tap()
            app.buttons["Проекты"].tap()
            XCTAssertTrue(app.buttons["capture-category-picker"].waitForExistence(timeout: 4))
            let initialHeight = input.frame.height
            let draft = String(repeating: "Подготовить подробное описание задачи и проверить поле ввода. ", count: 5)
            input.typeText(draft)
            XCTAssertGreaterThan(input.frame.height, initialHeight + 20)
            XCTAssertLessThanOrEqual(app.buttons["Добавить задачу"].frame.maxY, app.keyboards.firstMatch.frame.minY)
            XCTAssertEqual(app.buttons["capture-priority"].value as? String, "Высокий")
            capture(app, "Classic growing input \(appearance)")
            let keyboard = app.keyboards.firstMatch
            let dragStart = app.coordinate(withNormalizedOffset: .zero).withOffset(
                CGVector(dx: app.frame.midX, dy: input.frame.minY - 40))
            let dragEnd = app.coordinate(withNormalizedOffset: .zero).withOffset(
                CGVector(dx: app.frame.midX, dy: keyboard.frame.maxY - 15))
            dragStart.press(forDuration: 0.05, thenDragTo: dragEnd)
            XCTAssertTrue(app.buttons["Закрыть ввод"].waitForExistence(timeout: 4))
            XCTAssertLessThanOrEqual(input.frame.height, initialHeight + 1)
            XCTAssertEqual(input.frame.minX, compactLeading, accuracy: 1)
            waitForValue(input, draft)
            capture(app, "Classic collapsed draft \(appearance)")
            app.buttons["Закрыть ввод"].tap()
            XCTAssertTrue(add.waitForExistence(timeout: 4))
            add.tap()
            XCTAssertTrue(input.waitForExistence(timeout: 4))
            waitForValue(input, draft)
            input.tap()
            XCTAssertTrue(app.buttons["Скрыть клавиатуру"].waitForExistence(timeout: 4))
            app.buttons["Добавить задачу"].tap()
            XCTAssertTrue(
                XCTWaiter.wait(
                    for: [
                        XCTNSPredicateExpectation(
                            predicate: NSPredicate(format: "value == %@ OR value == %@", "", "Новая задача"),
                            object: input)
                    ], timeout: 4) == .completed)
            XCTAssertEqual(app.buttons["capture-priority"].value as? String, "Без приоритета")
            app.buttons["Скрыть клавиатуру"].tap()
            app.buttons["Закрыть ввод"].tap()
            app.buttons["navigation-settings"].tap()
            XCTAssertTrue(add.isHittable)
            app.terminate()
        }
    }

    func testPriorityCaptureSavesReminder() {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.egorkhmylkov.monotask")
        app.launchArguments = ["--screenshots"]
        app.launch()
        let add = app.buttons["navigation-add-task"]
        waitForHittable(add)
        add.tap()
        let input = app.descendants(matching: .any)["task-capture-title"].firstMatch
        waitForHittable(input)
        input.tap()

        let folderPicker = app.buttons["capture-category-picker"]
        let reminder = app.buttons["capture-reminder"]
        waitForHittable(folderPicker)
        XCTAssertFalse(reminder.exists)
        selectPriority("Высокий", in: app)
        waitForHittable(reminder)
        XCTAssertLessThanOrEqual(folderPicker.frame.maxX, reminder.frame.minX)
        capture(app, "Priority capture with reminder beside folder")
        folderPicker.tap()
        app.buttons["Учёба"].tap()

        reminder.tap()
        let done = app.buttons["Готово"]
        waitForHittable(done)
        let reminderHeader = app.navigationBars["Напоминание"]
        let compactTop = reminderHeader.frame.minY
        XCTAssertGreaterThan(compactTop, app.frame.height * 0.7)
        reminderHeader.swipeUp()
        XCTAssertEqual(reminderHeader.frame.minY, compactTop, accuracy: 2)
        capture(app, "Capture reminder date and time")
        let daily = app.buttons["capture-reminder-daily"]
        let date = app.datePickers["capture-reminder-date"]
        let time = app.datePickers["capture-reminder-time"]
        let initialDateFrame = date.frame
        let initialTimeFrame = time.frame
        let initialButtonFrame = daily.frame
        XCTAssertLessThan(initialDateFrame.midX, initialTimeFrame.midX)
        XCTAssertLessThan(initialTimeFrame.midX, initialButtonFrame.midX)
        XCTAssertEqual(initialDateFrame.union(initialButtonFrame).midX, reminderHeader.frame.midX, accuracy: 3)
        XCTAssertEqual(daily.value as? String, "Выключено")
        daily.tap()
        XCTAssertEqual(daily.value as? String, "Включено")
        XCTAssertLessThan(time.frame.midX, initialTimeFrame.midX)
        XCTAssertLessThan(daily.frame.midX, initialButtonFrame.midX)
        XCTAssertEqual(time.frame.union(daily.frame).midX, reminderHeader.frame.midX, accuracy: 3)
        capture(app, "Daily capture reminder")
        daily.tap()
        let recentered = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                abs(time.frame.midX - initialTimeFrame.midX) <= 3
                    && abs(daily.frame.midX - initialButtonFrame.midX) <= 3
            }, object: nil)
        wait(for: [recentered], timeout: 4)
        waitForHittable(date)
        daily.tap()
        done.tap()
        waitForHittable(reminder)
        XCTAssertTrue((reminder.value as? String)?.contains("Ежедневно") == true)

        selectPriority("Без приоритета", in: app)
        XCTAssertFalse(reminder.exists)
        selectPriority("Высокий", in: app)
        waitForHittable(reminder)
        XCTAssertEqual(reminder.value as? String, "Не задано")
        reminder.tap()
        waitForHittable(done)
        XCTAssertEqual(daily.value as? String, "Выключено")
        daily.tap()
        done.tap()
        waitForHittable(reminder)

        let taskTitle = "Проверка напоминания"
        input.typeText(taskTitle)
        app.buttons["Добавить задачу"].tap()
        XCTAssertTrue(reminder.waitForNonExistence(timeout: 4))
        app.buttons["Скрыть клавиатуру"].tap()
        app.buttons["Закрыть ввод"].tap()

        let folder = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'classic-folder-' AND label CONTAINS %@", "Учёба")
        ).firstMatch
        waitForHittable(folder)
        folder.tap()
        let task = app.staticTexts[taskTitle]
        waitForHittable(task)
        task.tap()
        let enabled = app.switches["task-reminder-enabled"]
        if !enabled.isHittable { app.swipeUp() }
        XCTAssertTrue(enabled.waitForExistence(timeout: 4))
        XCTAssertEqual(enabled.value as? String, "1")
        let savedDaily = app.switches["task-reminder-daily"]
        if !savedDaily.isHittable { app.swipeUp() }
        XCTAssertEqual(savedDaily.value as? String, "1")
    }

    func testCreateFolderFromCapturePreservesDraft() {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.egorkhmylkov.monotask")
        app.launchArguments = ["--screenshots"]
        app.launch()
        let add = app.buttons["navigation-add-task"]
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        add.tap()
        let input = app.descendants(matching: .any).matching(identifier: "task-capture-title").firstMatch
        waitForHittable(input)
        input.tap()
        input.typeText("Задача в новой папке")
        selectPriority("Высокий", in: app)
        let picker = app.buttons["capture-category-picker"]
        picker.tap()
        app.buttons["capture-create-folder"].tap()
        let name = app.textFields["Название"]
        XCTAssertTrue(name.waitForExistence(timeout: 4))
        name.tap()
        name.typeText("Новая из ввода")
        app.buttons["Сохранить"].tap()
        XCTAssertTrue(picker.waitForExistence(timeout: 4))
        XCTAssertTrue(picker.label.contains("Новая из ввода"))
        waitForValue(input, "Задача в новой папке")
        XCTAssertEqual(app.buttons["capture-priority"].value as? String, "Высокий")
        capture(app, "New folder selected for draft")
        app.buttons["Добавить задачу"].tap()
        app.buttons["Скрыть клавиатуру"].tap()
        app.buttons["Закрыть ввод"].tap()
        let folder = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'classic-folder-' AND label CONTAINS %@", "Новая из ввода")
        ).firstMatch
        waitForHittable(folder)
        folder.tap()
        XCTAssertTrue(app.staticTexts["Задача в новой папке"].waitForExistence(timeout: 4))
        app.terminate()
    }

    func testInputInsideFolderKeepsItsContext() {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.egorkhmylkov.monotask")
        app.launchArguments = ["--screenshots"]
        app.launch()
        let folder = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'classic-folder-' AND label CONTAINS %@", "Учёба")
        ).firstMatch
        XCTAssertTrue(folder.waitForExistence(timeout: 10))
        let tileY = folder.frame.midY
        folder.tap()
        let input = app.descendants(matching: .any).matching(identifier: "task-capture-title").firstMatch
        waitForHittable(input)
        capture(app, "Classic compact input inside folder")
        input.tap()
        XCTAssertTrue(app.buttons["Скрыть клавиатуру"].waitForExistence(timeout: 4))
        XCTAssertFalse(app.buttons["capture-category-picker"].exists)
        for title in ["Первое дело", "Второе дело"] {
            input.typeText(title)
            capture(app, "Classic folder input " + title)
            app.buttons["Добавить задачу"].tap()
            XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 4))
        }
        app.buttons["Скрыть клавиатуру"].tap()
        XCTAssertTrue(app.buttons["Закрыть ввод"].waitForExistence(timeout: 4))
        capture(app, "Classic folder tasks after capture")
        app.buttons["Закрыть ввод"].tap()
        app.buttons["classic-folder-menu"].tap()
        app.buttons["classic-close-folder"].tap()
        waitForHittable(folder)
        XCTAssertEqual(folder.frame.midY, tileY, accuracy: 2)
        folder.tap()
        XCTAssertTrue(app.staticTexts["Второе дело"].waitForExistence(timeout: 5))
        app.terminate()
    }

    func testCancelledFolderClosingRestoresCapture() {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.egorkhmylkov.monotask")
        app.launchArguments = ["--screenshots"]
        app.launch()
        let folder = app.descendants(matching: .any)["classic-all-tasks-folder"].firstMatch
        XCTAssertTrue(folder.waitForExistence(timeout: 10))
        folder.tap()
        let input = app.descendants(matching: .any)["task-capture-title"].firstMatch
        waitForHittable(input)
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.45))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.10, dy: 0.45))
        start.press(forDuration: 0.01, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.4)
        waitForHittable(app.staticTexts["classic-folder-title"])
        waitForHittable(input)
        XCTAssertFalse(app.buttons["navigation-add-task"].exists)
        capture(app, "Capture restored after cancelled interactive closing")
        app.terminate()
    }

    func testFolderCaptureFollowsRepeatedInteractiveClosing() {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.egorkhmylkov.monotask")
        app.launchArguments = ["--screenshots"]
        app.launch()
        let folder = app.descendants(matching: .any)["classic-all-tasks-folder"].firstMatch
        let input = app.descendants(matching: .any)["task-capture-title"].firstMatch
        let add = app.buttons["navigation-add-task"]
        XCTAssertTrue(folder.waitForExistence(timeout: 10))

        for attempt in 0..<3 {
            folder.tap()
            waitForHittable(input)
            if attempt == 0 {
                input.tap()
                input.typeText("Черновик при закрытии папки")
                app.buttons["Скрыть клавиатуру"].tap()
            }
            waitForValue(input, "Черновик при закрытии папки")
            // Use the native interactive pop rather than the folder menu's close action.
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.45))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.45))
            start.press(forDuration: 0.01, thenDragTo: end, withVelocity: .fast, thenHoldForDuration: 0)
            waitForHittable(add)
            XCTAssertFalse(input.exists)
            XCTAssertFalse(app.keyboards.firstMatch.exists)
            waitForHittable(folder)
        }
        folder.tap()
        waitForHittable(input)
        waitForValue(input, "Черновик при закрытии папки")
        capture(app, "Capture restored after repeated interactive closing")
        app.terminate()
    }

    func testTaskEditorOpensInActiveFolderAndSavesNotes() {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.egorkhmylkov.monotask")
        app.launchArguments = ["--screenshots"]
        app.launch()

        let folder = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'classic-folder-' AND label CONTAINS %@", "Учёба")
        ).firstMatch
        waitForHittable(folder)
        folder.tap()

        let task = app.staticTexts["Подготовить проект к защите"]
        waitForHittable(task)
        let title = app.descendants(matching: .any)["task-editor-title"].firstMatch
        task.tap()
        XCTAssertTrue(title.waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons["Отмена"].isHittable)
        XCTAssertTrue(app.buttons["Готово"].isHittable)
        capture(app, "Classic translucent task editor")
        let notes = app.descendants(matching: .any)["task-editor-notes"].firstMatch
        notes.tap()
        let insertedText = "Glass edit"
        notes.typeText(insertedText)
        app.buttons["Готово"].tap()

        task.tap()
        XCTAssertTrue(title.waitForExistence(timeout: 4))
        XCTAssertTrue((notes.value as? String)?.contains(insertedText) == true)
        notes.tap()
        notes.typeText(" discarded")
        app.buttons["Отмена"].tap()
        XCTAssertTrue(title.waitForNonExistence(timeout: 4))
        task.tap()
        XCTAssertTrue(title.waitForExistence(timeout: 4))
        XCTAssertFalse((notes.value as? String)?.contains("discarded") == true)
        app.buttons["Готово"].tap()

        let origin = app.coordinate(withNormalizedOffset: .zero)
        let swipeStart = origin.withOffset(CGVector(dx: app.frame.midX, dy: app.frame.height * 0.12))
        let swipeEnd = origin.withOffset(CGVector(dx: app.frame.midX, dy: app.frame.height * 0.68))
        swipeStart.press(forDuration: 0.05, thenDragTo: swipeEnd)

        let personal = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'classic-folder-' AND label CONTAINS %@", "Личное")
        ).firstMatch
        personal.tap()
        XCTAssertTrue(app.staticTexts["Прочитать главу книги"].waitForExistence(timeout: 4))
        XCTAssertFalse(title.exists)
    }

    func testLongTaskTextExpandsInPlace() throws {
        try checkLongTaskExpansion(compact: false)
    }

    func testLongTaskTextExpandsInPlaceCompactMode() throws {
        try checkLongTaskExpansion(compact: true)
    }

    private func checkLongTaskExpansion(compact: Bool) throws {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.egorkhmylkov.monotask")
        app.launchArguments = ["--screenshots", "-monotask_compact_rows", compact ? "YES" : "NO"]
        app.launch()

        let folder = app.descendants(matching: .any)["classic-all-tasks-folder"].firstMatch
        waitForHittable(folder)
        folder.tap()

        let task = app.staticTexts["Подготовить проект к защите"]
        let more = app.buttons["Раскрыть задачу полностью"]
        waitForHittable(task)
        XCTAssertFalse(more.exists)
        task.tap()

        let notesField = app.descendants(matching: .any)["task-editor-notes"].firstMatch
        waitForHittable(notesField)
        let extraNotes = String(repeating: " Подробности проекта к защите.", count: 6)
        notesField.tap()
        notesField.typeText(extraNotes)
        let notesValue = try XCTUnwrap(notesField.value as? String).trimmingCharacters(in: .whitespacesAndNewlines)
        app.buttons["Готово"].tap()

        waitForHittable(more)
        let notes = app.staticTexts.matching(NSPredicate(format: "label == %@", notesValue)).firstMatch
        XCTAssertTrue(notes.exists)
        let previewHeight = notes.frame.height
        XCTAssertEqual(more.frame.maxX, notes.frame.maxX, accuracy: 4)
        XCTAssertEqual(more.frame.maxY, notes.frame.maxY, accuracy: 4)
        XCTAssertGreaterThan(notes.frame.maxX, app.frame.width - 30)
        capture(app, "Long task preview")
        more.tap()

        let collapse = app.buttons["Свернуть задачу"]
        waitForHittable(collapse)
        XCTAssertGreaterThan(notes.frame.height, previewHeight + 20)
        XCTAssertFalse(notesField.exists)
        // Collapse stays beside the title; it must not create a footer below the notes.
        XCTAssertLessThan(abs(collapse.frame.midY - task.frame.minY - 10), 4)
        XCTAssertGreaterThanOrEqual(collapse.frame.minX, notes.frame.maxX - 1)
        XCTAssertEqual(collapse.frame.height, 44, accuracy: 1)
        let row = app.cells.containing(.staticText, identifier: "Подготовить проект к защите").firstMatch
        XCTAssertTrue(row.exists)
        XCTAssertLessThanOrEqual(row.frame.maxY - notes.frame.maxY, 14)
        capture(app, "Expanded task")

        collapse.tap()
        waitForHittable(more)
        XCTAssertEqual(notes.frame.height, previewHeight, accuracy: 1)
    }

    func testLongTitleEllipsisExpandsWithoutOpeningEditor() {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.egorkhmylkov.monotask")
        app.launchArguments = ["--screenshots"]
        app.launch()
        let folder = app.descendants(matching: .any)["classic-all-tasks-folder"].firstMatch
        waitForHittable(folder)
        folder.tap()
        let task = app.staticTexts["Подготовить проект к защите"]
        waitForHittable(task)
        task.tap()
        let titleField = app.descendants(matching: .any)["task-editor-title"].firstMatch
        waitForHittable(titleField)
        titleField.tap()
        titleField.typeText(String(repeating: " Подготовить материалы проекта для обсуждения", count: 3))
        app.buttons["Готово"].tap()
        let title = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Подготовить проект к защите"))
            .firstMatch
        let more = app.buttons["Раскрыть задачу полностью"]
        waitForHittable(more)
        let height = title.frame.height
        XCTAssertEqual(more.frame.maxX, title.frame.maxX, accuracy: 10)
        XCTAssertEqual(more.frame.maxY, title.frame.maxY, accuracy: 4)
        XCTAssertGreaterThan(title.frame.maxX, app.frame.width - 30)
        capture(app, "Title with one inline ellipsis")
        let ellipsis = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: title.frame.maxX - 4, dy: title.frame.maxY - 5))
        ellipsis.tap()
        let collapse = app.buttons["Свернуть задачу"]
        waitForHittable(collapse)
        XCTAssertGreaterThan(title.frame.height, height + 20)
        XCTAssertFalse(titleField.exists)
        XCTAssertLessThan(abs(collapse.frame.midY - title.frame.minY - 10), 4)
        XCTAssertGreaterThanOrEqual(collapse.frame.minX, title.frame.maxX - 1)
        capture(app, "Title expanded from inline ellipsis")
        collapse.tap()
        XCTAssertTrue(more.waitForExistence(timeout: 5))
        XCTAssertEqual(title.frame.height, height, accuracy: 1)
        ellipsis.tap()
        waitForHittable(collapse)
        XCTAssertGreaterThan(title.frame.height, height + 20)
        collapse.tap()
        XCTAssertTrue(more.waitForExistence(timeout: 5))
        // Tapping the title away from the ellipsis still edits the task.
        title.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.2)).tap()
        waitForHittable(titleField)
    }

    private func selectPriority(_ title: String, in app: XCUIApplication) {
        app.buttons["capture-priority"].tap()
        app.buttons[title].tap()
    }

    private func waitForHittable(_ element: XCUIElement) {
        XCTAssertEqual(
            XCTWaiter.wait(
                for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: element)],
                timeout: 5), .completed)
    }

    private func waitForValue(_ element: XCUIElement, _ value: String) {
        XCTAssertEqual(
            XCTWaiter.wait(
                for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: element)],
                timeout: 5), .completed)
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
