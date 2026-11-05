import XCTest

/// Captures key screens for owner design review. It asserts nothing about behaviour.
final class DesignReviewCaptureTests: XCTestCase {
    private static let screens: [(name: String, arguments: [String])] = [
        ("01-home", ["--uitesting-module", "home-feed"]),
        ("02-home-empty", ["--uitesting-module", "home-feed", "--uitesting-home-feed-scenario", "empty"]),
        ("03-discovery", ["--uitesting-module", "discovery"]),
        ("04-search-map", ["--uitesting-module", "searchMap"]),
        ("05-square", ["--uitesting-module", "square"]),
        ("06-activity-tickets", ["--uitesting-activity-fixture", "tickets"]),
        ("07-activity-people", ["--uitesting-activity-fixture", "people"]),
        ("08-topic", ["--uitesting-module", "topic"]),
        ("09-team", ["--uitesting-module", "teams"]),
        ("10-roam", ["--uitesting-module", "roam"]),
        ("11-play-choice", ["--uitesting-module", "play", "--uitesting-play-scenario", "choice"]),
        ("12-play-free-explore", ["--uitesting-module", "play", "--uitesting-play-scenario", "freeExploration"]),
        ("13-play-experience", ["--uitesting-module", "playExperience"]),
        ("14-play-backpack", ["--uitesting-module", "playBackpack"]),
        ("15-city-game", ["--uitesting-module", "cityGame"]),
        ("16-club-owner", ["--uitesting-club-fixture", "owner"]),
        ("17-club-visitor", ["--uitesting-club-fixture", "visitor"]),
        ("18-profile", ["--uitesting-module", "profile"]),
        ("19-social-account", ["--uitesting-module", "socialAccount"]),
        ("20-settings", ["--uitesting-module", "settingsNative"]),
        ("21-ticket-wallet", ["--uitesting-module", "ticketWallet"]),
        ("22-orders", ["--uitesting-module", "ownedOrderHistory"]),
        ("23-growth", ["--uitesting-module", "growthCenter"]),
        ("24-messages", ["--uitesting-module", "messaging"]),
        ("25-publish-templates", ["--ui-template-authoring", "--template-author-shelf", "--uitesting-theme-merchant"]),
        ("26-project-editor", ["--uitesting-module", "projectEdit", "--project-edit-starter-probe", "--project-story-image", "--uitesting-theme-merchant"]),
        ("27-merchant-operations", ["--uitesting-merchant-operations-fixture"]),
        ("28-merchant-business", ["--uitesting-merchant-business-fixture"]),
        ("29-merchant-content", ["--uitesting-merchant-content-fixture"]),
        ("30-merchant-engagement", ["--uitesting-merchant-engagement-fixture"]),
        ("31-cooperation", ["--uitesting-module", "cooperation", "--uitesting-theme-merchant"]),
        ("32-first-launch", ["--uitesting-first-launch-language"])
    ]

    /// Real root with the tab bar: each tab, then its first row, in both languages.
    func testCaptureRealRootTabs() {
        for (language, locale, tag) in [("zh-Hans", "zh_CN", "zh"), ("en", "en_US", "en")] {
            let app = XCUIApplication()
            app.launchArguments = ["--uitesting-integrated-native", "ready", "--uitesting-reset-language", "-AppleLanguages", "(\(language))", "-AppleLocale", locale]
            app.launch()
            Thread.sleep(forTimeInterval: 6)
            let count = app.tabBars.firstMatch.buttons.count
            for index in 0..<max(count, 1) {
                if count > index { app.tabBars.firstMatch.buttons.element(boundBy: index).tap() }
                Thread.sleep(forTimeInterval: 3)
                attach(app, name: "root-\(tag)-tab\(index)-a")
                app.swipeUp()
                Thread.sleep(forTimeInterval: 1.5)
                attach(app, name: "root-\(tag)-tab\(index)-b")
                app.swipeDown()
                let row = app.cells.firstMatch
                if row.waitForExistence(timeout: 2), row.isHittable {
                    row.tap()
                    Thread.sleep(forTimeInterval: 3)
                    attach(app, name: "root-\(tag)-tab\(index)-detail")
                }
            }
            app.terminate()
        }
    }

