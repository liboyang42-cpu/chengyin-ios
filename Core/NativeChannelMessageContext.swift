import Foundation
import Observation

public struct NativeChannelMessageContextPage: Decodable {
    public struct Side: Decodable {
        public let list:[NativeChannelMessageSnapshot]
        public let next_cursor:String?
        public let has_more:Bool
        public let next_after:String?
    }
    public let source:String
    public let conversation_id:NativeChannelMessageID
    public let anchor_id:NativeChannelMessageID
    public let anchor:NativeChannelMessageSnapshot
    public let older:Side
    public let newer:Side
    public func verify(binding:NativeChannelMessageBinding,anchor requested:NativeChannelMessageID)throws {
        let rows=older.list+[anchor]+newer.list
        guard source=="original-channel-message-context-v1",conversation_id==binding.conversationID,
              anchor_id==requested,anchor.id==requested,anchor.status==0,
              older.list.count<=20,newer.list.count<=20,Set(rows.map(\.id)).count==rows.count,
              rows.allSatisfy({$0.conversationID==binding.conversationID}),
              [older.next_cursor,older.next_after,newer.next_cursor,newer.next_after].compactMap({$0}).allSatisfy(NativeChannelMessageCursor.valid),
              !older.has_more || navigable(older.next_cursor,from:requested),
              !newer.has_more || navigable(newer.next_after,from:requested) else { throw APIError.malformedResponse }
    }
    private func navigable(_ cursor:String?,from anchor:NativeChannelMessageID)->Bool {
        guard let cursor,let id=NativeChannelMessageID(rawValue:cursor) else{return false}
        return id != anchor
    }
}
@MainActor @Observable public final class NativeChannelMessageContext {
    private var currentPage:NativeChannelMessageContextPage?
    public var page:NativeChannelMessageContextPage? {isCurrent ? currentPage:nil}
    public private(set) var selected:NativeChannelMessageID
    public private(set) var loading=false
    public private(set) var failed=false
    private let client:any NativeChannelMessageAccess
    private let expected:MessagingReadIdentity?
    private let expectedBinding:NativeChannelMessageBinding
    private var generation=0
    public init(client:any NativeChannelMessageAccess,selected:NativeChannelMessageID){self.client=client;self.selected=selected;expected=client.identity;expectedBinding=client.binding}
    public var isCurrent:Bool {expected != nil && client.identity==expected && client.binding==expectedBinding && client.allows(.context)}
    public func containsCurrent(_ snapshot:NativeChannelMessageSnapshot)->Bool {
        guard isCurrent,let page else{return false}
        return (page.older.list+[page.anchor]+page.newer.list).contains(snapshot)
    }
    public func currentMessage(id:Int)->MessagingMessage? {
        guard isCurrent,let page else{return nil}
        return (page.older.list+[page.anchor]+page.newer.list)
            .first(where:{$0.message.id==id && $0.status==0})?.message
    }
    public func open(_ id:NativeChannelMessageID?=nil) async {
        guard !Task.isCancelled else{return}
        if let id {selected=id}
        await readOriginal(replacing:true)
    }
    /// Same-source refresh keeps a still-authorized current row while the read is in flight.
    /// Failure/revocation or a changed result removes it; no stale fallback after completion.
    public func refresh() async { await readOriginal(replacing:false) }
    private func readOriginal(replacing:Bool) async {
        guard !Task.isCancelled else{return}
        generation+=1;let run=generation;let target=selected
        if replacing {currentPage=nil};failed=false;loading=true
        defer{if generation==run{
            loading=false
            if !isCurrent || Task.isCancelled {currentPage=nil}
        }}
        guard isCurrent else {currentPage=nil;return}
        do {
            let result=try await client.context(messageID:target)
            guard generation==run,isCurrent,!Task.isCancelled else{return}
            try result.verify(binding:expectedBinding,anchor:target);currentPage=result
        }catch{if generation==run {currentPage=nil;failed=isCurrent && !Task.isCancelled}}
    }
    public func retire(){generation+=1;currentPage=nil;loading=false;failed=false}
}

