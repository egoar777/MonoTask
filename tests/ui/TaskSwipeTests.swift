import XCTest

@MainActor
final class TaskSwipeTests: XCTestCase {
    private let app = XCUIApplication(bundleIdentifier: "com.egorkhmylkov.monotask")
    private var task: XCUIElement { app.staticTexts["Разобрать конспект по сетям"] }

    override func setUp() {
        continueAfterFailure = false
        app.terminate()
        app.launchArguments = ["--screenshots"]
        app.launch()
        let folder = app.descendants(matching: .any)["classic-all-tasks-folder"].firstMatch
        XCTAssertTrue(folder.waitForExistence(timeout: 10))
        folder.tap()
        XCTAssertTrue(task.waitForExistence(timeout: 5))
    }

    private func drag(_ distance: CGFloat, from x: CGFloat? = nil, on target: XCUIElement? = nil) {
        let start = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: x ?? app.frame.width - 32, dy: (target ?? task).frame.midY))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: distance, dy: 0)))
    }

    private func reveal(on target: XCUIElement? = nil) {
        drag(-110, on: target)
        XCTAssertTrue(app.buttons["task-swipe-edit"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["task-swipe-edit"].isHittable)
        XCTAssertTrue(app.buttons["task-swipe-priority"].isHittable)
        XCTAssertTrue(app.buttons["task-swipe-delete"].isHittable)
        XCTAssertFalse(app.buttons["Отменить удаление"].exists)
    }

    func testDragUpAssignsMediumPriority() {
        let header = app.descendants(matching: .any)["priority-drop-target"].firstMatch
        XCTAssertTrue(header.exists)
        task.press(forDuration: 0.7, thenDragTo: header)
        let checkbox = app.buttons.matching(identifier: "Отметить выполненной")
            .matching(NSPredicate(format: "value == %@", "Средний")).firstMatch
        XCTAssertTrue(checkbox.waitForExistence(timeout: 4))
        XCTAssertLessThan(app.staticTexts["Закончить макет приложения"].frame.minY, task.frame.minY)
        XCTAssertLessThan(task.frame.minY, app.staticTexts["Прочитать главу книги"].frame.minY)
        let other = app.staticTexts["Прочитать главу книги"]
        other.press(forDuration: 0.7, thenDragTo: header)
        XCTAssertLessThan(other.frame.minY, task.frame.minY)
        XCTAssertLessThan(app.staticTexts["Закончить макет приложения"].frame.minY, other.frame.minY)
        task.press(forDuration: 0.7, thenDragTo: header)
        XCTAssertLessThan(task.frame.minY, other.frame.minY)
        XCTAssertEqual(
            app.buttons.matching(identifier: "Отметить выполненной")
                .matching(NSPredicate(format: "value == %@", "Средний")).count, 2)
        reveal()
        app.buttons["task-swipe-edit"].tap()
        let picker = app.descendants(matching: .any)["task-editor-priority"].firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        XCTAssertEqual(picker.value as? String, "Средний")
    }

    func testSwipeEditsAndSavesPriority() {
        reveal()
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "task-three-swipe-actions"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["task-swipe-priority"].tap()
        XCTAssertTrue(app.buttons["Средний"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["Низкий"].exists)
        app.buttons["Средний"].tap()
        reveal()
        app.buttons["task-swipe-edit"].tap()
        let picker = app.descendants(matching: .any)["task-editor-priority"].firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        XCTAssertEqual(picker.value as? String, "Средний")
        app.buttons["Готово"].tap()
        XCTAssertFalse(app.buttons["task-swipe-delete"].exists && app.buttons["task-swipe-delete"].isHittable)
    }

    func testPriorityMenuStaysAtRevealedSwipeAction() {
        let originalX = task.frame.minX
        reveal()
        let revealedX = task.frame.minX
        XCTAssertLessThan(revealedX, originalX - 40)
        app.buttons["task-swipe-priority"].tap()
        XCTAssertTrue(app.buttons["Без приоритета"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Высокий"].exists)
        XCTAssertTrue(app.buttons["Средний"].exists)
        XCTAssertEqual(app.sheets.count, 0)
        XCTAssertEqual(task.frame.minX, revealedX, accuracy: 2)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "priority-menu-at-swipe-star"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["Без приоритета"].tap()
        XCTAssertTrue(task.exists)
    }

    func testPriorityMenuDismissesBackToStarAndReopens() {
        reveal()
        let revealedX = task.frame.minX
        let star = app.buttons["task-swipe-priority"]
        star.tap()
        XCTAssertTrue(app.buttons["Средний"].waitForExistence(timeout: 3))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25)).tap()
        XCTAssertTrue(star.waitForExistence(timeout: 3))
        XCTAssertTrue(star.isHittable)
        XCTAssertEqual(task.frame.minX, revealedX, accuracy: 2)
        star.tap()
        XCTAssertTrue(app.buttons["Средний"].waitForExistence(timeout: 3))
        app.buttons["Средний"].tap()
        XCTAssertTrue(task.exists)
    }

    func testMediumSortsBelowHighInContinuousList() {
        reveal()
        app.buttons["task-swipe-priority"].tap()
        XCTAssertTrue(app.buttons["Средний"].waitForExistence(timeout: 3))
        app.buttons["Средний"].tap()
        let highTask = app.staticTexts["Подготовить проект к защите"]
        let regularTask = app.staticTexts["Прочитать главу книги"]
        XCTAssertTrue(regularTask.waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["Приоритет"].exists)
        XCTAssertFalse(app.staticTexts["Задачи"].exists)
        XCTAssertLessThan(highTask.frame.midY, task.frame.midY)
        XCTAssertLessThan(task.frame.midY, regularTask.frame.midY)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "continuous-task-list"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testChangingPriorityMovesOnlyTheSelectedRowAndClosesSwipe() {
        let movedTask = app.staticTexts["Прочитать главу книги"]
        XCTAssertTrue(movedTask.waitForExistence(timeout: 3))
        let originalFrame = movedTask.frame
        let originalCellCount = app.cells.count
        let highTask = app.staticTexts["Закончить макет приложения"]
        let highTaskFrame = highTask.frame
        XCTAssertGreaterThan(movedTask.frame.midY, task.frame.midY)

        for priority in ["Средний", "Высокий", "Без приоритета"] {
            reveal(on: movedTask)
            app.buttons["task-swipe-priority"].tap()
            XCTAssertTrue(app.buttons[priority].waitForExistence(timeout: 3))
            app.buttons[priority].tap()

            XCTAssertEqual(movedTask.frame.minX, originalFrame.minX, accuracy: 2)
            XCTAssertEqual(task.frame.minX, originalFrame.minX, accuracy: 2)
            XCTAssertEqual(highTask.frame.midY, highTaskFrame.midY, accuracy: 2)
            XCTAssertEqual(app.cells.count, originalCellCount)
            XCTAssertFalse(app.buttons["task-swipe-priority"].exists)
            if priority == "Без приоритета" {
                XCTAssertEqual(movedTask.frame.midY, originalFrame.midY, accuracy: 2)
            } else {
                XCTAssertLessThan(movedTask.frame.midY, task.frame.midY)
                XCTAssertGreaterThan(movedTask.frame.midY, highTask.frame.midY)
            }
        }
    }

    func testSwipeDeleteAndClose() {
        reveal()
        drag(230, from: 65)
        XCTAssertFalse(app.buttons["task-swipe-delete"].exists && app.buttons["task-swipe-delete"].isHittable)
        XCTAssertTrue(task.exists)
        reveal()
        app.buttons["task-swipe-delete"].tap()
        undoDeletion()
        // A full swipe still deletes without a button tap.
        drag(-app.frame.width + 48)
        undoDeletion()
        reveal()
        // Repeat the swipe on the remaining visible portion of the row.
        drag(-90, from: 90)
        undoDeletion()
    }

    func testStretchingDeleteCapsuleCanBeCancelled() {
        let start = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: app.frame.width - 32, dy: task.frame.midY))
        start.press(
            forDuration: 0.05,
            thenDragTo: start.withOffset(CGVector(dx: -245, dy: 0)),
            withVelocity: .slow,
            thenHoldForDuration: 2)
        XCTAssertTrue(task.exists)
        XCTAssertFalse(app.buttons["Отменить удаление"].exists)
        XCTAssertTrue(app.buttons["task-swipe-edit"].isHittable)
        XCTAssertTrue(app.buttons["task-swipe-priority"].isHittable)
        XCTAssertTrue(app.buttons["task-swipe-delete"].isHittable)
        drag(230, from: 65)
        XCTAssertFalse(app.buttons["task-swipe-delete"].exists)
        XCTAssertTrue(task.exists)
    }

    private func undoDeletion() {
        let undo = app.buttons["Отменить удаление"]
        XCTAssertTrue(undo.waitForExistence(timeout: 3))
        XCTAssertFalse(task.exists)
        undo.tap()
        XCTAssertTrue(task.waitForExistence(timeout: 3))
    }
}
