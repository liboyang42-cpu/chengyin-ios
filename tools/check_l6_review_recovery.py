#!/usr/bin/env python3
"""Portable state-machine checks; host reader/document are test doubles.

This compiles the unchanged production recovery source, JSON/access types, record
validator and durable journal. It does not replace the macOS HTTP/XCTest journey.
Run with --swiftc /path/to/swiftc when Swift is not on PATH.
"""
import argparse
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
P = argparse.ArgumentParser(description=__doc__)
P.add_argument('--swiftc', default='swiftc')
ARGS = P.parse_args()

PORTS = r'''
import Foundation
public enum MerchantBusinessQuery: Equatable {
    case reviews(page: Int), customer(MerchantCustomerID), refund(MerchantRefundID), batch(MerchantBatchID), redemption(recordID: String)
}
public struct MerchantBusinessDocument: Equatable {
    public let query: MerchantBusinessQuery
    public let rows: [MerchantBusinessRecord]
    public let hasMore: Bool
}
@MainActor public protocol MerchantBusinessReading: AnyObject {
    var scope: MerchantBusinessScope? { get }
    var journalRealm: String? { get }
    var isConfigured: Bool { get }
    var authorizationGeneration: UUID? { get }
    func snapshot(_ query: MerchantBusinessQuery, isCurrent: () -> Bool) async throws -> MerchantBusinessSnapshot
}
'''

RUNNER = r'''
import Foundation
@MainActor final class Reader: MerchantBusinessReading {
    var scope: MerchantBusinessScope? = .init(realm: "synthetic://review", accountID: 21, epoch: 1)
    var journalRealm: String? { scope?.realm }
    var isConfigured = true
    var authorizationGeneration: UUID? = UUID()
    var access: MerchantBusinessAccess
    var reads: [Int] = []
    var totalPages = 1
    var targetPage: Int? = 1
    var fail = false
    var hook: (() -> Void)?
    init() throws {
        access = try .init(["active": .bool(true), "merchant": .object(["id": .int(610)]),
            "roleCode": .string("MERCHANT_OWNER"), "permissions": .array([.string("merchant:basic:read")])])
    }
    func snapshot(_ query: MerchantBusinessQuery, isCurrent: () -> Bool) async throws -> MerchantBusinessSnapshot {
        guard isCurrent(), case .reviews(let page) = query else { throw MerchantBusinessFailure.stale }
        reads.append(page); hook?()
        if fail { throw MerchantBusinessFailure.denied }
        let row = try MerchantBusinessRecord(kind: .review, fields: ["id": .int(targetPage == page ? 63001 : 80000 + page),
            "rating": .int(4), "version": .int(1), "status": .string("VISIBLE"), "imageUrls": .array([]),
            "verifiedRedemption": .bool(true), "canReply": .bool(false), "canReport": .bool(true),
            "merchantReply": .string("Current server reply")])
        guard isCurrent() else { throw MerchantBusinessFailure.stale }
        return .init(access: access, document: .init(query: query, rows: [row], hasMore: page < totalPages))
    }
}
@main struct Checks {
    @MainActor static func main() async throws {
        let reader = try Reader()
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("intent.json")
        defer { try? FileManager.default.removeItem(at: path.deletingLastPathComponent()) }
        let intent = MerchantBusinessIntent(scope: reader.scope!, merchantID: 610, target: "review:63001", requestID: "original-request")
        try MerchantBusinessFileIntentStore(url: path).reserve(intent)
        let reopened = MerchantBusinessFileIntentStore(url: path)
        let recovery = MerchantReviewReplyRecovery(reader: reader, journal: reopened)
        let pending = try recovery.pending(access: reader.access)[0]
        func check(_ passed: @autoclosure () -> Bool, _ label: String) {
            guard passed() else { fatalError(label) }; print("PASS " + label)
        }
        await recovery.refresh(pending, access: reader.access)
        if case .current(let row) = recovery.result { check(row.id == "63001", "durable reopen reads original target") }
        else { fatalError("missing row") }
        check(try reopened.intents() == [intent], "current state does not complete unknown intent")
        reader.scope = .init(realm: "synthetic://review", accountID: 21, epoch: 2)
        check(recovery.result == nil, "epoch change immediately hides result")
        reader.totalPages = 7; reader.targetPage = 7; reader.reads = []
        await recovery.refresh(pending, access: reader.access)
        check(recovery.result == .notInLoadedPages(hasMore: true) && reader.reads == [1,2,3,4,5], "five page bound")
        await recovery.loadMore()
        check(reader.reads == [1,2,3,4,5,6,7], "explicit continuation")
        reader.targetPage = nil; reader.totalPages = 1
        await recovery.refresh(pending, access: reader.access)
        check(recovery.result == .notInLoadedPages(hasMore: false), "missing row remains unknown")
        reader.targetPage = 1; reader.fail = true
        await recovery.refresh(pending, access: reader.access)
        check(recovery.result == nil && recovery.failure == .denied, "failed read publishes no result")
        reader.fail = false
        await recovery.refresh(pending, access: reader.access)
        check(recovery.result != nil, "explicit read retry")
        reader.authorizationGeneration = UUID()
        check(recovery.result == nil, "authorization change immediately hides result")
        reader.hook = { recovery.invalidate() }
        await recovery.refresh(pending, access: reader.access)
        check(recovery.result == nil && !recovery.isBusy, "dismissal fences late result")
        reader.hook = nil
        await recovery.refresh(pending, access: reader.access)
        try reopened.complete(intent)
        check(recovery.result == nil, "removed intent immediately hides result")
        try Data("corrupt".utf8).write(to: path)
        do { _ = try recovery.pending(access: reader.access); fatalError("accepted corrupt journal") }
        catch { check(error as? MerchantBusinessFailure == .journal, "corrupt journal fails closed") }
        print("12 isolated state-machine checks passed; HTTP/Xcode journey not run")
    }
}
'''

