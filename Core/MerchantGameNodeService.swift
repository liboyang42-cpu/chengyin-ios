import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum MerchantGameNodeMessage: Equatable {
    case key(String), server(String)
}

public enum MerchantGameNodeLoadResult: Equatable {
    case ready(MerchantContentValue)
    case businessError(MerchantGameNodeMessage, reasonCode: String?)
    case networkError(MerchantGameNodeMessage)
}

public struct MerchantGameNodeReceipt: Equatable {
    public let receiptID: Int?, activityID: Int?, requestID: String?, action: String?, outcome: String?
    public let reasonCode: String?, revision: Int?, replayed: Bool, reason: String?
    public init(_ raw: MerchantContentValue) {
        receiptID = MerchantGameNodeWire.validID(raw["receiptId"]) ? MerchantGameNodeWire.number(raw["receiptId"]) : nil
        activityID = MerchantGameNodeWire.validID(raw["activityId"]) ? MerchantGameNodeWire.number(raw["activityId"]) : nil
        requestID = raw["requestId"].text; action = raw["action"].text; outcome = raw["outcome"].text
        reasonCode = raw["reasonCode"].display; revision = MerchantGameNodeWire.revision(raw["revision"])
        replayed = raw["replayed"].flag == true
        reason = MerchantGameNodeWire.safeReason(raw["result"]["reason"].text ?? raw["reason"].text)
    }
    /// validTerminalReceipt: positive receiptId and a numeric revision >= 0.
    public var isValidTerminal: Bool { (receiptID ?? 0) > 0 && revision != nil }
    /// matchingTerminalReceipt against the exact pending command/index.
    public func matches(_ pending: MerchantGameNodePendingIndex, outcome expected: String) -> Bool {
        isValidTerminal && activityID == pending.activityID && requestID == pending.requestID
            && action == pending.action.rawValue && outcome == expected
    }
}

public enum MerchantGameNodeWriteResult: Equatable {
    case success(MerchantGameNodeReceipt)
    case businessError(MerchantGameNodeMessage?, reasonCode: String?, receipt: MerchantGameNodeReceipt?)
    case unknown(MerchantGameNodeMessage?)
}

public enum MerchantGameNodeReceiptResult: Equatable {
    case matched(MerchantGameNodeReceipt)
    /// Backend PENDING views carry no action or revision; only identity is correlated.
    case pending
    case businessError(MerchantGameNodeMessage?, reasonCode: String?, receipt: MerchantGameNodeReceipt?)
    case invalidResponse(MerchantGameNodeMessage)
    case networkError
}

public enum MerchantGameNodeLiveCodeResult: Equatable {
    case ready(qrcodeURL: String, code: String, ttlSeconds: Int)
    case failure(MerchantGameNodeMessage)
}

public struct MerchantGameNodeEntry: Equatable, Identifiable {
    public var id: Int { activityID }
    public let activityID: Int, topicID: Int, activityName: String, startAt: String, endAt: String, stationCount: Int
    /// normalizeMerchantEntry
    public init?(_ raw: MerchantContentValue) {
        typealias W = MerchantGameNodeWire
        guard raw.object != nil, W.validID(raw["activityId"]), W.validID(raw["topicId"]),
              let activity = W.number(raw["activityId"]), let topic = W.number(raw["topicId"]) else { return nil }
        func entryText(_ value: MerchantContentValue, _ max: Int) -> String {
            guard case .string(let s) = value else { return "" }
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines); return t.utf16.count <= max ? t : ""
        }
        let name = entryText(raw["activityName"], 120)
        guard !name.isEmpty, case .integer(let count) = raw["stationCount"], count > 0 else { return nil }
        let start = raw["startAt"] == .null ? "" : entryText(raw["startAt"], 32)
        let end = raw["endAt"] == .null ? "" : entryText(raw["endAt"], 32)
        guard raw["startAt"] == .null || !start.isEmpty, raw["endAt"] == .null || !end.isEmpty else { return nil }
        activityID = activity; topicID = topic; activityName = name; startAt = start; endAt = end; stationCount = count
    }
}
public enum MerchantGameNodeEntriesResult: Equatable {
    case ready([MerchantGameNodeEntry])
    case failure(MerchantGameNodeMessage)
}

