#!/usr/bin/env python3
"""Compile and run the actual settlement read chain without Apple-only writers.

The temporary package selects verbatim production JSON values, read methods,
session reader, App adapter, detail parser and lifecycle. Only the unrelated write
container/constructor is omitted. No production source or dependency is changed.
HTTPTransport is replaced by a fake wire, never by a fake service or parser.
This verifies the read journey, not a SwiftUI build or a live backend.
"""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
P = argparse.ArgumentParser(description=__doc__)
P.add_argument('--swift', default='swift')
ARGS = P.parse_args()

HTTP_TESTS = r'''
import XCTest
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

@MainActor final class SettlementHTTPJourneyTests: XCTestCase {
    private let host = #"{"topics":[{"topicId":7,"topicName":"Walk","settled":true,"myIncome":20,"myIncomeArrived":false,"totalSales":100,"verifiedSales":80,"platformAmount":5,"merchantTotal":40}]}"#
    private let merchant = #"{"settlements":[{"id":31,"topicId":7,"verifiedSales":120,"verifiedHeads":6,"amount":30,"status":1,"shareMode":0}]}"#
    private final class SessionBox { var value: CoopFlowSession? = try! .init(accountID: 21, epoch: 1, token: "synthetic-token") }
    private func reader(_ wire: Wire, session: SessionBox, unauthorized: @escaping (CoopFlowSession) -> Void = { _ in }) throws -> CoopFlowSessionReader {
        .init(service: .init(configuration: try .init(baseURL: URL(string: "https://example.com")!), transport: wire), current: { session.value }, unauthorized: unauthorized)
    }
    func testNormalHostListToDetailUsesOriginalPOSTReaderAndServerAmounts() async throws {
        let wire = Wire(host), session = SessionBox(), actual = try reader(wire, session: session)
        let list = try CoopFinanceProfit(await actual.read(.finance))
        let selected = try XCTUnwrap(list.topics.first?.topicID)
        let adapter = l6SettlementAdapter(actual), journey = CoopSettlementReadJourney()
        await journey.load(reader: adapter, source: .finance, id: selected)
        let detail = try XCTUnwrap(journey.detail(reader: adapter, source: .finance, id: selected))
        XCTAssertEqual(detail.amount, 20); XCTAssertEqual(detail.status, .awaitingCredit)
        XCTAssertEqual(detail.lines.first?.value, .money(100))
        XCTAssertEqual(wire.requests.count, 2)
        for request in wire.requests {
            XCTAssertEqual(request.url?.path, "/api/coop/finance")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "synthetic-token")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            XCTAssertEqual(String(decoding: request.httpBody!, as: UTF8.self), "{}")
        }
    }
    func testNormalMerchantLedgerToDetailUsesSeparateOriginalSource() async throws {
        let wire = Wire(merchant), session = SessionBox(), actual = try reader(wire, session: session)
        let rows = try await actual.read(.myBusiness)["settlements"].rows!
        let selected = try XCTUnwrap(rows.first?["id"].integer)
        let adapter = l6SettlementAdapter(actual), journey = CoopSettlementReadJourney()
        await journey.load(reader: adapter, source: .mybiz, id: selected)
        let detail = try XCTUnwrap(journey.detail(reader: adapter, source: .mybiz, id: selected))
        XCTAssertEqual(detail.perspective, .merchant); XCTAssertEqual(detail.amount, 30)
        XCTAssertEqual(detail.status, .creditedBalance)
        XCTAssertTrue(wire.requests.allSatisfy { $0.url?.path == "/api/coop/mybiz" })
    }
    func testTransientHTTPFailureRetainsLabelledStaleDetailThenExplicitRetryReadsFresh() async throws {
        let wire = Wire(host), session = SessionBox(), actual = try reader(wire, session: session)
        let adapter = l6SettlementAdapter(actual), journey = CoopSettlementReadJourney()
        await journey.load(reader: adapter, source: .finance, id: 7)
        wire.status = 503; wire.code = 503
        await journey.load(reader: adapter, source: .finance, id: 7)
        XCTAssertEqual(journey.detail(reader: adapter, source: .finance, id: 7)?.amount, 20)
        XCTAssertEqual(journey.issue(reader: adapter, source: .finance, id: 7), .failed(nil))
        wire.status = 200; wire.code = 200; wire.payload = host.replacingOccurrences(of: "\"myIncome\":20", with: "\"myIncome\":25")
        await journey.load(reader: adapter, source: .finance, id: 7)
        XCTAssertEqual(journey.detail(reader: adapter, source: .finance, id: 7)?.amount, 25)
        XCTAssertNil(journey.issue(reader: adapter, source: .finance, id: 7)); XCTAssertEqual(wire.requests.count, 3)
    }
    func testHTTP401RetiresOnlyCapturedSessionAndHidesDetail() async throws {
        let wire = Wire(host), session = SessionBox(); var expired = 0
        let actual = try reader(wire, session: session) { old in if session.value == old { expired += 1; session.value = nil } }
        let adapter = l6SettlementAdapter(actual), journey = CoopSettlementReadJourney()
        await journey.load(reader: adapter, source: .finance, id: 7)
        wire.status = 401; wire.code = 401
        await journey.load(reader: adapter, source: .finance, id: 7)
        XCTAssertEqual(expired, 1); XCTAssertNil(adapter.scope)
        XCTAssertNil(journey.detail(reader: adapter, source: .finance, id: 7))
    }
    func testSameEpochTokenReplacementFencesLateHTTPAndNextReadUsesNewToken() async throws {
        let wire = Wire(host), session = SessionBox(), actual = try reader(wire, session: session)
        let adapter = l6SettlementAdapter(actual), journey = CoopSettlementReadJourney()
        let oldScope = adapter.scope
        wire.beforeReturn = { session.value = try! .init(accountID: 21, epoch: 1, token: "replacement-token") }
        await journey.load(reader: adapter, source: .finance, id: 7)
        XCTAssertNil(journey.detail(reader: adapter, source: .finance, id: 7)); XCTAssertNotEqual(adapter.scope, oldScope)
        wire.beforeReturn = nil
        await journey.load(reader: adapter, source: .finance, id: 7)
        XCTAssertNotNil(journey.detail(reader: adapter, source: .finance, id: 7))
        XCTAssertEqual(wire.requests.last?.value(forHTTPHeaderField: "Authorization"), "replacement-token")
    }
    func testDismissalRetiresAdapterAndReentryMustReadAgain() async throws {
        let wire = Wire(host), session = SessionBox(), actual = try reader(wire, session: session)
        let adapter = l6SettlementAdapter(actual), journey = CoopSettlementReadJourney()
        wire.beforeReturn = { l6RetireSettlementAdapter(adapter); journey.invalidate() }
        await journey.load(reader: adapter, source: .finance, id: 7)
        XCTAssertNil(journey.detail(reader: adapter, source: .finance, id: 7)); XCTAssertNil(adapter.scope)
        wire.beforeReturn = nil
        let reentry = l6SettlementAdapter(actual)
        await journey.load(reader: reentry, source: .finance, id: 7)
        XCTAssertNotNil(journey.detail(reader: reentry, source: .finance, id: 7)); XCTAssertEqual(wire.requests.count, 2)
    }
    func testDuplicateAndMalformedHTTPPayloadsClearPriorFinancialState() async throws {
        for duplicate in [false, true] {
            let wire = Wire(host), session = SessionBox(), actual = try reader(wire, session: session)
            let adapter = l6SettlementAdapter(actual), journey = CoopSettlementReadJourney()
            await journey.load(reader: adapter, source: .finance, id: 7)
            let row = try JSONDecoder().decode(CoopFlowJSON.self, from: Data(host.utf8))["topics"].rows![0]
            let value: CoopFlowJSON = .object(["topics": .array(duplicate ? [row, row] : [row, .object([:])])])
            wire.payload = String(decoding: try value.canonical(), as: UTF8.self)
            await journey.load(reader: adapter, source: .finance, id: 7)
            XCTAssertNil(journey.detail(reader: adapter, source: .finance, id: 7))
            XCTAssertEqual(journey.issue(reader: adapter, source: .finance, id: 7), .failed(nil))
        }
    }
    func testPermissionRevocationAndMissingRecordClearOldDetail() async throws {
        let wire = Wire(host), session = SessionBox(), actual = try reader(wire, session: session)
        let adapter = l6SettlementAdapter(actual), journey = CoopSettlementReadJourney()
        await journey.load(reader: adapter, source: .finance, id: 7)
        wire.code = 403
        await journey.load(reader: adapter, source: .finance, id: 7)
        XCTAssertNil(journey.detail(reader: adapter, source: .finance, id: 7))
        XCTAssertEqual(journey.issue(reader: adapter, source: .finance, id: 7), .permission(nil))
        wire.code = 200; wire.payload = #"{"topics":[]}"#
        await journey.load(reader: adapter, source: .finance, id: 7)
        XCTAssertEqual(journey.issue(reader: adapter, source: .finance, id: 7), .missingRecord)
    }
    func testOlderOverlappingHTTPReadCannotReplaceNewerServerResult() async throws {
        let wire = Wire(host), session = SessionBox(), actual = try reader(wire, session: session)
        let adapter = l6SettlementAdapter(actual), journey = CoopSettlementReadJourney()
        wire.hold = true
        let older = Task { await journey.load(reader: adapter, source: .finance, id: 7) }
        for _ in 0..<1000 { if wire.held != nil { break }; await Task.yield() }
        XCTAssertNotNil(wire.held)
        wire.hold = false; wire.payload = host.replacingOccurrences(of: "\"myIncome\":20", with: "\"myIncome\":25")
        await journey.load(reader: adapter, source: .finance, id: 7)
        wire.release(); await older.value
        XCTAssertEqual(journey.detail(reader: adapter, source: .finance, id: 7)?.amount, 25)
        XCTAssertFalse(journey.isLoading); XCTAssertEqual(wire.requests.count, 2)
    }
    func testCancelledHTTPRefreshClearsDetailAndDoesNotInventFailure() async throws {
        let wire = Wire(host), session = SessionBox(), actual = try reader(wire, session: session)
        let adapter = l6SettlementAdapter(actual), journey = CoopSettlementReadJourney()
        await journey.load(reader: adapter, source: .finance, id: 7)
        wire.hold = true
        let refresh = Task { await journey.load(reader: adapter, source: .finance, id: 7) }
        for _ in 0..<1000 { if wire.held != nil { break }; await Task.yield() }
        XCTAssertNotNil(wire.held); refresh.cancel(); wire.release(); await refresh.value
        XCTAssertNil(journey.detail(reader: adapter, source: .finance, id: 7))
        XCTAssertNil(journey.issue(reader: adapter, source: .finance, id: 7)); XCTAssertFalse(journey.isLoading)
    }
    func testRecreatedJourneyReadsServerInsteadOfCachingPrivateAmounts() async throws {
        let wire = Wire(host), session = SessionBox(), actual = try reader(wire, session: session)
        let previous = CoopSettlementReadJourney(), adapter = l6SettlementAdapter(actual)
        await previous.load(reader: adapter, source: .finance, id: 7)
        let reopened = CoopSettlementReadJourney(), rebound = l6SettlementAdapter(actual)
        XCTAssertNil(reopened.detail(reader: rebound, source: .finance, id: 7))
        wire.payload = host.replacingOccurrences(of: "\"myIncome\":20", with: "\"myIncome\":25")
        await reopened.load(reader: rebound, source: .finance, id: 7)
        XCTAssertEqual(reopened.detail(reader: rebound, source: .finance, id: 7)?.amount, 25)
    }
    private final class Wire: HTTPTransport {
        var payload: String
        var status = 200
        var code = 200
        var requests: [URLRequest] = []
        var beforeReturn: (() -> Void)?
        var hold = false
        var held: CheckedContinuation<(Data, Int), Error>?
        private var response: (Data, Int)?
        init(_ payload: String) { self.payload = payload }
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request)
            let result = (Data(("{\"code\":\(code),\"data\":" + payload + "}").utf8), status)
            if hold {
                response = result
                return try await withCheckedThrowingContinuation { held = $0 }
            }
            beforeReturn?(); return result
        }
        func release() { let continuation = held; held = nil; continuation?.resume(returning: response!) }
    }
}
'''

