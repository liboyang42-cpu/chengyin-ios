import XCTest
@testable import QuestifyCore

final class InvoiceHistoryUnknownProjectionTests: XCTestCase {
    func testSubmittedManualApplicationHasUnknownFileAndDoesNotStartNewApply() {
        var history = InvoiceHistoryUnknownProjection()
        let fact = InvoiceApplicationFact(originalRequestID: "c07-inv-1",
                                          status: InvoiceHistoryKnown.submitted,
                                          invoiceNo: nil, fileLocator: nil,
                                          provider: InvoiceHistoryKnown.manualProvider)
        let view = history.reread(fact)
        XCTAssertEqual(view.fileStatus, .unknown)
        XCTAssertFalse(view.startedNewApply)
        XCTAssertTrue(view.historyIsNotAFile)
        XCTAssertFalse(view.currentProjectionIsOriginalFileSuccess)
        XCTAssertEqual(view.originalRequestID, "c07-inv-1")
        XCTAssertEqual(view.applicationStatus, InvoiceHistoryKnown.submitted)
        XCTAssertEqual(history.requery(fact).fileStatus, view.fileStatus)
        XCTAssertTrue(history.originalUnknownNotReplacedByProjectionSuccess(
            view, projectionClaimsFileSuccess: true))
        XCTAssertEqual(history.recoverOriginal(originalRequestID: "c07-inv-1").fileStatus, .unknown)
    }
    func testIssuedInvoiceNoWithoutFileIsStillUnknown() {
        var history = InvoiceHistoryUnknownProjection()
        let fact = InvoiceApplicationFact(originalRequestID: "c07-inv-2",
                                          status: InvoiceHistoryKnown.issued,
                                          invoiceNo: "INV-9", fileLocator: "",
                                          provider: InvoiceHistoryKnown.manualProvider)
        let view = history.reread(fact)
        XCTAssertEqual(view.fileStatus, .unknown)
        XCTAssertFalse(view.startedNewApply)
        XCTAssertEqual(view.originalRequestID, "c07-inv-2")
        XCTAssertEqual(fact.invoiceNo, "INV-9")
        XCTAssertNil(fact.fileLocator)
    }
    func testBlankOriginalRequestIDDoesNotMintNewRequest() throws {
        var history = InvoiceHistoryUnknownProjection()
        let view = history.reread(
            InvoiceApplicationFact(originalRequestID: nil, status: InvoiceHistoryKnown.issued,
                                   invoiceNo: "INV-1", fileLocator: "file://x", provider: "OTHER"))
        XCTAssertNil(view.originalRequestID)
        XCTAssertEqual(view.fileStatus, .unknown)
        XCTAssertFalse(view.startedNewApply)
        let object = try JSONSerialization.jsonObject(
            with: try JSONSerialization.data(withJSONObject: view.jsonObject())) as! [String: Any]
        XCTAssertTrue(object["originalRequestID"] is NSNull)
        XCTAssertEqual(history.recoverOriginal(originalRequestID: "c07-inv-missing").fileStatus, .unknown)
        XCTAssertNil(history.recoverOriginal(originalRequestID: "c07-inv-missing").originalRequestID)
    }
    func testRecoverOfNeverSeenIdDoesNotOccupyLedgerThenPresentApplies() {
        var history = InvoiceHistoryUnknownProjection()
        XCTAssertEqual(history.recoverOriginal(originalRequestID: "c07-inv-never-seen").fileStatus, .unknown)
        let missing = InvoiceApplicationFact(originalRequestID: "c07-inv-never-seen",
                                             status: InvoiceHistoryKnown.submitted,
                                             invoiceNo: nil, fileLocator: nil,
                                             provider: InvoiceHistoryKnown.manualProvider)
        XCTAssertEqual(history.reread(missing).fileStatus, .unknown)
        XCTAssertEqual(history.recoverOriginal(originalRequestID: "c07-inv-never-seen").fileStatus, .unknown)
        let present = InvoiceApplicationFact(originalRequestID: "c07-inv-never-seen",
                                             status: InvoiceHistoryKnown.issued,
                                             invoiceNo: "INV-9", fileLocator: "file://x",
                                             provider: "OTHER")
        XCTAssertEqual(history.reread(present).fileStatus, .present)
        XCTAssertEqual(history.recoverOriginal(originalRequestID: "c07-inv-never-seen").fileStatus, .present)
    }
}