/// Pure response classification shared by every transport (game-session-client.js).
public enum MerchantGameNodeResults {
    public static let dynamicTTLMilliseconds = 300_000
    public static func projection(code: Int?, message: String?, data: MerchantContentValue, activityID: Int) -> MerchantGameNodeLoadResult {
        guard code == 200 else {
            return .businessError(MerchantGameNodeWire.safeMessage(message).map(MerchantGameNodeMessage.server) ?? .key("merchantGameNode.error.readFailed"),
                                  reasonCode: data["reasonCode"].display)
        }
        guard data.object != nil, data["perspective"].text == "MERCHANT", MerchantGameNodeWire.sameID(data["activityId"], activityID),
              MerchantGameNodeWire.revision(data["revision"]) != nil, MerchantGameNodeWire.validID(data["sessionId"]) else {
            return .businessError(.key("merchantGameNode.error.invalidData"), reasonCode: nil)
        }
        return .ready(data)
    }
    public static func command(code: Int?, message: String?, data: MerchantContentValue, command: MerchantGameNodeCommand) -> MerchantGameNodeWriteResult {
        guard code == 200 else {
            return .businessError(MerchantGameNodeWire.safeMessage(message).map(MerchantGameNodeMessage.server),
                                  reasonCode: data["reasonCode"].display, receipt: nil)
        }
        let receipt = MerchantGameNodeReceipt(data)
        guard data.object != nil, MerchantGameNodeWire.sameID(data["activityId"], command.activityID),
              receipt.requestID == command.requestID, receipt.action == command.action.rawValue else { return .unknown(nil) }
        if receipt.outcome == "FAILED" {
            guard receipt.isValidTerminal else { return .unknown(nil) }
            return .businessError(receipt.reason.map(MerchantGameNodeMessage.server), reasonCode: receipt.reasonCode, receipt: receipt)
        }
        guard receipt.outcome == "APPLIED", receipt.isValidTerminal else { return .unknown(nil) }
        return .success(receipt)
    }
    public static func receipt(code: Int?, message: String?, data: MerchantContentValue, activityID: Int, requestID: String) -> MerchantGameNodeReceiptResult {
        guard code == 200 else {
            return .businessError(MerchantGameNodeWire.safeMessage(message).map(MerchantGameNodeMessage.server) ?? .key("merchantGameNode.error.receiptRead"),
                                  reasonCode: data["reasonCode"].display, receipt: nil)
        }
        let receipt = MerchantGameNodeReceipt(data)
        guard data.object != nil, MerchantGameNodeWire.sameID(data["activityId"], activityID), receipt.requestID == requestID else {
            return .invalidResponse(.key("merchantGameNode.error.receiptInvalid"))
        }
        if receipt.outcome == "PENDING" { return .pending }
        if receipt.outcome == "FAILED" {
            guard receipt.isValidTerminal else { return .invalidResponse(.key("merchantGameNode.error.receiptIncomplete")) }
            return .businessError(receipt.reason.map(MerchantGameNodeMessage.server), reasonCode: receipt.reasonCode, receipt: receipt)
        }
        guard receipt.outcome == "APPLIED", receipt.isValidTerminal else { return .invalidResponse(.key("merchantGameNode.error.receiptState")) }
        return .matched(receipt)
    }
    public static func liveCode(code: Int?, message: String?, data: MerchantContentValue) -> MerchantGameNodeLiveCodeResult {
        guard code == 200, data.object != nil, let value = data["code"].text, !value.isEmpty else {
            let text = (message ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return .failure(text.isEmpty ? .key("merchantGameNode.checkin.error") : .server(text))
        }
        let ttl = MerchantGameNodeWire.number(data["ttlMs"]).flatMap { $0 > 0 ? $0 : nil } ?? dynamicTTLMilliseconds
        return .ready(qrcodeURL: data["qrcodeUrl"].text ?? "", code: value, ttlSeconds: ttl / 1000)
    }
    public static func entries(code: Int?, message: String?, data: MerchantContentValue) -> MerchantGameNodeEntriesResult {
        guard code == 200 else {
            return .failure(MerchantGameNodeWire.safeMessage(message).map(MerchantGameNodeMessage.server) ?? .key("merchantGameNode.entries.failed"))
        }
        guard let rows = data.array else { return .failure(.key("merchantGameNode.entries.invalid")) }
        let entries = rows.compactMap(MerchantGameNodeEntry.init)
        guard entries.count == rows.count else { return .failure(.key("merchantGameNode.entries.invalid")) }
        return .ready(entries)
    }
}

@MainActor public protocol MerchantGameNodeJournal: AnyObject {
    func index(forKey key: String) throws -> MerchantGameNodePendingIndex?
    func save(_ index: MerchantGameNodePendingIndex, forKey key: String) throws
    func remove(forKey key: String) throws
}
@MainActor public final class MerchantGameNodeMemoryJournal: MerchantGameNodeJournal {
    private var values: [String: MerchantGameNodePendingIndex] = [:]
    public var failsWrites = false
    public init(seed: [String: MerchantGameNodePendingIndex] = [:]) { values = seed }
    public func index(forKey key: String) throws -> MerchantGameNodePendingIndex? { values[key] }
    public func save(_ index: MerchantGameNodePendingIndex, forKey key: String) throws {
        guard !failsWrites else { throw MerchantContentFailure.storage }; values[key] = index
    }
    public func remove(forKey key: String) throws { values[key] = nil }
}

@MainActor public protocol MerchantGameNodeServing: AnyObject {
    var scope: UUID { get }
    var isAuthenticated: Bool { get }
    var permitsWrites: Bool { get }
    func loadProjection(activityID: Int) async -> MerchantGameNodeLoadResult
    func loadEntries() async -> MerchantGameNodeEntriesResult
    func issueLiveCode(activityID: Int, nodeID: Int) async -> MerchantGameNodeLiveCodeResult
    func submit(_ command: MerchantGameNodeCommand) async -> MerchantGameNodeWriteResult
    func readReceipt(activityID: Int, requestID: String) async -> MerchantGameNodeReceiptResult
    func persistPending(_ index: MerchantGameNodePendingIndex) -> Bool
    func restorePending(activityID: Int) -> MerchantGameNodePendingIndex?
    func clearPending(activityID: Int)
}

public struct MerchantGameNodeSession: Equatable {
    public let accountID: Int, epoch: UInt64, storageScope: String
    let token: String
    public init(accountID: Int, epoch: UInt64, storageScope: String, token: String) throws {
        guard accountID > 0, !storageScope.isEmpty, AuthRequestBuilder.isValidToken(token) else { throw MerchantContentFailure.invalid }
        self.accountID = accountID; self.epoch = epoch; self.storageScope = storageScope; self.token = token
    }
    func journalKey(activityID: Int) -> String {
        "merchant_game_unknown_write_v1_" + String(storageScope.utf8.count) + ":" + storageScope + "_m" + String(accountID) + "_a" + String(activityID)
    }
}

/// Direct HTTP binding. Writes require a journal and either the injected offline harness or an
/// enabled gate whose reviewed per-market allowlist names both routes (empty by default).
@MainActor public final class MerchantGameNodeHTTPService: MerchantGameNodeServing {
    public static let viewPath = "api/game/session/view", entriesPath = "api/game/session/merchant/entries"
    public static let commandPath = "api/game/session/command", receiptPath = "api/game/session/receipt"
    public static let liveCodePath = "api/merchant/chapter-node/live-checkin-code"
    private let configuration: APIConfiguration?
    private let transport: any HTTPTransport
    private let currentSession: () -> MerchantGameNodeSession?
    private let journal: (any MerchantGameNodeJournal)?
    private let execution: MerchantContentService.Execution
    private let gates: MerchantCityNPCParityGates
    private let market: RegionalMarket?
    private let onUnauthorized: (MerchantGameNodeSession) -> Void
    private var previous: MerchantGameNodeSession?
    private var stamp = UUID()
    public init(configuration: APIConfiguration?, transport: any HTTPTransport, currentSession: @escaping () -> MerchantGameNodeSession?,
                journal: (any MerchantGameNodeJournal)? = nil, execution: MerchantContentService.Execution = .disabled,
                gates: MerchantCityNPCParityGates = .disabled, market: RegionalMarket? = nil,
                onUnauthorized: @escaping (MerchantGameNodeSession) -> Void = { _ in }) {
        self.configuration = configuration; self.transport = transport; self.currentSession = currentSession
        self.journal = journal; self.execution = execution; self.gates = gates; self.market = market
        self.onUnauthorized = onUnauthorized; previous = currentSession()
    }
    public var scope: UUID { let s = currentSession(); if s != previous { previous = s; stamp = UUID() }; return stamp }
    public var isAuthenticated: Bool { currentSession() != nil }
    public var permitsWrites: Bool {
        guard journal != nil else { return false }
        if execution == .injectedOfflineHarness && transport is any MerchantContentOfflineTransport { return true }
        guard gates.stationCommands, let market else { return false }
        return gates.allows(Self.commandPath, market: market) && gates.allows(Self.receiptPath, market: market)
    }

