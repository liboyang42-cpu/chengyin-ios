import XCTest

/// Requires DEBUG host registration documented in integration.md. Runtime NOT_RUN on Linux.
final class WalletCommerceFlowTests: XCTestCase {
    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting-reset-language", "--wallet-commerce-fixture", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"] + extra
        app.launch(); return app
    }
    func testIncomeEntryOpensExistingServerRowAndCloseReturnsToList() {
        let app = launch(); app.buttons["wallet.fixture.income"].tap()
        let row = app.buttons["wallet.income.detail.open.4"]
        XCTAssertTrue(row.waitForExistence(timeout: 5)); row.tap()
        let close = app.buttons["wallet.income.detail.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["wallet.income.detail.retired"].exists)
        XCTAssertFalse(app.buttons["Pay"].exists)
        close.tap(); XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap(); XCTAssertTrue(close.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["wallet.income.detail.retired"].exists)
        close.tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["wallet.fixture.income"].waitForExistence(timeout: 5))
    }
    func testIncomeDetailClosesOnBackgroundAndCanBeOpenedAgain() {
        let app = launch(); app.buttons["wallet.fixture.income"].tap()
        let row = app.buttons["wallet.income.detail.open.4"]
        XCTAssertTrue(row.waitForExistence(timeout: 5)); row.tap()
        XCTAssertTrue(app.buttons["wallet.income.detail.close"].waitForExistence(timeout: 5))
        XCUIDevice.shared.press(.home); app.activate()
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["wallet.income.detail.close"].exists)
        row.tap()
        XCTAssertTrue(app.buttons["wallet.income.detail.close"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["wallet.income.detail.retired"].exists)
    }

    func testFundsStagesUnknownCurrencyAndZeroRemainDistinct() {
        let app = launch(); app.buttons["wallet.fixture.assets"].tap()
        XCTAssertTrue(app.staticTexts["wallet.assets.unknown"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Available to withdraw"].exists)
        XCTAssertFalse(app.otherElements["wallet.assets.available"].exists)
        // LabeledContent may expose the amount together with its row label.
        let zeroAmount = app.staticTexts.matching(NSPredicate(format: "label == %@ OR label ENDSWITH %@", "0 currency unspecified", ", 0 currency unspecified")).firstMatch
        XCTAssertFalse(zeroAmount.exists, app.debugDescription)
        XCTAssertFalse(app.staticTexts["Pending settlement"].exists)
        XCTAssertFalse(app.staticTexts["In dispute"].exists)
    }
    func testCheckoutIsPreviewAndCannotRedeem() {
        let app = launch(); app.buttons["wallet.fixture.cart"].tap()
        let row = app.switches["wallet.cart.20"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        let nativeSwitch = row.switches.firstMatch
        if nativeSwitch.exists { nativeSwitch.tap() }
        else { row.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap() }
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "1"), object: row)
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 5), .completed, app.debugDescription)
        let preview = app.buttons["Checkout preview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 5), app.debugDescription); preview.tap()
        XCTAssertTrue(app.staticTexts["wallet.previewOnly"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Place order"].exists)
        XCTAssertFalse(app.buttons["Pay"].exists)
    }
    func testUnknownNonzeroPlaceholdersNeverAppearAsMoney() {
        let app = launch(["--wallet-assets-unknown-nonzero"]); app.buttons["wallet.fixture.assets"].tap()
        XCTAssertTrue(app.staticTexts["wallet.assets.unknown"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Available to withdraw"].exists)
        let amount = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "7 currency unspecified")).firstMatch
        XCTAssertFalse(amount.exists, app.debugDescription)
    }
    func testKnownZeroRemainsAnExplicitZero() {
        let app = launch(["--wallet-assets-known-zero"]); app.buttons["wallet.fixture.assets"].tap()
        XCTAssertTrue(app.staticTexts["Available to withdraw"].waitForExistence(timeout: 5))
        let amount = app.staticTexts.matching(NSPredicate(format: "label == %@ OR label ENDSWITH %@", "0 currency unspecified", ", 0 currency unspecified")).firstMatch
        XCTAssertTrue(amount.exists, app.debugDescription)
        XCTAssertFalse(app.staticTexts["wallet.assets.unknown"].exists)
    }
    func testDeniedAssetReadHasNoRetry() {
        let app = launch(["--wallet-assets-denied"]); app.buttons["wallet.fixture.assets"].tap()
        XCTAssertTrue(app.staticTexts["wallet.issue"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Try again"].exists)
        XCTAssertFalse(app.staticTexts["Available to withdraw"].exists)
    }
    func testTransientAssetReadRetriesAndShowsServerResult() {
        let app = launch(["--wallet-assets-recover"]); app.buttons["wallet.fixture.assets"].tap()
        let retry = app.buttons["Try again"]
        XCTAssertTrue(retry.waitForExistence(timeout: 5)); retry.tap()
        XCTAssertTrue(app.staticTexts["Available to withdraw"].waitForExistence(timeout: 5))
        let amount = app.staticTexts.matching(NSPredicate(format: "label == %@ OR label ENDSWITH %@", "7 currency unspecified", ", 7 currency unspecified")).firstMatch
        XCTAssertTrue(amount.exists, app.debugDescription)
        XCTAssertFalse(app.staticTexts["wallet.issue"].exists)
    }
    func testReturningFromLedgerReloadsAssetsInSameScope() {
        let app = launch(["--wallet-assets-return-refresh"]); app.buttons["wallet.fixture.assets"].tap()
        XCTAssertTrue(app.staticTexts["Available to withdraw"].waitForExistence(timeout: 5))
        let zero = app.staticTexts.matching(NSPredicate(format: "label == %@ OR label ENDSWITH %@", "0 currency unspecified", ", 0 currency unspecified")).firstMatch
        XCTAssertTrue(zero.exists, app.debugDescription)
        app.buttons["wallet.assets.balanceLedger"].tap()
        XCTAssertTrue(app.staticTexts["wallet.ledger.1"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let refreshed = app.staticTexts.matching(NSPredicate(format: "label == %@ OR label ENDSWITH %@", "7 currency unspecified", ", 7 currency unspecified")).firstMatch
        XCTAssertTrue(refreshed.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(zero.exists)
    }
    func testDeniedLedgerHasNoRetryLoadMoreOrEmptySuccess() {
        let app = launch(["--wallet-ledger-denied"])
        app.buttons["wallet.fixture.assets"].tap(); app.buttons["wallet.assets.balanceLedger"].tap()
        XCTAssertTrue(app.staticTexts["wallet.issue"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Try again"].exists)
        XCTAssertFalse(app.buttons["wallet.ledger.loadMore"].exists)
        XCTAssertFalse(app.staticTexts["wallet.ledger.empty"].exists)
        XCTAssertFalse(app.staticTexts["wallet.ledger.1"].exists)
    }
    func testUnauthorizedAssetPointsShowsSignInWithoutRetry() {
        let app = launch(["--wallet-ledger-unauthorized"])
        app.buttons["wallet.fixture.assets"].tap(); app.buttons["wallet.assets.pointsLedger"].tap()
        XCTAssertTrue(app.staticTexts["Sign in to view this information"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Try again"].exists)
        XCTAssertFalse(app.buttons["wallet.ledger.loadMore"].exists)
        XCTAssertFalse(app.staticTexts["wallet.ledger.empty"].exists)
    }
    func testBalanceLedgerRetryReadsServerRowsAndHasNoInventedPagination() {
        let app = launch(["--wallet-ledger-recover"])
        app.buttons["wallet.fixture.assets"].tap(); app.buttons["wallet.assets.balanceLedger"].tap()
        let retry = app.buttons["Try again"]
        XCTAssertTrue(retry.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["wallet.ledger.empty"].exists)
        XCTAssertFalse(app.buttons["wallet.ledger.loadMore"].exists)
        retry.tap()
        XCTAssertTrue(app.staticTexts["wallet.ledger.1"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["wallet.issue"].exists)
        XCTAssertFalse(app.buttons["wallet.ledger.loadMore"].exists)
    }
    func testAssetPointsSuccessfulEmptyHasNoErrorOrLoadMore() {
        let app = launch(["--wallet-ledger-empty"])
        app.buttons["wallet.fixture.assets"].tap(); app.buttons["wallet.assets.pointsLedger"].tap()
        XCTAssertTrue(app.staticTexts["wallet.ledger.empty"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["wallet.issue"].exists)
        XCTAssertFalse(app.buttons["wallet.ledger.loadMore"].exists)
    }
    func testSignedOutLedgerNeverShowsEmptySuccess() {
        let app = launch(); app.buttons["wallet.fixture.signOut"].tap()
        app.buttons["wallet.fixture.assets"].tap(); app.buttons["wallet.assets.balanceLedger"].tap()
        XCTAssertTrue(app.staticTexts["Sign in to view this information"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["wallet.ledger.empty"].exists)
        XCTAssertFalse(app.buttons["Try again"].exists)
        XCTAssertFalse(app.buttons["wallet.ledger.loadMore"].exists)
    }
    func testWithdrawalDenialHasNoRetryOrEmptySuccess() {
        let app = launch(["--wallet-withdrawals-denied"]); app.buttons["wallet.fixture.withdrawals"].tap()
        XCTAssertTrue(app.staticTexts["wallet.issue"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Try again"].exists)
        XCTAssertFalse(app.staticTexts["wallet.withdrawals.empty"].exists)
        XCTAssertFalse(app.staticTexts["wallet.withdrawal.40"].exists)
        XCTAssertTrue(app.buttons["wallet.withdrawals.support"].exists)
    }
    func testWithdrawal401ShowsSignInWithoutRetry() {
        let app = launch(["--wallet-withdrawals-unauthorized"]); app.buttons["wallet.fixture.withdrawals"].tap()
        XCTAssertTrue(app.staticTexts["Sign in to view this information"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Try again"].exists)
        XCTAssertFalse(app.staticTexts["wallet.withdrawals.empty"].exists)
    }
    func testWithdrawalTransientFailureRetriesIntoServerStatus() {
        let app = launch(["--wallet-withdrawals-recover"]); app.buttons["wallet.fixture.withdrawals"].tap()
        let retry = app.buttons["Try again"]
        XCTAssertTrue(retry.waitForExistence(timeout: 5)); retry.tap()
        let row = app.staticTexts["wallet.withdrawal.41"]
        XCTAssertTrue(row.waitForExistence(timeout: 5)); XCTAssertTrue(row.label.contains("Rejected"))
        XCTAssertFalse(app.staticTexts["wallet.issue"].exists)
    }
    func testWithdrawalMissingStatusIsFailureRatherThanPaidOrEmpty() {
        let app = launch(["--wallet-withdrawals-invalid-status"]); app.buttons["wallet.fixture.withdrawals"].tap()
        XCTAssertTrue(app.staticTexts["wallet.issue"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["wallet.withdrawal.40"].exists)
        XCTAssertFalse(app.staticTexts["wallet.withdrawals.empty"].exists)
    }
    func testEmptyWithdrawalHistoryStillOffersSafeSupportAndReturn() {
        let app = launch(["--wallet-withdrawals-empty"]); app.buttons["wallet.fixture.withdrawals"].tap()
        XCTAssertTrue(app.staticTexts["wallet.withdrawals.empty"].waitForExistence(timeout: 5))
        app.buttons["wallet.withdrawals.support"].tap()
        XCTAssertTrue(app.otherElements["withdrawal.support.unconfigured"].waitForExistence(timeout: 5)
                      || app.staticTexts["withdrawal.support.unconfigured"].exists)
        XCTAssertFalse(app.buttons["withdrawal.support.copyWeChat"].exists)
        app.buttons["withdrawal.support.close"].tap()
        XCTAssertTrue(app.staticTexts["wallet.withdrawals.empty"].waitForExistence(timeout: 5))
        app.buttons["wallet.withdrawals.support"].tap()
        XCTAssertTrue(app.buttons["withdrawal.support.close"].waitForExistence(timeout: 5))
        app.buttons["withdrawal.support.close"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["wallet.fixture.withdrawals"].waitForExistence(timeout: 5))
    }
    func testApprovalIsNotFinalPayoutAndBankAccountIsMasked() {
        let app = launch(); app.buttons["wallet.fixture.withdrawals"].tap()
        XCTAssertTrue(app.staticTexts["wallet.withdrawal.40"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["SYNTHETIC-1234"].exists)
        XCTAssertFalse(app.buttons["Withdraw"].exists)
    }
    func testFailureOffersRetryWithoutInventedZero() {
        let app = launch(["--wallet-failure"]); app.buttons["wallet.fixture.assets"].tap()
        XCTAssertTrue(app.staticTexts["wallet.issue"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["0 currency unspecified"].exists)
        app.buttons["Try again"].tap()
        XCTAssertTrue(app.staticTexts["wallet.issue"].exists)
    }
    func testSignOutHidesAccountData() {
        let app = launch(); app.buttons["wallet.fixture.signOut"].tap()
        app.buttons["wallet.fixture.points"].tap()
        XCTAssertTrue(app.staticTexts["Sign in to view this information"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["wallet.ledger.3"].exists)
    }
    func testBankFormIsReachableAndClearlyDormant() {
        let app = launch(); app.buttons["wallet.fixture.bankWithdrawal"].tap()
        XCTAssertTrue(app.staticTexts["Bank-card submission is not enabled in this build. No banking details will be sent."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.secureTextFields["bank.withdrawal.account"].exists)
        XCTAssertFalse(app.buttons["bank.withdrawal.confirmSubmit"].exists)
    }
    func testBankReviewValidatesBeforeOpeningConfirmation() {
        let app = launch(); app.buttons["wallet.fixture.bankWithdrawal"].tap()
        let review = app.buttons["bank.withdrawal.review"]
        if !review.isHittable { app.swipeUp() }
        review.tap()
        XCTAssertTrue(app.staticTexts["bank.withdrawal.issue"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["bank.withdrawal.prepare"].exists)
    }
    func testBankHistoryUsesServerRejectedStatusInsteadOfPaid() {
        let app = launch(); app.buttons["wallet.fixture.withdrawals"].tap()
        let row = app.staticTexts["wallet.withdrawal.41"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.label.contains("Rejected"))
        XCTAssertFalse(row.label.contains("Paid"))
    }

}
