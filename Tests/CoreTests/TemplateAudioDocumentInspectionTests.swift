import XCTest
@testable import QuestifyCore

final class TemplateAudioDocumentInspectionTests: XCTestCase {
    private func inspect(count: Int, reported: Int? = nil, fileExtension: String = "mp3",
                         requests: ((Int) -> Void)? = nil) throws -> TemplateAudioDocumentMetadata {
        var remaining = count
        return try TemplateAudioDocumentInspection.inspect(fileExtension: fileExtension, reportedByteCount: reported) { limit in
            requests?(limit)
            let length = min(limit, remaining)
            remaining -= length
            return Data(repeating: 0, count: length)
        }
    }

    func testOnlySourceExtensionsAreAcceptedWithoutBroadAudioFallback() throws {
        XCTAssertEqual(TemplateAudioDocumentMetadata.Format.allCases.map(\.rawValue), ["mp3", "m4a", "aac"])
        for name in ["mp3", "MP3", "m4a", "M4A", "aac", "AaC"] {
            XCTAssertEqual(try inspect(count: 1, fileExtension: name).format.rawValue, name.lowercased())
        }
        for name in ["", "wav", "mp4", "aiff", "flac", "ogg", ".mp3", "mp3 ", "mp3.exe", "audio/mpeg"] {
            XCTAssertThrowsError(try inspect(count: 1, fileExtension: name)) {
                XCTAssertEqual($0 as? TemplateAudioDocumentFailure, .unsupportedExtension)
            }
        }
    }

    func testOneByteAndExactlyTenMiBAreAccepted() throws {
        XCTAssertEqual(try inspect(count: 1).byteCount, 1)
        let cap = TemplateAudioDocumentInspection.maximumBytes
        XCTAssertEqual(cap, 10 * 1024 * 1024)
        XCTAssertEqual(try inspect(count: cap, reported: cap).byteCount, cap)
    }

    func testEmptyDocumentIsRejected() {
        for reported in [nil, 0] as [Int?] {
            XCTAssertThrowsError(try inspect(count: 0, reported: reported)) {
                XCTAssertEqual($0 as? TemplateAudioDocumentFailure, .empty)
            }
        }
    }

    func testKnownOversizeAndInvalidMetadataFailBeforeAnyRead() {
        for (reported, expected) in [(TemplateAudioDocumentInspection.maximumBytes + 1, TemplateAudioDocumentFailure.tooLarge),
                                     (-1, .unreadable), (Int.max, .tooLarge)] {
            var called = false
            XCTAssertThrowsError(try TemplateAudioDocumentInspection.inspect(fileExtension: "aac", reportedByteCount: reported) { _ in
                called = true; return Data()
            }) { XCTAssertEqual($0 as? TemplateAudioDocumentFailure, expected) }
            XCTAssertFalse(called)
        }
    }

    func testUnknownAndDishonestMetadataCannotBypassMeasuredCap() {
        let cap = TemplateAudioDocumentInspection.maximumBytes
        for reported in [nil, 1, cap] as [Int?] {
            var totalRead = 0
            XCTAssertThrowsError(try TemplateAudioDocumentInspection.inspect(fileExtension: "m4a", reportedByteCount: reported) { limit in
                totalRead += limit
                return Data(repeating: 0, count: limit)
            }) { XCTAssertEqual($0 as? TemplateAudioDocumentFailure, .tooLarge) }
            XCTAssertEqual(totalRead, cap + 1)
        }
    }

    func testReadRequestsAreBoundedIncludingOneByteOverflowProbe() throws {
        var requests: [Int] = []
        _ = try inspect(count: TemplateAudioDocumentInspection.maximumBytes) { requests.append($0) }
        XCTAssertTrue(requests.allSatisfy { $0 > 0 && $0 <= 64 * 1024 })
        XCTAssertEqual(requests.last, 1)
        XCTAssertEqual(requests.count, 161)
    }

    func testShortReadsContinueUntilEOF() throws {
        var calls = 0
        let metadata = try TemplateAudioDocumentInspection.inspect(fileExtension: "mp3", reportedByteCount: 3) { _ in
            calls += 1
            return calls <= 3 ? Data([0]) : Data()
        }
        XCTAssertEqual(metadata.byteCount, 3)
        XCTAssertEqual(calls, 4)
    }

    func testMetadataMismatchRejectsChangingDocument() {
        for pair in [(count: 1, reported: 2), (count: 2, reported: 1)] {
            XCTAssertThrowsError(try inspect(count: pair.count, reported: pair.reported)) {
                XCTAssertEqual($0 as? TemplateAudioDocumentFailure, .changedDuringRead)
            }
        }
    }

    func testBrokenReaderCannotReturnMoreThanRequested() {
        XCTAssertThrowsError(try TemplateAudioDocumentInspection.inspect(fileExtension: "mp3", reportedByteCount: nil) { limit in
            Data(repeating: 0, count: limit + 1)
        }) { XCTAssertEqual($0 as? TemplateAudioDocumentFailure, .invalidReader) }
    }

    func testReadFailureIsPropagatedWithoutReceipt() {
        struct SyntheticFailure: Error {}
        XCTAssertThrowsError(try TemplateAudioDocumentInspection.inspect(fileExtension: "mp3", reportedByteCount: nil) { _ in
            throw SyntheticFailure()
        }) { XCTAssertTrue($0 is SyntheticFailure) }
    }

    func testCancellationBeforeReadAndAfterEachChunkStopsInspection() {
        for cancellationCheck in [1, 3] {
            var checks = 0
            var reads = 0
            XCTAssertThrowsError(try TemplateAudioDocumentInspection.inspect(fileExtension: "aac", reportedByteCount: nil,
                checkCancellation: { checks += 1; if checks == cancellationCheck { throw CancellationError() } },
                readChunk: { _ in reads += 1; return Data([0]) })) { XCTAssertTrue($0 is CancellationError) }
            XCTAssertEqual(reads, cancellationCheck == 1 ? 0 : 1)
        }
    }

    func testInspectionIsExplicitlyNotAudioDecodeOrAttachmentEvidence() throws {
        // Intentionally not an audio fixture: extension + length do not prove audio decodability.
        let metadata = try inspect(count: 17, reported: 17, fileExtension: "m4a")
        XCTAssertEqual(metadata.evidence, .extensionAndByteCountOnly)
        XCTAssertEqual(metadata.byteCount, 17)
        XCTAssertEqual(Set(Mirror(reflecting: metadata).children.compactMap(\.label)), ["format", "byteCount", "evidence"])
    }

    func testRequestPurposesCoverQuestionFourOptionsAndNarrationWithDistinctIdentity() {
        let purposes: [TemplateAudioDocumentPurpose] = [.questionAudio, .optionAudio(.a), .optionAudio(.b),
                                                       .optionAudio(.c), .optionAudio(.d), .narration]
        let requests = purposes.map { TemplateAudioDocumentRequest(purpose: $0) }
        XCTAssertEqual(requests.map(\.purpose), purposes)
        XCTAssertEqual(Set(requests.map(\.id)).count, 6)
    }
}
