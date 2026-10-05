import SwiftUI
import XCTest
@testable import Questify

/// Authored app-hosted navigation tests. Apple execution remains a separate gate.
@MainActor final class ClubStoryNavigationTests: XCTestCase {
    private let access = ClubGovernanceFixtureAccess()
    private func snapshot() throws -> ClubGovernanceSnapshot {
        let scope = ClubGovernanceScope(clubID: 81, topicID: 91)
        let permissions = try ClubGovernancePermissions(value: ClubGovernanceFixtures.permissions, scope: scope)
        return .init(operation: .topicOverview, scope: scope, permissions: permissions,
            value: ClubGovernanceFixtures.value(.topicOverview))
    }
    private func context(_ reader: any MemberTemplateReading, viewerRevision: UInt64 = 1) -> ClubGovernanceReadContext {
        .init(operation: .topicOverview, scope: .init(clubID: 81, topicID: 91),
            identity: access.identity, viewerRevision: viewerRevision,
            authorizationGeneration: access.authorizationGeneration,
            readerIdentity: ObjectIdentifier(reader), accessIdentity: ObjectIdentifier(access))
    }
    private func templates(_ reader: any MemberTemplateReading, destination: Bool = true) -> ClubStoryTemplateContext {
        .init(viewerRevision: 1, reader: reader, destination: destination ? { id in AnyView(Text(verbatim: String(id.rawValue))) } : nil)
    }
    private func play(_ snapshot: ClubGovernanceSnapshot) throws -> ClubStoryGameplay {
        try XCTUnwrap(ClubStoryPresentation(snapshot: snapshot).chapters.first?.gameplay.first)
    }
    func testExactMemberIDRemainsSeparateFromNodeAndTopicAndSelectionDoesNotRead() throws {
        let reader = ClubStoryUnitMemberReader(), snapshot = try snapshot(), context = context(reader)
        let selection = try XCTUnwrap(ClubStoryTemplateSelection(gameplay: play(snapshot), snapshot: snapshot,
            context: context, snapshotGeneration: 3, templates: templates(reader)))
        XCTAssertEqual(selection.route.templateID.rawValue, 142)
        XCTAssertNotEqual(selection.route.templateID.rawValue, snapshot.scope.topicID)
        XCTAssertTrue(selection.isCurrent(snapshot: snapshot, context: context, snapshotGeneration: 3, templates: templates(reader)))
        XCTAssertEqual(reader.reads, 0)
    }
    func testMissingDestinationSignedOutAndDefaultOffReaderCannotConstructSelection() throws {
        let reader = ClubStoryUnitMemberReader(), snapshot = try snapshot(), play = try play(snapshot), context = context(reader)
        for change in ["destination", "configured", "authenticated", "empty"] {
            reader.isConfigured = change != "configured"; reader.isAuthenticated = change != "authenticated"
            let input = change == "empty" ? ClubStoryTemplateContext() : templates(reader, destination: change != "destination")
            XCTAssertNil(ClubStoryTemplateSelection(gameplay: play, snapshot: snapshot, context: context,
                snapshotGeneration: 1, templates: input), change)
        }
        XCTAssertEqual(reader.reads, 0)
    }
    func testQueuedSelectionRejectsSessionABAReaderReplacementAndPermissionChange() throws {
        let reader = ClubStoryUnitMemberReader(), snapshot = try snapshot(), context = context(reader)
        let selection = try XCTUnwrap(ClubStoryTemplateSelection(gameplay: play(snapshot), snapshot: snapshot,
            context: context, snapshotGeneration: 4, templates: templates(reader)))
        let originalScope = reader.scope
        reader.scope = UUID()
        XCTAssertFalse(selection.isCurrent(snapshot: snapshot, context: context, snapshotGeneration: 4, templates: templates(reader)))
        reader.scope = originalScope
        reader.isConfigured = false
        XCTAssertFalse(selection.isCurrent(snapshot: snapshot, context: context, snapshotGeneration: 4, templates: templates(reader)))
        reader.isConfigured = true; reader.isAuthenticated = false
        XCTAssertFalse(selection.isCurrent(snapshot: snapshot, context: context, snapshotGeneration: 4, templates: templates(reader)))
        reader.isAuthenticated = true
        let replacement = ClubStoryUnitMemberReader(); replacement.scope = originalScope
        XCTAssertFalse(selection.isCurrent(snapshot: snapshot, context: context, snapshotGeneration: 4, templates: templates(replacement)))
        XCTAssertFalse(selection.isCurrent(snapshot: snapshot, context: self.context(reader, viewerRevision: 2), snapshotGeneration: 4, templates: templates(reader)))
        XCTAssertEqual(reader.reads + replacement.reads, 0)
    }
    func testRefreshClearsSelectionEvenForIdenticalBytesAndChangedUnselectedChapter() throws {
        let reader = ClubStoryUnitMemberReader(), snapshot = try snapshot(), context = context(reader)
        let selection = try XCTUnwrap(ClubStoryTemplateSelection(gameplay: play(snapshot), snapshot: snapshot,
            context: context, snapshotGeneration: 5, templates: templates(reader)))
        XCTAssertFalse(selection.isCurrent(snapshot: nil, context: context, snapshotGeneration: 5, templates: templates(reader)))
        XCTAssertFalse(selection.isCurrent(snapshot: snapshot, context: context, snapshotGeneration: 6, templates: templates(reader)))
        var value = try XCTUnwrap(snapshot.value.object)
        value["name"] = .string("Source changed while selection was queued")
        let changed = ClubGovernanceSnapshot(operation: snapshot.operation, scope: snapshot.scope,
            permissions: snapshot.permissions, value: .object(value))
        XCTAssertFalse(selection.isCurrent(snapshot: changed, context: context, snapshotGeneration: 5, templates: templates(reader)))
        XCTAssertEqual(reader.reads, 0)
    }
    func testCurrentReaderUsesExactMyInfoAndRejectsWrongReturnedID() async throws {
        let wire = ClubStoryUnitWire()
        let service = PlayerJourneyService(configuration: try APIConfiguration(baseURL: URL(string: "https://example.test")!), transport: wire, readsEnabled: true)
        let session = try PlayerJourneySession(accountID: 701, epoch: 1, namespace: "synthetic", token: "synthetic")
        let reader = PlayerJourneySessionReader(service: service, currentSession: { session })
        let id = try XCTUnwrap(MemberPlayTemplateID(rawValue: 142))
        let detail = try await reader.memberTemplate(id: id)
        XCTAssertEqual(detail.id, id)
        XCTAssertEqual(wire.requests.count, 1)
        XCTAssertEqual(wire.requests.first?.url?.path, "/api/template/myinfo")
        XCTAssertEqual(String(data: try XCTUnwrap(wire.requests.first?.httpBody), encoding: .utf8), "id=142")
        wire.returnedID = 141
        do { _ = try await reader.memberTemplate(id: id); XCTFail("wrong returned ID") }
        catch { XCTAssertEqual(error as? APIError, .malformedResponse) }
        XCTAssertTrue(wire.requests.allSatisfy { $0.url?.path == "/api/template/myinfo" })
    }
    func testDefaultServiceGrantStillPreventsDispatch() async throws {
        let wire = ClubStoryUnitWire()
        let service = PlayerJourneyService(configuration: try APIConfiguration(baseURL: URL(string: "https://example.test")!), transport: wire)
        let session = try PlayerJourneySession(accountID: 701, epoch: 1, namespace: "synthetic", token: "synthetic")
        let reader = PlayerJourneySessionReader(service: service, currentSession: { session })
        XCTAssertFalse(templates(reader).isAvailable)
        let id = try XCTUnwrap(MemberPlayTemplateID(rawValue: 142))
        do { _ = try await reader.memberTemplate(id: id); XCTFail("grant should remain off") }
        catch { XCTAssertEqual(error as? APIError, .notConfigured) }
        XCTAssertTrue(wire.requests.isEmpty)
    }
}
@MainActor private final class ClubStoryUnitMemberReader: MemberTemplateReading {
    var scope = UUID(), isAuthenticated = true, isConfigured = true
    var reads = 0
    func memberTemplate(id: MemberPlayTemplateID) async throws -> MemberTemplateDetail {
        reads += 1; throw APIError.notConfigured
    }
}
private final class ClubStoryUnitWire: HTTPTransport {
    var returnedID = 142
    var requests: [URLRequest] = []
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        return (Data("{\"code\":200,\"data\":{\"id\":\(returnedID),\"title\":\"Synthetic personal template\"}}".utf8), 200)
    }
}
