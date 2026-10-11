import XCTest
import SwiftUI
@testable import Questify

@MainActor final class ProfileSelfProjectsAppTests: XCTestCase {
    private let social=ProfileSelfProjectsFixturePublicReader(),source=ProfileSelfProjectsFixtureReader()
    private func access() -> ProfileSelfProjectsAccess { .init(reader:source,owner:social.identity,detail:{ _ in AnyView(Text("Synthetic destination")) }) }
    func testNormalOwnerHasContext() {XCTAssertNotNil(access().context(memberID:81,accountReader:social,isCurrent:true))}
    func testOtherMemberHasNoPrivateEntry() {XCTAssertNil(access().context(memberID:92,accountReader:social,isCurrent:true))}
    func testCapturedAccessDoesNotFollowNewAccount() {let a=access();social.identity = .init(accountID:82,epoch:2);source.scope=UUID();XCTAssertNil(a.context(memberID:82,accountReader:social,isCurrent:true))}
    func testScopeChangeRetiresEvenSameAccount() {let a=access();source.scope=UUID();XCTAssertNil(a.context(memberID:81,accountReader:social,isCurrent:true))}
    func testSelectionIdentityDoesNotAliasSameProjectReopened() async throws {let page=try await source.projects(query:.init());let row=try XCTUnwrap(page.rows.first);XCTAssertNotEqual(ProfileSelfProjectSelection(project:row).id,ProfileSelfProjectSelection(project:row).id)}
    func testFixtureOnlyLiveTopicsReachPreview() async throws {let page=try await source.projects(query:.init());let preview=ProfileSelfProjectsPreview(page:page,today:"2026-10-11");XCTAssertEqual(preview.rows.map(\.sourceID),[7,9]);XCTAssertTrue(preview.rows.allSatisfy{$0.bizType == "topic"})}
    func testHostBuildsWithoutNetworkOrCredentials() {let host=UIHostingController(rootView:ProfileSelfProjectsFixtureHost());host.loadViewIfNeeded();XCTAssertNotNil(host.view)}
}
