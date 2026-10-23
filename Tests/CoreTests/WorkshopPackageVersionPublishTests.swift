import XCTest
@testable import QuestifyCore

final class WorkshopPackageVersionPublishTests: XCTestCase {
    private let content = String(repeating: "ab", count: 32)
    private let terms = String(repeating: "cd", count: 32)
    private let other = String(repeating: "ef", count: 32)
    func testFreezeIsIdempotentForSameOriginalRequestID() throws {
        var publish = WorkshopPackageVersionPublish()
        XCTAssertThrowsError(try publish.freeze(contentHash: content, termsHash: terms,
                                                versionLabel: "1.0.0", originalRequestID: "req-p1",
                                                reviewed: false)) { error in
            XCTAssertEqual(error as? WorkshopPackagePublishFailure, .notReviewed)
        }
        try publish.freeze(contentHash: content, termsHash: terms, versionLabel: "1.0.0",
                           originalRequestID: "req-p1", reviewed: true)
        XCTAssertEqual(publish.publishCount, 1)
        try publish.republish(originalRequestID: "req-p1")
        XCTAssertEqual(publish.publishCount, 1)
        XCTAssertEqual(publish.frozen?.contentHash, content)
        XCTAssertEqual(publish.frozen?.termsHash, terms)
        XCTAssertEqual(publish.frozen?.versionLabel, "1.0.0")
    }
    func testMutatingFrozenHashWithoutNewVersionFails() throws {
        var publish = WorkshopPackageVersionPublish()
        try publish.freeze(contentHash: content, termsHash: terms, versionLabel: "1.0.0",
                           originalRequestID: "req-p1", reviewed: true)
        XCTAssertThrowsError(try publish.mutateFrozenHash(other, termsHash: terms,
                                                          versionLabel: "1.0.0",
                                                          originalRequestID: "req-p1")) { error in
            XCTAssertEqual(error as? WorkshopPackagePublishFailure, .frozenHashMutation)
        }
        XCTAssertEqual(publish.frozen?.contentHash, content)
        XCTAssertEqual(waiting { try publish.registerPublicAuthorPublish() }, .publicRegistryReserved)
        publish = WorkshopPackageVersionPublish()
        XCTAssertEqual(waiting { try publish.consumeModulePackOriginal() },
                       .waitingSource(capability: WorkshopModuleSourceInventory.modulePackOriginal))
        XCTAssertFalse(WorkshopModuleSourceInventory.modulePackOriginalPresent)
    }
    func testOtherRequestIdCannotMutateFrozenOriginal() throws {
        var publish = WorkshopPackageVersionPublish()
        try publish.freeze(contentHash: content, termsHash: terms, versionLabel: "1.0.0",
                           originalRequestID: "req-p1", reviewed: true)
        XCTAssertThrowsError(try publish.freeze(contentHash: content, termsHash: terms,
                                                versionLabel: "1.0.0", originalRequestID: "req-p-other",
                                                reviewed: true)) { error in
            XCTAssertEqual(error as? WorkshopPackagePublishFailure, .frozenHashMutation)
        }
        XCTAssertEqual(publish.frozen?.originalRequestID, "req-p1")
        XCTAssertEqual(publish.publishCount, 1)
        XCTAssertThrowsError(try publish.republish(originalRequestID: "req-p-other")) { error in
            XCTAssertEqual(error as? WorkshopPackagePublishFailure, .requestMismatch)
        }
        XCTAssertEqual(publish.frozen?.originalRequestID, "req-p1")
    }
    private func waiting(_ body: () throws -> Never) -> WorkshopPackagePublishFailure? {
        do { try body(); return nil } catch let error as WorkshopPackagePublishFailure { return error } catch { return nil }
    }
}
