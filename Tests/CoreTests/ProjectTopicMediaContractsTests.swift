import Foundation
import CryptoKit
import XCTest
@testable import QuestifyCore

/// Synthetic inspection reports test the Core seam. They do not decode any real
/// image/movie or prove that the future PhotosUI/file inspector is implemented.
enum ProjectTopicMediaTestSupport {
    static func context(account: Int = 7, epoch: UInt64 = 1, namespace: String = "topic-media",
                        viewer: UInt64 = 0, configuration: UInt64 = 0, revision: UInt64 = 1,
                        visit: UUID = UUID(uuidString: "00000000-0000-0000-0000-000000000010")!,
                        identity: ProjectEditDraftIdentity? = nil, product: ProjectEditProduct = .city,
                        owner: ProjectEditOwner = .personal) throws -> ProjectTopicMediaContext {
        try .init(session: .init(accountID: account, epoch: epoch, storageNamespace: namespace,
                                 viewerRevision: viewer, configurationRevision: configuration),
                  identity: identity ?? .init(draftUUID: "00000000-0000-0000-0000-000000000011"),
                  product: product, owner: owner, publishMode: "pro", editScope: .full,
                  draftRevision: revision, visit: visit)
    }
    static func policy(id: UUID = UUID(uuidString: "00000000-0000-0000-0000-000000000012")!,
                       revision: UInt64 = 1, items: UInt64 = 3, total: UInt64 = 100,
                       bytes: UInt64 = 50, width: UInt64 = 10, height: UInt64 = 10,
                       pixels: UInt64 = 100, duration: UInt64 = 1000,
                       mixing: ProjectTopicMediaPolicy.Mixing = .mixed) throws -> ProjectTopicMediaPolicy {
        // These numbers are explicit synthetic test policy, not production defaults.
        try .init(id: id, revision: revision, maximumItems: items, maximumTotalBytes: total, mixing: mixing, kinds: [
            .init(kind: .image, mimeTypes: ["image/jpeg"], maximumBytes: bytes, maximumWidth: width,
                  maximumHeight: height, maximumPixels: pixels, maximumDurationMilliseconds: nil),
            .init(kind: .video, mimeTypes: ["video/mp4"], maximumBytes: bytes, maximumWidth: width,
                  maximumHeight: height, maximumPixels: pixels, maximumDurationMilliseconds: duration)
        ])
    }
    static func reference() -> ProjectTopicMediaLocalReference { .init(id: UUID(), revision: UUID()) }
    static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    static func request(policy: ProjectTopicMediaPolicy? = nil) throws -> ProjectTopicMediaInspectionRequest {
        let context = try Self.context(), resolvedPolicy = try policy ?? Self.policy()
        let selection = ProjectTopicMediaSelection(context: context, policy: resolvedPolicy)
        let ticket = try XCTUnwrap(selection.begin(visit: selection.visit, context: context, policy: resolvedPolicy))
        return try XCTUnwrap(selection.prepareInspection([reference()], ticket: ticket, context: context, policy: resolvedPolicy)?.first)
    }
    final class Inspector: ProjectTopicMediaInspecting {
        var chunks = [Data("abcd".utf8)]
        var kind: ProjectTopicMediaKind = .image
        var mime = "image/jpeg"
        var width: UInt64 = 4, height: UInt64 = 4
        var duration: UInt64?
        var wrongRequest = false, wrongReference = false, wrongDigest = false, wrongSize = false, missingChecks = false
        var swallowConsumerFailure = false
        var calls = 0
        func inspect(_ request: ProjectTopicMediaInspectionRequest, consume: (Data) throws -> Void) throws -> ProjectTopicMediaInspectionReport {
            calls += 1; var consumed = Data()
            for chunk in chunks {
                do { try consume(chunk); consumed.append(chunk) }
                catch { if !swallowConsumerFailure { throw error } }
            }
            var checks: Set<ProjectTopicMediaInspectionReport.Check> = [.regularAppManagedFile, .containerRecognized, .metadataDecoded]
            if kind == .image { checks.insert(.imageDecoded) }
            else { checks.formUnion([.videoTrackInspected, .durationMeasured]) }
            if missingChecks { checks.remove(.containerRecognized) }
            return .init(requestID: wrongRequest ? UUID() : request.id,
                         reference: wrongReference ? ProjectTopicMediaTestSupport.reference() : request.reference,
                         kind: kind, mimeType: mime, byteCount: wrongSize ? UInt64.max : UInt64(consumed.count),
                         width: width, height: height, durationMilliseconds: duration,
                         decodedContentSHA256: wrongDigest ? String(repeating: "0", count: 64) : ProjectTopicMediaTestSupport.hash(consumed), checks: checks)
        }
    }
    static func accepted() throws -> ProjectTopicMediaSelection.LocalSelectionIntent {
        let context = try Self.context(), policy = try Self.policy()
        let selection = ProjectTopicMediaSelection(context: context, policy: policy)
        let ticket = try XCTUnwrap(selection.begin(visit: selection.visit, context: context, policy: policy))
        let requests = try XCTUnwrap(selection.prepareInspection([reference()], ticket: ticket, context: context, policy: policy))
        let evidence = try requests.map { try ProjectTopicMediaInspectionEvidence.inspect($0, using: Inspector()) }
        let preview = try XCTUnwrap(selection.finishInspection(evidence, ticket: ticket, context: context, policy: policy))
        return try XCTUnwrap(selection.confirm(preview, context: context, policy: policy))
    }
}

