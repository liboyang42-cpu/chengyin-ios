import XCTest
import SwiftUI
import UIKit
@testable import Questify

/// Presentation-only closure. No real service, grant, write, settlement or reward delivery.
@MainActor final class OfficialEventComponentsClosureTests: XCTestCase {
    private var componentSource: String {
        get throws {
            let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            return try String(contentsOf: root.appendingPathComponent("App/OfficialEventComponents.swift"), encoding: .utf8)
        }
    }
    private func render<V: View>(_ view: V, locale: String) {
        let host = UIHostingController(rootView: view.environment(\.locale, Locale(identifier: locale)).environment(\.dynamicTypeSize, .accessibility5))
        host.loadViewIfNeeded()
        host.view.frame = CGRect(x: 0, y: 0, width: 320, height: 640)
        host.view.setNeedsLayout(); host.view.layoutIfNeeded()
        XCTAssertNotNil(host.view)
    }
    func testIssueMappingPreservesAuthorizationAndUnavailableStates() {
        if case .unconfigured = OfficialScreenIssue(APIError.notConfigured) {} else { XCTFail("Configuration failure changed") }
        if case .unauthorized = OfficialScreenIssue(APIError.unauthorized) {} else { XCTFail("Guest failure changed") }
        if case .noPublisherPermission = OfficialScreenIssue(OfficialReadFailure.noPublisherPermission) {} else { XCTFail("Publisher gate changed") }
        if case .forbidden = OfficialScreenIssue(OfficialReadFailure.forbidden) {} else { XCTFail("Forbidden state changed") }
        if case .unavailable = OfficialScreenIssue(OfficialReadFailure.unavailable) {} else { XCTFail("Unavailable state changed") }
        if case .failed = OfficialScreenIssue(APIError.malformedResponse) {} else { XCTFail("Unknown failure became success") }
    }
    func testErrorStatesRenderWithoutAutomaticallyInvokingActions() {
        var callbacks = 0
        for locale in ["en", "zh-Hans"] {
            let issues: [OfficialScreenIssue] = [.unconfigured, .unauthorized, .noPublisherPermission, .forbidden, .unavailable, .failed]
            for issue in issues {
                render(OfficialIssueView(issue: issue, onLogin: { callbacks += 1 }, retry: { callbacks += 1 },
                    copy: OfficialIssueCopy(title: "official.failed", detail: "official.readOnly", backTitle: "action.close"),
                    onBack: { callbacks += 1 }), locale: locale)
            }
        }
        XCTAssertEqual(callbacks, 0)
    }
    func testCollectiveIndicatorClampsDisplayWithoutRewritingOriginalFacts() throws {
        for (raw, displayed) in [(-2, 0.0), (35, 0.35), (102, 1.0)] {
            let json = "{\"id\":7,\"title\":\"Original title\",\"status\":3,\"collective\":{\"enabled\":true,\"pct\":\(raw)}}"
            let event = try JSONDecoder().decode(OfficialEvent.self, from: Data(json.utf8))
            XCTAssertEqual(event.collective?.percent, raw)
            XCTAssertEqual(event.collective?.displayFraction, displayed)
            for locale in ["en", "zh-Hans"] { render(OfficialEventCard(event: event), locale: locale) }
        }
        let missing = try JSONDecoder().decode(OfficialCollectiveProgress.self, from: Data(#"{"enabled":true}"#.utf8))
        XCTAssertNil(missing.percent); XCTAssertNil(missing.displayFraction)
    }
    func testUnknownStatusNeverBecomesParticipationOrPaidRewardProof() throws {
        let event = try JSONDecoder().decode(OfficialEvent.self, from: Data(#"{"id":7,"title":"Original","status":42,"signed":true,"collective":{"enabled":true,"pct":100}}"#.utf8))
        XCTAssertEqual(event.statusKey, "official.status.unknown")
        XCTAssertEqual(event.participationKey, "official.participation.unavailable")
        XCTAssertTrue(event.rewards.isEmpty)
    }
    func testGuestPrivateReadStillRejectsWithoutAService() async {
        let reader = OfficialSessionReader(service: nil, currentContext: { OfficialReadContext(guestEpoch: 5) })
        do { _ = try await reader.myEvents(); XCTFail("Guest read was allowed") }
        catch { XCTAssertEqual(error as? APIError, .unauthorized) }
    }
    func testReadOnlyNoticeStillAppearsForOnlineAndOfflineConsumers() throws {
        let source = try componentSource
        let notice = try XCTUnwrap(source.components(separatedBy: "struct OfficialReadOnlyNotice: View {").last?.components(separatedBy: "struct OfficialEventCard:").first)
        XCTAssertTrue(notice.contains("\n            Text(\"official.readOnly\")"))
        XCTAssertFalse(notice.contains("if offline { Text(\"official.readOnly\") }"))
        for offline in [true, false] {
            for locale in ["en", "zh-Hans"] { render(OfficialReadOnlyNotice(offline: offline), locale: locale) }
        }
    }
    func testReadLifecycleAndExactActionGatesAreStillPresent() throws {
        let source = try componentSource
        for guardText in ["if case .unauthorized = issue, let onLogin", "else if case .failed = issue, let retry",
                          "else if case .unavailable = issue, let onBack, let copy, let backTitle = copy.backTitle",
                          "guard reader.isConfigured, !isPrivate || reader.isAuthenticated else { return }",
                          "guard !Task.isCancelled, generation == operation, key == captured else { return }",
                          ".onDisappear { generation &+= 1; loading = false }"] {
            XCTAssertTrue(source.contains(guardText), guardText)
        }
        XCTAssertFalse(source.contains("URLSession")); XCTAssertFalse(source.contains("OperationEndpointApproval"))
    }
    func testLocalStatelessPresentationHelpersRenderLongOriginalValues() {
        for locale in ["en", "zh-Hans"] {
            render(List {
                OfficialFlowNotice(text: String(repeating: "Original long notice ", count: 8))
                OfficialRecordValue(title: "official.title", value: String(repeating: "original-reference-", count: 12))
            }.modifier(OfficialFlowSurface()).modifier(OfficialFlowActions())
                .safeAreaInset(edge: .bottom) { OfficialFlowActionBar { Button("action.close") {} } }, locale: locale)
        }
    }
}
