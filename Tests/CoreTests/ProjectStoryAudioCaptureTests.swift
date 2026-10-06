import XCTest
@testable import QuestifyCore

final class ProjectStoryAudioCaptureTests: XCTestCase {
    private func copy(_ data: Data, name: String = "声音 e\u{301}.mp3", reported: Int? = nil) throws -> ProjectStorySelectedAudio {
        var offset = 0
        return try ProjectStoryAudioCapture.read(filename: name, reportedByteCount: reported, checkCancellation: {}, readChunk: { limit in
            let count = min(limit, data.count - offset); let chunk = data.subdata(in: offset..<(offset + count)); offset += count; return chunk
        })
    }
    func testActualSelectedBytesAndFilenameStayExactWithoutClaimingDecoding() throws {
        let bytes = Data("Opaque selected bytes, deliberately not a decodable MP3".utf8), name = "声音 e\u{301}.mp3"
        let selected = try copy(bytes, name: name, reported: bytes.count)
        XCTAssertEqual(selected.bytes, bytes); XCTAssertEqual(Array(selected.filename.utf8), Array(name.utf8))
        XCTAssertEqual(selected.metadata.format, .mp3); XCTAssertEqual(selected.metadata.byteCount, bytes.count)
        XCTAssertEqual(selected.metadata.evidence, .extensionAndByteCountOnly)
    }
    func testAllThreeSourceExtensionsAreAcceptedButVideoAndOtherTypesAreRejectedBeforeRead() throws {
        for ext in ["mp3", "m4a", "aac", "MP3"] {
            XCTAssertEqual(try copy(Data([1,2,3]), name: "fixture." + ext).metadata.format.rawValue, ext.lowercased())
        }
        for name in ["fixture.mp4", "fixture.wav", "fixture.pdf", "fixture"] {
            var reads = 0
            XCTAssertThrowsError(try ProjectStoryAudioCapture.read(filename: name, reportedByteCount: nil, checkCancellation: {}, readChunk: { _ in reads += 1; return Data() }))
            XCTAssertEqual(reads, 0)
        }
    }
    func testFilenameCannotInjectMultipartFieldsOrPathComponents() throws {
        for name in ["a\r\nowner=8.mp3", "a/b.mp3", "a\\b.mp3", "\u{0}a.mp3", String(repeating: "a", count: 256) + ".mp3"] {
            XCTAssertThrowsError(try copy(Data([1]), name: name))
        }
    }
    func testMeasuredByteLimitIsEnforcedWhenMetadataIsMissingOrIncorrect() throws {
        let maximum = TemplateAudioDocumentInspection.maximumBytes
        XCTAssertEqual(try copy(Data(repeating: 1, count: maximum)).bytes.count, maximum)
        XCTAssertThrowsError(try copy(Data(repeating: 1, count: maximum + 1))) { XCTAssertEqual($0 as? TemplateAudioDocumentFailure, .tooLarge) }
        XCTAssertThrowsError(try copy(Data([1,2,3]), reported: 2)) { XCTAssertEqual($0 as? TemplateAudioDocumentFailure, .changedDuringRead) }
        XCTAssertThrowsError(try copy(Data())) { XCTAssertEqual($0 as? TemplateAudioDocumentFailure, .empty) }
    }
    func testOversizedReportedSizeRejectsBeforeOpeningAnyStreamChunk() {
        var reads = 0
        XCTAssertThrowsError(try ProjectStoryAudioCapture.read(filename: "fixture.aac", reportedByteCount: TemplateAudioDocumentInspection.maximumBytes + 1, checkCancellation: {}, readChunk: { _ in reads += 1; return Data() }))
        XCTAssertEqual(reads, 0)
    }
    func testMisbehavingChunkReaderAndMidReadCancellationReturnNoSelection() {
        XCTAssertThrowsError(try ProjectStoryAudioCapture.read(filename: "fixture.m4a", reportedByteCount: nil, checkCancellation: {}, readChunk: { Data(repeating: 1, count: $0 + 1) })) {
            XCTAssertEqual($0 as? TemplateAudioDocumentFailure, .invalidReader)
        }
        var checks = 0, reads = 0
        XCTAssertThrowsError(try ProjectStoryAudioCapture.read(filename: "fixture.mp3", reportedByteCount: nil, checkCancellation: {
            checks += 1; if reads > 0 { throw CancellationError() }
        }, readChunk: { _ in reads += 1; return Data([1,2,3]) })) { XCTAssertTrue($0 is CancellationError) }
        XCTAssertEqual(reads, 1); XCTAssertGreaterThan(checks, 1)
    }
}
