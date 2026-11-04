import Foundation
import CryptoKit
import Observation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private func checkinID(_ s: String) -> Bool { Int64(s).map { $0 > 0 && String($0) == s } == true }
private func checkinDate(_ s: String) -> Bool {
    guard s.range(of: #"^[1-9][0-9]{3}-[0-9]{2}-[0-9]{2}$"#, options: .regularExpression) != nil else { return false }
    let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.calendar = Calendar(identifier: .gregorian)
    f.timeZone = TimeZone(secondsFromGMT: 0); f.dateFormat = "yyyy-MM-dd"; f.isLenient = false
    return f.date(from: s).map { f.string(from: $0) == s } == true
}
public struct NativeChannelCheckinCommand: Codable, Equatable {
    public let requestId, channelId, checkinDate: String
    public var digest: String { SHA256.hash(data: Data(["checkin-v1", channelId, checkinDate].map { "\($0.utf8.count):\($0)" }.joined().utf8)).map { String(format: "%02x", $0) }.joined() }
    fileprivate func validate() throws {
        guard checkinID(channelId), checkinDateIsValid(checkinDate), UUID(uuidString: requestId)?.uuidString.lowercased() == requestId else { throw APIError.invalidRequest }
    }
}
private func checkinDateIsValid(_ value: String) -> Bool { checkinDate(value) }
/// Business dates and rollover come from one server snapshot, never the device timezone.
private func checkinClock(date: String, timezone: String, serverTime: Int64, nextDayAt: Int64) -> Bool {
    guard timezone == "Asia/Shanghai", checkinDateIsValid(date), serverTime > 0,
          nextDayAt > serverTime, nextDayAt <= 253_402_300_799_999,
          let zone = TimeZone(identifier: timezone) else { return false }
    var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
    let instant = Date(timeIntervalSince1970: Double(serverTime) / 1000)
    let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.calendar = calendar; formatter.timeZone = zone; formatter.dateFormat = "yyyy-MM-dd"
    guard formatter.string(from: instant) == date,
          let next = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: instant)) else { return false }
    return Int64((next.timeIntervalSince1970 * 1000).rounded()) == nextDayAt
}
public struct NativeChannelCheckinFact: Decodable {
    public let id, channelId, memberId, checkinDate, source: String
    public let streak: Int
    public let checkedAt: Int64
    fileprivate func validate(channel: String, actor: String, date: String) throws {
        guard checkinID(id), channelId == channel, memberId == actor, checkinDate == date, streak > 0,
              streak <= Int(Int32.max), checkedAt > 0, ["CHANNEL", "EVENT", "MANUAL"].contains(source) else { throw APIError.malformedResponse }
    }
}
public struct NativeChannelCheckinHistory: Decodable, Identifiable {
    public let checkinDate, kind: String
    public let policyVersion: String?
    public var id: String { checkinDate }
}
public struct NativeChannelCheckinPolicy: Decodable {
    public let configured, enabled: Bool
    public let version: String?
    public let windowDays: Int?
    public let publishedAt: Int64?
    public let timezone: String
    fileprivate func validate() throws {
        guard timezone == "Asia/Shanghai" else { throw APIError.malformedResponse }
        if !configured { guard !enabled, version == nil, windowDays == nil, publishedAt == nil else { throw APIError.malformedResponse }; return }
        guard version.map(checkinID) == true, publishedAt.map({ $0 > 0 }) == true,
              enabled ? windowDays.map({ $0 > 0 && $0 <= Int(Int32.max) }) == true : windowDays == nil else { throw APIError.malformedResponse }
    }
}
public struct NativeChannelCheckinStatus: Decodable {
    let source: String
    public let actorId, channelId, timezone, checkinDate: String
    public let serverTime, nextDayAt: Int64
    public let checked, canCheckin, makeupSelfService, rewardPolicyConfigured: Bool
    public let fact: NativeChannelCheckinFact?
    public let streak: Int
    public let streakThrough: String?
    public let history: [NativeChannelCheckinHistory]
    public let makeupPolicy: NativeChannelCheckinPolicy
    fileprivate func validate(channel: String, actor: String) throws {
        guard source == "original-channel-checkin-v1", channelId == channel, actorId == actor,
              checkinClock(date: checkinDate, timezone: timezone, serverTime: serverTime, nextDayAt: nextDayAt),
              checked == (fact != nil), !checked || !canCheckin, !makeupSelfService, !rewardPolicyConfigured,
              streak >= 0, streak <= Int(Int32.max), history.count <= 30, Set(history.map(\.id)).count == history.count,
              streak == 0 ? streakThrough == nil : streakThrough.map(checkinDateIsValid) == true else { throw APIError.malformedResponse }
        if let fact { try fact.validate(channel: channel, actor: actor, date: checkinDate); guard streak == fact.streak, streakThrough == checkinDate else { throw APIError.malformedResponse } }
        var previous: String?
        for day in history {
            guard checkinDateIsValid(day.checkinDate), day.checkinDate <= checkinDate,
                  previous.map({ day.checkinDate < $0 }) ?? true,
                  day.kind == "CHECKIN" ? day.policyVersion == nil : day.kind == "MAKEUP" && day.policyVersion.map(checkinID) == true else { throw APIError.malformedResponse }
            previous = day.checkinDate
        }
        try makeupPolicy.validate()
    }
}
public struct NativeChannelCheckinRankRow: Decodable, Identifiable {
    public let memberId: String
    public let rank: Int?
    public let days, makeupDays, streak: Int
    public let nickname, avatar: String?
    public var id: String { memberId }
    fileprivate func validate(period: Int) throws {
        guard checkinID(memberId), (0...period).contains(days), (0...days).contains(makeupDays),
              streak >= 0, streak <= Int(Int32.max), rank.map({ $0 > 0 && $0 <= Int(Int32.max) }) ?? true else { throw APIError.malformedResponse }
    }
}
public struct NativeChannelCheckinRank: Decodable {
    let source: String
    public let actorId, channelId, timezone, checkinDate: String
    public let serverTime, nextDayAt: Int64
    public let periodDays, limit: Int
    public let list: [NativeChannelCheckinRankRow]
    public let me: NativeChannelCheckinRankRow
    public let othersVisible, hasMore: Bool
    fileprivate func validate(channel: String, actor: String, requestedLimit: Int) throws {
        guard source == "original-channel-checkin-v1", actorId == actor, channelId == channel,
              checkinClock(date: checkinDate, timezone: timezone, serverTime: serverTime, nextDayAt: nextDayAt),
              periodDays == 30, limit == requestedLimit,
              list.count <= limit, Set(list.map(\.id)).count == list.count, me.memberId == actor,
              othersVisible || (list.isEmpty && me.rank == nil && !hasMore), !hasMore || (list.count == limit && limit < 50) else { throw APIError.malformedResponse }
        try me.validate(period: periodDays)
        for (index, row) in list.enumerated() {
            try row.validate(period: periodDays)
            guard row.rank == index + 1, row.days > 0 else { throw APIError.malformedResponse }
            if index > 0 {
                let prior = list[index-1]
                guard prior.days > row.days || prior.days == row.days && Int64(prior.memberId)! < Int64(row.memberId)! else { throw APIError.malformedResponse }
            }
        }
        if let own = list.first(where: { $0.memberId == actor }) {
            guard own.rank == me.rank, own.days == me.days, own.makeupDays == me.makeupDays,
                  own.streak == me.streak else { throw APIError.malformedResponse }
        } else if let rank = me.rank, rank <= list.count { throw APIError.malformedResponse }
    }
}
private struct CheckinReceipt: Decodable {
    struct Result: Decodable {
        let id, channelId, memberId, checkinDate, source, resultCode: String
        let streak: Int
        let checkedAt: Int64
        let rewardIssued: Bool
    }
    let source, actorId, channelId, requestId, state: String
    let requestHash, checkinDate: String?
    let unappliedFinal, resultRedacted: Bool?
    let result: Result?
    func validate(_ command: NativeChannelCheckinCommand, actor: String) throws {
        guard source == "original-channel-checkin-request-v1", actorId == actor, channelId == command.channelId,
              requestId == command.requestId, requestHash == command.digest, checkinDate == command.checkinDate else { throw APIError.malformedResponse }
        if state == "NOT_FOUND" { guard unappliedFinal != nil, result == nil, resultRedacted == nil else { throw APIError.malformedResponse }; return }
        guard unappliedFinal == nil else { throw APIError.malformedResponse }
        if state == "PENDING" { guard result == nil, resultRedacted == nil else { throw APIError.malformedResponse }; return }
        guard state == "APPLIED" else { throw APIError.malformedResponse }
        if resultRedacted == true { guard result == nil else { throw APIError.malformedResponse }; return }
        guard resultRedacted == false, let result, checkinID(result.id), result.channelId == channelId,
              result.memberId == actor, result.checkinDate == checkinDate, ["CHANNEL", "EVENT", "MANUAL"].contains(result.source), result.streak > 0,
              result.streak <= Int(Int32.max),
              result.checkedAt > 0, ["CHECKED", "ALREADY_CHECKED"].contains(result.resultCode), result.resultCode != "CHECKED" || result.source == "CHANNEL", !result.rewardIssued else { throw APIError.malformedResponse }
    }
}
private struct CheckinHeader: Decodable { let code: Int; let errorCode: String? }
private struct CheckinEnvelope<Value: Decodable>: Decodable { let data: Value }
private enum CheckinError: Error { case rejected(String) }
@MainActor public final class NativeChannelCheckinService {
    public let channelID: String
    public var actorID: String { String(context.session.accountID) }
    private let context: RuntimeDependencyContext
    private let transport: any HTTPTransport
    private let permits: (String, String) -> Bool
    private let current: () -> Bool
    private let unauthorized: () -> Void
    private var retired = false
    public var isCurrent: Bool { guard !retired, current() else { retired = true; return false }; return true }
    public var canRead: Bool { allows("GET", "checkin-status") }
    public var canRank: Bool { allows("GET", "checkin-rank") }
    public var canWrite: Bool { allows("POST", "checkin") }
    public var canRecover: Bool { allows("GET", "checkin-request") }
    fileprivate func matches(_ candidate: RuntimeDependencyContext) -> Bool { context == candidate }
    public init(context: RuntimeDependencyContext, channelID: String, transport: any HTTPTransport,
                permits: @escaping (String, String) -> Bool, current: @escaping () -> Bool, unauthorized: @escaping () -> Void) throws {
        guard context.market == .china, context.session.accountID > 0, checkinID(channelID) else { throw APIError.notConfigured }
        self.context = context; self.channelID = channelID; self.transport = transport; self.permits = permits; self.current = current; self.unauthorized = unauthorized
    }
    private func allows(_ method: String, _ suffix: String) -> Bool { isCurrent && permits(method, "api/im/channel/" + suffix) }
    private func send<Value: Decodable>(_ suffix: String, command: NativeChannelCheckinCommand? = nil, query: [String: String] = [:], source: () -> Bool) async throws -> Value {
        let method = command == nil ? "GET" : "POST"
        guard source(), !Task.isCancelled, allows(method, suffix) else { throw APIError.notConfigured }
        var url = URLComponents(url: context.baseURL.appendingPathComponent("api/im/channel/" + suffix), resolvingAgainstBaseURL: false)!
        if command == nil { url.queryItems = (["channel_id": channelID].merging(query) { _, rhs in rhs }).sorted { $0.key < $1.key }.map { .init(name: $0.key, value: $0.value) } }
        guard let endpoint = url.url else { throw APIError.invalidRequest }
        var request = URLRequest(url: endpoint); request.httpMethod = method; request.httpShouldHandleCookies = false
        request.setValue(context.session.token, forHTTPHeaderField: "Authorization"); request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let command { try command.validate(); guard command.channelId == channelID else { throw APIError.invalidRequest }; request.httpBody = try JSONEncoder().encode(command); request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let (data, status) = try await transport.send(request)
        try Task.checkCancellation(); guard allows(method, suffix), source(), data.count <= 512 * 1024 else { throw APIError.notConfigured }
        let header = try? JSONDecoder().decode(CheckinHeader.self, from: data)
        if status == 401 || header?.code == 401 { unauthorized(); retired = true; throw APIError.unauthorized }
        guard (200..<300).contains(status), let header else { throw APIError.malformedResponse }
        guard header.code == 200 else {
            if [400,403,404,409].contains(header.code), let code = header.errorCode { throw CheckinError.rejected(code) }
            throw APIError.malformedResponse
        }
        return try JSONDecoder().decode(CheckinEnvelope<Value>.self, from: data).data
    }
    public func status(source: () -> Bool) async throws -> NativeChannelCheckinStatus {
        let value: NativeChannelCheckinStatus = try await send("checkin-status", source: source)
        try value.validate(channel: channelID, actor: actorID); return value
    }
    public func rank(limit: Int, source: () -> Bool) async throws -> NativeChannelCheckinRank {
        guard [10,50].contains(limit) else { throw APIError.invalidRequest }
        let value: NativeChannelCheckinRank = try await send("checkin-rank", query: ["days": "30", "limit": String(limit)], source: source)
        try value.validate(channel: channelID, actor: actorID, requestedLimit: limit); return value
    }
    fileprivate func receipt(_ command: NativeChannelCheckinCommand, source: () -> Bool) async throws -> CheckinReceipt {
        let value: CheckinReceipt = try await send("checkin-request", query: ["request_id": command.requestId, "checkin_date": command.checkinDate], source: source)
        try value.validate(command, actor: actorID); return value
    }
    fileprivate func perform(_ command: NativeChannelCheckinCommand, source: () -> Bool) async throws -> CheckinReceipt {
        let value: CheckinReceipt = try await send("checkin", command: command, source: source)
        try value.validate(command, actor: actorID); return value
    }
}

@MainActor private final class CheckinJournal {
    private let storage: any ProjectEditDataStorage
    private let owner, key: String
    private let channel: String
    private struct Stored: Codable { let schema: Int, owner: String, command: NativeChannelCheckinCommand }
    private static var leases: Set<String> = []
    init(storage: any ProjectEditDataStorage, context: RuntimeDependencyContext, channel: String) {
        self.storage = storage; self.channel = channel
        owner = [context.baseURL.absoluteString, context.session.namespace, String(context.session.accountID), channel].map { "\($0.utf8.count):\($0)" }.joined()
        key = "channel-daily-checkin.v1." + SHA256.hash(data: Data(owner.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    func acquire() -> Bool { Self.leases.insert(key).inserted }
    func release() { Self.leases.remove(key) }
    func restore() throws -> NativeChannelCheckinCommand? {
        guard let data = try storage.read(key) else { return nil }
        guard data.count < 8192 else { throw APIError.malformedResponse }
        let saved = try JSONDecoder().decode(Stored.self, from: data)
        guard saved.schema == 1, saved.owner == owner, saved.command.channelId == channel,
              (try JSONSerialization.jsonObject(with: data) as? NSDictionary) == (try JSONSerialization.jsonObject(with: JSONEncoder().encode(saved)) as? NSDictionary) else { throw APIError.malformedResponse }
        try saved.command.validate(); return saved.command
    }
    func save(_ command: NativeChannelCheckinCommand) throws {
        try command.validate(); guard command.channelId == channel, try restore() == nil else { throw APIError.invalidRequest }
        try storage.write(JSONEncoder().encode(Stored(schema: 1, owner: owner, command: command)), key: key)
        guard try restore() == command else { throw APIError.malformedResponse }
    }
    func settle(_ command: NativeChannelCheckinCommand) throws {
        guard try restore() == command else { throw APIError.invalidRequest }
        try storage.remove(key); guard try restore() == nil else { throw APIError.malformedResponse }
    }
}
public enum NativeChannelCheckinPhase: Equatable { case idle, reading, reviewing, submitting, unknown, applied, redacted, expiredUnapplied, rejected(String), failed, persistenceFailed, closed }
public struct NativeChannelCheckinConfirmedRequest: Equatable {
    public let requestID, checkinDate: String
    public let resultRedacted: Bool
}
@MainActor @Observable public final class NativeChannelCheckinFlow {
    public let service: NativeChannelCheckinService
    private var currentStatus: NativeChannelCheckinStatus?
    public var status: NativeChannelCheckinStatus? { isCurrent && service.canRead ? currentStatus : nil }
    private var confirmedRequest: NativeChannelCheckinConfirmedRequest?
    /// A current-status read cannot stand in for the original request's receipt.
    public var lastConfirmedRequest: NativeChannelCheckinConfirmedRequest? {
        isCurrent && service.canRecover ? confirmedRequest : nil
    }
    public private(set) var pending: NativeChannelCheckinCommand?
    public private(set) var review: NativeChannelCheckinCommand?
    public private(set) var phase: NativeChannelCheckinPhase = .idle
    public private(set) var busy = false
    private let journal: CheckinJournal
    private var active = false
    private var generation: UInt64 = 0
    @ObservationIgnored private var source: () -> Bool = { false }
    public var isCurrent: Bool { active && source() && service.isCurrent }
    public var canCheckin: Bool { isCurrent && !busy && pending == nil && review == nil && phase != .persistenceFailed && status?.canCheckin == true && service.canRead && service.canWrite && service.canRecover }
    public init(service: NativeChannelCheckinService, context: RuntimeDependencyContext, storage: any ProjectEditDataStorage) throws {
        guard service.matches(context) else { throw APIError.invalidRequest }
        self.service = service; journal = .init(storage: storage, context: context, channel: service.channelID)
    }
    public func activate(current: @escaping () -> Bool) async {
        deactivate()
        source = current; active = true; generation &+= 1; phase = .idle
        guard isCurrent, !Task.isCancelled else { deactivate(); return }
        do { pending = try journal.restore() } catch { phase = .persistenceFailed; return }
        if pending != nil { await recover() }
        if isCurrent, phase != .redacted, phase != .persistenceFailed { await refresh() }
    }
    public func deactivate() { active = false; generation &+= 1; busy = false; currentStatus = nil; confirmedRequest = nil; pending = nil; review = nil; phase = .closed }
    private func valid(_ run: UInt64) -> Bool { generation == run && isCurrent && !Task.isCancelled }
    public func refresh() async {
        guard isCurrent, !busy, review == nil, service.canRead else { return }
        generation &+= 1; let run = generation; busy = true; currentStatus = nil
        if pending == nil { phase = .reading }
        defer { if generation == run { busy = false } }
        do { let value = try await service.status(source: { self.valid(run) }); guard valid(run) else { return }; currentStatus = value; if pending == nil { phase = .idle } }
        catch { if valid(run) { currentStatus = nil; if pending == nil { phase = .failed } } }
    }
    public func prepare() {
        guard canCheckin, let status else { return }
        confirmedRequest = nil
        review = .init(requestId: UUID().uuidString.lowercased(), channelId: service.channelID, checkinDate: status.checkinDate); phase = .reviewing
    }
    public func cancelReview() { guard !busy else { return }; review = nil; phase = .idle }
    public func confirm() async {
        guard isCurrent, !busy, pending == nil, let command = review, service.canWrite, service.canRecover, journal.acquire() else { return }
        generation &+= 1; let run = generation; busy = true
        defer { journal.release(); if generation == run { busy = false } }
        do {
            let fresh = try await service.status(source: { self.valid(run) }); guard valid(run) else { return }; currentStatus = fresh
            guard fresh.canCheckin, fresh.checkinDate == command.checkinDate else { review = nil; phase = .rejected("CHECKIN_DATE_OR_STATE_CHANGED"); return }
            do { try journal.save(command) } catch { phase = .persistenceFailed; return }
            pending = command; review = nil; phase = .submitting
            await dispatch(command, run: run, retry: false)
        } catch { if valid(run) { review = nil; phase = .failed } }
    }
    public func recover() async {
        guard isCurrent, !busy, let command = pending, service.canRecover else { return }
        generation &+= 1; let run = generation; busy = true; phase = .reading
        defer { if generation == run { busy = false } }
        do { let value = try await service.receipt(command, source: { self.valid(run) }); guard valid(run) else { return }; try settle(value, command) }
        catch { if valid(run) { phase = .unknown } }
    }
    public func retryOriginal() async {
        guard isCurrent, !busy, let command = pending, service.canRecover, service.canWrite, journal.acquire() else { return }
        generation &+= 1; let run = generation; busy = true; phase = .reading
        defer { journal.release(); if generation == run { busy = false } }
        do {
            let receipt = try await service.receipt(command, source: { self.valid(run) }); guard valid(run) else { return }
            if receipt.state == "APPLIED" || receipt.unappliedFinal == true { try settle(receipt, command); return }
            guard receipt.state == "NOT_FOUND", try journal.restore() == command else { phase = .unknown; return }
            phase = .submitting; await dispatch(command, run: run, retry: true)
        } catch { if valid(run) { phase = .unknown } }
    }
    private func dispatch(_ command: NativeChannelCheckinCommand, run: UInt64, retry: Bool) async {
        do { let value = try await service.perform(command, source: { self.valid(run) }); guard valid(run) else { return }; try settle(value, command) }
        catch {
            guard valid(run) else { return }
            if !retry, case CheckinError.rejected(let code) = error, code != "REQUEST_ID_CONFLICT" {
                do { try journal.settle(command); pending = nil; phase = .rejected(code) } catch { phase = .persistenceFailed }
            } else { phase = .unknown }
        }
    }
    private func settle(_ value: CheckinReceipt, _ command: NativeChannelCheckinCommand) throws {
        guard value.state == "APPLIED" || value.state == "NOT_FOUND" && value.unappliedFinal == true else { phase = .unknown; return }
        do { try journal.settle(command) } catch { phase = .persistenceFailed; return }
        pending = nil; review = nil; currentStatus = nil
        confirmedRequest = value.state == "APPLIED" ? .init(requestID: command.requestId, checkinDate: command.checkinDate,
                                                          resultRedacted: value.resultRedacted == true) : nil
        phase = value.unappliedFinal == true ? .expiredUnapplied : value.resultRedacted == true ? .redacted : .applied
    }
}

/// A member cannot manufacture this system sender by putting a marker in a user card.
public enum NativeChannelCheckinReminder {
    public static func day(in snapshot: NativeChannelMessageSnapshot) -> String? {
        struct Body: Decodable { let source, channelId, checkinDate: String }
        guard snapshot.status == 0, snapshot.kind == .card, snapshot.senderType == 3, snapshot.senderID == nil,
              let bytes = snapshot.extraJSON?.data(using: .utf8), bytes.count <= 1024,
              let value = try? JSONDecoder().decode(Body.self, from: bytes),
              value.source == "original-channel-checkin-reminder-v1", value.channelId == snapshot.conversationID.rawValue,
              checkinDateIsValid(value.checkinDate) else { return nil }
        return value.checkinDate
    }
}
