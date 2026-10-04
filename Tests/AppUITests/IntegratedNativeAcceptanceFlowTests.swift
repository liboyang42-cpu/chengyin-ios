import XCTest

/// Normal root, sheets, navigation stacks and coordinators; synthetic transport only.
@MainActor final class IntegratedNativeAcceptanceFlowTests: XCTestCase {
    private struct Entry: Decodable {
        let route: String
        let method: String
        let url: String
        let fields: [String: String]
        let accountID: Int?
        let role: String?
        let epoch: UInt64
        let namespace: String
        let token: String?
    }
    private struct Evidence: Decodable {
        let ledger: [Entry]
        let violations: [String]
        let accountID: Int?
        let role: String?
        let epoch: UInt64
        let tokenStored: Bool
        let manualArea: Bool
    }
    private let home = ["home.banners", "home.categories", "home.recommended", "home.nearby", "home.upcoming", "home.stream"]
    override func setUp() { super.setUp(); continueAfterFailure = false }
    private func launch(_ mode: String = "ready") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting-integrated-native", mode, "--uitesting-reset-language", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch(); return app
    }
    private func availableEvidence(_ app: XCUIApplication) -> Evidence? {
        let element = app.staticTexts["integratedAcceptance.evidence"]
        guard element.exists, let text = element.value as? String else { return nil }
        return try? JSONDecoder().decode(Evidence.self, from: Data(text.utf8))
    }
    private func evidence(_ app: XCUIApplication) throws -> Evidence {
        XCTAssertTrue(app.staticTexts["integratedAcceptance.evidence"].waitForExistence(timeout: 5))
        let value = try XCTUnwrap(availableEvidence(app))
        XCTAssertTrue(value.violations.isEmpty, value.violations.joined(separator: ", "))
        return value
    }
    private func wait(_ app: XCUIApplication, _ condition: @escaping (Evidence) -> Bool) {
        // Polling may encounter an animated or modal-covered root; do not assert inside it.
        let predicate = NSPredicate { _, _ in self.availableEvidence(app).map(condition) == true }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: app)], timeout: 8), .completed)
        if let value = availableEvidence(app) {
            XCTAssertTrue(value.violations.isEmpty, value.violations.joined(separator: ", "))
        }
    }
    private func tap(_ id: String, _ app: XCUIApplication) {
        let barButton = app.navigationBars.buttons[id]
        if barButton.exists { XCTAssertTrue(barButton.isHittable); barButton.tap(); return }
        let element = app.buttons[id]
        XCTAssertTrue(revealFixtureElement(element, in: app)); element.tap()
    }
    private func closeFrontSheet(_ app: XCUIApplication) throws {
        let close = try XCTUnwrap(app.navigationBars.buttons.matching(identifier: "Close").allElementsBoundByIndex.last(where: { $0.isHittable }))
        close.tap()
    }
    private func phoneSheet(_ app: XCUIApplication) {
        tap("welcome.player", app); tap("auth.otherChannels", app)
        XCTAssertTrue(app.textFields["auth.channels.phone"].waitForExistence(timeout: 5))
    }
    private func signIn(_ app: XCUIApplication, owner: Int = 7, requestCode: Bool = true) {
        phoneSheet(app)
        app.textFields["auth.channels.phone"].tap()
        app.textFields["auth.channels.phone"].typeText(owner == 7 ? "10000000000" : "10000000001")
        if requestCode {
            tap("auth.channels.sendCode", app)
            XCTAssertTrue(app.staticTexts["Code sent. Check your messages."].waitForExistence(timeout: 5))
            XCTAssertFalse(app.buttons["auth.channels.sendCode"].isEnabled)
        }
        app.textFields["auth.channels.code"].tap(); app.textFields["auth.channels.code"].typeText("123456")
        tap("auth.channels.phoneSignIn", app)
        wait(app) { $0.accountID == owner && $0.tokenStored }
    }
    private func tab(_ title: String, _ app: XCUIApplication) {
        let button = app.tabBars.buttons[title]; XCTAssertTrue(button.waitForExistence(timeout: 5)); button.tap()
    }
    private func chooseManualArea(_ app: XCUIApplication) {
        tap("roam.chooseArea", app)
        for (field, value) in [("latitude", "31.2"), ("longitude", "121.5"), ("name", "Synthetic manual area")] {
            let input = app.textFields["roam.area.\(field).input"]
            XCTAssertTrue(input.waitForExistence(timeout: 5)); input.tap(); input.typeText(value)
        }
        tap("roam.area.select", app)
    }
    private func orders(_ app: XCUIApplication, owner: Int) {
        tab("Account", app); tap("profile.open.orders", app)
        XCTAssertTrue(app.staticTexts["Owner \(owner) list snapshot"].waitForExistence(timeout: 5))
        tap("profile.order.41", app)
        XCTAssertTrue(app.staticTexts["Owner \(owner) fresh detail"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Owner \(owner) list snapshot"].exists)
        XCTAssertFalse(app.buttons["profile.order.lifecycle"].exists)
    }
    private func assertIdentity(_ entries: [Entry], owner: Int, epoch: UInt64) {
        for entry in entries {
            XCTAssertEqual(entry.accountID, owner); XCTAssertEqual(entry.role, "player")
            XCTAssertEqual(entry.epoch, epoch); XCTAssertEqual(entry.token, "synthetic-\(owner)")
            let components = ["test.questify.integrated-acceptance", "CN", "https://native-acceptance.example/native", "synthetic"]
            let identity = components.map { "\($0.utf8.count):\($0)" }.joined()
            XCTAssertEqual(entry.namespace, "questify.session.v2." + Data(identity.utf8).base64EncodedString())
            XCTAssertTrue(entry.url.hasPrefix("https://native-acceptance.example/native/api/"))
            XCTAssertEqual(entry.method, entry.route.hasPrefix("play-") || entry.route == "map.places" ? "GET" : "POST")
        }
        XCTAssertEqual(Set(entries.map(\.namespace)).count, 1)
    }
    func testActualPhoneHomeDetailManualMapPlayAndFreshOwnedOrderJourney() throws {
        let app = launch(); XCTAssertEqual(try evidence(app).ledger.count, 0)
        signIn(app)
        wait(app) { $0.ledger.count == 9 }
        let initial = try evidence(app)
        XCTAssertEqual(Array(initial.ledger.prefix(3)).map(\.route), ["sms-send", "phone", "userInfo"])
        XCTAssertNil(initial.ledger[0].token); XCTAssertNil(initial.ledger[0].accountID)
        XCTAssertEqual(initial.ledger[0].fields, ["phone": "10000000000"])
        XCTAssertEqual(initial.ledger.filter { $0.route == "sms-send" }.count, 1)
        XCTAssertNil(initial.ledger[1].token); XCTAssertNil(initial.ledger[1].accountID)
        XCTAssertEqual(initial.ledger[1].fields, ["phone": "10000000000", "code": "123456"])
        XCTAssertEqual(initial.ledger[2].token, "synthetic-7"); XCTAssertNil(initial.ledger[2].accountID)
        XCTAssertEqual(Array(initial.ledger.dropFirst(3)).map(\.route).sorted(), home.sorted())
        tap("homeFeed.nearby.activity.21", app)
        XCTAssertTrue(app.staticTexts["Synthetic activity detail"].waitForExistence(timeout: 5))
        wait(app) { $0.ledger.count == 10 }
        tab("Explore the map", app)
        // Select the normal list presentation before supplying a center.
        // The API ledger is not evidence about all operating-system networking.
        tap("roam.display.toggle", app); chooseManualArea(app)
        XCTAssertTrue(app.staticTexts["Synthetic manual place"].waitForExistence(timeout: 5))
        wait(app) { $0.ledger.count == 11 }
        XCTAssertFalse(app.alerts.firstMatch.exists)
        tab("Home", app)
        XCTAssertTrue(app.staticTexts["Synthetic activity detail"].waitForExistence(timeout: 5))
        tap("activity.openPlay", app)
        XCTAssertTrue(app.staticTexts["Synthetic read-only play"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["play.node.1"].exists); XCTAssertFalse(app.buttons["play.node.2"].exists)
        orders(app, owner: 7)
        let final = try evidence(app)
        XCTAssertEqual(final.ledger.dropFirst(9).map(\.route), ["activity-detail", "map.places", "activity-detail", "play-nodes", "play-route", "orders.list", "orders.detail"])
        assertIdentity(Array(final.ledger.dropFirst(3)), owner: 7, epoch: final.epoch)
        XCTAssertEqual(final.ledger.last?.fields, ["id": "41"])
        XCTAssertEqual(final.ledger[final.ledger.count - 2].fields, ["owner_type": "3"])
        XCTAssertTrue(final.manualArea)
    }
    func testPhoneCancelLogoutAccountSwitchAndColdLaunchDoNotReuseOwnerState() throws {
        let app = launch(); phoneSheet(app)
        app.textFields["auth.channels.phone"].tap(); app.textFields["auth.channels.phone"].typeText("10000000000")
        try closeFrontSheet(app); try closeFrontSheet(app)
        XCTAssertTrue(app.buttons["welcome.player"].waitForExistence(timeout: 5))
        XCTAssertEqual(try evidence(app).ledger.count, 0)
        signIn(app); orders(app, owner: 7)
        let oldEpoch = try evidence(app).epoch
        let detailBack = app.navigationBars["Order details"].buttons.firstMatch
        XCTAssertTrue(detailBack.waitForExistence(timeout: 5)); detailBack.tap()
        XCTAssertTrue(app.buttons["profile.order.41"].waitForExistence(timeout: 5))
        let listBack = app.navigationBars["My orders"].buttons.firstMatch
        XCTAssertTrue(listBack.waitForExistence(timeout: 5)); listBack.tap()
        XCTAssertTrue(app.buttons["profile.open.orders"].waitForExistence(timeout: 5))
        tap("Sign out", app)
        let confirmation = app.sheets["Sign out of this account?"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        tapFixtureSheetAction("Sign out", in: confirmation, app: app)
        XCTAssertTrue(app.buttons["welcome.player"].waitForExistence(timeout: 5))
        wait(app) { $0.ledger.last?.route == "logout" }
        let loggedOut = try evidence(app)
        XCTAssertNil(loggedOut.accountID); XCTAssertFalse(loggedOut.tokenStored); XCTAssertFalse(loggedOut.manualArea)
        XCTAssertGreaterThan(loggedOut.epoch, oldEpoch)
        XCTAssertFalse(app.staticTexts["Owner 7 fresh detail"].exists)
        // The real coordinator retains a 60-second cross-number SMS cooldown.
        // Use the supplied synthetic code for the second owner without resetting it.
        signIn(app, owner: 8, requestCode: false); orders(app, owner: 8)
        let switched = try evidence(app)
        XCTAssertFalse(app.staticTexts["Owner 7 fresh detail"].exists)
        assertIdentity(switched.ledger.filter { $0.accountID == 8 }, owner: 8, epoch: switched.epoch)
        XCTAssertEqual(switched.ledger.filter { $0.accountID == 8 && $0.route.hasPrefix("orders.") }.map(\.route), ["orders.list", "orders.detail"])
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["welcome.player"].waitForExistence(timeout: 5))
        let reset = try evidence(app)
        XCTAssertTrue(reset.ledger.isEmpty); XCTAssertNil(reset.accountID); XCTAssertFalse(reset.tokenStored); XCTAssertFalse(reset.manualArea)
    }
    func testConfiguredAuthenticationDoesNotGrantDetailMapPlayOrOwnedOrders() throws {
        let app = launch("denied"); signIn(app)
        tap("homeFeed.nearby.activity.21", app)
        XCTAssertTrue(app.staticTexts["activity.detail.error"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["activity.openPlay"].exists)
        tab("Explore the map", app); tap("roam.display.toggle", app); chooseManualArea(app)
        XCTAssertTrue(app.descendants(matching: .any)["roam.error"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Synthetic manual place"].exists)
        tab("Account", app); tap("profile.open.orders", app)
        XCTAssertTrue(app.descendants(matching: .any)["profile.orders.unavailable"].firstMatch.waitForExistence(timeout: 5))
        let value = try evidence(app)
        XCTAssertEqual(Array(value.ledger.prefix(3)).map(\.route), ["sms-send", "phone", "userInfo"])
        XCTAssertEqual(value.ledger.dropFirst(3).map(\.route).sorted(), home.sorted())
        XCTAssertEqual(value.accountID, 7); XCTAssertTrue(value.manualArea)
    }
}