final class ProjectTopicMediaContractsTests: XCTestCase {
    private typealias F = ProjectTopicMediaTestSupport
    func testPolicyRequiresAllPositiveLimitsKnownKindsAndExactMIMEFamilies() throws {
        let valid = try F.policy()
        XCTAssertThrowsError(try ProjectTopicMediaPolicy(id: UUID(), revision: 1, maximumItems: 0, maximumTotalBytes: 1, mixing: .mixed, kinds: valid.kinds))
        XCTAssertThrowsError(try ProjectTopicMediaPolicy(id: UUID(), revision: 1, maximumItems: 1, maximumTotalBytes: 0, mixing: .mixed, kinds: valid.kinds))
        XCTAssertThrowsError(try ProjectTopicMediaPolicy(id: UUID(), revision: 1, maximumItems: 1, maximumTotalBytes: 1, mixing: .mixed, kinds: []))
        XCTAssertThrowsError(try ProjectTopicMediaPolicy(id: UUID(), revision: 1, maximumItems: 1, maximumTotalBytes: 1, mixing: .mixed, kinds: [valid.kinds[0], valid.kinds[0]]))
        for mime in ["video/mp4", "IMAGE/JPEG", "image/jpeg; quality=1", "image/", "image/a/b", "https://example.invalid/x"] {
            XCTAssertThrowsError(try ProjectTopicMediaPolicy.KindLimit(kind: .image, mimeTypes: [mime], maximumBytes: 1, maximumWidth: 1, maximumHeight: 1, maximumPixels: 1, maximumDurationMilliseconds: nil))
        }
        XCTAssertThrowsError(try ProjectTopicMediaPolicy.KindLimit(kind: .video, mimeTypes: ["video/mp4"], maximumBytes: 1, maximumWidth: 1, maximumHeight: 1, maximumPixels: 1, maximumDurationMilliseconds: nil))
        XCTAssertThrowsError(try ProjectTopicMediaPolicy.KindLimit(kind: .image, mimeTypes: ["image/jpeg"], maximumBytes: 1, maximumWidth: 1, maximumHeight: 1, maximumPixels: 1, maximumDurationMilliseconds: 1))
        XCTAssertThrowsError(try F.policy(width: 0)); XCTAssertThrowsError(try F.policy(height: 0)); XCTAssertThrowsError(try F.policy(pixels: 0)); XCTAssertThrowsError(try F.policy(bytes: 0)); XCTAssertThrowsError(try F.policy(duration: 0))
    }
    func testContextRejectsMissingOrConflictingIdentityAndNonProfessionalOrWhitelistScope() throws {
        let good = try F.context()
        for raw in ["{}", "{\"topicID\":1,\"draftUUID\":\"00000000-0000-0000-0000-000000000011\"}", "{\"topicID\":0}", "{\"draftUUID\":\"https://example.invalid/video.mp4\"}"] {
            let identity = try JSONDecoder().decode(ProjectEditDraftIdentity.self, from: Data(raw.utf8))
            XCTAssertThrowsError(try ProjectTopicMediaContext(session: good.session, identity: identity, product: .city, owner: .personal, publishMode: "pro", editScope: .full, draftRevision: 1, visit: UUID()))
        }
        for (mode, scope) in [("simple", ProjectEditScope.full), ("pro", .whitelist)] {
            XCTAssertThrowsError(try ProjectTopicMediaContext(session: good.session, identity: good.identity, product: .city, owner: .personal, publishMode: mode, editScope: scope, draftRevision: 1, visit: UUID()))
        }
        XCTAssertEqual(try F.context(product: .freeExplore).product, .freeExplore)
        XCTAssertEqual(try F.context(identity: .init(topicID: 42)).identity.topicID, 42)
    }
    func testNamespaceUsesExactUTF8RatherThanCanonicalUnicodeEquality() throws {
        let a = try F.context(namespace: "café"), b = try F.context(namespace: "cafe\u{301}")
        XCTAssertEqual(a.session.storageNamespace, b.session.storageNamespace)
        XCTAssertNotEqual(a, b)
    }
    func testNoInspectorCannotMintEvidenceAndReferenceIsOnlyAnOpaqueToken() throws {
        let request = try F.request()
        XCTAssertThrowsError(try ProjectTopicMediaInspectionEvidence.inspect(request, using: nil)) { XCTAssertEqual($0 as? ProjectTopicMediaFailure, .inspectionUnavailable) }
        for raw in ["\"https://example.invalid/a.mp4\"", "{\"id\":\"file:///tmp/a\",\"revision\":\"x\"}"] {
            XCTAssertThrowsError(try JSONDecoder().decode(ProjectTopicMediaLocalReference.self, from: Data(raw.utf8)))
        }
    }
    func testCoreComputesStreamDigestAndCountRatherThanTrustingReportValues() throws {
        let request = try F.request(), inspector = F.Inspector(); inspector.chunks = [Data("ab".utf8), Data("cd".utf8)]
        let evidence = try ProjectTopicMediaInspectionEvidence.inspect(request, using: inspector)
        XCTAssertEqual(evidence.facts.byteCount, 4); XCTAssertEqual(evidence.facts.contentSHA256, F.hash(Data("abcd".utf8)))
        XCTAssertEqual(evidence.request, request); XCTAssertEqual(inspector.calls, 1)
        for mode in 0..<5 {
            let source = F.Inspector()
            source.wrongRequest = mode == 0; source.wrongReference = mode == 1; source.wrongDigest = mode == 2
            source.wrongSize = mode == 3; source.missingChecks = mode == 4
            XCTAssertThrowsError(try ProjectTopicMediaInspectionEvidence.inspect(F.request(), using: source)) { XCTAssertEqual($0 as? ProjectTopicMediaFailure, .invalidInspection) }
        }
    }
    func testByteLimitIsStickyEvenWhenInspectorSwallowsConsumerError() throws {
        let inspector = F.Inspector(); inspector.chunks = [Data("ab".utf8), Data("overflow".utf8)]; inspector.swallowConsumerFailure = true
        XCTAssertThrowsError(try ProjectTopicMediaInspectionEvidence.inspect(F.request(policy: F.policy(total: 4, bytes: 4)), using: inspector)) { XCTAssertEqual($0 as? ProjectTopicMediaFailure, .byteLimit) }
        let empty = F.Inspector(); empty.chunks = [Data(), Data("abcd".utf8)]; empty.swallowConsumerFailure = true
        XCTAssertThrowsError(try ProjectTopicMediaInspectionEvidence.inspect(F.request(), using: empty)) { XCTAssertEqual($0 as? ProjectTopicMediaFailure, .invalidInspection) }
    }
    func testAggregateInspectionBudgetStopsSecondFileAndNeverRefundsReadBytes() throws {
        let context = try F.context(), policy = try F.policy(total: 7)
        let selection = ProjectTopicMediaSelection(context: context, policy: policy)
        let ticket = try XCTUnwrap(selection.begin(visit: selection.visit, context: context, policy: policy))
        let requests = try XCTUnwrap(selection.prepareInspection([F.reference(), F.reference()], ticket: ticket, context: context, policy: policy))
        _ = try ProjectTopicMediaInspectionEvidence.inspect(requests[0], using: F.Inspector())
        XCTAssertThrowsError(try ProjectTopicMediaInspectionEvidence.inspect(requests[1], using: F.Inspector())) { XCTAssertEqual($0 as? ProjectTopicMediaFailure, .byteLimit) }
        XCTAssertThrowsError(try ProjectTopicMediaInspectionEvidence.inspect(requests[0], using: F.Inspector())) { XCTAssertEqual($0 as? ProjectTopicMediaFailure, .byteLimit) }
    }
    func testVideoChecksMIMEPositiveDurationAndExactPolicyBoundary() throws {
        for duration in [UInt64(0), 1000, 1001] {
            let source = F.Inspector(); source.kind = .video; source.mime = "video/mp4"; source.duration = duration
            if duration == 1000 { XCTAssertEqual(try ProjectTopicMediaInspectionEvidence.inspect(F.request(), using: source).facts.kind, .video) }
            else { XCTAssertThrowsError(try ProjectTopicMediaInspectionEvidence.inspect(F.request(), using: source)) { XCTAssertEqual($0 as? ProjectTopicMediaFailure, .durationLimit) } }
        }
        let wrong = F.Inspector(); wrong.kind = .video; wrong.mime = "image/jpeg"; wrong.duration = 1
        XCTAssertThrowsError(try ProjectTopicMediaInspectionEvidence.inspect(F.request(), using: wrong)) { XCTAssertEqual($0 as? ProjectTopicMediaFailure, .unsupportedType) }
        let timedImage = F.Inspector(); timedImage.duration = 1
        XCTAssertThrowsError(try ProjectTopicMediaInspectionEvidence.inspect(F.request(), using: timedImage)) { XCTAssertEqual($0 as? ProjectTopicMediaFailure, .durationLimit) }
    }
    func testDimensionAndPixelChecksAvoidOverflowAtUInt64Maximum() throws {
        let source = F.Inspector(); source.width = UInt64.max; source.height = UInt64.max
        let policy = try F.policy(width: UInt64.max, height: UInt64.max, pixels: UInt64.max)
        XCTAssertThrowsError(try ProjectTopicMediaInspectionEvidence.inspect(F.request(policy: policy), using: source)) { XCTAssertEqual($0 as? ProjectTopicMediaFailure, .dimensionLimit) }
        for width in [UInt64(0), 10, 11] {
            let sample = F.Inspector(); sample.width = width; sample.height = 10
            if width == 10 { XCTAssertNoThrow(try ProjectTopicMediaInspectionEvidence.inspect(F.request(), using: sample)) }
            else { XCTAssertThrowsError(try ProjectTopicMediaInspectionEvidence.inspect(F.request(), using: sample)) }
        }
    }
    func testHistoricalRecordRoundtripDoesNotStoreInspectionOrRemoteAuthority() throws {
        let record = try F.accepted().localRecord, data = try record.encoded()
        XCTAssertEqual(try ProjectTopicMediaLocalRecord.decode(data, maximumRecordBytes: data.count), record)
        XCTAssertThrowsError(try ProjectTopicMediaLocalRecord.decode(data, maximumRecordBytes: data.count - 1))
        XCTAssertThrowsError(try ProjectTopicMediaLocalRecord.decode(data, maximumRecordBytes: 0))
        let text = String(decoding: data, as: UTF8.self)
        for forbidden in ["receipt", "uploaded", "approved", "url", "imgUrl", "imgArr", "checks", "epoch"] { XCTAssertFalse(text.contains("\"" + forbidden + "\"")) }
    }
    func testUnknownNestedFieldsDuplicateEscapedKeysAndUnknownSchemaAreRejected() throws {
        let data = try F.accepted().localRecord.encoded(), text = String(decoding: data, as: UTF8.self)
        let duplicate = "{\"schemaVersion\":1," + text.dropFirst()
        let escaped = "{\"schemaVer\\u0073ion\":1," + text.dropFirst()
        for raw in [duplicate, escaped, "{\"uploaded\":true," + text.dropFirst(), text.replacingOccurrences(of: "\"schemaVersion\":1", with: "\"schemaVersion\":2"), text + " true"] {
            XCTAssertThrowsError(try ProjectTopicMediaLocalRecord.decode(Data(raw.utf8), maximumRecordBytes: 100_000))
        }
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var items = try XCTUnwrap(object["items"] as? [[String: Any]]); items[0]["ownershipProof"] = "forged"; object["items"] = items
        XCTAssertThrowsError(try ProjectTopicMediaLocalRecord.decode(JSONSerialization.data(withJSONObject: object), maximumRecordBytes: 100_000))
    }
    func testRecordRejectsWrongKindMalformedHashDuplicateReferencesAndInvalidOwner() throws {
        let data = try F.accepted().localRecord.encoded()
        for mode in 0..<5 {
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            var items = try XCTUnwrap(object["items"] as? [[String: Any]])
            if mode == 0 { items[0]["kind"] = "audio" }
            if mode == 1 { items[0]["contentSHA256"] = "https://example.invalid/hash" }
            if mode == 2 { let duplicate = items[0]; items.append(duplicate) }
            if mode == 3 { object["accountID"] = 0 }
            if mode == 4 { object["identity"] = [:] }
            object["items"] = items
            XCTAssertThrowsError(try ProjectTopicMediaLocalRecord.decode(JSONSerialization.data(withJSONObject: object), maximumRecordBytes: 100_000))
        }
    }
}
