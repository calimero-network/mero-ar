import XCTest

/// UI tests. The first runs anywhere; the rest drive a real node and skip
/// unless one is given:
///
///     TEST_RUNNER_MEROAR_TEST_NODE=http://localhost:4301 \
///     TEST_RUNNER_MEROAR_TEST_USER=admin TEST_RUNNER_MEROAR_TEST_PASS=calimero1234 \
///       xcodebuild test … -only-testing:MeroARUITests
///
/// `TEST_RUNNER_MEROAR_PAUSE=1` holds each screen for a moment, which is how
/// `scripts/record-demo.sh` films them.
final class MeroARUITests: XCTestCase {
    private let env = ProcessInfo.processInfo.environment

    override func setUp() {
        continueAfterFailure = false
    }

    func testSignInOffersCloudAndAManualNodeURL() {
        let app = XCUIApplication()
        app.launch()
        expect(app.staticTexts["Mero AR"], 8)
        expect(app.buttons["cloudSignInButton"], 5)
        XCTAssertFalse(app.textFields["nodeURLField"].exists, "the node form is behind the link")
        pause()
        app.buttons["manualNode"].tap()
        expect(app.textFields["nodeURLField"], 5)
        XCTAssertTrue(app.secureTextFields["nodePassField"].exists)
        XCTAssertTrue(app.buttons["nodeConnectButton"].exists)
        pause()
        app.buttons["useCloud"].tap()
        expect(app.buttons["cloudSignInButton"], 5)
    }

    /// Node sign-in → new room → place objects → a note → an invite → leave.
    func testBuildARoomOnANode() throws {
        guard let node = env["MEROAR_TEST_NODE"], let user = env["MEROAR_TEST_USER"], let pass = env["MEROAR_TEST_PASS"]
        else { throw XCTSkip("set MEROAR_TEST_NODE / _USER / _PASS to run against a node") }
        let app = XCUIApplication()
        app.launchArguments += ["-meroar.nodeURL", node, "-meroar.nodeUser", user, "-meroar.username", "Maya"]
        app.launchEnvironment["MEROAR_PREVIEW"] = "1"
        app.launch()

        expect(app.buttons["manualNode"], 8)
        pause(2)
        app.buttons["manualNode"].tap()
        let password = app.secureTextFields["nodePassField"]
        expect(password, 5)
        password.tap()
        password.typeText(pass)
        pause(1)
        let create = app.buttons["createRoomButton"]
        signIn(app, password: password, until: create)
        dismissSavePassword(app)
        pause(2)
        let name = app.textFields["roomNameInput"]
        tap(create, until: name)
        name.tap()
        name.typeText((env["MEROAR_TEST_ROOM"] ?? "Living room") + "\n")

        let add = app.buttons["addObjectButton"]
        expect(add, 90, "room did not open")
        XCTAssertTrue(app.staticTexts["3D preview · live AR needs an ARKit iPhone or iPad"].exists || app.otherElements["previewBanner"].exists)
        pause(2)
        for kind in ["cube", "sphere", "marker"] {
            let place = app.buttons["place-\(kind)"]
            tap(add, until: place)
            pause(1)
            place.tap()
            pause(1.5)
        }
        XCTAssertTrue(
            app.staticTexts.containing(NSPredicate(format: "label CONTAINS '3 objects'")).firstMatch
                .waitForExistence(timeout: 20)
                || app.otherElements["roomStatus"].label.contains("3 objects"),
            "objects did not land")

        let comment = app.textFields["commentInput"]
        tap(app.buttons["commentsButton"], until: comment)
        comment.tap()
        comment.typeText("Sofa goes here\n")
        expect(app.staticTexts["Sofa goes here"], 20, "note not posted")
        pause(2)
        closeSheet(app)

        let invite = app.buttons["createInviteButton"]
        tap(app.buttons["membersButton"], until: invite)
        pause(1)
        invite.tap()
        expect(app.buttons["shareInviteButton"], 30, "invite not minted")
        pause(3)
        closeSheet(app)
        pause(4)

        app.buttons["leaveButton"].tap()
        expect(app.buttons["createRoomButton"], 10)
        pause(3)
    }

    // MARK: - Recordings (scripts/record-demo.sh)

    private func recordingApp(room: String? = nil) throws -> XCUIApplication {
        guard env["MEROAR_RECORD"] != nil, let node = env["MEROAR_TEST_NODE"], let user = env["MEROAR_TEST_USER"],
            let pass = env["MEROAR_TEST_PASS"]
        else { throw XCTSkip("recording scenes run from scripts/record-demo.sh") }
        let app = XCUIApplication()
        app.launchArguments += ["-meroar.nodeURL", node, "-meroar.nodeUser", user, "-meroar.username", "Maya"]
        app.launchEnvironment["MEROAR_PREVIEW"] = "1"
        if let room {
            app.launchEnvironment["MEROAR_NODE"] = node
            app.launchEnvironment["MEROAR_NODE_USER"] = user
            app.launchEnvironment["MEROAR_NODE_PASS"] = pass
            app.launchEnvironment["MEROAR_ROOM"] = room
        }
        app.launch()
        return app
    }

