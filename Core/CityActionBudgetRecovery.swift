import Foundation
import Observation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Per-deployment/account durable original, separate from participation. No tokens, location or deletion API.
@MainActor public final class CityActionBudgetJournal {
    struct Record: Codable, Equatable {
        let scope: [String], prepared: CityActionBudgetPrepared, bytes: Data
        var response: Data?, status: Int?
    }
    private let root: URL
    public init(directory: URL) throws { guard directory.isFileURL else { throw CityActionBudgetFailure.storage }; root = directory }
    private func file(_ scope: CityActionBudgetScope) throws -> URL {
        try scope.durableKey.reduce(root.appendingPathComponent("city-action-budget-original-v1", isDirectory: true)) { url, value in
            let component = Data(value.utf8).base64EncodedString().replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "+", with: "-")
            guard !component.isEmpty, component.utf8.count <= 240 else { throw CityActionBudgetFailure.storage }
            return url.appendingPathComponent(component, isDirectory: true)
        }.appendingPathComponent("original.json")
    }
    func load(_ scope: CityActionBudgetScope) throws -> Record? {
        let path = try file(scope); guard FileManager.default.fileExists(atPath: path.path) else { return nil }
        let data = try Data(contentsOf: path); guard data.count <= 2_000_000 else { throw CityActionBudgetFailure.storage }
        let record = try JSONDecoder().decode(Record.self, from: data); try record.prepared.validate()
        guard record.scope == scope.durableKey, try record.prepared.command.bytes() == record.bytes else { throw CityActionBudgetFailure.storage }
        if let status = record.status, let response = record.response {
            guard case .complete = try CityActionBudgetReader.decodeReceipt(response, status: status, prepared: record.prepared) else { throw CityActionBudgetFailure.storage }
        } else if record.status != nil || record.response != nil { throw CityActionBudgetFailure.storage }
        return record
    }
    func begin(_ prepared: CityActionBudgetPrepared, scope: CityActionBudgetScope) throws -> Record {
        try prepared.validate(); let bytes = try prepared.command.bytes(), path = try file(scope)
        let archive = path.deletingLastPathComponent().appendingPathComponent("completed", isDirectory: true)
        guard !FileManager.default.fileExists(atPath: archive.appendingPathComponent(prepared.command.requestId + ".json").path) else { throw CityActionBudgetFailure.busy }
        if let old = try load(scope) {
            guard old.status != nil, old.prepared.command.requestId != prepared.command.requestId else { throw CityActionBudgetFailure.busy }
            let target = archive.appendingPathComponent(old.prepared.command.requestId + ".json")
            if FileManager.default.fileExists(atPath: target.path) {
                let saved = try JSONDecoder().decode(Record.self, from: Data(contentsOf: target))
                guard saved == old else { throw CityActionBudgetFailure.storage }
            } else { try write(JSONEncoder().encode(old), to: target) }
        }
        let record = Record(scope: scope.durableKey, prepared: prepared, bytes: bytes, response: nil, status: nil)
        try write(JSONEncoder().encode(record), to: path); return record
    }
    func complete(_ record: Record, response: Data, status: Int, scope: CityActionBudgetScope) throws {
        guard let saved = try load(scope), saved == record, saved.status == nil,
              case .complete = try CityActionBudgetReader.decodeReceipt(response, status: status, prepared: saved.prepared) else { throw CityActionBudgetFailure.storage }
        var completed = saved; completed.response = response; completed.status = status
        try write(JSONEncoder().encode(completed), to: file(scope))
    }
    private func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try data.write(to: url, options: .atomic); try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        guard try Data(contentsOf: url) == data else { throw CityActionBudgetFailure.storage }
    }
}

