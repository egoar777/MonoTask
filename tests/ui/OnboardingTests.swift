import XCTest

@MainActor
final class OnboardingTests: XCTestCase {
    private let app = XCUIApplication(bundleIdentifier: "com.egorkhmylkov.monotask")

    override func setUp() {
        continueAfterFailure = false
        app.launchArguments = ["--reset-onboarding"]
        app.launch()
        XCTAssertTrue(app.buttons["onboarding-next"].waitForExistence(timeout: 10))
    }

    func testPagesBackCompletionAndPersistence() {
        XCTAssertTrue(app.staticTexts["onboarding-title"].label.contains("Задачи и приоритеты"))
        capture("onboarding-tasks")
        app.swipeLeft()
        XCTAssertTrue(app.staticTexts["onboarding-title"].label.contains("Личные и общие папки"))
        app.swipeRight()
        XCTAssertTrue(app.staticTexts["onboarding-title"].label.contains("Задачи и приоритеты"))
        app.buttons["onboarding-next"].tap()
        XCTAssertTrue(app.staticTexts["onboarding-title"].label.contains("Личные и общие папки"))
        capture("onboarding-folders")
        app.buttons["Назад"].tap()
        XCTAssertTrue(app.staticTexts["onboarding-title"].label.contains("Задачи и приоритеты"))
        app.buttons["onboarding-next"].tap()
        app.buttons["onboarding-next"].tap()
        XCTAssertTrue(app.staticTexts["onboarding-title"].label.contains("История выполненных задач"))
        capture("onboarding-progress")
        app.buttons["onboarding-next"].tap()
        let signIn = app.buttons["Войти"]
        XCTAssertTrue(signIn.waitForExistence(timeout: 10))
        signIn.tap()
        XCTAssertTrue(app.textFields.firstMatch.waitForExistence(timeout: 10))
        app.terminate()
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(signIn.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["onboarding-next"].exists)
    }

    func testSkipAndPersistence() {
        app.buttons["onboarding-skip"].tap()
        let createAccount = app.buttons["Создать аккаунт"]
        XCTAssertTrue(createAccount.waitForExistence(timeout: 10))
        createAccount.tap()
        XCTAssertTrue(app.staticTexts["Регистрация"].exists)
        app.buttons["Назад"].tap()
        XCTAssertTrue(createAccount.exists)
        app.terminate()
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(createAccount.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["onboarding-next"].exists)
    }

    func testLargeTextKeepsNavigationReachable() {
        app.terminate()
        app.launchArguments = [
            "--reset-onboarding", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
        ]
        app.launch()
        XCTAssertTrue(app.buttons["onboarding-next"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["onboarding-next"].isHittable)
        app.buttons["onboarding-next"].tap()
        XCTAssertTrue(app.buttons["Назад"].isHittable)
        XCTAssertTrue(app.buttons["onboarding-next"].isHittable)
        capture("onboarding-large-text")
        app.buttons["onboarding-skip"].tap()
        XCTAssertTrue(app.buttons["Войти"].waitForExistence(timeout: 10))
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
