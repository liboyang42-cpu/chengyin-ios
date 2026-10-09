import XCTest
@testable import QuestifyCore

final class ProjectEditIssueLocationTests: XCTestCase {
    private func issue(_ id: String, in draft: ProjectEditDraft, scope: ProjectEditScope = .full) throws -> ProjectEditIssue {
        try XCTUnwrap(ProjectEditValidation.issues(draft, scope: scope).first { $0.id == id })
    }
    func testKnownBasicFieldsUseExactAnchorsWithoutLocalizedTextMatching() throws {
        let draft = ProjectEditDraft(product: .freeExplore)
        for (id, anchor) in [("name", "name"), ("description", "description"), ("cover", "cover"),
                             ("categories", "categories"), ("start", "start"), ("end", "end"),
                             ("deadline", "deadline"), ("chapters", "chapters")] {
            XCTAssertEqual(ProjectEditIssueLocation.location(for: try issue(id, in: draft), in: draft, scope: .full),
                           .root(anchor: "project-issue-anchor-" + anchor))
        }
        XCTAssertNil(ProjectEditIssueLocation.location(for: .init("name", "made-up-label"), in: draft, scope: .full))
        XCTAssertNil(ProjectEditIssueLocation.location(for: .init("unknown", "projectEdit.validation.name"), in: draft, scope: .full))
    }
    func testChapterOrdinalIsResolvedToStableChapterIdentityAndNodeUsesExactID() throws {
        var draft = ProjectEditSyntheticFixtures.draft(product: .city)
        draft.chapters[0].description = ""; draft.chapters[0].blocks = nil
        let chapter = draft.chapters[0].id, node = draft.chapters[0].nodes[0].id
        draft.chapters[0].nodes[0].name = ""
        XCTAssertEqual(ProjectEditIssueLocation.location(for: try issue("story0", in: draft), in: draft, scope: .full),
                       .chapter(id: chapter, anchor: "project-issue-anchor-story"))
        XCTAssertEqual(ProjectEditIssueLocation.location(for: try issue("nodeName" + node, in: draft), in: draft, scope: .full),
                       .node(chapterID: chapter, nodeID: node, anchor: "project-issue-anchor-nodeName"))
    }
    func testTicketDestinationDoesNotParseAnIndexFromDigitsInsideItsID() throws {
        var draft = ProjectEditSyntheticFixtures.draft(product: .freeExplore)
        var ticket = ProjectEditTicket(); ticket.id = "ticket-901-3"; ticket.price = ""
        draft.tickets = [ticket]
        XCTAssertEqual(ProjectEditIssueLocation.location(for: try issue("price" + ticket.id, in: draft), in: draft, scope: .full),
                       .ticket(id: ticket.id, anchor: "project-issue-anchor-price"))
        let old = try issue("price" + ticket.id, in: draft); draft.tickets[0].price = "0"
        XCTAssertNil(ProjectEditIssueLocation.location(for: old, in: draft, scope: .full))
    }
    func testAmbiguousDuplicateNodeOrTicketIdentityAndWhitelistChildrenStayInert() throws {
        var draft = ProjectEditSyntheticFixtures.draft(product: .freeExplore)
        draft.chapters[0].nodes[0].name = ""
        let nodeID = draft.chapters[0].nodes[0].id
        var second = draft.chapters[0]; second.id = "another-chapter"; draft.chapters.append(second)
        let nodeIssue = try issue("nodeName" + nodeID, in: draft)
        XCTAssertNil(ProjectEditIssueLocation.location(for: nodeIssue, in: draft, scope: .full))
        XCTAssertNil(ProjectEditIssueLocation.location(for: nodeIssue, in: draft, scope: .whitelist))
        var ticket = ProjectEditTicket(); ticket.id = "duplicate"; ticket.price = ""
        draft.tickets = [ticket, ticket]
        XCTAssertNil(ProjectEditIssueLocation.location(for: try issue("price" + ticket.id, in: draft), in: draft, scope: .full))
    }
    func testStoryGameMissingTemplateLocatesGameplayInsteadOfAlreadyEmptyCoordinates() throws {
        var draft = ProjectEditSyntheticFixtures.draft(product: .city)
        let nodeID = draft.chapters[0].nodes[0].id
        draft.chapters[0].nodes[0].longitude = ""; draft.chapters[0].nodes[0].latitude = ""; draft.chapters[0].nodes[0].templateID = nil
        var block = ProjectEditBlock(kind: .node, nodeID: nodeID); block.sourceFields = ["locationRequired": .bool(false)]
        draft.chapters[0].blocks = [block]
        XCTAssertEqual(ProjectEditIssueLocation.location(for: try issue("coordinate" + nodeID, in: draft), in: draft, scope: .full),
                       .node(chapterID: draft.chapters[0].id, nodeID: nodeID, anchor: "project-issue-anchor-gameplay"))
    }
}
