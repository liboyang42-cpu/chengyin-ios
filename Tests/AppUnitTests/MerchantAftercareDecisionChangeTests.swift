import XCTest
@testable import Questify

final class MerchantAftercareDecisionChangeTests: XCTestCase {
    private func harness() throws -> (MerchantBusinessEditorContext, MerchantBusinessSnapshot) {
        let query = MerchantBusinessQuery.refund(try .init(62001))
        let document = try MerchantBusinessDocument(query: query, payload: MerchantBusinessSyntheticFixtures.payload(query))
        let access = try MerchantBusinessAccess(XCTUnwrap(MerchantBusinessSyntheticFixtures.decode(MerchantBusinessSyntheticFixtures.access).object))
        let row = try XCTUnwrap(document.rows.first(where: { $0.kind == .refund }))
        return (.init(kind: .aftercare(row)), .init(access: access, document: document))
    }
    private func proposal(_ context: MerchantBusinessEditorContext, _ snapshot: MerchantBusinessSnapshot?, content: String = "Reason", evidence: String = "raw evidence") -> MerchantAftercareDecisionChange? {
        .init(context: context, snapshot: snapshot, decision: .reject, proposed: .agree, content: content, evidence: evidence)
    }
    func testNonblankExplanationRequiresExplicitDiscardWhileEmptyAndWhitespaceDoNot() throws {
        let (context, snapshot) = try harness()
        for text in ["", " \n\t "] { XCTAssertFalse(try XCTUnwrap(proposal(context, snapshot, content: text)).requiresDiscardConfirmation) }
        for text in ["Reason", "  Reason\n", "理由"] { XCTAssertTrue(try XCTUnwrap(proposal(context, snapshot, content: text)).requiresDiscardConfirmation) }
    }
    func testUnchangedAndUnavailableSourceChoicesDoNotCreateProposal() throws {
        let (context, snapshot) = try harness()
        XCTAssertNil(MerchantAftercareDecisionChange(context: context, snapshot: snapshot, decision: .agree, proposed: .agree, content: "Reason", evidence: "Evidence"))
        guard case .aftercare(let row) = context.kind else { return XCTFail() }
        var fields = row.fields; fields["allowedDecisions"] = .array([.string("EVIDENCE")])
        let restricted = try MerchantBusinessRecord(kind: .refund, fields: fields)
        let other = MerchantBusinessEditorContext(kind: .aftercare(restricted))
        let restrictedDocument = try MerchantBusinessDocument(query: snapshot.document.query, payload: .object(fields))
        let restrictedSnapshot = MerchantBusinessSnapshot(access: snapshot.access, document: restrictedDocument)
        XCTAssertNil(proposal(other, restrictedSnapshot))
    }
    func testProposalMatchesOnlyOriginalContextSnapshotAndText() throws {
        let (context, snapshot) = try harness(); let change = try XCTUnwrap(proposal(context, snapshot))
        XCTAssertEqual(change.proposed, .agree)
        XCTAssertTrue(change.matches(context: context, snapshot: snapshot, decision: .reject, content: "Reason", evidence: "raw evidence"))
        XCTAssertFalse(change.matches(context: .init(kind: context.kind), snapshot: snapshot, decision: .reject, content: "Reason", evidence: "raw evidence"))
        XCTAssertFalse(change.matches(context: context, snapshot: snapshot, decision: .evidence, content: "Reason", evidence: "raw evidence"))
        XCTAssertFalse(change.matches(context: context, snapshot: snapshot, decision: .reject, content: "Newer explanation", evidence: "raw evidence"))
        XCTAssertFalse(change.matches(context: context, snapshot: snapshot, decision: .reject, content: "Reason", evidence: "new evidence"))
    }
    func testMissingOrDifferentOwnerSnapshotRetiresProposal() throws {
        let (context, snapshot) = try harness(); let change = try XCTUnwrap(proposal(context, snapshot))
        XCTAssertNil(proposal(context, nil))
        XCTAssertFalse(change.matches(context: context, snapshot: nil, decision: .reject, content: "Reason", evidence: "raw evidence"))
        var access = try XCTUnwrap(MerchantBusinessSyntheticFixtures.decode(MerchantBusinessSyntheticFixtures.access).object)
        access["merchant"] = .object(["id": .int(611), "name": .string("Different store")])
        let other = MerchantBusinessSnapshot(access: try .init(access), document: snapshot.document)
        XCTAssertFalse(change.matches(context: context, snapshot: other, decision: .reject, content: "Reason", evidence: "raw evidence"))
    }
    func testDifferentEditorCaseAndSourceDocumentCannotReceiveDecisionChange() throws {
        let (context, snapshot) = try harness(); let change = try XCTUnwrap(proposal(context, snapshot))
        let note = MerchantBusinessEditorContext(kind: .note(try .init(61001), corrects: 901))
        XCTAssertNil(proposal(note, snapshot))
        XCTAssertFalse(change.matches(context: note, snapshot: snapshot, decision: .reject, content: "Reason", evidence: "raw evidence"))
        let query = MerchantBusinessQuery.customer(try .init(61001))
        let other = MerchantBusinessSnapshot(access: snapshot.access, document: try .init(query: query, payload: MerchantBusinessSyntheticFixtures.payload(query)))
        XCTAssertNil(proposal(context, other))
    }
    func testRawUnicodeAndWhitespaceChangesCannotClearNewerContentOrEvidence() throws {
        let (context, snapshot) = try harness()
        let change = try XCTUnwrap(proposal(context, snapshot, content: "Caf\u{00E9}", evidence: " Raw\u{00E9} "))
        XCTAssertTrue(change.matches(context: context, snapshot: snapshot, decision: .reject, content: "Caf\u{00E9}", evidence: " Raw\u{00E9} "))
        XCTAssertFalse(change.matches(context: context, snapshot: snapshot, decision: .reject, content: "Cafe\u{0301}", evidence: " Raw\u{00E9} "))
        XCTAssertFalse(change.matches(context: context, snapshot: snapshot, decision: .reject, content: "Caf\u{00E9}", evidence: " Rawe\u{0301} "))
        XCTAssertFalse(change.matches(context: context, snapshot: snapshot, decision: .reject, content: "Caf\u{00E9}", evidence: "Raw\u{00E9}"))
    }
    func testCreatingAndCheckingProposalLeavesOriginalOpinionAndEvidenceUntouched() throws {
        let (context, snapshot) = try harness()
        let original = MerchantBusinessMutation.aftercare(refund: try .init(62001), decision: .reject, content: "Reason", evidenceKey: nil)
        let before = try original.request(requestID: "unchanged-request")
        let change = try XCTUnwrap(proposal(context, snapshot)); _ = change.matches(context: context, snapshot: snapshot, decision: .reject, content: "Reason", evidence: "raw evidence")
        XCTAssertEqual(try original.request(requestID: "unchanged-request"), before)
        XCTAssertEqual(snapshot.document, try harness().1.document)
    }
}
