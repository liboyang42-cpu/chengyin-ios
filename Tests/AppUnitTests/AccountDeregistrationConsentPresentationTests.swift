import Foundation
import SwiftUI
import XCTest
@testable import Questify

/// Bundled presentation contract only. This is not a screenshot or VoiceOver runtime check.
@MainActor final class AccountDeregistrationConsentPresentationTests: XCTestCase {
    private let states: [AccountDeregistrationConsentReadState] = [
        .unread, .none, .unknown(requestID: "aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa"), .unavailable
    ]
    private func text(_ key: String, language: String) throws -> String {
        let app = Bundle(for: ComplianceViewModel.self)
        let path = try XCTUnwrap(app.path(forResource: language, ofType: "lproj"), "Missing language bundle: \(language)")
        let bundle = try XCTUnwrap(Bundle(path: path))
        return bundle.localizedString(forKey: key, value: nil, table: "AccountDeregistrationConsent")
    }
    func testAllFourActualStatesHaveDistinctBilingualCopy() throws {
        XCTAssertEqual(Set(states.map(\.messageKey)).count, 4)
        for language in ["en", "zh-Hans"] {
            let messages = try states.map { try text($0.messageKey, language: language) }
            XCTAssertEqual(Set(messages).count, 4)
            for (state, message) in zip(states, messages) {
                XCTAssertFalse(message.isEmpty); XCTAssertNotEqual(message, state.messageKey)
            }
        }
        for state in states {
            XCTAssertNotEqual(try text(state.messageKey, language: "en"), try text(state.messageKey, language: "zh-Hans"))
        }
    }
    func testOnlyReadAbsenceAllowsNewConsentAndApplication() {
        for state in states { XCTAssertEqual(state.allowsNewConsent, state == .none) }
        XCTAssertEqual(ComplianceState().localCancellationConsent, .unread)
    }
    func testUnknownReferenceIsOnlySavedLocalMetadata() {
        XCTAssertEqual(states[2].requestID, "aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa")
        for state in [states[0], states[1], states[3]] { XCTAssertNil(state.requestID) }
    }
    func testLocalScopeAndCurrentAccountStatusRemainSeparateInBothLanguages() throws {
        for key in ["cancellationConsent.title", "cancellationConsent.scope", "cancellationConsent.request"] {
            for language in ["en", "zh-Hans"] { XCTAssertNotEqual(try text(key, language: language), key) }
        }
        let english = try text("cancellationConsent.scope", language: "en")
        XCTAssertTrue(english.contains("Older records do not identify the server environment or notice version"))
        XCTAssertTrue(english.contains("shown separately"))
        let chinese = try text("cancellationConsent.scope", language: "zh-Hans")
        XCTAssertTrue(chinese.contains("旧记录没有服务器环境或须知版本"))
        XCTAssertTrue(chinese.contains("当前注销状态单独展示"))
    }
    func testRefreshCopyDoesNotOfferAReplacementConsentOrClear() throws {
        let english = try text("cancellationConsent.unknown", language: "en")
        let chinese = try text("cancellationConsent.unknown", language: "zh-Hans")
        XCTAssertTrue(english.contains("does not resend")); XCTAssertTrue(chinese.contains("不会重新发送"))
        XCTAssertTrue(try text("cancellationConsent.unavailable", language: "en").contains("has not been cleared"))
        XCTAssertTrue(try text("cancellationConsent.unavailable", language: "zh-Hans").contains("未被清除"))
        XCTAssertTrue(try text("cancellationConsent.none", language: "en").contains("does not confirm consent"))
        XCTAssertTrue(try text("cancellationConsent.none", language: "zh-Hans").contains("不代表已同意或已注销"))
    }
    func testLocalUnknownDoesNotInventOrReplaceCurrentApplicationState() {
        var state = ComplianceState()
        state.localCancellationConsent = .unknown(requestID: "saved-local-request")
        state.step = .pending
        XCTAssertEqual(state.step, .pending)
        XCTAssertNil(state.originalApplication)
        XCTAssertFalse(state.localCancellationConsent.allowsNewConsent)
        state = .init()
        XCTAssertEqual(state.localCancellationConsent, .unread)
        XCTAssertNil(state.localCancellationConsent.requestID)
    }
}