/// An independent current-source observation AFTER the original same-UUID receipt.
/// No journal, writer, replacement message cache, or inference of a request outcome.
public struct NativeChannelMessageEditRecallObservation: Equatable {
    public enum State: Equatable {
        case reading, unavailable, failed, accessClosed
        case visible(version: Int64, atAppliedEditVersion: Bool)
    }
    public let requestID: String
    public let operation: NativeChannelMessageOperation
    public let messageID: NativeChannelMessageID
    public let appliedVersion: Int64
    public let state: State
}

@MainActor @Observable public final class NativeChannelMessageEditRecallReadback {
    private let client: any NativeChannelMessageAccess
    private let expected: MessagingReadIdentity?
    private var binding: NativeChannelMessageBinding?
    private var value: NativeChannelMessageEditRecallObservation?
    private var generation = 0
    public private(set) var refreshing = false
    public init(client: any NativeChannelMessageAccess) { self.client = client; expected = client.identity }
    private var sameIdentity: Bool { expected != nil && client.identity == expected }
    public var observation: NativeChannelMessageEditRecallObservation? {
        guard sameIdentity, client.allows(.receipt), let value else { return nil }
        // Revocation must hide even the previously observed version immediately.
        return canRefresh ? value : observation(state: .accessClosed)
    }
    public var canRefresh: Bool {
        sameIdentity && client.allows(.receipt) && client.allows(.context)
            && value != nil && binding == client.binding
    }

    /// Called only by the existing coordinator after it verifies and settles its original journal.
    /// Receipt fields remain historical proof; a later context read cannot replace them.
    public func observeApplied(_ command: NativeChannelMessageCommand, receipt: NativeChannelMessageReceipt) async {
        guard command.operation == .edit || command.operation == .recall,
              command.binding.sameTarget(as: client.binding), sameIdentity,
              (try? receipt.verify(command)) == true, receipt.result_redacted != true,
              let version = receipt.result?.version, let messageID = command.messageID else { retire(); return }
        // Keep only proof identity/version, never the original edit body or recall reason.
        generation += 1; binding = client.binding
        refreshing = false
        value = .init(requestID: command.requestID, operation: command.operation, messageID: messageID,
                      appliedVersion: version, state: .accessClosed)
        await refresh()
    }
    /// Retry is GET-only. It never creates a UUID, settles a request, or submits a mutation.
    public func refresh() async {
        guard let proof = value, let binding,
              canRefresh, !refreshing, !Task.isCancelled else { return }
        generation += 1; let run = generation
        refreshing = true
        value = observation(state: .reading)
        defer {
            if generation == run {
                refreshing = false
                if value?.state == .reading { value = observation(state: canRefresh ? .failed : .accessClosed) }
            }
        }
        do {
            let page = try await client.context(messageID: proof.messageID)
            guard current(run), binding == client.binding else { return }
            try page.verify(binding: binding, anchor: proof.messageID)
            // A visible message after recall can be a later restoration. It never undoes APPLIED.
            value = observation(state: .visible(version: page.anchor.version,
                atAppliedEditVersion: proof.operation == .edit && page.anchor.version == proof.appliedVersion))
        } catch {
            guard current(run) else { return }
            // The real source deliberately collapses recalled/hidden/missing into this 404.
            // Do not label it "recalled", "not executed", or successful read-back of a tombstone.
            if let failure = error as? NativeChannelMessageFailure,
               (failure.httpStatus == 200 || failure.httpStatus == 404), failure.code == 404,
               failure.errorCode == "MESSAGE_CONTEXT_UNAVAILABLE" {
                value = observation(state: .unavailable)
            } else { value = observation(state: .failed) }
        }
    }
    public func retire() { generation += 1; binding = nil; value = nil; refreshing = false }
    private func current(_ run: Int) -> Bool { run == generation && canRefresh && !Task.isCancelled }
    private func observation(state: NativeChannelMessageEditRecallObservation.State) -> NativeChannelMessageEditRecallObservation? {
        guard let value else { return nil }
        return .init(requestID: value.requestID, operation: value.operation, messageID: value.messageID,
                     appliedVersion: value.appliedVersion, state: state)
    }
}
