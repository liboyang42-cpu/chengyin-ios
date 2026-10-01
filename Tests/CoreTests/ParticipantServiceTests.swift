import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

@MainActor
final class ParticipantServiceTests: XCTestCase {
    private func service(_ transport: ProfileTestTransport) throws -> ParticipantService {
        ParticipantService(configuration: try APIConfiguration(baseURL: URL(string: "https://example.com/fixture/")!), transport: transport)
    }
    func testSaveDeleteDefaultUseExactMultipartRoutesFieldsAndRawAuthorization() async throws {
        let transport = ProfileTestTransport(Array(repeating: .json(#"{"code":200}"#), count: 4))
        let service = try service(transport)
        let create = participantDraftFixture()
        let edit = ParticipantFormDraft(detail: try participantFixture())
        let mutations: [ParticipantMutation] = [.save(create), .save(edit), .delete(id: 7), .setDefault(id: 7)]
        for mutation in mutations { try await service.perform(mutation, token: "fixture-token") }
        XCTAssertEqual(transport.requests.map { $0.url!.path }, ["/fixture/api/user/address/action", "/fixture/api/user/address/action", "/fixture/api/user/address/delete", "/fixture/api/user/address/setDefault"])
        for (index, request) in transport.requests.enumerated() {
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "fixture-token")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
            XCTAssertTrue(request.value(forHTTPHeaderField: "Content-Type")!.hasPrefix("multipart/form-data; boundary="))
            let fields = try mutations[index].fields()
            let body = try XCTUnwrap(String(data: request.httpBody!, encoding: .utf8))
            XCTAssertEqual(body.components(separatedBy: "Content-Disposition:").count - 1, fields.count)
            for (key, value) in fields { XCTAssertTrue(body.contains("name=\"\(key)\"\r\n\r\n\(value)\r\n")) }
            XCTAssertFalse(body.contains("name=\"city\"")); XCTAssertFalse(body.contains("name=\"area\""))
            XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
        }
    }
    func testInvalidInputNeverReachesTransport() async throws {
        let transport = ProfileTestTransport([])
        let service = try service(transport)
        for mutation in [ParticipantMutation.save(ParticipantFormDraft()), .delete(id: 0), .setDefault(id: -1)] {
            do { try await service.perform(mutation, token: "fixture-token"); XCTFail() }
            catch { XCTAssertEqual(error as? ParticipantWriteError, .notSent(.invalidRequest)) }
        }
        do { try await service.perform(.delete(id: 7), token: "bad\r\nheader"); XCTFail() }
        catch { XCTAssertEqual(error as? ParticipantWriteError, .notSent(.invalidRequest)) }
        XCTAssertTrue(transport.requests.isEmpty)
    }
    func testCode200AllowsAbsentNullOrUnrelatedDataWithoutInventingNewID() async throws {
        for json in [#"{"code":200}"#, #"{"code":200,"data":null}"#, #"{"code":200,"data":{"id":999}}"#] {
            let transport = ProfileTestTransport([.json(json)])
            try await service(transport).perform(.save(participantDraftFixture()), token: "fixture-token")
            XCTAssertEqual(transport.requests.count, 1)
        }
    }
    func testExplicitBusinessRejectionPreservesMessageAndDoesNotRetry() async throws {
        let transport = ProfileTestTransport([.json(#"{"code":403,"msg":"地址不可用"}"#)])
        do { try await service(transport).perform(.delete(id: 7), token: "fixture-token"); XCTFail() }
        catch {
            XCTAssertEqual(error as? ParticipantWriteError, .rejected(.init(code: 403, message: "地址不可用")))
        }
        XCTAssertEqual(transport.requests.count, 1)
    }
    func testHTTP401IsRejectionButServerAndProxyErrorsRemainUncertain() async throws {
        for status in [401, 400, 403, 500, 503] {
            let transport = ProfileTestTransport([.json(#"{"code":500,"msg":"Synthetic failure"}"#, status: status)])
            do { try await service(transport).perform(.setDefault(id: 7), token: "fixture-token"); XCTFail() }
            catch let error as ParticipantWriteError {
                let failure = ParticipantResponseFailure(httpStatus: status, code: 500, message: "Synthetic failure")
                XCTAssertEqual(error, status == 401 ? .rejected(failure) : .outcomeUnknown(.response(failure)))
            }
            XCTAssertEqual(transport.requests.count, 1)
        }
    }
    func testTransportTimeoutCancellationMalformedAndMissingCodeNeverAutomaticallyResend() async throws {
        for reply in [ProfileTestReply.failure(URLError(.timedOut)), .failure(CancellationError()), .json("not json"), .json(#"{"data":{}}"#), .json(#"{"code":"200"}"#)] {
            let transport = ProfileTestTransport([reply])
            do { try await service(transport).perform(.save(participantDraftFixture()), token: "fixture-token"); XCTFail() }
            catch let error as ParticipantWriteError {
                guard case .outcomeUnknown = error else { return XCTFail("Dispatched request must stay uncertain") }
            }
            XCTAssertEqual(transport.requests.count, 1)
        }
    }
    func testCancelledBeforeDispatchSendsNothing() async throws {
        let transport = ProfileTestTransport([])
        let service = try service(transport)
        let task = Task { @MainActor in
            try await service.perform(.delete(id: 7), token: "fixture-token")
        }
        task.cancel()
        do { try await task.value; XCTFail() }
        catch { XCTAssertEqual(error as? ParticipantWriteError, .cancelledBeforeDispatch) }
        XCTAssertTrue(transport.requests.isEmpty)
    }
}
