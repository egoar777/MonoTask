import XCTest

@MainActor
final class TaskCompletionTests: XCTestCase {
    func testRepeatedCompletionAndRestoreLeavesNoEmptyRows() {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.egorkhmylkov.monotask")
        app.launchArguments = ["--screenshots"]
        app.launch()
        let folder = app.descendants(matching: .any)["classic-all-tasks-folder"].firstMatch
        XCTAssertTrue(folder.waitForExistence(timeout: 10))
        folder.tap()

        let title = "Подготовить проект к защите"
        let task = app.staticTexts[title]
        XCTAssertTrue(task.waitForExistence(timeout: 5))
        let originalY = task.frame.minY
        let completedHeader = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Выполнено'")).firstMatch
        XCTAssertTrue(completedHeader.exists)
        completedHeader.tap()
        let otherCompleted = app.staticTexts["Составить план дня"]
        XCTAssertTrue(otherCompleted.waitForExistence(timeout: 3))
        let originalCompletedY = otherCompleted.frame.minY
        let originalCellCount = app.cells.count

        for _ in 0..<3 {
            let openRow = app.cells.containing(.staticText, identifier: title).firstMatch
            let complete = openRow.buttons["Отметить выполненной"]
            XCTAssertTrue(complete.waitForExistence(timeout: 3))
            // Native List may expose a stale accessibility activation point after a move.
            // Tap the visible control at its current screen position, as a user does.
            app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: complete.frame.midX, dy: complete.frame.midY)).tap()
            let completed = NSPredicate(format: "label == %@", "Выполнено, 2")
            expectation(for: completed, evaluatedWith: completedHeader)
            waitForExpectations(timeout: 5)

            let completedRow = app.cells.containing(.staticText, identifier: title).firstMatch
            let restore = completedRow.buttons["Вернуть в работу"]
            if !restore.isHittable { app.swipeUp() }
            XCTAssertTrue(restore.waitForExistence(timeout: 3))
            app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: restore.frame.midX, dy: restore.frame.midY)).tap()
            let restored = NSPredicate(format: "label == %@", "Выполнено, 1")
            expectation(for: restored, evaluatedWith: completedHeader)
            waitForExpectations(timeout: 5)
            XCTAssertTrue(task.waitForExistence(timeout: 3))
            XCTAssertTrue(
                app.cells.containing(.staticText, identifier: title).firstMatch.buttons["Отметить выполненной"]
                    .exists)
            XCTAssertEqual(task.frame.minY, originalY, accuracy: 2)
            XCTAssertEqual(otherCompleted.frame.minY, originalCompletedY, accuracy: 2)
            XCTAssertEqual(app.cells.count, originalCellCount)
        }
    }
}
