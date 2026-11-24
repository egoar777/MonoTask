import XCTest

@MainActor
final class SharedFolderTests: XCTestCase {
    let app = XCUIApplication(bundleIdentifier: "com.egorkhmylkov.monotask")

    override func setUp() {
        continueAfterFailure = false
        app.launchArguments = ["--screenshots", "--shared-preview"]
        app.launch()
    }

    private func openFolderEditor() {
        let button = app.buttons["classic-add-folder"]
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        button.tap()
        XCTAssertTrue(app.segmentedControls["folder-type"].waitForExistence(timeout: 5))
    }

    func testCustomFolderColorFitsAndPersists() {
        openFolderEditor()
        let editor = XCTAttachment(screenshot: app.screenshot())
        editor.name = "Folder editor"
        editor.lifetime = .keepAlways
        add(editor)

        let customColor = app.buttons["folder-custom-color"]
        if !customColor.isHittable { app.swipeUp() }
        customColor.tap()

        let palette = app.otherElements["UIColorPicker"].firstMatch
        let grid = palette.buttons.matching(NSPredicate(format: "label IN %@", ["Сетка", "Grid"])).firstMatch
        XCTAssertTrue(grid.waitForExistence(timeout: 5))
        grid.tap()

        let black = palette.otherElements.matching(NSPredicate(format: "label IN %@", ["черный 0", "black 0"]))
            .firstMatch
        XCTAssertTrue(black.waitForExistence(timeout: 3))
        XCTAssertTrue(black.isHittable)
        XCTAssertLessThanOrEqual(black.frame.maxX, palette.frame.maxX)
        let gridScreenshot = XCTAttachment(screenshot: app.screenshot())
        gridScreenshot.name = "Folder color grid"
        gridScreenshot.lifetime = .keepAlways
        add(gridScreenshot)
        black.tap()
        XCTAssertEqual(customColor.value as? String, "#000000")

        let sliders = palette.buttons.matching(NSPredicate(format: "label IN %@", ["Слайдеры", "Sliders"])).firstMatch
        sliders.tap()
        let hex = palette.textFields.matching(NSPredicate(format: "value == %@", "000000")).firstMatch
        XCTAssertTrue(hex.waitForExistence(timeout: 3))
        XCTAssertTrue(hex.isHittable)
        XCTAssertLessThanOrEqual(hex.frame.maxX, palette.frame.maxX)
        hex.tap()
        hex.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 6) + "3578A0\n")
        XCTAssertEqual(customColor.value as? String, "#3578A0")
        customColor.tap()
        XCTAssertFalse(palette.exists)

        let name = app.textFields["personal-folder-name"]
        name.tap()
        name.typeText("Custom color")
        app.buttons["folder-save"].tap()
        app.buttons["navigation-settings"].tap()
        app.buttons["settings-folders"].tap()
        let savedFolder = app.buttons["settings-edit-category-Custom color"]
        XCTAssertTrue(savedFolder.waitForExistence(timeout: 5))
        if !savedFolder.isHittable { app.swipeUp() }
        savedFolder.tap()
        XCTAssertTrue(customColor.waitForExistence(timeout: 3))
        XCTAssertEqual(customColor.value as? String, "#3578A0")
    }

    func testCreateFolderShowsQRAndAppearsOnHome() {
        openFolderEditor()
        let personalName = app.textFields["personal-folder-name"]
        personalName.tap()
        personalName.typeText("Вместе")
        app.segmentedControls["folder-type"].buttons["Общая"].tap()
        let title = app.textFields["shared-folder-name"]
        XCTAssertEqual(title.value as? String, "Вместе")
        let editor = XCTAttachment(screenshot: app.screenshot())
        editor.name = "FolderTypeSelection"
        editor.lifetime = .keepAlways
        add(editor)
        app.buttons["folder-save"].tap()
        XCTAssertTrue(app.images["shared-invite-qr"].waitForExistence(timeout: 8))
        app.buttons["shared-open-created-folder"].tap()
        let heading = app.staticTexts["classic-folder-title"]
        XCTAssertTrue(heading.waitForExistence(timeout: 5))
        XCTAssertEqual(heading.label, "ВМЕСТЕ")
    }

    func testSwitchingTypePreservesPersonalFolder() {
        openFolderEditor()
        app.segmentedControls["folder-type"].buttons["Общая"].tap()
        app.segmentedControls["folder-type"].buttons["Личная"].tap()
        XCTAssertTrue(app.buttons["folder-color-#5AA9FF"].exists)
        let name = app.textFields["personal-folder-name"]
        name.tap()
        name.typeText("Личная проверка")
        app.buttons["folder-save"].tap()
        let folder = app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH 'classic-folder-' AND label BEGINSWITH %@", "Личная проверка")).firstMatch
        XCTAssertTrue(folder.waitForExistence(timeout: 5))
    }

    func testJoinValidationAndScannerFallback() {
        openFolderEditor()
        app.segmentedControls["folder-type"].buttons["Общая"].tap()
        app.buttons["classic-join-shared-folder"].tap()
        let field = app.descendants(matching: .any).matching(identifier: "shared-invite-code").firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["shared-confirm-join"].isEnabled)
        app.buttons["shared-scan-qr"].tap()
        XCTAssertTrue(app.buttons["Ввести код вручную"].waitForExistence(timeout: 5))
        app.buttons["Ввести код вручную"].tap()
        field.tap()
        field.typeText("bad-code")
        XCTAssertFalse(app.buttons["shared-confirm-join"].isEnabled)
        field.typeText(
            String(repeating: XCUIKeyboardKey.delete.rawValue, count: 8) + "0123456789abcdef0123456789abcdef")
        app.buttons["shared-confirm-join"].tap()
        let heading = app.staticTexts["classic-folder-title"]
        XCTAssertTrue(heading.waitForExistence(timeout: 5))
        XCTAssertEqual(heading.label, "ОБЩИЙ ПРОЕКТ")
    }

    func testInvitationLinkOpensJoinAndFolder() {
        let code = "0123456789abcdef0123456789abcdef"
        app.open(URL(string: "com.monotask.ios://join?code=\(code)")!)
        let field = app.descendants(matching: .any).matching(identifier: "shared-invite-code").firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        XCTAssertEqual(field.value as? String, code)
        app.buttons["shared-confirm-join"].tap()
        XCTAssertTrue(app.buttons["shared-manage-members"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Общий проект"].exists)
    }
}
