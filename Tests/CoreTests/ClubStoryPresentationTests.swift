import XCTest
@testable import QuestifyCore

final class ClubStoryPresentationTests: XCTestCase {
    private let scope = ClubGovernanceScope(clubID: 81, topicID: 91)
    private let reader = NSObject(), access = NSObject()
    private func context(identity: ClubReadIdentity? = .init(accountID: 701, epoch: 1), revision: UInt64 = 4,
                         authorization: UUID? = nil, reader: ObjectIdentifier? = nil, access: ObjectIdentifier? = nil,
                         scope: ClubGovernanceScope? = nil) -> ClubGovernanceReadContext {
        .init(operation: .topicOverview, scope: scope ?? self.scope, identity: identity, viewerRevision: revision,
            authorizationGeneration: authorization, readerIdentity: reader ?? ObjectIdentifier(self.reader),
            accessIdentity: access ?? ObjectIdentifier(self.access))
    }
    private func permissions(_ canAnswer: Bool = true) throws -> ClubGovernancePermissions {
        try .init(value: .object(["active": .bool(true), "club": .object(["id": .integer(81)]),
            "roleCodes": .array([.string("CLUB_MEMBER")]),
            "permissions": .array(canAnswer ? [.string("club:content:manage")] : [])]), scope: scope)
    }
    private func template(_ id: ClubGovernanceValue = .integer(501), _ changes: [String: ClubGovernanceValue] = [:]) -> ClubGovernanceValue {
        var value: [String: ClubGovernanceValue] = ["id": id, "title": .string(" Find the sign "), "validationMethod": .integer(1),
            "validationMethodStr": .string(" Text answer "), "players": .string("2–4"), "duration": .integer(20),
            "difficulty": .integer(3), "imgUrl": .string("https://example.invalid/template.jpg")]
        value.merge(changes) { _, new in new }; return .object(value)
    }
    private func node(_ id: ClubGovernanceValue = .integer(301), template: ClubGovernanceValue? = nil,
                      _ changes: [String: ClubGovernanceValue] = [:]) -> ClubGovernanceValue {
        var value: [String: ClubGovernanceValue] = ["id": id, "name": .string(" Archive "), "address": .string(" Fixture lane "),
            "businessTime": .string("09:00–18:00"), "imgUrl": .string("https://example.invalid/node.jpg"),
            "cmsMemberTemplate": template ?? self.template()]
        value.merge(changes) { _, new in new }; return .object(value)
    }
    private func chapter(_ id: ClubGovernanceValue = .integer(201), nodes: [ClubGovernanceValue]? = nil,
                         _ changes: [String: ClubGovernanceValue] = [:]) -> ClubGovernanceValue {
        var value: [String: ClubGovernanceValue] = ["id": id, "name": .string(" Arrival "),
            "description": .string(" Find the archive. "), "totalTime": .integer(90), "nodes": .array(nodes ?? [node()])]
        value.merge(changes) { _, new in new }; return .object(value)
    }
    private func snapshot(_ chapters: [ClubGovernanceValue]? = nil, canAnswer: Bool = true,
                          _ changes: [String: ClubGovernanceValue] = [:]) throws -> ClubGovernanceSnapshot {
        var value: [String: ClubGovernanceValue] = ["id": .integer(91), "name": .string("Synthetic topic"), "chaptersList": .array(chapters ?? [chapter()])]
        value.merge(changes) { _, new in new }
        return .init(operation: .topicOverview, scope: scope, permissions: try permissions(canAnswer), value: .object(value))
    }
    private func game(_ snapshot: ClubGovernanceSnapshot) throws -> ClubStoryGameplay {
        try XCTUnwrap(ClubStoryPresentation(snapshot: snapshot).chapters.first?.gameplay.first)
    }
    private func templateRoute(_ snapshot: ClubGovernanceSnapshot, context: ClubGovernanceReadContext? = nil) throws -> ClubStoryTemplateRoute? {
        .init(gameplay: try game(snapshot), snapshot: snapshot, context: context ?? self.context(), snapshotGeneration: 7)
    }
    private func answerRoute(_ snapshot: ClubGovernanceSnapshot, context: ClubGovernanceReadContext? = nil) throws -> ClubStoryAnswerRoute? {
        .init(gameplay: try game(snapshot), snapshot: snapshot, context: context ?? self.context(), snapshotGeneration: 7)
    }