def between(text, first, last):
    return text.split(first, 1)[1].split(last, 1)[0]

with tempfile.TemporaryDirectory(prefix='l6-settlement-read-') as directory:
    temp = Path(directory)
    core = temp / 'Core'; core.mkdir()
    tests = temp / 'Tests'; tests.mkdir()
    for name in ['APIConfiguration.swift', 'AuthRequestBuilder.swift', 'CoopFinanceProfit.swift', 'CoopSettlementDetailModel.swift']:
        shutil.copyfile(ROOT / 'Core' / name, core / name)
    contracts = (ROOT / 'Core/CooperationFlowContracts.swift').read_text()
    values = contracts.split('public struct CoopFlowIdentity:', 1)[0]
    values += 'public struct CoopFlowMoney:' + between(contracts, 'public struct CoopFlowMoney:', 'public struct CoopFlowNearbyPartner:')
    values += 'public enum CoopFlowTargetKind:' + between(contracts, 'public enum CoopFlowTargetKind:', 'public enum CoopFlowCompensation:')
    home = (ROOT / 'Core/PublicMerchantHome.swift').read_text()
    values += 'public struct PublicMerchantOwnerID:' + between(home, 'public struct PublicMerchantOwnerID:', 'public struct PublicMerchantRowID:')
    (core / 'ReadValues.swift').write_text(values)
    service = (ROOT / 'Core/CooperationFlowService.swift').read_text()
    projection = service.split('public struct CoopFlowService {', 1)[0]
    projection += '''public struct CoopFlowService {
    private let configuration: APIConfiguration
    private let transport: any HTTPTransport
    public init(configuration: APIConfiguration, transport: any HTTPTransport) {
        self.configuration = configuration; self.transport = transport
    }
'''
    projection += '    public func read(' + between(service, '    public func read(', '    func permitsDispatch(')
    projection += '    private func makeRequest(' + service.split('    private func makeRequest(', 1)[1]
    auth = (ROOT / 'Core/AuthService.swift').read_text()
    projection += auth.split('/// Prevent following redirects', 1)[0]
    relations = (ROOT / 'Core/CoopRelationDiscovery.swift').read_text()
    projection += 'public enum CoopRelationDiscoveryKind:' + between(relations, 'public enum CoopRelationDiscoveryKind:', 'public struct CoopRelationProfileScope:')
    adapter = (ROOT / 'App/CoopSettlementDetailView.swift').read_text()
    projection += '@MainActor private final class CoopSettlementJourneyAdapter:' + between(adapter, '@MainActor private final class CoopSettlementJourneyAdapter:', '@MainActor private final class CoopSettlementJourneyViewModel:')
    projection += '''
@MainActor public func l6SettlementAdapter(_ reader: any CoopFlowReading) -> any CoopSettlementJourneyReading { CoopSettlementJourneyAdapter(reader) }
@MainActor public func l6RetireSettlementAdapter(_ adapter: any CoopSettlementJourneyReading) { (adapter as? CoopSettlementJourneyAdapter)?.invalidate() }
'''
    (core / 'ReadProjection.swift').write_text(projection)
    for name in ['CoopSettlementDetailModelTests.swift', 'CoopSettlementReadJourneyTests.swift']:
        shutil.copyfile(ROOT / 'Tests/CoreTests' / name, tests / name)
    (tests / 'SettlementHTTPJourneyTests.swift').write_text(HTTP_TESTS)
    (temp / 'Package.swift').write_text('''// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "QuestifyCore", targets: [
    .target(name: "QuestifyCore", path: "Core"),
    .testTarget(name: "QuestifyCoreTests", dependencies: ["QuestifyCore"], path: "Tests")])
''')
    env = dict(os.environ, CLANG_MODULE_CACHE_PATH=str(temp / 'clang-cache'), XDG_CACHE_HOME=str(temp / 'cache'), SWIFTPM_MODULECACHE_OVERRIDE=str(temp / 'module-cache'))
    subprocess.run([ARGS.swift, 'test', '--package-path', str(temp), '--cache-path', str(temp / 'spm-cache'),
                    '--config-path', str(temp / 'spm-config'), '--security-path', str(temp / 'spm-security'), '--jobs', '4'],
                   env=env, check=True)
