import XCTest

/// Native smoke tests use a Development-only startup path, a fresh preferences
/// domain/data directory, and a named synthetic pasteboard for every test.
@MainActor final class UtilitySmokeTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        #if SAYSTONE_DEVELOPMENT
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-test-session", UUID().uuidString]
        app.launch()
        app.activate()
        XCTAssertEqual(app.state, .runningForeground)
        XCTAssertTrue(element("utilities.workspace").waitForExistence(timeout: 10))
        #else
        throw XCTSkip("Interactive smoke tests require the isolated SayStone Development configuration.")
        #endif
    }

    override func tearDownWithError() throws {
        app?.terminate()
        app = nil
    }

    func testSearchTransformAndSyntheticPasteDenial() async {
        await replaceText(in: app.textFields["utilities.palette.search"], with: "Transform text")
        XCTAssertTrue(element("utilities.action.transformText").waitForExistence(timeout: 3))
        XCTAssertFalse(element("utilities.action.launchApp").exists)
        await replaceText(in: app.textViews["utilities.palette.text"], with: "   Authored trim fixture 123   ")
        app.buttons["utilities.palette.run"].click()
        await assertText("Authored trim fixture 123", of: element("utilities.palette.result"))

        await replaceText(in: app.textFields["utilities.palette.search"], with: "Paste text")
        await replaceText(in: app.textViews["utilities.palette.text"], with: "Authored text that must stay inside the fixture")
        app.buttons["utilities.palette.run"].click()
        await assertText("External actions are disabled in synthetic UI tests.", of: element("utilities.palette.result"))
    }

    func testSnippetSaveEditAndHistoryOffByDefault() async {
        let originalBody = "Authored reusable text 456: \"quoted\" -- dash  "
        let editedBody = "Authored edited text 789: \"literal\" -- dash  "
        app.buttons["utilities.tab.clipboard"].click()
        app.buttons["clipboard.newSnippet"].click()
        await replaceText(in: app.textFields["clipboard.editorTitle"], with: "Authored snippet title")
        await replaceText(in: app.textViews["clipboard.editorText"], with: originalBody)
        app.buttons["clipboard.editorSave"].click()
        XCTAssertTrue(staticText("Authored snippet title").waitForExistence(timeout: 3))
        element(label: "Options for Authored snippet title").click()
        clickSnippetEditMenuItem()
        await assertValue(originalBody, of: app.textViews["clipboard.editorText"])
        await replaceText(in: app.textFields["clipboard.editorTitle"], with: "Edited authored snippet")
        await replaceText(in: app.textViews["clipboard.editorText"], with: editedBody)
        app.buttons["clipboard.editorSave"].click()
        XCTAssertTrue(staticText("Edited authored snippet").waitForExistence(timeout: 3))
        XCTAssertFalse(staticText("Authored snippet title").exists)

        // Reopen the same isolated fixture session to check disk persistence,
        // including literal quotes, two dashes and both trailing spaces.
        app.terminate()
        app.launch()
        XCTAssertTrue(element("utilities.workspace").waitForExistence(timeout: 10))
        app.buttons["utilities.tab.clipboard"].click()
        XCTAssertTrue(staticText("Edited authored snippet").waitForExistence(timeout: 3))
        element(label: "Options for Edited authored snippet").click()
        clickSnippetEditMenuItem()
        await assertValue(editedBody, of: app.textViews["clipboard.editorText"])
        app.buttons["Cancel"].firstMatch.click()

        let section = element("clipboard.section")
        section.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "History")).firstMatch.click()
        let historyToggle = element("clipboard.historyEnabled")
        XCTAssertTrue(historyToggle.waitForExistence(timeout: 3))
        assertToggle(historyToggle, isOn: false)
        XCTAssertTrue(staticText("History collection is off.").exists)
        XCTAssertFalse(app.buttons["clipboard.clearHistory"].isEnabled)
    }

    func testWorkflowTransformCopyAndPersistence() async {
        app.buttons["utilities.tab.workflows"].click()
        app.buttons["utilities.workflows.add"].click()
        await replaceText(in: app.textFields["utilities.workflows.name"], with: "Authored workflow fixture")
        let afterDictation = element("utilities.workflows.afterDictation")
        XCTAssertTrue(afterDictation.waitForExistence(timeout: 3))
        assertToggle(afterDictation, isOn: false)
        afterDictation.click()
        assertToggle(afterDictation, isOn: true)
        let actions = app.popUpButtons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND identifier ENDSWITH %@",
            "utilities.workflows.step.",
            ".action"
        ))
        XCTAssertEqual(actions.count, 1)
        selectMenuItem("Transform text", in: actions.element(boundBy: 0))
        reveal(app.buttons["utilities.workflows.addStep"])
        app.buttons["utilities.workflows.addStep"].click()
        XCTAssertEqual(actions.count, 2)
        reveal(actions.element(boundBy: 1))
        selectMenuItem("Copy text", in: actions.element(boundBy: 1))
        let input = app.textViews["utilities.workflows.input"]
        reveal(input)
        await replaceText(in: input, with: "   Authored workflow output 246   ")
        reveal(app.buttons["utilities.workflows.run"])
        app.buttons["utilities.workflows.run"].click()
        await assertText("Completed", of: element("utilities.workflows.status"))
        XCTAssertTrue(element("utilities.workflows.output").waitForExistence(timeout: 3))
        await assertText("Authored workflow output 246", of: element("utilities.workflows.output"))

        // Preserve the same fixture session to verify the saved definition is read.
        scrollEditorToTop()
        app.buttons["utilities.workflows.save"].click()
        app.terminate()
        app.launch()
        XCTAssertTrue(element("utilities.workspace").waitForExistence(timeout: 10))
        app.buttons["utilities.tab.workflows"].click()
        XCTAssertTrue(staticText("Authored workflow fixture").waitForExistence(timeout: 3))
        assertToggle(element("utilities.workflows.afterDictation"), isOn: true)
        XCTAssertEqual(actions.count, 2)
    }

    func testShortcutValidationAndConflict() async {
        app.activate()
        app.buttons["utilities.tab.shortcuts"].click()
        let record = app.buttons["utilities.shortcuts.record"]
        let save = app.buttons["utilities.shortcuts.save"]
        XCTAssertFalse(save.isEnabled)
        record.click()
        app.typeKey("j", modifierFlags: [])
        await assertText("Choose a key with Command, Control or Option.", of: element("utilities.shortcuts.status"))
        XCTAssertFalse(save.isEnabled)
        app.typeKey("j", modifierFlags: [.control, .command])
        await assertText("Ready to save.", of: element("utilities.shortcuts.status"))
        XCTAssertTrue(save.isEnabled)
        save.click()
        await assertText("Shortcut saved.", of: element("utilities.shortcuts.status"))
        let rows = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "utilities.shortcuts.binding."))
        XCTAssertEqual(rows.count, 1)
        record.click()
        app.typeKey("j", modifierFlags: [.control, .command])
        save.click()
        await assertText("This shortcut conflicts with another SayStone shortcut.", of: element("utilities.shortcuts.status"))
        XCTAssertEqual(rows.count, 1)
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func element(label: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    private func staticText(_ text: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label == %@ OR value == %@", text, text)).firstMatch
    }

    private func clickSnippetEditMenuItem() {
        let edits = app.menuItems.matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND identifier ENDSWITH %@",
            "clipboard.snippet.",
            ".edit"
        ))
        XCTAssertTrue(edits.firstMatch.waitForExistence(timeout: 3))
        XCTAssertEqual(edits.count, 1, "Only the selected snippet's Edit menu item should be visible")
        edits.firstMatch.click()
    }

    private func replaceText(in element: XCUIElement, with text: String) async {
        app.activate()
        XCTAssertEqual(app.state, .runningForeground)
        XCTAssertTrue(element.waitForExistence(timeout: 3))
        // SwiftUI TextEditor exposes a native TextView without a stable scroll
        // identity in this SDK. Click its locator-derived visible point directly
        // rather than invoking XCTest's failing implicit scroll-to-visible path.
        if element.elementType == .textView {
            element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        } else {
            element.click()
        }
        guard element.waitForExistence(timeout: 3) else {
            XCTFail("The authored input field disappeared after focusing it.")
            return
        }
        app.typeKey("a", modifierFlags: .command)
        app.typeText(text)
        await assertValue(text, of: element)
    }

    private func assertValue(_ text: String, of element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) async {
        XCTAssertTrue(element.waitForExistence(timeout: 3), file: file, line: line)
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", text), object: element)
        let result = await XCTWaiter.fulfillment(of: [expectation], timeout: 5)
        XCTAssertEqual(result, .completed, "Expected authored value in \(element.identifier); value=\(String(describing: element.value))", file: file, line: line)
    }

    private func assertText(_ text: String, of element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) async {
        XCTAssertTrue(element.waitForExistence(timeout: 3), file: file, line: line)
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@ OR value == %@", text, text), object: element)
        let result = await XCTWaiter.fulfillment(of: [expectation], timeout: 5)
        XCTAssertEqual(result, .completed, "Expected \(text); label=\(element.label), value=\(String(describing: element.value))", file: file, line: line)
    }

    private func assertToggle(_ element: XCUIElement, isOn: Bool, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 3), file: file, line: line)
        if let value = element.value as? String {
            XCTAssertEqual(value, isOn ? "1" : "0", file: file, line: line)
        } else if let value = element.value as? NSNumber {
            XCTAssertEqual(value.boolValue, isOn, file: file, line: line)
        } else {
            XCTFail("Toggle did not expose an on/off value", file: file, line: line)
        }
    }

    private func selectMenuItem(_ title: String, in picker: XCUIElement) {
        XCTAssertTrue(picker.waitForExistence(timeout: 3))
        picker.click()
        let item = app.menuItems[title].firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 3))
        item.click()
    }

    private func reveal(_ element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 3))
        let editor = app.scrollViews.containing(.textField, identifier: "utilities.workflows.name").firstMatch
        for _ in 0..<8 {
            if element.isHittable { return }
            editor.scroll(byDeltaX: 0, deltaY: -220)
        }
        XCTAssertTrue(element.isHittable)
    }

    private func scrollEditorToTop() {
        let editor = app.scrollViews.containing(.textField, identifier: "utilities.workflows.name").firstMatch
        for _ in 0..<8 {
            if app.buttons["utilities.workflows.save"].isHittable { return }
            editor.scroll(byDeltaX: 0, deltaY: 220)
        }
        XCTAssertTrue(app.buttons["utilities.workflows.save"].isHittable)
    }
}