    /// Lists whose useful page is one tap in.
    func testCaptureDetailPages() {
        let screens: [(String, [String])] = [
            ("detail-activity", ["--uitesting-activity-fixture", "tickets"]),
            ("detail-activity-people", ["--uitesting-activity-fixture", "people"]),
            ("detail-topic", ["--uitesting-module", "topic"]),
            ("detail-club", ["--uitesting-club-fixture", "owner"]),
            ("detail-message", ["--uitesting-module", "messaging"]),
            ("detail-order", ["--uitesting-module", "ownedOrderHistory"]),
            ("detail-ticket", ["--uitesting-module", "ticketWallet"]),
            ("detail-square", ["--uitesting-module", "square"]),
            ("detail-merchant-operations", ["--uitesting-merchant-operations-fixture"]),
            ("detail-merchant-business", ["--uitesting-merchant-business-fixture"])
        ]
        for (name, arguments) in screens {
            let app = XCUIApplication()
            app.launchArguments = ["--uitesting-reset-language", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"] + arguments
            app.launch()
            Thread.sleep(forTimeInterval: 5)
            let row = app.cells.firstMatch
            if row.waitForExistence(timeout: 3), row.isHittable { row.tap() }
            Thread.sleep(forTimeInterval: 3)
            attach(app, name: name + "-a")
            app.swipeUp()
            Thread.sleep(forTimeInterval: 1.5)
            attach(app, name: name + "-b")
            app.terminate()
        }
    }

    func testCaptureAllScreens() {
        for screen in Self.screens {
            let app = XCUIApplication()
            app.launchArguments = ["--uitesting-reset-language", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"] + screen.arguments
            app.launch()
            Thread.sleep(forTimeInterval: 5)
            attach(app, name: screen.name + "-a")
            app.swipeUp()
            Thread.sleep(forTimeInterval: 1.5)
            attach(app, name: screen.name + "-b")
            app.terminate()
        }
    }

    private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

// Targeted follow-up to run 41979785867. These routes use existing sealed DEBUG
// fixtures. No production endpoint, grant, identity or UI implementation changes.
extension DesignReviewCaptureTests {
    private enum VerifiedCaptureFailure: Error { case missingTarget }

    private func verifiedLaunch(_ arguments: [String], language: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting-reset-language", "-AppleLanguages", "(\(language))", "-AppleLocale", language == "en" ? "en_US" : "zh_CN"] + arguments
        app.launch()
        return app
    }

    private func requireCaptureTarget(_ element: XCUIElement, app: XCUIApplication, name: String) throws {
        guard element.waitForExistence(timeout: 12) else {
            attach(app, name: "BLOCKED-" + name + "-synthetic")
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = "BLOCKED-" + name + "-accessibility"; tree.lifetime = .keepAlways; add(tree)
            XCTFail("Missing exact target: " + name)
            throw VerifiedCaptureFailure.missingTarget
        }
    }

    private func tapCaptureTarget(_ identifier: String, app: XCUIApplication) throws {
        let target = app.buttons[identifier]
        try requireCaptureTarget(target, app: app, name: identifier)
        for _ in 0..<5 {
            if target.isHittable && target.isEnabled { target.tap(); return }
            app.swipeUp()
        }
        attach(app, name: "BLOCKED-" + identifier + "-synthetic")
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "BLOCKED-" + identifier + "-accessibility"; tree.lifetime = .keepAlways; add(tree)
        XCTFail("Exact target is not hittable: " + identifier)
        throw VerifiedCaptureFailure.missingTarget
    }

    private func captureVerified(_ app: XCUIApplication, target: XCUIElement, name: String) throws {
        try requireCaptureTarget(target, app: app, name: name)
        attach(app, name: "verified-" + name + "-synthetic-a")
        app.swipeUp()
        attach(app, name: "verified-" + name + "-synthetic-b")
    }

    func testCaptureVerifiedRootTabs() throws {
        for language in ["zh-Hans", "en"] {
            let app = verifiedLaunch(["--uitesting-integrated-native", "ready"], language: language)
            defer { app.terminate() }
            // The existing fixture starts signed out; ready is a transport mode.
            // Exercise its normal UI sign-in with its existing synthetic values.
            try tapCaptureTarget("welcome.player", app: app)
            try tapCaptureTarget("auth.otherChannels", app: app)
            let phone = app.textFields["auth.channels.phone"]
            try requireCaptureTarget(phone, app: app, name: "synthetic-phone-field")
            phone.tap(); phone.typeText("10000000000")
            let code = app.textFields["auth.channels.code"]
            try requireCaptureTarget(code, app: app, name: "synthetic-code-field")
            code.tap(); code.typeText("123456")
            try tapCaptureTarget("auth.channels.phoneSignIn", app: app)
            let tabs = app.tabBars.firstMatch
            try requireCaptureTarget(tabs, app: app, name: "root-tabs-" + language)
            let count = tabs.buttons.count
            guard count > 0 else { XCTFail("No root tabs after synthetic sign-in"); throw VerifiedCaptureFailure.missingTarget }
            for index in 0..<count {
                let tab = tabs.buttons.element(boundBy: index)
                guard tab.isHittable else { XCTFail("Root tab is not hittable"); throw VerifiedCaptureFailure.missingTarget }
                tab.tap()
                try captureVerified(app, target: tabs, name: "root-" + language + "-tab" + String(index))
            }
        }
    }

    func testCaptureVerifiedOrders() throws {
        for language in ["zh-Hans", "en"] {
            let app = verifiedLaunch(["--uitesting-module", "ownedOrderHistory"], language: language)
            defer { app.terminate() }
            try tapCaptureTarget("profile.open.orders", app: app)
            let row = app.buttons["profile.order.41"]
            try captureVerified(app, target: row, name: "orders-list-" + language)
            app.swipeDown()
            try tapCaptureTarget("profile.order.41", app: app)
            try captureVerified(app, target: app.descendants(matching: .any)["profile.order.detail.name"].firstMatch, name: "order-detail-" + language)
        }
    }

    func testCaptureVerifiedTopic() throws {
        for language in ["zh-Hans", "en"] {
            let app = verifiedLaunch(["--uitesting-module", "topic"], language: language)
            defer { app.terminate() }
            try tapCaptureTarget("topic.row.7", app: app)
            try captureVerified(app, target: app.descendants(matching: .any)["topic.detail.content"].firstMatch, name: "topic-detail-" + language)
        }
    }

    func testCaptureVerifiedMessage() throws {
        for language in ["zh-Hans", "en"] {
            let app = verifiedLaunch(["--uitesting-module", "messaging"], language: language)
            defer { app.terminate() }
            try tapCaptureTarget("messaging.conversation.901", app: app)
            try captureVerified(app, target: app.buttons["messaging.history.earlier"], name: "message-history-" + language)
        }
    }
}
