import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Synthetic HTTP only. These tests do not contact uploadOSS or decode image bytes.
@MainActor final class ProjectTopicImageUploadTests: XCTestCase {
    @MainActor private final class Wire: HTTPTransport {
        var requests: [URLRequest] = []
        var response = Data(#"{"code":200,"url":"https://media.example/topic.jpg"}"#.utf8)
        var status = 200
        var beforeReply: (() -> Void)?
        var failure = false
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request); beforeReply?()
            if failure { throw URLError(.timedOut) }
            return (response, status)
        }
    }
    @MainActor private final class Owner {
        var session = try! ProjectEditSession(accountID: 7, epoch: 1, storageNamespace: "topic-image-test")
        var approval: ProjectTopicImageUploadApproval?
        let wire = Wire()
    }
    private func policy() throws -> ProjectTopicMediaPolicy {
        try .init(id: UUID(), revision: 1, maximumItems: 1, maximumTotalBytes: 1_000_000, mixing: .singleKind,
                  kinds: [.init(kind: .image, mimeTypes: ["image/jpeg"], maximumBytes: 1_000_000,
                                maximumWidth: 4096, maximumHeight: 4096, maximumPixels: 16_777_216, maximumDurationMilliseconds: nil)])
    }
    private func context(_ owner: Owner, merchant: Bool = false) throws -> ProjectTopicMediaContext {
        try .init(session: owner.session, identity: .init(), product: .city, owner: merchant ? .merchant : .personal,
                  publishMode: "pro", editScope: .full, draftRevision: 0, visit: UUID())
    }
    private func client(_ owner: Owner, enabled: Bool = true, fields: Set<ProjectTopicImageField> = [.cover, .gallery], picker: Bool = true) throws -> ProjectTopicImageUploadClient {
        let api = try APIConfiguration(baseURL: URL(string: "https://api.example")!)
        owner.approval = enabled ? try .init(baseURL: api.baseURL, namespace: owner.session.storageNamespace, accountID: 7,
             fields: fields, approvedOrigins: ["https://media.example"], policy: policy(), nativePicker: picker) : nil
        return .init(configuration: api, approval: owner.approval, transport: owner.wire,
                     credentials: { try? .init(session: owner.session, token: "synthetic-topic-token") }, currentApproval: { owner.approval })
    }
    private func image(_ field: ProjectTopicImageField = .cover) throws -> RetainedSelectedImage {
        try .init(jpeg: Data([255,216,255,1,2,3]), width: field.widthUnits * 10, height: field.heightUnits * 10)
    }
    func testDefaultNilAndDistinctFieldGatesDoNotDispatch() async throws {
        let owner = Owner(), context = try context(owner), off = try client(owner, enabled: false)
        do { _ = try await off.upload(image(), attemptID: UUID(), context: context, field: .cover); XCTFail() } catch {}
        XCTAssertTrue(owner.wire.requests.isEmpty)
        let cover = try client(owner, fields: [.cover], picker: false)
        XCTAssertTrue(cover.isCurrent(context: context, field: .cover)); XCTAssertFalse(cover.permitsPicker(context: context, field: .cover))
        XCTAssertNil(cover.policy(context: context, field: .gallery))
        do { _ = try await cover.upload(image(.gallery), attemptID: UUID(), context: context, field: .gallery); XCTFail() } catch {}
        XCTAssertTrue(owner.wire.requests.isEmpty)
    }
    func testExactExistingRatioWireAndDraftIdentityWithoutTopicID() async throws {
        let owner = Owner(), source = try client(owner), context = try context(owner)
        XCTAssertNil(context.identity.topicID)
        for field in [ProjectTopicImageField.cover, .gallery] {
            let receipt = try await source.upload(image(field), attemptID: UUID(), context: context, field: field)
            XCTAssertEqual(source.permittedURL(receipt, context: context, field: field), "https://media.example/topic.jpg")
            let request = try XCTUnwrap(owner.wire.requests.last), body = String(decoding: try XCTUnwrap(request.httpBody), as: UTF8.self)
            XCTAssertEqual(request.url?.path, "/api/common/uploadOSS"); XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "synthetic-topic-token")
            XCTAssertTrue(body.contains("name=\"bizType\"\r\n\r\n" + field.businessType))
            XCTAssertTrue(body.contains("name=\"file\"; filename=\"topic.jpg\""))
            for forbidden in ["image_free", "topicId", "assetId", "ownerId"] { XCTAssertFalse(body.contains(forbidden)) }
        }
        XCTAssertEqual(owner.wire.requests.count, 2)
    }
    func testWrongRatioAndMerchantScopeCannotUpload() async throws {
        let owner = Owner(), source = try client(owner), context = try context(owner)
        do { _ = try await source.upload(image(.gallery), attemptID: UUID(), context: context, field: .cover); XCTFail() } catch {}
        do { _ = try await source.upload(image(), attemptID: UUID(), context: self.context(owner, merchant: true), field: .cover); XCTFail() } catch {}
        XCTAssertTrue(owner.wire.requests.isEmpty)
    }
    func testInvalidOriginsDuplicateKeysAndFieldLengthsCannotMintReceipt() async throws {
        let owner = Owner(), source = try client(owner), context = try context(owner)
        for raw in [#"{"code":200,"url":"http://media.example/a.jpg"}"#,
                    #"{"code":200,"url":"https://evil.example/a.jpg"}"#,
                    #"{"code":200,"url":"https://media.example/a.jpg","url":"https://media.example/b.jpg"}"#,
                    #"{"code":200,"url":"https://user@media.example/a.jpg"}"#] {
            owner.wire.response = Data(raw.utf8)
            do { _ = try await source.upload(image(), attemptID: UUID(), context: context, field: .cover); XCTFail(raw) } catch {}
        }
        owner.wire.response = try JSONEncoder().encode(["code": ProjectEditJSON.number(200), "url": .string("https://media.example/" + String(repeating: "a", count: 240))])
        do { _ = try await source.upload(image(), attemptID: UUID(), context: context, field: .cover); XCTFail() } catch {}
        owner.wire.response = Data(#"{"code":200,"url":"https://media.example/a,b.jpg"}"#.utf8)
        do { _ = try await source.upload(image(.gallery), attemptID: UUID(), context: context, field: .gallery); XCTFail() } catch {}
    }
    func testReceiptCannotCrossFieldDraftOrWithdrawnApproval() async throws {
        let owner = Owner(), source = try client(owner), context = try context(owner)
        let receipt = try await source.upload(image(), attemptID: UUID(), context: context, field: .cover)
        XCTAssertNil(source.permittedURL(receipt, context: context, field: .gallery))
        XCTAssertNil(source.permittedURL(receipt, context: try self.context(owner), field: .cover))
        owner.approval = nil; XCTAssertNil(source.permittedURL(receipt, context: context, field: .cover))
    }
    func testUnknownNeverRetriesSameAttemptAndRevocationRejectsLateReply() async throws {
        let owner = Owner(), source = try client(owner), context = try context(owner), attempt = UUID()
        owner.wire.failure = true
        for _ in 0..<2 {
            do { _ = try await source.upload(image(), attemptID: attempt, context: context, field: .cover); XCTFail() } catch {}
        }
        XCTAssertEqual(owner.wire.requests.count, 1)
        owner.wire.failure = false; owner.wire.beforeReply = { owner.approval = nil }
        do { _ = try await source.upload(image(), attemptID: UUID(), context: context, field: .cover); XCTFail() } catch {}
        XCTAssertEqual(owner.wire.requests.count, 2)
    }
    func testResponseBudgetAndNon200StayUnresolved() async throws {
        let owner = Owner(), source = try client(owner), context = try context(owner)
        owner.wire.response = Data(repeating: 32, count: 65537)
        do { _ = try await source.upload(image(), attemptID: UUID(), context: context, field: .cover); XCTFail() } catch {}
        owner.wire.status = 503
        do { _ = try await source.upload(image(), attemptID: UUID(), context: context, field: .cover); XCTFail() } catch {}
    }
}
