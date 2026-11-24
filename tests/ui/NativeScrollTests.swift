import XCTest

@MainActor
final class NativeScrollTests: XCTestCase {
    func testVerticalScrollingAndCompletionWithNativeSwipeRows() {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.egorkhmylkov.monotask")
        app.terminate()
        app.launchArguments = ["--scroll-gesture-test"]
        app.launch()
        let folder = app.descendants(matching: .any)["classic-all-tasks-folder"].firstMatch
        XCTAssertTrue(folder.waitForExistence(timeout: 10))
        folder.tap()
        let firstTask = app.staticTexts["Тест прокрутки · 1"]
        XCTAssertTrue(firstTask.waitForExistence(timeout: 5))
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.75))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.35))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.3)
        XCTAssertTrue(app.staticTexts["Тест прокрутки · 10"].isHittable)
        end.press(forDuration: 0.05, thenDragTo: start, withVelocity: .slow, thenHoldForDuration: 0.3)
        XCTAssertTrue(firstTask.isHittable)
        let checkbox = app.cells.containing(.staticText, identifier: "Тест прокрутки · 1").buttons.matching(
            identifier: "Отметить выполненной"
        ).firstMatch
        XCTAssertTrue(checkbox.isHittable)
        checkbox.tap()
        let removed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: firstTask)
        XCTAssertEqual(XCTWaiter.wait(for: [removed], timeout: 3), .completed)
    }
}