with tempfile.TemporaryDirectory(prefix='l6-review-recovery-') as directory:
    temp = Path(directory)
    sources = [ROOT / 'Core/MerchantBusinessValue.swift', ROOT / 'Core/MerchantReviewReplyRecovery.swift']
    # These unmodified declarations are extracted to avoid unrelated Apple-only
    # writer dependencies. The reader and document above are explicitly test doubles.
    reading = (ROOT / 'Core/MerchantBusinessReading.swift').read_text()
    declarations = 'import Foundation\npublic struct MerchantBusinessScope:' + reading.split('public struct MerchantBusinessScope:', 1)[1].split('@MainActor public protocol MerchantBusinessReading:')[0]
    declarations += (ROOT / 'Core/MerchantBusinessCoordinator.swift').read_text().split('public struct MerchantBusinessConfirmation:')[0]
    declarations += (ROOT / 'Core/MerchantBusinessDocuments.swift').read_text().split('public struct MerchantBusinessSection:')[0]
    (temp / 'Declarations.swift').write_text(declarations)
    (temp / 'Ports.swift').write_text(PORTS)
    # Check throwing operations outside the autoclosure.
    runner = RUNNER.replace('check(try reopened.intents() == [intent],', 'let retained = try reopened.intents(); check(retained == [intent],')
    (temp / 'Runner.swift').write_text(runner)
    env = dict(os.environ, CLANG_MODULE_CACHE_PATH=str(temp / 'cache'))
    subprocess.run([ARGS.swiftc, '-swift-version', '5', '-parse-as-library', *map(str, sources),
                    str(temp / 'Declarations.swift'), str(temp / 'Ports.swift'), str(temp / 'Runner.swift'),
                    '-o', str(temp / 'checks')], env=env, check=True)
    subprocess.run([str(temp / 'checks')], check=True)
