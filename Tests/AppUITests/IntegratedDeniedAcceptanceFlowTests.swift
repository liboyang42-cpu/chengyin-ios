import XCTest

/// Normal root, sheets, navigation stacks and coordinators; synthetic transport only.
@MainActor final class IntegratedDeniedAcceptanceFlowTests: XCTestCase {
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
    private var runningApp: XCUIApplication?
    override func tearDownWithError() throws {
        attachFailureScreenshot(self, app: runningApp)
        if let app = runningApp, (testRun?.totalFailureCount ?? 0) > 0 {
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "Integrated acceptance failure accessibility hierarchy"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
        }
        runningApp?.terminate(); runningApp = nil
    }
    private let home = ["home.banners", "home.categories", "home.recommended", "home.nearby", "home.upcoming", "home.stream"]
    override func setUp() { super.setUp(); continueAfterFailure = false }
    private func launch(_ mode: String = "ready") -> XCUIApplication {
        let app = XCUIApplication(); runningApp = app
        app.launchArguments = ["--uitesting-integrated-native", mode, "--uitesting-reset-language", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        if mode == "denied" { app.launchArguments.append("--uitesting-integrated-login-diagnostics") }
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
    private func orderRowFits(_ row: CGRect, viewport: CGRect) -> Bool {
        !row.isEmpty && !viewport.isEmpty && !viewport.isNull && viewport.contains(row)
    }
    private func assertOrderRowMayMeetButNotCrossNavigationBoundary() {
        let viewport = CGRect(x: 0, y: 174, width: 420, height: 655)
        XCTAssertTrue(orderRowFits(CGRect(x: 20, y: 174, width: 380, height: 116.7), viewport: viewport))
        XCTAssertFalse(orderRowFits(CGRect(x: 20, y: 170, width: 380, height: 116.7), viewport: viewport))
        XCTAssertFalse(orderRowFits(CGRect(x: 20, y: 800, width: 380, height: 116.7), viewport: viewport))
        XCTAssertFalse(orderRowFits(.zero, viewport: viewport))
    }
    private func tap(_ id: String, _ app: XCUIApplication) {
        if id == "templateAuthor.shelf.loadMore" {
            tapOwnedShelfNextPage(app); return
        }
        if id == "roam.display.toggle", !app.navigationBars.buttons[id].exists {
            tapRoamOverflowToggle(app); return
        }
        let barButton = app.navigationBars.buttons[id]
        if barButton.exists { XCTAssertTrue(barButton.isHittable); barButton.tap(); return }
        let element = app.buttons[id]
        if id == "profile.order.41" {
            // Actual AX places this first List row exactly at the navigation bar's
            // lower edge. A synthetic four-point inset rejects it forever.
            let navigation = app.navigationBars["My orders"]
            let tabs = app.tabBars.firstMatch
            XCTAssertTrue(navigation.exists); XCTAssertTrue(tabs.exists)
            let viewport = CGRect(x: app.frame.minX, y: navigation.frame.maxY,
                                  width: app.frame.width, height: tabs.frame.minY - navigation.frame.maxY)
            XCTAssertTrue(element.exists); XCTAssertTrue(element.isEnabled)
            XCTAssertTrue(orderRowFits(element.frame, viewport: viewport), app.debugDescription)
            XCTAssertTrue(element.isHittable); element.tap(); return
        }
        XCTAssertTrue(revealFixtureElement(element, in: app)); element.tap()
    }


    private func tapRoamOverflowToggle(_ app: XCUIApplication) {
        let navigation = app.navigationBars["Explore the map"]
        let city = navigation.buttons["Official city"]
        guard navigation.exists, city.exists, city.isEnabled, city.isHittable else {
            XCTFail("Expected the visible Explore city toolbar anchor. " + app.debugDescription); return
        }
        // Actual run101 PNG shows the system overflow leaf to the right of City.
        // Do not guess its localized title or tap a hidden destination directly.
        let leaves = navigation.buttons.allElementsBoundByIndex.filter {
            let frame = $0.frame
            return $0.descendants(matching: .button).count == 0 && !frame.isEmpty
                && frame.minX >= city.frame.maxX && navigation.frame.contains(frame)
                && app.frame.contains(frame) && $0.isEnabled && $0.isHittable
        }
        guard leaves.count == 1, let overflow = leaves.first else {
            XCTFail("Expected one trailing native overflow action. " + app.debugDescription); return
        }
        overflow.tap()
        // Both run108 ready/denied AX trees expose this visible menu label, but
        // the system overflow clone does not retain roam.display.toggle.
        // launch() fixes en/en_US, and both journeys select list before any area.
        let exact = app.buttons.matching(NSPredicate(format: "label == %@", "Show list only"))
        guard exact.firstMatch.waitForExistence(timeout: 5), exact.count == 1 else {
            XCTFail("Native overflow must expose exactly one Show list only action. " + app.debugDescription); return
        }
        let toggle = exact.element(boundBy: 0)
        guard toggle.isEnabled, toggle.isHittable, !toggle.frame.isEmpty, app.frame.contains(toggle.frame) else {
            XCTFail("The exact native Show list only action is not visible and enabled. " + app.debugDescription); return
        }
        toggle.tap()
    }
    private func tapOwnedShelfNextPage(_ app: XCUIApplication) {
        let target = app.buttons["templateAuthor.shelf.loadMore"]
        let navigation = app.navigationBars["My play templates"]
        let tabs = app.tabBars.firstMatch
        XCTAssertTrue(navigation.exists); XCTAssertTrue(tabs.exists)
        let containers = app.collectionViews.allElementsBoundByIndex
            + app.tables.allElementsBoundByIndex + app.scrollViews.allElementsBoundByIndex
        let candidates = containers.filter {
            !$0.frame.isEmpty && $0.descendants(matching: .button).matching(
                NSPredicate(format: "identifier BEGINSWITH %@", "memberTemplate.mine.")).count > 0
        }
        guard let container = candidates.max(by: { $0.frame.height < $1.frame.height }) else {
            XCTFail("Owned shelf has no native scrolling container. " + app.debugDescription); return
        }
        func viewport() -> CGRect {
            container.frame.intersection(CGRect(x: app.frame.minX + 4, y: navigation.frame.maxY + 4,
                width: app.frame.width - 8, height: max(0, tabs.frame.minY - navigation.frame.maxY - 8)))
        }
        func visibleRows(_ bounds: CGRect) -> [String] {
            container.descendants(matching: .staticText).allElementsBoundByIndex.compactMap {
                let frame = $0.frame
                guard !frame.isEmpty, bounds.intersects(frame) else { return nil }
                return $0.label + ":" + String(Int(frame.minY.rounded()))
            }
        }
        // Ten full cards per actual page, at most three short gestures per card.
        // One stagnant center gesture is not evidence that the page has ended.
        var stagnantTraversals = 0
        var useGutter = false
        for _ in 0..<30 {
            let bounds = viewport()
            guard !bounds.isNull, bounds.height > 80 else { break }
            if target.exists && bounds.contains(target.frame) && target.isEnabled && target.isHittable {
                target.tap(); return
            }
            if stagnantTraversals >= 2 {
                let nextCardIsBelowViewport = container.buttons.allElementsBoundByIndex.contains {
                    $0.identifier.hasPrefix("memberTemplate.mine.") && !$0.frame.isEmpty && $0.frame.maxY > bounds.maxY
                }
                XCTFail((nextCardIsBelowViewport
                    ? "Shelf traversal stalled while another template remained below the viewport. "
                    : "Shelf traversal stalled twice without exposing an actionable Load more. ") + app.debugDescription)
                return
            }
            let before = visibleRows(bounds)
            // Run117 stopped at card9 after a center drag. The native List gutter
            // remains inside the viewport and clear of its inset card controls.
            let dragX = useGutter ? bounds.minX + min(8, bounds.width * 0.1) : bounds.midX
            let start = container.coordinate(withNormalizedOffset: .zero).withOffset(
                CGVector(dx: dragX - container.frame.minX, dy: bounds.minY + bounds.height * 0.8 - container.frame.minY))
            let end = container.coordinate(withNormalizedOffset: .zero).withOffset(
                CGVector(dx: dragX - container.frame.minX, dy: bounds.minY + bounds.height * 0.25 - container.frame.minY))
            start.press(forDuration: 0.05, thenDragTo: end)
            if !before.isEmpty && before == visibleRows(viewport()) {
                stagnantTraversals += 1
                useGutter = true
            } else {
                stagnantTraversals = 0
            }
        }
        XCTFail("Owned shelf Load more was not visible and enabled after bounded page traversal. " + app.debugDescription)
    }
    private func closeFrontSheet(_ app: XCUIApplication) throws {
        let close = try XCTUnwrap(app.navigationBars.buttons.matching(identifier: "Close").allElementsBoundByIndex.last(where: { $0.isHittable }))
        close.tap()
    }
    private func phoneSheet(_ app: XCUIApplication) {
        tap("welcome.player", app); tap("auth.otherChannels", app)
        XCTAssertTrue(app.textFields["auth.channels.phone"].waitForExistence(timeout: 5),
                      "Login presentation: first=" + String(app.navigationBars["Sign in"].exists) +
                      ";channels=" + String(app.navigationBars["More ways to sign in"].exists) +
                      ";otherButton=" + String(app.buttons["auth.otherChannels"].exists))
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
        assertOrderRowMayMeetButNotCrossNavigationBoundary()
        tab("Account", app); tap("profile.open.orders", app)
        XCTAssertTrue(app.staticTexts["Owner \(owner) list snapshot"].waitForExistence(timeout: 5))
        tap("profile.order.41", app)
        XCTAssertTrue(app.staticTexts["Activity or route, Owner \(owner) fresh detail"].waitForExistence(timeout: 5))
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

    func testNormalRootIMHistoryDefaultNilNeverDispatches() throws {
        let app = launch("denied"); signIn(app); tab("Account", app); tap("Messages", app)
        XCTAssertTrue(app.staticTexts["messaging.list.unconfigured"].waitForExistence(timeout: 5))
        XCTAssertTrue(try evidence(app).ledger.filter { $0.route.hasPrefix("history.") }.isEmpty)
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
