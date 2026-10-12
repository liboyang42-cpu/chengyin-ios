import XCTest
@testable import QuestifyCore

final class CooperationInboxTopicFilterTests: XCTestCase {
    private func decode<T: Decodable>(_ text: String, as type: T.Type) throws -> T {
        try JSONDecoder().decode(type, from: Data(text.utf8))
    }
    private func inbox(direction: CooperationDirection = .received) throws -> CooperationInbox {
        let invitations = try decode(#"{"received":[{"id":1,"topicId":301},{"id":1,"topicId":302},{"id":1,"topicId":301},{"id":2}],"sent":[{"id":3,"topicId":303}]}"#, as: CooperationInvites.self)
        let applications = try decode(#"[{"applyId":1,"topicId":301,"topicName":"Loaded route"},{"applyId":2,"topicId":304,"topicName":"Another route"}]"#, as: [CooperationApplication].self)
        let registrations = try decode(#"{"rows":[{"id":1,"topicId":301,"topicName":"Later duplicate name"},{"id":2},{"id":3,"topicId":305}],"hasMore":true}"#, as: CooperationRegistrations.self)
        return .init(direction: direction, invitations: .content(invitations), applications: .content(applications), registrations: .content(registrations))
    }
    func testOptionsUnionAllLoadedSourcesWithoutDuplicateTopics() throws {
        let options = CooperationInboxTopicFilter.options(in: try inbox())
        XCTAssertEqual(options.map(\.id), [301,302,303,304,305])
        XCTAssertEqual(options.first?.name, "Loaded route")
        XCTAssertNil(options.first(where: { $0.id == 303 })?.name)
    }
    func testUnknownNonpositiveAndUnloadedChoicesCannotCreateSelection() throws {
        let box = try inbox(), owner = NSObject(), scope = UUID()
        for id in [0,-1,999] { XCTAssertNil(CooperationInboxTopicFilter(topicID: id, inbox: box, owner: ObjectIdentifier(owner), scope: scope)) }
    }
    func testValidLoadedSelectionIsBoundToExactOwnerAndScope() throws {
        let owner = NSObject(), replacement = NSObject(), scope = UUID()
        let filter = try XCTUnwrap(CooperationInboxTopicFilter(topicID: 301, inbox: inbox(), owner: ObjectIdentifier(owner), scope: scope))
        XCTAssertEqual(filter.selectedTopic(owner: ObjectIdentifier(owner), scope: scope), 301)
        XCTAssertNil(filter.selectedTopic(owner: ObjectIdentifier(replacement), scope: scope))
        XCTAssertNil(filter.selectedTopic(owner: ObjectIdentifier(owner), scope: UUID()))
    }
    func testFilteredInvitationsPreserveDuplicatesAndOriginalOrdinals() throws {
        guard case .content(let list) = try inbox().invitations else { return XCTFail("Fixture") }
        let rows = CooperationInboxTopicFilter.visibleRows(list.received, topicID: 301, topic: { $0.topicId })
        XCTAssertEqual(rows.map(\.offset), [0,2]); XCTAssertEqual(rows.map { $0.element.id }, [1,1])
    }
    func testAllScopeIncludesMissingTopicRowsAndOriginalOrder() throws {
        guard case .content(let list) = try inbox().invitations else { return XCTFail("Fixture") }
        let rows = CooperationInboxTopicFilter.visibleRows(list.received, topicID: nil, topic: { $0.topicId })
        XCTAssertEqual(rows.map(\.offset), [0,1,2,3]); XCTAssertEqual(rows.map(\.element), list.received)
    }
    func testApplicationsUseTopicIDNotApplicationID() throws {
        guard case .content(let rows) = try inbox().applications else { return XCTFail("Fixture") }
        XCTAssertEqual(CooperationInboxTopicFilter.visibleRows(rows, topicID: 301, topic: { $0.topicId }).map { $0.element.applyId }, [1])
        XCTAssertTrue(CooperationInboxTopicFilter.visibleRows(rows, topicID: 1, topic: { $0.topicId }).isEmpty)
    }
    func testRegistrationsWithMissingTopicAreExcludedOnlyWhileScoped() throws {
        guard let section = try inbox().registrations, case .content(let page) = section else { return XCTFail("Fixture") }
        XCTAssertEqual(CooperationInboxTopicFilter.visibleRows(page.rows, topicID: 301, topic: { $0.topicId }).map(\.offset), [0])
        XCTAssertEqual(CooperationInboxTopicFilter.visibleRows(page.rows, topicID: nil, topic: { $0.topicId }).count, 3)
        XCTAssertEqual(page.hasMore, true)
    }
    func testPartialFailuresStayFailuresAndDoNotInventOptions() throws {
        let box = CooperationInbox(direction: .received, invitations: .failure(.failure), applications: .failure(.forbidden("No access")), registrations: .failure(.unavailable))
        XCTAssertTrue(box.isPartial); XCTAssertTrue(CooperationInboxTopicFilter.options(in: box).isEmpty)
        guard case .failure(let issue) = box.applications else { return XCTFail("Failure changed") }
        XCTAssertEqual(issue, .forbidden("No access"))
    }
    func testDirectionSwitchUsesSameTopicAndDoesNotAutoClearOnZeroMatches() throws {
        let owner = NSObject(), scope = UUID(), box = try inbox()
        let filter = try XCTUnwrap(CooperationInboxTopicFilter(topicID: 301, inbox: box, owner: ObjectIdentifier(owner), scope: scope))
        guard case .content(let list) = try inbox(direction: .sent).invitations else { return XCTFail("Fixture") }
        let selected = filter.selectedTopic(owner: ObjectIdentifier(owner), scope: scope)
        XCTAssertTrue(CooperationInboxTopicFilter.visibleRows(list.sent, topicID: selected, topic: { $0.topicId }).isEmpty)
        XCTAssertEqual(selected, 301)
    }
    func testClearSelectionRestoresEveryLoadedRowWithoutRefetch() throws {
        guard case .content(let list) = try inbox().invitations else { return XCTFail("Fixture") }
        let scoped = CooperationInboxTopicFilter.visibleRows(list.received, topicID: 301, topic: { $0.topicId })
        let restored = CooperationInboxTopicFilter.visibleRows(list.received, topicID: nil, topic: { $0.topicId })
        XCTAssertEqual(scoped.count, 2); XCTAssertEqual(restored.map(\.element), list.received)
    }
}