    /// Scene 1: sign in to a node and create a room.
    func testRecordSignIn() throws {
        let app = try recordingApp()
        expect(app.buttons["manualNode"], 10)
        Thread.sleep(forTimeInterval: 2.5)
        app.buttons["manualNode"].tap()
        let password = app.secureTextFields["nodePassField"]
        expect(password, 5)
        Thread.sleep(forTimeInterval: 1)
        password.tap()
        password.typeText(env["MEROAR_TEST_PASS"] ?? "")
        Thread.sleep(forTimeInterval: 0.8)
        let create = app.buttons["createRoomButton"]
        signIn(app, password: password, until: create)
        dismissSavePassword(app)
        Thread.sleep(forTimeInterval: 2)
        let name = app.textFields["roomNameInput"]
        tap(create, until: name)
        name.tap()
        name.typeText(env["MEROAR_TEST_ROOM"] ?? "Studio")
        Thread.sleep(forTimeInterval: 0.8)
        name.typeText("\n")
        expect(app.buttons["addObjectButton"], 90)
        Thread.sleep(forTimeInterval: 3)
    }

    /// Scene 2: build in the room while a second person joins from their node.
    func testRecordRoom() throws {
        let app = try recordingApp(room: env["MEROAR_ROOM"])
        let add = app.buttons["addObjectButton"]
        expect(add, 60)
        Thread.sleep(forTimeInterval: 2)
        for kind in ["cube", "sphere"] {
            let place = app.buttons["place-\(kind)"]
            tap(add, until: place)
            Thread.sleep(forTimeInterval: 1)
            place.tap()
            Thread.sleep(forTimeInterval: 2)
        }
        let label = app.textFields["labelInput"]
        tap(add, until: label)
        label.tap()
        label.typeText("Reading corner\n")
        Thread.sleep(forTimeInterval: 6)
        let comment = app.textFields["commentInput"]
        tap(app.buttons["commentsButton"], until: comment)
        comment.tap()
        comment.typeText("Plant goes by the window\n")
        Thread.sleep(forTimeInterval: 2.5)
        closeSheet(app)
        Thread.sleep(forTimeInterval: 2)
        if let tapAt = env["MEROAR_TAP_OBJECT"]?.split(separator: ",").compactMap({ Double($0) }), tapAt.count == 2 {
            app.coordinate(withNormalizedOffset: CGVector(dx: tapAt[0], dy: tapAt[1])).tap()
            Thread.sleep(forTimeInterval: 1.5)
            for id in ["rotate", "grow", "nudge-right"] where app.buttons[id].exists {
                app.buttons[id].tap()
                Thread.sleep(forTimeInterval: 1)
            }
            Thread.sleep(forTimeInterval: 2)
            if app.buttons["closeInspectorButton"].exists { app.buttons["closeInspectorButton"].tap() }
        }
        Thread.sleep(forTimeInterval: 4)
    }

    /// Scene 3: invite someone.
    func testRecordInvite() throws {
        let app = try recordingApp(room: env["MEROAR_ROOM"])
        let invite = app.buttons["createInviteButton"]
        expect(app.buttons["addObjectButton"], 60)
        Thread.sleep(forTimeInterval: 2)
        tap(app.buttons["membersButton"], until: invite)
        Thread.sleep(forTimeInterval: 2)
        invite.tap()
        expect(app.buttons["shareInviteButton"], 30)
        Thread.sleep(forTimeInterval: 4)
        closeSheet(app)
        Thread.sleep(forTimeInterval: 2)
    }

    /// Submit the node form from the keyboard (Return runs the same connect as
    /// the button, which a tap can miss while the keyboard is up), then the
    /// button as a fallback.
    private func signIn(_ app: XCUIApplication, password: XCUIElement, until lobby: XCUIElement) {
        password.typeText("\n")
        if lobby.waitForExistence(timeout: 15) { return }
        let connect = app.buttons["nodeConnectButton"]
        if connect.exists { connect.tap() }
        expect(lobby, 20, "did not reach the lobby")
    }

    private func closeSheet(_ app: XCUIApplication) {
        let close = app.buttons["closeSheetButton"].firstMatch
        if close.waitForExistence(timeout: 3) {
            close.tap()
            _ = close.waitForNonExistence(timeout: 5)
        }
    }

    /// iOS offers to save the node password after sign-in; that sheet sits
    /// over the app and swallows the next tap.
    private func dismissSavePassword(_ app: XCUIApplication) {
        let notNow = app.buttons["Not Now"]
        if notNow.waitForExistence(timeout: 3) {
            notNow.tap()
            _ = notNow.waitForNonExistence(timeout: 5)
        }
    }

    /// Taps `button` until `target` appears (a sheet can swallow a tap that
    /// lands while another is still animating away).
    private func tap(_ button: XCUIElement, until target: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        for _ in 0..<3 {
            if button.waitForExistence(timeout: 5) { button.tap() }
            if target.waitForExistence(timeout: 4) { return }
        }
        expect(target, 1, "tapping \(button) never showed it", file: file, line: line)
    }

    /// Waits for `element`; on a miss, prints the screen's element tree so the
    /// log says what was there instead.
    private func expect(
        _ element: XCUIElement, _ timeout: TimeInterval, _ message: String = "", file: StaticString = #filePath,
        line: UInt = #line
    ) {
        if element.waitForExistence(timeout: timeout) { return }
        print("UI-TREE:\n\(XCUIApplication().debugDescription)")
        XCTFail("missing \(element): \(message)", file: file, line: line)
    }

    /// Holds the screen when `MEROAR_PAUSE` is set, for recordings.
    private func pause(_ seconds: Double = 1.5) {
        if env["MEROAR_PAUSE"] != nil { Thread.sleep(forTimeInterval: seconds) }
    }
}