    func testTypedProjectionUsesExactSourceFieldsAndMemberTemplateNamespace() throws {
        let value = try ClubStoryPresentation(snapshot: snapshot()), chapter = try XCTUnwrap(value.chapters.first)
        let stop = try XCTUnwrap(chapter.stops.first), gameplay = try XCTUnwrap(chapter.gameplay.first)
        XCTAssertEqual(value.topicID, 91); XCTAssertEqual(chapter.chapterID, 201); XCTAssertEqual(chapter.id, 0)
        XCTAssertEqual(chapter.name, "Arrival"); XCTAssertEqual(chapter.description, "Find the archive."); XCTAssertEqual(chapter.totalTime, 90)
        XCTAssertEqual(stop.nodeID, 301); XCTAssertEqual(stop.sequence, 1); XCTAssertEqual(stop.businessTime, "09:00–18:00")
        XCTAssertEqual(stop.name, "Archive"); XCTAssertEqual(stop.address, "Fixture lane"); XCTAssertEqual(stop.imgUrl, "https://example.invalid/node.jpg")
        XCTAssertEqual(gameplay.chapterID, 201); XCTAssertEqual(gameplay.nodeID, 301)
        XCTAssertEqual(gameplay.memberTemplateID, MemberPlayTemplateID(rawValue: 501))
        XCTAssertEqual(gameplay.title, "Find the sign"); XCTAssertEqual(gameplay.validationMethod, 1)
        XCTAssertEqual(gameplay.validationMethodLabel, "Text answer"); XCTAssertEqual(gameplay.players, "2–4")
        XCTAssertEqual(gameplay.duration, 20); XCTAssertEqual(gameplay.difficulty, "3"); XCTAssertTrue(gameplay.isAnswerable)
        XCTAssertEqual(gameplay.imgUrl, "https://example.invalid/template.jpg")
    }
    func testSequenceContinuesAcrossChaptersAndNodesWithoutGames() throws {
        let snap = try snapshot([chapter(nodes: [node(template: .null), node(.integer(302))]),
            chapter(.integer(202), nodes: [node(.integer(303), template: template(.integer(502)))])])
        let result = try ClubStoryPresentation(snapshot: snap)
        XCTAssertEqual(result.chapters.flatMap(\.stops).map(\.sequence), [1, 2, 3])
        XCTAssertEqual(result.chapters.flatMap(\.gameplay).map(\.sequence), [2, 3])
        XCTAssertEqual(result.chapters.flatMap(\.stops).map(\.id), [1, 2, 3])
    }
    func testEmptyChaptersAndMissingOptionalListsRemainDisplayable() throws {
        XCTAssertTrue(try ClubStoryPresentation(snapshot: snapshot([])).chapters.isEmpty)
        XCTAssertTrue(try ClubStoryPresentation(snapshot: snapshot(nil, canAnswer: true, ["chaptersList": .null])).chapters.isEmpty)
        let value = try ClubStoryPresentation(snapshot: snapshot([chapter(nodes: [])]))
        XCTAssertEqual(value.chapters.count, 1); XCTAssertTrue(value.chapters[0].stops.isEmpty); XCTAssertTrue(value.chapters[0].gameplay.isEmpty)
        XCTAssertTrue(try ClubStoryPresentation(snapshot: snapshot([chapter(nilID, nodes: nil, ["nodes": .null])])).chapters[0].stops.isEmpty)
    }
    private var nilID: ClubGovernanceValue { .null }
    func testMalformedNestedListsFailInsteadOfPretendingTheRouteIsEmpty() throws {
        for value in [ClubGovernanceValue.bool(false), .object([:]), .string("missing"), .array([.null])] {
            XCTAssertThrowsError(try ClubStoryPresentation(snapshot: snapshot(nil, canAnswer: true, ["chaptersList": value])))
            XCTAssertThrowsError(try ClubStoryPresentation(snapshot: snapshot([chapter(.integer(201), nodes: nil, ["nodes": value])])))
        }
        for value in [ClubGovernanceValue.bool(false), .array([]), .string("missing")] {
            XCTAssertThrowsError(try ClubStoryPresentation(snapshot: snapshot([chapter(nodes: [node(template: value)])])))
        }
    }
    func testMissingInvalidAndDuplicateIDsPreserveContentButDisableEveryAction() throws {
        let invalid: [ClubGovernanceValue] = [.null, .integer(0), .integer(-1), .integer(Int.max), .decimal(1.5), .bool(true), .string("wrong")]
        for id in invalid {
            for chapters in [[chapter(id)], [chapter(nodes: [node(id)])], [chapter(nodes: [node(template: template(id))])]] {
                let snap = try snapshot(chapters), gameplay = try game(snap)
                XCTAssertEqual(gameplay.title, "Find the sign"); XCTAssertNil(gameplay.chapterID); XCTAssertNil(gameplay.nodeID); XCTAssertNil(gameplay.memberTemplateID)
                XCTAssertNil(try templateRoute(snap)); XCTAssertNil(try answerRoute(snap))
            }
        }
        let duplicateSets = [
            [chapter(), chapter(nodes: [node(.integer(302), template: template(.integer(502)))])],
            [chapter(), chapter(.integer(202), nodes: [node(template: template(.integer(502)))])],
            [chapter(), chapter(.integer(202), nodes: [node(.integer(302))])]
        ]
        for chapters in duplicateSets {
            let snap = try snapshot(chapters), all = try ClubStoryPresentation(snapshot: snap).chapters.flatMap(\.gameplay)
            XCTAssertEqual(all.count, 2)
            for item in all {
                XCTAssertNil(item.nodeID); XCTAssertNil(item.memberTemplateID)
                XCTAssertNil(ClubStoryTemplateRoute(gameplay: item, snapshot: snap, context: context(), snapshotGeneration: 7))
                XCTAssertNil(ClubStoryAnswerRoute(gameplay: item, snapshot: snap, context: context(), snapshotGeneration: 7))
            }
        }
    }
    func testEquivalentStringAndIntegerIDsAreDuplicateAndSafeIntegerLimitIsEnforced() throws {
        let duplicate = try snapshot([chapter(nodes: [node(), node(.string(" 301 "), template: template(.integer(502)))])])
        XCTAssertTrue(try ClubStoryPresentation(snapshot: duplicate).chapters[0].gameplay.allSatisfy { $0.nodeID == nil })
        let exact = try snapshot([chapter(.string("201"), nodes: [node(.decimal(301), template: template(.string("501")))])])
        XCTAssertEqual(try templateRoute(exact)?.templateID.rawValue, 501)
        let tooLarge = try snapshot([chapter(nodes: [node(template: template(.string("9007199254740992")))])])
        XCTAssertNil(try templateRoute(tooLarge))
    }
    func testUnknownAndNonPositiveDurationsAreNotZeroOrInventedEstimates() throws {
        for value in [ClubGovernanceValue.null, .integer(0), .integer(-1), .string("unknown"), .bool(false), .decimal(.infinity)] {
            let snap = try snapshot([chapter(.integer(201), nodes: [node(template: template(.integer(501), ["duration": value]))], ["totalTime": value])])
            let result = try ClubStoryPresentation(snapshot: snap)
            XCTAssertNil(result.chapters[0].totalTime); XCTAssertNil(result.chapters[0].gameplay[0].duration)
        }
        let snap = try snapshot([chapter(.integer(201), nodes: [node(template: template(.integer(501), ["duration": .string("12.5")]))], ["totalTime": .decimal(60.5)])])
        XCTAssertEqual(try game(snap).duration, 12.5)
        XCTAssertEqual(try ClubStoryPresentation(snapshot: snap).chapters[0].totalTime, 60.5)
    }
    func testTitleAndCoverFallbackUseOnlyTheSourceNodeAndSafeMedia() throws {
        let snap = try snapshot([chapter(nodes: [node(template: template(.integer(501), ["title": .string(" "), "imgUrl": .null]))])])
        XCTAssertEqual(try game(snap).title, "Archive"); XCTAssertEqual(try game(snap).imgUrl, "https://example.invalid/node.jpg")
        for image in ["http://example.invalid/a.jpg", "file:///tmp/a.jpg", "data:image/png;base64,a", "object/a.jpg", "https://user:pass@example.invalid/a.jpg", "https://example.invalid/%QQ", "https://example.invalid/a\nb.jpg", String(repeating: "x", count: 8193)] {
            let value = ClubGovernanceValue.string(image)
            let result = try ClubStoryPresentation(snapshot: snapshot([chapter(nodes: [node(template: template(.integer(501), ["imgUrl": value]), ["imgUrl": value])])]))
            XCTAssertNil(result.chapters[0].stops[0].imgUrl); XCTAssertNil(result.chapters[0].gameplay[0].imgUrl)
        }
    }
    func testOnlyTextAndChoiceMethodsCanRequestAnswersAndStillNeedPermission() throws {
        for method in [ClubGovernanceValue.integer(1), .string("3"), .decimal(3)] {
            let snap = try snapshot([chapter(nodes: [node(template: template(.integer(501), ["validationMethod": method]))])])
            XCTAssertTrue(try game(snap).isAnswerable); XCTAssertNotNil(try answerRoute(snap))
        }
        for method in [ClubGovernanceValue.null, .bool(true), .integer(0), .integer(2), .integer(4), .integer(5), .integer(6), .integer(7), .integer(99), .string("")] {
            let snap = try snapshot([chapter(nodes: [node(template: template(.integer(501), ["validationMethod": method]))])])
            XCTAssertFalse(try game(snap).isAnswerable); XCTAssertNil(try answerRoute(snap)); XCTAssertNotNil(try templateRoute(snap))
        }
        let snap = try snapshot(canAnswer: false)
        XCTAssertTrue(try game(snap).isAnswerable); XCTAssertNil(try answerRoute(snap)); XCTAssertNotNil(try templateRoute(snap))
    }
    func testRoutesUseExactMemberTemplateAndNodeIDsWithoutPublicLibraryFallback() throws {
        let snap = try snapshot(), template = try XCTUnwrap(templateRoute(snap)), answer = try XCTUnwrap(answerRoute(snap))
        XCTAssertEqual(template.templateID, MemberPlayTemplateID(rawValue: 501)); XCTAssertEqual(answer.nodeID, 301)
        XCTAssertEqual(answer.scope, .init(clubID: 81, topicID: 91, nodeID: 301))
        XCTAssertEqual(try ClubGovernanceRead.topicOverview.fields(scope: scope), ["id": .string("91")])
        XCTAssertEqual(try ClubGovernanceRead.nodeAnswer.fields(scope: answer.scope), ["clubId": .integer(81), "topicId": .integer(91), "nodeId": .integer(301)])
        XCTAssertEqual(ClubGovernanceRead.nodeAnswer.permission, "club:content:manage")
    }
    func testWrongReadScopeTopicOrMissingAccessCannotCreatePresentation() throws {
        let valid = try snapshot()
        for snap in [ClubGovernanceSnapshot(operation: .topicSettings, scope: scope, permissions: valid.permissions, value: valid.value),
            .init(operation: .topicOverview, scope: .init(topicID: 91), permissions: valid.permissions, value: valid.value),
            .init(operation: .topicOverview, scope: .init(clubID: 82, topicID: 91), permissions: valid.permissions, value: valid.value),
            .init(operation: .topicOverview, scope: scope, permissions: nil, value: valid.value),
            try snapshot(nil, canAnswer: true, ["id": .integer(92)])] {
            XCTAssertThrowsError(try ClubStoryPresentation(snapshot: snap))
        }
    }
    func testRefreshAccountEpochReaderAuthorityAndScopeChangesExpireBothRoutes() throws {
        let snap = try snapshot(), template = try XCTUnwrap(templateRoute(snap)), answer = try XCTUnwrap(answerRoute(snap)), replacement = NSObject()
        let variants = [context(identity: nil), context(identity: .init(accountID: 702, epoch: 1)),
            context(identity: .init(accountID: 701, epoch: 2)), context(revision: 5), context(revision: 6), context(authorization: UUID()),
            context(reader: ObjectIdentifier(replacement)), context(access: ObjectIdentifier(replacement)), context(scope: .init(clubID: 81, topicID: 92))]
        for changed in variants {
            XCTAssertFalse(template.isCurrent(snapshot: snap, context: changed, snapshotGeneration: 7))
            XCTAssertFalse(answer.isCurrent(snapshot: snap, context: changed, snapshotGeneration: 7))
        }
        for changedGeneration in [UInt64(0), 8] {
            XCTAssertFalse(template.isCurrent(snapshot: snap, context: context(), snapshotGeneration: changedGeneration))
            XCTAssertFalse(answer.isCurrent(snapshot: snap, context: context(), snapshotGeneration: changedGeneration))
        }
        XCTAssertFalse(template.isCurrent(snapshot: nil, context: context(), snapshotGeneration: 7))
        XCTAssertFalse(answer.isCurrent(snapshot: nil, context: context(), snapshotGeneration: 7))
    }
    func testAnyChangedSourceFieldAndRemovedOrReplacedRowsExpireSelection() throws {
        let snap = try snapshot(), template = try XCTUnwrap(templateRoute(snap)), answer = try XCTUnwrap(answerRoute(snap))
        let variants = [try snapshot([]), try snapshot([chapter(nodes: [])]),
            try snapshot([chapter(nodes: [node(.integer(302))])]),
            try snapshot([chapter(nodes: [node(template: self.template(.integer(502)))])]),
            try snapshot([chapter(.integer(202))]), try snapshot(nil, canAnswer: true, ["unrenderedSourceField": .string("changed")]),
            try snapshot([chapter(.integer(201), nodes: nil, ["description": .string("Changed story")])])]
        for changed in variants {
            XCTAssertFalse(template.isCurrent(snapshot: changed, context: context(), snapshotGeneration: 7))
            XCTAssertFalse(answer.isCurrent(snapshot: changed, context: context(), snapshotGeneration: 7))
        }
        XCTAssertTrue(template.isCurrent(snapshot: snap, context: context(), snapshotGeneration: 7))
        XCTAssertTrue(answer.isCurrent(snapshot: snap, context: context(), snapshotGeneration: 7))
    }
    func testPermissionLossDisablesAnswerAndForeignGameplayCannotSelect() throws {
        let snap = try snapshot(), route = try XCTUnwrap(answerRoute(snap)), denied = try snapshot(canAnswer: false)
        XCTAssertFalse(route.isCurrent(snapshot: denied, context: context(), snapshotGeneration: 7))
        let foreign = try game(snapshot([chapter(nodes: [node(template: template(.integer(502)))])]))
        XCTAssertNil(ClubStoryTemplateRoute(gameplay: foreign, snapshot: snap, context: context(), snapshotGeneration: 7))
        XCTAssertNil(ClubStoryAnswerRoute(gameplay: foreign, snapshot: snap, context: context(), snapshotGeneration: 7))
        let missingAccess = ClubGovernanceReadContext(operation: .topicOverview, scope: scope, identity: .init(accountID: 701, epoch: 1), viewerRevision: 4, authorizationGeneration: nil)
        XCTAssertNil(try templateRoute(snap, context: missingAccess)); XCTAssertNil(try answerRoute(snap, context: missingAccess))
    }
    func testProjectionNeverRetainsProtectedTemplateAndNodeFields() throws {
        let plain = try snapshot(), privateFields: [String: ClubGovernanceValue] = ["answer": .string("private"), "answerReveal": .string("private"),
            "hints": .array([.string("private")]), "feedbackText": .string("private"), "secretStory": .string("private"),
            "questionAnswer": .string("private"), "token": .string("private"), "phone": .string("private")]
        let withPrivateFields = try snapshot([chapter(nodes: [node(template: template(.integer(501), privateFields), privateFields)])])
        XCTAssertEqual(try ClubStoryPresentation(snapshot: plain), try ClubStoryPresentation(snapshot: withPrivateFields))
        XCTAssertFalse(String(describing: try game(withPrivateFields)).contains("private"))
    }
}