/// Explicit caller must retire currentScope on full identity/role/revision loss. Default grants are nil.
@MainActor @Observable public final class CityActionBudgetRecovery {
    public enum Display: Equatable { case hidden, unavailable, empty, unknown, complete(Int), storageBlocked }
    public private(set) var display: Display = .hidden
    private var stateValue: CityActionBudgetState?
    public var state: CityActionBudgetState? { guard let scope, isCurrent, reader.isStateCurrent(scope, region: region) else { return nil }; return stateValue }
    public private(set) var result: CityActionBudgetResult?
    public private(set) var prepared: CityActionBudgetPrepared?
    public private(set) var busy = false
    private let api: APIConfiguration, region: String
    private let transport: any HTTPTransport
    private let journal: CityActionBudgetJournal
    private let reader: CityActionBudgetReader
    private let currentScope: () -> CityActionBudgetScope?
    private let commandGrant: () -> CityActionBudgetCommandGrant?
    private var scope: CityActionBudgetScope?
    private var visit: UInt64 = 0
    public init(configuration: APIConfiguration, region: String, transport: any HTTPTransport, journal: CityActionBudgetJournal,
                currentScope: @escaping () -> CityActionBudgetScope?, readGrant: @escaping () -> CityActionBudgetReadGrant? = { nil },
                commandGrant: @escaping () -> CityActionBudgetCommandGrant? = { nil },
                receiptGrant: @escaping (CityOriginalReceiptReference) -> CityOriginalReceiptReadGrant? = { _ in nil }) {
        api = configuration; self.region = region; self.transport = transport; self.journal = journal; self.currentScope = currentScope; self.commandGrant = commandGrant
        reader = .init(configuration: configuration, transport: transport, current: currentScope, grant: readGrant, receiptGrant: receiptGrant)
    }
    private func valid(_ original: CityActionBudgetScope, _ stamp: UInt64) -> Bool {
        scope == original && currentScope() == original && visit == stamp && api.baseURL == original.session.baseURL && original.session.market == .china
    }
    public var isCurrent: Bool { guard let scope else { return false }; return valid(scope, visit) }
    public func close() { visit &+= 1; scope = nil; stateValue = nil; result = nil; prepared = nil; busy = false; display = .hidden }
    public func open() async {
        close(); guard let current = currentScope(), current.session.baseURL == api.baseURL, current.session.market == .china else { display = .unavailable; return }
        scope = current
        do { try restore(current) } catch { display = .storageBlocked; return }
        await refresh()
    }
    private func restore(_ original: CityActionBudgetScope) throws {
        result = nil
        guard let saved = try journal.load(original) else { display = .empty; return }
        if let status = saved.status, let response = saved.response,
           case .complete(_, let verified) = try CityActionBudgetReader.decodeReceipt(response, status: status, prepared: saved.prepared) {
            display = .complete(status); result = verified
        } else { display = .unknown }
    }
    public func refresh() async {
        guard !busy, let original = scope else { return }; let stamp = visit
        stateValue = nil; prepared = nil; busy = true; defer { if visit == stamp { busy = false } }
        do {
            let fresh = try await reader.state(original, region: region)
            guard valid(original, stamp) else { if visit == stamp { close() }; return }; stateValue = fresh
        } catch { if !valid(original, stamp), visit == stamp { close() } }
    }
    public func prepare() {
        guard !busy, let original = scope, valid(original, visit), display == .empty || isComplete, let state else { return }
        prepared = try? .init(state: state, region: region, requestID: UUID().uuidString.lowercased())
    }
    public func cancelPreparation() { prepared = nil }
    private var isComplete: Bool { if case .complete = display { return true }; return false }
    public var canSubmit: Bool {
        guard !busy, display == .empty || isComplete, let original = scope, valid(original, visit), let prepared,
              let issued = commandGrant(), issued.scope == original, !issued.isRevoked,
              let bytes = try? prepared.command.bytes(), issued.bytes == bytes else { return false }; return true
    }
    public func submit() async {
        guard canSubmit, let original = scope, let pending = prepared, let issued = commandGrant(),
              issued.scope == original, !issued.isRevoked, let bytes = try? pending.command.bytes(), issued.bytes == bytes else { return }
        let stamp = visit; busy = true; defer { if visit == stamp { busy = false } }
        let saved: CityActionBudgetJournal.Record
        do { saved = try journal.begin(pending, scope: original) }
        catch { prepared = nil; do { try restore(original) } catch { display = .storageBlocked }; return }
        stateValue = nil; prepared = nil; result = nil; display = .unknown
        guard valid(original, stamp), commandGrant() === issued, !issued.isRevoked, !Task.isCancelled else { close(); return }
        var request = URLRequest(url: api.baseURL.appendingPathComponent("api/city-game/action-budget/command"))
        request.httpMethod = "POST"; request.httpBody = saved.bytes; request.httpShouldHandleCookies = false; request.timeoutInterval = 20; request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(original.token, forHTTPHeaderField: "Authorization"); request.setValue("application/json", forHTTPHeaderField: "Content-Type"); request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (body, status) = try await transport.send(request)
            guard valid(original, stamp), commandGrant() === issued, !issued.isRevoked, !Task.isCancelled else { if visit == stamp { close() }; return }
            if case .complete = try CityActionBudgetReader.decodeReceipt(body, status: status, prepared: saved.prepared) {
                try journal.complete(saved, response: body, status: status, scope: original); try restore(original)
            }
        } catch { if !valid(original, stamp), visit == stamp { close() } }
    }
    public func recheck() async {
        guard !busy, display == .unknown, let original = scope else { return }; let stamp = visit
        busy = true; defer { if visit == stamp { busy = false } }
        do {
            guard let saved = try journal.load(original), saved.status == nil else { return }
            let (body, status) = try await reader.receipt(original, prepared: saved.prepared)
            guard valid(original, stamp) else { if visit == stamp { close() }; return }
            if case .complete = try CityActionBudgetReader.decodeReceipt(body, status: status, prepared: saved.prepared) {
                try journal.complete(saved, response: body, status: status, scope: original); try restore(original)
            }
        } catch { if !valid(original, stamp), visit == stamp { close() } }
    }
}
