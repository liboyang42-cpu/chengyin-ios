import Foundation
import Observation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Original own member-state writer and receipt, not an alternate notification preference store.
@MainActor @Observable public final class NativeChannelPersonalStateFlow {
    public struct Snapshot: Equatable { public let pinned: Bool, hidden: Bool, muted: Bool, permanentMuted: Bool; public let mutedUntil: String? }
    public enum Field: String, Codable, CaseIterable { case pinned, hidden, muted }
    public enum State: Equatable { case idle, loading, ready, reviewing, submitting, unknown, applied, appliedHidden, unavailable }
    public private(set) var state: State = .idle
    public private(set) var reviewedSummary = ""
    public private(set) var originalRequestID: String?
    public private(set) var readingCurrent = false
    public private(set) var currentReadFailed = false
    private var snapshot: Snapshot?
    private var pending: Record?
    private var review: Record?
    private var generation: UInt64 = 0
    private var active = false
    private var busy = false
    private var storageFailed = false
    @ObservationIgnored private let captured: NativeChannelManagementIntegrationContext
    @ObservationIgnored private let channels: any NativeChannelManagementIntegrationContextProviding
    @ObservationIgnored private let context: RuntimeDependencyContext
    @ObservationIgnored private let transport: any HTTPTransport
    @ObservationIgnored private let storage: any ProjectEditDataStorage
    @ObservationIgnored private let current: () -> Bool
    @ObservationIgnored private let permits: (String,String) -> Bool
    @ObservationIgnored private let unauthorized: () -> Void
    @ObservationIgnored private let makeRequestID: () -> UUID
    private static var leases: Set<String> = []
    private struct Record: Codable, Equatable { let schema: Int, owner: String, requestID: String, field: Field, value: Bool, body: Data }
    private var owner: String { [context.session.namespace,context.baseURL.absoluteString,String(context.session.accountID),captured.ownerType,captured.ownerID.rawValue,captured.channelID.rawValue].map { "\($0.utf8.count):\($0)" }.joined() }
    private var key: String { "channel-personal-state.v1."+Data(owner.utf8).base64EncodedString() }
    private var path: String { "api/channels/"+captured.channelID.rawValue }
    public var isCurrent: Bool { active && current() && channels.contextIsCurrent(captured) }
    public var currentState: Snapshot? { isCurrent ? snapshot : nil }
    public var hasPending: Bool { pending != nil }
    public var canPrepare: Bool { isCurrent && !busy && !storageFailed && pending == nil && snapshot != nil && permits("POST",path+"/member-state") }
    public var canRecover: Bool { isCurrent && !busy && !storageFailed && pending.map { permits("GET",receiptPath($0.requestID)) } == true }
    public var canRetry: Bool { canRecover && permits("POST",path+"/member-state") }
    public init(captured: NativeChannelManagementIntegrationContext,channels: any NativeChannelManagementIntegrationContextProviding,
                context: RuntimeDependencyContext,transport: any HTTPTransport,storage: any ProjectEditDataStorage,
                current: @escaping () -> Bool,permits: @escaping (String,String) -> Bool,unauthorized: @escaping () -> Void, makeRequestID: @escaping () -> UUID = { UUID() }) throws {
        guard captured.identity.owner.accountID == context.session.accountID,captured.identity.owner.namespace == context.session.namespace,
              captured.identity.owner.baseURL == context.baseURL.absoluteString,captured.identity.epoch == context.session.epoch,
              channels.contextIsCurrent(captured) else { throw APIError.unauthorized }
        self.captured=captured;self.channels=channels;self.context=context;self.transport=transport;self.storage=storage
        self.current=current;self.permits=permits;self.unauthorized=unauthorized;self.makeRequestID=makeRequestID
        do { pending=try restore();originalRequestID=pending?.requestID;if pending != nil { state = .unknown } }
        catch { storageFailed=true;state = .unavailable }
    }
    public func deactivate() { generation &+= 1; active=false;snapshot=nil;readingCurrent=false;currentReadFailed=false;review=nil;reviewedSummary="";state = .unavailable }
    public func activate() async { guard !active else { return };active=true;await refresh() }
    public func refresh() async {
        guard isCurrent,!busy,!storageFailed,Self.leases.insert(key).inserted else { return }
        busy=true;let run = generation;defer { busy=false;Self.leases.remove(key) }
        do {
            pending=try restore();originalRequestID=pending?.requestID
            if let original=pending {
                state = .unknown;let result=try await exchange("GET",receiptPath(original.requestID))
                guard valid(run) else { throw APIError.unauthorized }
                if try settle(original,result),state == .applied { await readCurrent(afterApplied:true) }
                return
            }
            await readCurrent(afterApplied:state == .applied)
        } catch { guard valid(run) else { return }; snapshot=nil;if isCurrent { state = pending == nil ? .unavailable : .unknown } }
    }
    public func prepare(_ field: Field,value: Bool) {
        guard canPrepare else { return };let id=makeRequestID().uuidString.lowercased()
        guard let bytes=try? JSONSerialization.data(withJSONObject:["request_id":id,field.rawValue:value ? 1 : 0],options:[.sortedKeys]) else { return }
        review=Record(schema:1,owner:owner,requestID:id,field:field,value:value,body:bytes)
        let name=field == .pinned ? "本人置顶" : field == .hidden ? "本人隐藏" : "本人静音"
        reviewedSummary="频道 \(captured.channelID.rawValue) · \(name)：\(value ? "开启" : "关闭")\n只修改当前本人这一项偏好，不影响他人的偏好或频道可见权限。"+(field == .muted ? "静音开启沿原通知服务设置永久静音；关闭取消本频道静音，但其他原通知设置仍可能让有效状态静音。" : "隐藏后可从目录的本人隐藏恢复入口重新显示。")
        state = .reviewing
    }
    public func cancelReview() { review=nil;reviewedSummary="";state = pending == nil ? .ready : .unknown }
    public func confirm() async {
        guard let original=review,canPrepare,Self.leases.insert(key).inserted else { return }
        busy=true;let run = generation;defer { busy=false;Self.leases.remove(key) }
        // A new command must be recoverable by its own immutable request ID.
        // Missing capability is not a dispatched/unknown request or a storage failure.
        guard permits("GET",receiptPath(original.requestID)) else {
            review=nil;reviewedSummary="";state = .unavailable;return
        }
        do {
            guard try restore() == nil else { throw APIError.invalidRequest }
            try storage.write(JSONEncoder().encode(original),key:key);guard try restore() == original else { throw APIError.malformedResponse }
            pending=original;originalRequestID=original.requestID;review=nil;state = .submitting
            let result = try await exchange("POST",path+"/member-state",body:original.body,freshReceiptID:original.requestID)
            guard valid(run) else { return }
            if try settle(original,result) {
                if state == .applied { await readCurrent(afterApplied:true) }
            } else { state = .unknown }
        } catch { guard valid(run) else { return }; if pending == nil { storageFailed=true };if isCurrent { state = pending == nil ? .unavailable : .unknown } }
    }
    public func retryOriginal() async {
        guard canRetry,let original=pending,Self.leases.insert(key).inserted else { return }
        busy=true;let run = generation;defer { busy=false;Self.leases.remove(key) }
        do {
            guard try restore() == original else { throw APIError.malformedResponse }
            let receipt=try await exchange("GET",receiptPath(original.requestID))
            guard valid(run) else { throw APIError.unauthorized }
            if try settle(original,receipt) { if state == .applied { await readCurrent(afterApplied:true) };return }
            guard receipt["status"] as? String == "NOT_FOUND",receipt["request_id"] as? String == original.requestID,
                  receipt["resume_with_same_request"] as? Int == 1 else { state = .unknown;return }
            state = .submitting
            let result = try await exchange("POST",path+"/member-state",body:original.body)
            guard valid(run) else { return }
            if try settle(original,result) {
                if state == .applied { await readCurrent(afterApplied:true) }
            } else { state = .unknown }
        } catch { guard valid(run) else { return }; if isCurrent { state = .unknown } }
    }
    private func settle(_ original: Record,_ value: [String:Any]) throws -> Bool {
        guard value["request_id"] as? String == original.requestID else { throw APIError.malformedResponse }
        guard value["status"] as? String == "APPLIED" else { return false }
        guard isCurrent,try restore() == original else { throw APIError.malformedResponse }
        let hidden=value["result_redacted"] as? Int == 1
        var result: Snapshot?
        if !hidden {
            guard NativeChannelGovernanceNotice.positive(value["channel_id"]) == captured.channelID.rawValue,
                  NativeChannelGovernanceNotice.positive(value["member_id"]) == String(context.session.accountID) else { throw APIError.malformedResponse }
            result=try parse(value)
            if original.field == .pinned { guard result?.pinned == original.value else { throw APIError.malformedResponse } }
            if original.field == .hidden { guard result?.hidden == original.value else { throw APIError.malformedResponse } }
            // Effective muted can still be true after cancelling this channel mute: do not falsify the original result.
        }
        try storage.remove(key);guard try restore() == nil else { throw APIError.malformedResponse }
        // Historical receipt fields validate the original result only. They must never
        // become the current toggle source for the next independent command.
        pending=nil;originalRequestID=nil;snapshot=nil;currentReadFailed=false;reviewedSummary="";state=hidden ? .appliedHidden : .applied;return true
    }
    /// An independently authorized original detail read, never a mutation retry.
    /// Failure here cannot revoke a proved APPLIED receipt or revive its journal.
    private func readCurrent(afterApplied: Bool) async {
        let run = generation
        snapshot=nil;currentReadFailed=false;readingCurrent=true
        if !afterApplied { state = .loading }
        defer { readingCurrent=false }
        do {
            let result=try await exchange("GET",path)
            guard valid(run),
                  NativeChannelGovernanceNotice.positive(result["id"]) == captured.channelID.rawValue,
                  let own=result["my_state"] as? [String:Any] else { throw APIError.malformedResponse }
            snapshot=try parse(own);state = afterApplied ? .applied : .ready
        } catch {
            guard valid(run) else { return }
            snapshot=nil
            if isCurrent { currentReadFailed=true;state = afterApplied ? .applied : .unavailable }
        }
    }
    private func parse(_ value: [String:Any]) throws -> Snapshot {
        func flag(_ name: String) throws -> Bool { guard let n=value[name] as? Int,[0,1].contains(n) else { throw APIError.malformedResponse };return n == 1 }
        guard let permanent=value["permanent_muted"] as? Bool else { throw APIError.malformedResponse }
        return try Snapshot(pinned:flag("pinned"),hidden:flag("hidden"),muted:flag("muted"),permanentMuted:permanent,mutedUntil:value["muted_until"] as? String)
    }
    private func restore() throws -> Record? {
        guard let bytes=try storage.read(key) else { return nil };guard bytes.count <= 8192 else { throw APIError.malformedResponse }
        let row=try JSONDecoder().decode(Record.self,from:bytes)
        guard row.schema == 1,row.owner == owner,UUID(uuidString:row.requestID) != nil,row.body.count <= 1024,
              let body=try JSONSerialization.jsonObject(with:row.body) as? [String:Any],Set(body.keys) == ["request_id",row.field.rawValue],
              body["request_id"] as? String == row.requestID,body[row.field.rawValue] as? Int == (row.value ? 1 : 0) else { throw APIError.malformedResponse };return row
    }
    private func receiptPath(_ id: String) -> String { "api/channels/member-state-requests/"+id }
    private func valid(_ run: UInt64) -> Bool { run == generation && isCurrent && !Task.isCancelled }
    private func exchange(_ method: String,_ path: String,body: Data? = nil,query: [URLQueryItem] = [],freshReceiptID: String? = nil) async throws -> [String:Any] {
        let run = generation
        guard valid(run),permits(method,path) else { throw APIError.unauthorized }
        let fresh=try await channels.currentChannelContext(channelID:captured.channelID)
        guard valid(run),permits(method,path),fresh == captured else { throw APIError.unauthorized }
        // Recheck after the asynchronous context refresh. A journal already saved
        // remains pending if authority changes; receipt-only recovery stays separate.
        guard freshReceiptID.map({ permits(method,path) && permits("GET",receiptPath($0)) }) ?? true else { throw APIError.unauthorized }
        guard var url=URLComponents(url:context.baseURL.appendingPathComponent(path),resolvingAgainstBaseURL:false) else { throw APIError.invalidRequest }
        if !query.isEmpty { url.queryItems=query };guard let target=url.url else { throw APIError.invalidRequest }
        var request=URLRequest(url:target);request.httpMethod=method;request.httpShouldHandleCookies=false
        request.setValue(context.session.token,forHTTPHeaderField:"Authorization");request.setValue("application/json",forHTTPHeaderField:"Accept")
        if let body { request.httpBody=body;request.setValue("application/json",forHTTPHeaderField:"Content-Type") }
        guard valid(run), permits(method,path) else { throw APIError.unauthorized }
        try Task.checkCancellation();let (bytes,status)=try await transport.send(request)
        guard valid(run), permits(method,path) else { throw APIError.unauthorized };try Task.checkCancellation()
        if status == 401 { unauthorized();throw APIError.unauthorized }
        guard bytes.count <= 512*1024,let envelope=try JSONSerialization.jsonObject(with:bytes) as? [String:Any] else { throw APIError.malformedResponse }
        let code=(envelope["code"] as? NSNumber)?.intValue
        if status == 401 || code == 401 { unauthorized();throw APIError.unauthorized }
        guard (200..<300).contains(status),code == 200,let result=envelope["data"] as? [String:Any] else { throw APIError.malformedResponse };return result
    }
}