    private enum Body { case none, json([String: MerchantContentValue]), form([String: String]) }
    private struct Reply { let code: Int?; let message: String?; let data: MerchantContentValue }
    private enum Failure: Error { case network, unauthorized }

    private func send(_ path: String, query: [String: String] = [:], body: Body) async throws -> Reply {
        guard let session = currentSession(), let configuration else { throw Failure.network }
        var components = URLComponents(url: configuration.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        if !query.isEmpty { components?.queryItems = query.keys.sorted().map { URLQueryItem(name: $0, value: query[$0]) } }
        guard let url = components?.url else { throw Failure.network }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20; request.cachePolicy = .reloadIgnoringLocalCacheData; request.httpShouldHandleCookies = false
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(session.token, forHTTPHeaderField: "Authorization")
        switch body {
        case .none: request.httpMethod = "GET"
        case .json(let fields):
            request.httpMethod = "POST"; request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(fields)
        case .form(let fields):
            request.httpMethod = "POST"; request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            var encoder = URLComponents(); encoder.queryItems = fields.keys.sorted().map { URLQueryItem(name: $0, value: fields[$0]) }
            request.httpBody = Data((encoder.percentEncodedQuery ?? "").utf8)
        }
        let bytes: Data, status: Int
        do { (bytes, status) = try await transport.send(request) } catch { throw Failure.network }
        guard currentSession() == session else { throw Failure.network }
        if status == 401 { onUnauthorized(session); throw Failure.unauthorized }
        guard (200..<300).contains(status), let value = try? JSONDecoder().decode(MerchantContentValue.self, from: bytes),
              value.object != nil else { throw Failure.network }
        return Reply(code: MerchantGameNodeWire.number(value["code"]), message: value["msg"].text, data: value["data"])
    }

    public func loadProjection(activityID: Int) async -> MerchantGameNodeLoadResult {
        guard activityID > 0 else { return .businessError(.key("merchantGameNode.error.badParameters"), reasonCode: nil) }
        do {
            let reply = try await send(Self.viewPath, query: ["activityId": String(activityID), "perspective": "MERCHANT"], body: .none)
            return MerchantGameNodeResults.projection(code: reply.code, message: reply.message, data: reply.data, activityID: activityID)
        } catch { return .networkError(.key("merchantGameNode.error.network")) }
    }
    public func loadEntries() async -> MerchantGameNodeEntriesResult {
        do {
            let reply = try await send(Self.entriesPath, body: .none)
            return MerchantGameNodeResults.entries(code: reply.code, message: reply.message, data: reply.data)
        } catch { return .failure(.key("merchantGameNode.entries.network")) }
    }
    public func issueLiveCode(activityID: Int, nodeID: Int) async -> MerchantGameNodeLiveCodeResult {
        guard nodeID > 0 else { return .failure(.key("merchantGameNode.checkin.error")) }
        do {
            let reply = try await send(Self.liveCodePath, body: .form(["nodeId": String(nodeID)]))
            return MerchantGameNodeResults.liveCode(code: reply.code, message: reply.message, data: reply.data)
        } catch { return .failure(.key("merchantGameNode.checkin.network")) }
    }
    public func submit(_ command: MerchantGameNodeCommand) async -> MerchantGameNodeWriteResult {
        guard permitsWrites else { return .businessError(.key("merchantGameNode.writesDisabled"), reasonCode: nil, receipt: nil) }
        guard let body = try? command.body() else { return .businessError(.key("merchantGameNode.error.invalidCommand"), reasonCode: nil, receipt: nil) }
        do {
            let reply = try await send(Self.commandPath, body: .json(body))
            return MerchantGameNodeResults.command(code: reply.code, message: reply.message, data: reply.data, command: command)
        } catch { return .unknown(nil) }
    }
    public func readReceipt(activityID: Int, requestID: String) async -> MerchantGameNodeReceiptResult {
        guard activityID > 0, MerchantGameNodeRequestID.isValid(requestID) else { return .businessError(.key("merchantGameNode.error.receiptParameters"), reasonCode: nil, receipt: nil) }
        do {
            let reply = try await send(Self.receiptPath, query: ["activityId": String(activityID), "requestId": requestID], body: .none)
            return MerchantGameNodeResults.receipt(code: reply.code, message: reply.message, data: reply.data, activityID: activityID, requestID: requestID)
        } catch { return .networkError }
    }
    public func persistPending(_ index: MerchantGameNodePendingIndex) -> Bool {
        guard let journal, let session = currentSession(), index.isValid else { return false }
        do { try journal.save(index, forKey: session.journalKey(activityID: index.activityID)); return true } catch { return false }
    }
    public func restorePending(activityID: Int) -> MerchantGameNodePendingIndex? {
        guard let journal, let session = currentSession() else { return nil }
        let key = session.journalKey(activityID: activityID)
        guard let saved = try? journal.index(forKey: key) else { return nil }
        guard saved.activityID == activityID, saved.isValid else { try? journal.remove(forKey: key); return nil }
        return saved
    }
    public func clearPending(activityID: Int) {
        guard let journal, let session = currentSession() else { return }
        try? journal.remove(forKey: session.journalKey(activityID: activityID))
    }
}

/// Production read binding over the existing approved merchant-content service. It never writes:
/// commands and receipt reads stay unavailable until a reviewed station-command composition exists.
@MainActor public final class MerchantGameNodeContentReader: MerchantGameNodeServing {
    private let service: any MerchantContentServing
    public init(service: any MerchantContentServing) { self.service = service }
    public var scope: UUID { service.scope }
    public var isAuthenticated: Bool { service.isAuthenticated }
    public var permitsWrites: Bool { false }
    private func message(_ error: Error) -> (MerchantGameNodeMessage, network: Bool) {
        if case MerchantContentFailure.rejected(_, let text)? = error as? MerchantContentFailure {
            return (MerchantGameNodeWire.safeMessage(text).map(MerchantGameNodeMessage.server) ?? .key("merchantGameNode.error.readFailed"), false)
        }
        switch error as? MerchantContentFailure {
        case .denied?: return (.key("merchantGameNode.error.forbidden"), false)
        case .malformed?, .invalid?: return (.key("merchantGameNode.error.invalidData"), false)
        default: break
        }
        if error as? APIError == .unauthorized { return (.key("merchantGameNode.error.signedOut"), false) }
        return (.key("merchantGameNode.error.network"), true)
    }
    public func loadProjection(activityID: Int) async -> MerchantGameNodeLoadResult {
        guard activityID > 0 else { return .businessError(.key("merchantGameNode.error.badParameters"), reasonCode: nil) }
        do {
            let snapshot = try await service.load(.game(activityID: activityID))
            return MerchantGameNodeResults.projection(code: 200, message: nil, data: snapshot.value, activityID: activityID)
        } catch {
            let mapped = message(error)
            return mapped.network ? .networkError(mapped.0) : .businessError(mapped.0, reasonCode: nil)
        }
    }
    public func loadEntries() async -> MerchantGameNodeEntriesResult {
        do {
            let snapshot = try await service.load(.gameEntries)
            return MerchantGameNodeResults.entries(code: 200, message: nil, data: snapshot.value)
        } catch { return .failure(message(error).network ? .key("merchantGameNode.entries.network") : .key("merchantGameNode.entries.failed")) }
    }
    public func issueLiveCode(activityID: Int, nodeID: Int) async -> MerchantGameNodeLiveCodeResult {
        do {
            let snapshot = try await service.load(.liveCode(activityID: activityID, nodeID: nodeID))
            return MerchantGameNodeResults.liveCode(code: 200, message: nil, data: snapshot.value)
        } catch {
            if case MerchantContentFailure.rejected(_, let text)? = error as? MerchantContentFailure,
               let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .failure(.server(text)) }
            return .failure(message(error).network ? .key("merchantGameNode.checkin.network") : .key("merchantGameNode.checkin.error"))
        }
    }
    public func submit(_ command: MerchantGameNodeCommand) async -> MerchantGameNodeWriteResult {
        .businessError(.key("merchantGameNode.writesDisabled"), reasonCode: nil, receipt: nil)
    }
    public func readReceipt(activityID: Int, requestID: String) async -> MerchantGameNodeReceiptResult {
        .businessError(.key("merchantGameNode.writesDisabled"), reasonCode: nil, receipt: nil)
    }
    public func persistPending(_ index: MerchantGameNodePendingIndex) -> Bool { false }
    public func restorePending(activityID: Int) -> MerchantGameNodePendingIndex? { nil }
    public func clearPending(activityID: Int) {}
}
