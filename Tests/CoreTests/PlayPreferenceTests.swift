import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

@available(macOS 14.0, *)
@MainActor final class PlayPreferenceTests: XCTestCase {
    private let questionnaire = #"{"nodeId":701,"steps":[{"key":"FIRST","type":"single","title":"Synthetic question","options":[{"key":"A","text":"Synthetic A"},{"key":"B","text":"Synthetic B"}]}],"inheritedTags":[{"id":81,"tagCode":"EXISTING","tagValue":"Synthetic condition","status":1}]}"#
    private func raw(_ text: String) throws -> PlayWireValue { try PlayExperienceSyntheticFixtures.wire(text) }
    private func session() throws -> PlayExperienceSession { try .init(accountID: 9001, epoch: 1, namespace: "synthetic-pref", token: "synthetic-token") }
    private func service(_ transport: any HTTPTransport) throws -> PlayExperienceService {
        .init(configuration: try APIConfiguration(baseURL: URL(string: "https://example.com/fixture/")!), transport: transport, enabled: [.reads,.preference,.tags])
    }
    func testQuestionnaireRejectsForeignNodeAndDuplicateOptions() throws {
        XCTAssertThrowsError(try PlayPreferenceQuestionnaire(raw(questionnaire), nodeID: 702))
        XCTAssertThrowsError(try PlayPreferenceStep(raw(#"{"key":"Q","type":"single","title":"Synthetic","options":[{"key":"A","text":"A"},{"key":"A","text":"B"}]}"#)))
    }
    func testDiscardRemainsServerChoiceInsteadOfClientScoring() throws {
        let step = try PlayPreferenceStep(raw(#"{"key":"Q","type":"discard","title":"Set one aside","options":[{"key":"A","text":"A"},{"key":"B","text":"B"}]}"#))
        XCTAssertEqual(step.type,"discard"); XCTAssertEqual(step.options.map(\.id),["A","B"])
    }
    func testMissingTiebreakAndMissingProgressAreUnknownShapes() throws {
        XCTAssertThrowsError(try PlayPreferenceSubmission(raw(#"{"needsTiebreak":true}"#),nodeID:701))
        XCTAssertThrowsError(try PlayPreferenceSubmission(raw(#"{"needsTiebreak":false,"evaluation":{"resultCode":"X","title":"Synthetic","body":"Synthetic"}}"#),nodeID:701))
    }
    func testTagConfirmationRequiresDisclosedRecipientAndPurpose() throws {
        let noDisclosure = try PlayPreferenceSubmission(raw(#"{"evaluation":{"resultCode":"X","title":"Synthetic","body":"Synthetic"},"progress":{"nodeId":701},"pendingTag":{"id":81,"tagCode":"X","tagValue":"Synthetic"}}"#),nodeID:701)
        XCTAssertFalse(noDisclosure.canDiscloseTag)
    }
    func testPreferenceSubmitUsesOnlyExactJSONFields() async throws {
        let transport=PlayPreferenceTestTransport { _ in (PlayExperienceSyntheticFixtures.envelope(#"{"evaluation":{"resultCode":"X","title":"Synthetic","body":"Synthetic"},"progress":{"nodeId":701}}"#),200) }
        let review=PlayPreferenceReview(choices:["FIRST":"A"],reusedTagCode:nil,advance:try .init(actionID:"same",expectedVersion:2),session:try session(),generation:1)
        _ = try await service(transport).submitPreference(scope:.topic(71),nodeID:701,review:review,token:"synthetic")
        let request=transport.requests[0],body=try JSONDecoder().decode(PlayWireValue.self,from:request.httpBody!)
        XCTAssertEqual(request.url?.path,"/fixture/api/play/preference/701/submit")
        XCTAssertEqual(request.value(forHTTPHeaderField:"Content-Type"),"application/json")
        XCTAssertEqual(Set(body.object!.keys),["topicId","choices","routeActionId","expectedRouteVersion"])
        XCTAssertEqual(body["choices"]["FIRST"],.string("A"));XCTAssertEqual(body["expectedRouteVersion"],.int(2))
    }
    func testTiebreakRetainsSourceRouteActionIdentity() async throws {
        let current = try session(), questionnaire = questionnaire
        let transport = PlayPreferenceTestTransport { request in
            let path = request.url?.path ?? ""
            if path.hasSuffix("/route-state") { return (PlayExperienceSyntheticFixtures.envelope(PlayExperienceSyntheticFixtures.route), 200) }
            if path.hasSuffix("/nodes") {
                return (PlayExperienceSyntheticFixtures.envelope(#"{"topicId":71,"mode":1,"playable":true,"nodes":[{"nodeId":701,"done":false,"validationMethod":6}],"routeState":{"routeMode":"BRANCH_GRAPH","sessionId":501,"status":"ACTIVE","version":2,"nodeStates":{"701":"PLAYABLE"}}}"#), 200)
            }
            if path.hasSuffix("/submit") {
                return (PlayExperienceSyntheticFixtures.envelope(#"{"needsTiebreak":true,"tiebreak":{"key":"TIE","type":"discard","title":"Synthetic tiebreak","options":[{"key":"C","text":"C"},{"key":"D","text":"D"}]}}"#),200)
            }
            return (PlayExperienceSyntheticFixtures.envelope(questionnaire),200)
        }
        let model=PlayPreferenceCoordinator(scope:.activity(41),nodeID:701,service:try service(transport),currentSession:{current})
        await model.load();model.select(stepID:"FIRST",optionID:"A");let first=try model.review();await model.submit(first)
        XCTAssertEqual(model.steps.count,2);model.select(stepID:"TIE",optionID:"C");let second=try model.review()
        XCTAssertEqual(first.advance,second.advance);XCTAssertEqual(second.choices,["FIRST":"A","TIE":"C"])
    }
    func testTagConfirmHasNoBodyAndCorrectionHasOneJSONField() async throws {
        let tag=try PlayPreferenceTag(raw(#"{"id":81,"tagCode":"X","tagValue":"A","status":0}"#))
        let transport=PlayPreferenceTestTransport { request in
            (PlayExperienceSyntheticFixtures.envelope(request.url?.path.hasSuffix("/confirm") == true ? #"{"id":81,"tagCode":"X","tagValue":"A","status":1}"# : #"{"id":81,"tagCode":"X","tagValue":"B","status":1}"#),200)
        }
        let api=try service(transport)
        _ = try await api.writePreferenceTag(tag,correctedValue:nil,token:"synthetic")
        _ = try await api.writePreferenceTag(tag,correctedValue:"B",token:"synthetic")
        XCTAssertNil(transport.requests[0].httpBody)
        let body=try JSONDecoder().decode(PlayWireValue.self,from:transport.requests[1].httpBody!)
        XCTAssertEqual(Set(body.object!.keys),["tagValue"])
    }
    func testOperatingSummaryKeepsUnknownCountsAndInvalidMapAnchorsOut() throws {
        let summary=try PlayOperatingSummary(raw(#"{"topicId":71,"tags":[{"id":81,"tagValue":"Synthetic","status":"REVOKED"}],"mapAnchors":[{"nodeId":1,"name":"Missing coordinates"},{"nodeId":2,"latitude":91,"longitude":0}],"actions7Days":[{"title":"Synthetic action"}]}"#),topicID:71)
        XCTAssertTrue(summary.tags[0].revoked);XCTAssertTrue(summary.anchors.isEmpty);XCTAssertEqual(summary.actions7Days,["Synthetic action"])
    }
    func testOperatingSummaryRejectsForeignTopicAndDuplicateTags() throws {
        XCTAssertThrowsError(try PlayOperatingSummary(raw(#"{"topicId":72}"#),topicID:71))
        XCTAssertThrowsError(try PlayOperatingSummary(raw(#"{"topicId":71,"tags":[{"id":81,"value":"A"},{"id":81,"value":"B"}]}"#),topicID:71))
    }
    func testRevokeRequiresAuthoritativeAbsenceOrRevokedReadback() async throws {
        let current=try session();var writes=0
        let transport=PlayPreferenceTestTransport { request in
            if request.httpMethod=="POST" {writes+=1;return (PlayExperienceSyntheticFixtures.envelope(#"{"id":81,"tagValue":"Synthetic","status":"REVOKED"}"#),200)}
            return (PlayExperienceSyntheticFixtures.envelope(#"{"topicId":71,"tags":[{"id":81,"tagValue":"Synthetic","status":"ACTIVE"}]}"#),200)
        }
        let model=PlayOperatingSummaryCoordinator(topicID:71,service:try service(transport),currentSession:{current})
        await model.load();await model.revoke(tagID:81)
        XCTAssertEqual(model.phase,"unknown");XCTAssertEqual(model.unresolvedTagIDs,[81]);await model.revoke(tagID:81);XCTAssertEqual(writes,1)
    }
}
private final class PlayPreferenceTestTransport:HTTPTransport {
    var requests:[URLRequest]=[]
    let response:@MainActor(URLRequest) async throws -> (Data,Int)
    init(_ response:@escaping @MainActor(URLRequest) async throws -> (Data,Int)){self.response=response}
    func send(_ request:URLRequest) async throws -> (Data,Int){requests.append(request);return try await response(request)}
}
