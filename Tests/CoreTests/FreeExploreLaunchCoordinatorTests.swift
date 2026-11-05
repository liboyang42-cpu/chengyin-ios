import XCTest
import Foundation
@testable import QuestifyCore

@MainActor final class FreeExploreLaunchCoordinatorTests: XCTestCase {
    func testUnknownPostRelaunchRecoversOriginalReceiptThenOrderWithoutSecondPost() async throws {
        let session = try FX.session(), command = try FX.command(), storage = FXStorage(), transport = FXTransport()
        let pending = FreeExploreLaunchPendingStore(storage: storage, session: session)
        var booked = false
        transport.handler = { request in
            switch request.url!.path {
            case "/api/free-explore/bundle/catalog": return try FX.response(FX.catalog)
            case "/api/free-explore/bundle/order": return try FX.response(FX.order(command, reservations: booked ? [FX.receipt(command)] : [], unitStatus: booked ? "RESERVED" : "AVAILABLE"))
            case "/api/free-explore/bundle/reservation":
                XCTAssertEqual(try pending.load(), command) // Persisted before transport.
                booked = true; throw URLError(.timedOut) // Server committed before connection loss.
            case "/api/free-explore/bundle/reservation/receipt": return try FX.response(booked ? FX.receipt(command) as Any : NSNull())
            default: XCTFail("unapproved route"); throw URLError(.unsupportedURL)
            }
        }
        let service = FreeExploreLaunchService(session: session, transport: transport, currentSession: { session }, reservationAllowed: { true })
        let coordinator = try FreeExploreLaunchCoordinator(service: service, pending: pending)
        do { try await coordinator.reserve(command, topicID: FX.id(88)); XCTFail("unknown POST") }
        catch { XCTAssertEqual(error as? FreeExploreLaunchFailure, .outcomeUnknown) }
        XCTAssertEqual(coordinator.state, .outcomeUnknown)
        XCTAssertEqual(try pending.load(), command)
        let recreatedStore = FreeExploreLaunchPendingStore(storage: storage, session: session)
        let recreated = try FreeExploreLaunchCoordinator(service: service, pending: recreatedStore)
        let recovered = try await recreated.recover()
        XCTAssertEqual(recovered?.registrationId, command.registrationId)
        XCTAssertEqual(recreated.state, .confirmed); XCTAssertNil(try recreatedStore.load())
        XCTAssertEqual(transport.requests.filter { $0.httpMethod == "POST" }.count, 1)
        XCTAssertEqual(Array(transport.requests.suffix(2)).compactMap { $0.url?.path },
            ["/api/free-explore/bundle/reservation/receipt", "/api/free-explore/bundle/order"])
    }
    func testNullReceiptRetainsUnknownAndExplicitRetryReusesExactBody() async throws {
        let session = try FX.session(), command = try FX.command(), transport = FXTransport()
        let pending = FreeExploreLaunchPendingStore(storage: FXStorage(), session: session)
        try pending.save(command)
        var booked = false
        transport.handler = { request in
            switch request.url!.path {
            case "/api/free-explore/bundle/catalog": return try FX.response(FX.catalog)
            case "/api/free-explore/bundle/order": return try FX.response(FX.order(command, reservations: booked ? [FX.receipt(command)] : []))
            case "/api/free-explore/bundle/reservation/receipt": return try FX.response(booked ? FX.receipt(command) as Any : NSNull())
            case "/api/free-explore/bundle/reservation": booked = true; return try FX.response(FX.receipt(command))
            default: throw URLError(.unsupportedURL)
            }
        }
        let service = FreeExploreLaunchService(session: session, transport: transport, currentSession: { session }, reservationAllowed: { true })
        let coordinator = try FreeExploreLaunchCoordinator(service: service, pending: pending)
        let unresolved = try await coordinator.recover()
        XCTAssertNil(unresolved); XCTAssertEqual(coordinator.state, .outcomeUnknown)
        XCTAssertEqual(try pending.load(), command)
        XCTAssertTrue(transport.requests.allSatisfy { $0.httpMethod == "GET" })
        try await coordinator.retryOriginalReservation()
        XCTAssertEqual(transport.requests.filter { $0.httpMethod == "POST" }.map(\.httpBody), [try command.wireData()])
        XCTAssertEqual(coordinator.state, .confirmed)
    }
    func testStorageFailureBlocksPost() async throws {
        let session = try FX.session(), command = try FX.command(), storage = FXStorage(), transport = FXTransport()
        storage.failWrite = true
        transport.handler = { request in try FX.response(request.url!.path.hasSuffix("catalog") ? FX.catalog : FX.order(command)) }
        let service = FreeExploreLaunchService(session: session, transport: transport, currentSession: { session }, reservationAllowed: { true })
        let coordinator = try FreeExploreLaunchCoordinator(service: service, pending: FreeExploreLaunchPendingStore(storage: storage, session: session))
        do { try await coordinator.reserve(command, topicID: FX.id(88)); XCTFail("storage") }
        catch { XCTAssertEqual(error as? FreeExploreLaunchFailure, .storageUnavailable) }
        XCTAssertTrue(transport.requests.allSatisfy { $0.httpMethod == "GET" })
    }
    func testReadFailureAfterReceiptDoesNotClearLockOrReportSuccess() async throws {
        let session = try FX.session(), command = try FX.command(), transport = FXTransport()
        let pending = FreeExploreLaunchPendingStore(storage: FXStorage(), session: session)
        try pending.save(command)
        transport.handler = { request in
            if request.url!.path.hasSuffix("receipt") { return try FX.response(FX.receipt(command)) }
            throw URLError(.networkConnectionLost)
        }
        let service = FreeExploreLaunchService(session: session, transport: transport, currentSession: { session })
        let coordinator = try FreeExploreLaunchCoordinator(service: service, pending: pending)
        do { _ = try await coordinator.recover(); XCTFail("read failure") } catch {}
        XCTAssertEqual(coordinator.state, .outcomeUnknown); XCTAssertNil(coordinator.order)
        XCTAssertEqual(try pending.load(), command)
    }
    func testExistingPendingBlocksNewCommandWithoutHTTP() async throws {
        let session = try FX.session(), transport = FXTransport()
        let pending = FreeExploreLaunchPendingStore(storage: FXStorage(), session: session)
        try pending.save(FX.command())
        let service = FreeExploreLaunchService(session: session, transport: transport, currentSession: { session })
        let coordinator = try FreeExploreLaunchCoordinator(service: service, pending: pending)
        do { try await coordinator.reserve(FX.command(key: "different"), topicID: FX.id(88)); XCTFail("pending") }
        catch { XCTAssertEqual(error as? FreeExploreLaunchFailure, .pendingConflict) }
        XCTAssertTrue(transport.requests.isEmpty)
    }
    func testReentrantDuplicateIsBlockedWhileFirstReadIsSuspended() async throws {
        let session = try FX.session(), command = try FX.command(), transport = FXTransport()
        let service = FreeExploreLaunchService(session: session, transport: transport, currentSession: { session })
        let coordinator = try FreeExploreLaunchCoordinator(service: service, pending: FreeExploreLaunchPendingStore(storage: FXStorage(), session: session))
        var checked = false
        transport.handler = { _ in
            if !checked {
                checked = true
                do { try await coordinator.readOrder(registrationID: FX.id(11)); XCTFail("duplicate") }
                catch { XCTAssertEqual(error as? FreeExploreLaunchFailure, .busy) }
            }
            return try FX.response(FX.order(command))
        }
        try await coordinator.readOrder(registrationID: FX.id(11))
        XCTAssertTrue(checked); XCTAssertEqual(transport.requests.count, 1)
    }
    func testAccountSwitchImmediatelyHidesPublishedStateAndPreventsWrites() async throws {
        let session = try FX.session(), command = try FX.command(), transport = FXTransport()
        var current: FreeExploreLaunchSession? = session
        transport.handler = { _ in try FX.response(FX.order(command)) }
        let service = FreeExploreLaunchService(session: session, transport: transport, currentSession: { current })
        let coordinator = try FreeExploreLaunchCoordinator(service: service, pending: FreeExploreLaunchPendingStore(storage: FXStorage(), session: session))
        try await coordinator.readOrder(registrationID: FX.id(11))
        XCTAssertNotNil(coordinator.order)
        current = try FX.session(account: 8)
        XCTAssertNil(coordinator.order); XCTAssertNil(coordinator.catalog); XCTAssertNil(coordinator.refundQuote)
        XCTAssertEqual(coordinator.state, .staleSession)
        do { try await coordinator.reserve(command, topicID: FX.id(88)); XCTFail("stale write") }
        catch { XCTAssertEqual(error as? FreeExploreLaunchFailure, .staleSession) }
        XCTAssertEqual(transport.requests.count, 1)
    }
    func testUnknownUnitStateDoesNotAuthorizeReservation() async throws {
        let session = try FX.session(), command = try FX.command(), transport = FXTransport()
        transport.handler = { request in try FX.response(request.url!.path.hasSuffix("catalog") ? FX.catalog : FX.order(command, unitStatus: "FUTURE_STATE")) }
        let service = FreeExploreLaunchService(session: session, transport: transport, currentSession: { session }, reservationAllowed: { true })
        let pending = FreeExploreLaunchPendingStore(storage: FXStorage(), session: session)
        let coordinator = try FreeExploreLaunchCoordinator(service: service, pending: pending)
        do { try await coordinator.reserve(command, topicID: FX.id(88)); XCTFail("unknown status") }
        catch { XCTAssertEqual(error as? FreeExploreLaunchFailure, .disabled) }
        XCTAssertNil(try pending.load()); XCTAssertTrue(transport.requests.allSatisfy { $0.httpMethod == "GET" })
    }
    func testCancellationQuoteGapDispatchesNothingAndRetainsPending() throws {
        let session = try FX.session(), command = try FX.command(), transport = FXTransport()
        let pending = FreeExploreLaunchPendingStore(storage: FXStorage(), session: session); try pending.save(command)
        let service = FreeExploreLaunchService(session: session, transport: transport, currentSession: { session })
        let coordinator = try FreeExploreLaunchCoordinator(service: service, pending: pending)
        XCTAssertThrowsError(try coordinator.prepareCancellation(reservationID: FX.id(44), useWaiver: false)) {
            XCTAssertEqual($0 as? FreeExploreLaunchFailure, .cancellationQuoteUnavailable)
        }
        XCTAssertEqual(try pending.load(), command); XCTAssertTrue(transport.requests.isEmpty)
    }
}
