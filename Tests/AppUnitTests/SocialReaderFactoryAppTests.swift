import XCTest
import Foundation
@testable import Questify

@MainActor private final class SocialReaderAppRecorder: HTTPTransport {
    var calls = 0
    func send(_ request: URLRequest) async throws -> (Data, Int) { calls += 1; throw APIError.notConfigured }
}
@MainActor final class SocialReaderFactoryAppTests: XCTestCase {
    func testShippedSocialReadApprovalIsAbsent() {
        XCTAssertNil(NativeRuntimeDependencies.dormant.socialReaderApproval)
    }
    func testNormalReadersUseFactoriesAndCannotSendWhileUnapprovedOrSignedOut() async throws {
        let recorder = SocialReaderAppRecorder()
        let session = AppSession(runtimeDependencies: .init(transport: recorder))
        XCTAssertFalse(session.objectCardReader.isConfigured)
        XCTAssertFalse(session.socialMessageMediaReader.isConfigured)
        XCTAssertFalse(session.makeObjectCardReader().isConfigured)
        XCTAssertFalse(session.makeSocialMessageMediaReader().isConfigured)
        do { _ = try await session.objectCardReader.list(category: .all); XCTFail() } catch {}
        let message = try JSONDecoder().decode(MessagingMessage.self,
            from: Data(#"{"id":21,"conversationId":9,"msgType":2,"content":"https://media.example.com/a.png"}"#.utf8))
        do {
            _ = try await session.socialMessageMediaReader.image(.init(message: message), expectedIdentity: .init(accountID: 7, epoch: 1))
            XCTFail()
        } catch { XCTAssertEqual(error as? APIError, .unauthorized) }
        XCTAssertEqual(recorder.calls, 0)
    }
}
