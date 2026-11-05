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
