import Foundation
import Observation

/// Read-only locator for the existing v1 journal. It is not an index, grant, or
/// replacement record. The original flow remains the sole record/receipt parser.
public enum NativeChannelReportJournalLocator {
    public static func conversationID(in key: String, context: RuntimeDependencyContext) -> Int? {
        let family = "native-channel-report.v1."
        guard key.utf8.count <= 16 * 1024, key.hasPrefix(family),
              let data = Data(base64Encoded: String(key.dropFirst(family.count))),
              data.base64EncodedString() == String(key.dropFirst(family.count)) else { return nil }
        let owner = [context.session.namespace, context.baseURL.absoluteString, String(context.session.accountID)]
            .map { "\($0.utf8.count):\($0)" }.joined()
        let prefix = Array(owner.utf8), bytes = Array(data)
        guard context.market == .china, context.session.accountID > 0, !context.session.namespace.isEmpty,
              bytes.starts(with: prefix), let tail = String(bytes: bytes.dropFirst(prefix.count), encoding: .utf8),
              let colon = tail.firstIndex(of: ":") else { return nil }
        let number = String(tail[tail.index(after: colon)...])
        guard let id = Int(number), id > 0, String(id) == number,
              String(tail[..<colon]) == String(number.utf8.count) else { return nil }
        return id
    }
}

/// Pending requests saved on this device only, not a server-wide report history.
/// Channel membership/history is intentionally absent. Account, token, epoch,
/// viewer context, and exact receipt issuance remain live independent fences.
@MainActor @Observable public final class NativeChannelReportRecoveryDirectory {
    public enum State: Equatable { case idle, ready, unavailable }
    public struct Entry: Identifiable {
        public let conversationID: Int
        public let requestID: String
        public let owner: NativeChannelReportFlow
        public var id: String { "\(conversationID):\(requestID)" }
    }
    public private(set) var state: State = .idle
    public private(set) var entries: [Entry] = []
    public private(set) var hasUnreadableRecords = false
    @ObservationIgnored private let context: RuntimeDependencyContext
    @ObservationIgnored private let transport: any HTTPTransport
    @ObservationIgnored private let storage: any ProjectEditDataStorage
    @ObservationIgnored private let journalKeys: () throws -> [String]
    @ObservationIgnored private let current: () -> Bool
    @ObservationIgnored private let permitsRead: (String) -> Bool
    @ObservationIgnored private let unauthorized: () -> Void
    private var active = true
    private var generation: UInt64 = 0

    public init(context: RuntimeDependencyContext, transport: any HTTPTransport,
                storage: any ProjectEditDataStorage, journalKeys: @escaping () throws -> [String],
                current: @escaping () -> Bool, permitsRead: @escaping (String) -> Bool,
                unauthorized: @escaping () -> Void) throws {
        _ = try NativeChannelTextScope(context: context, conversationID: 1)
        self.context = context; self.transport = transport; self.storage = storage
        self.journalKeys = journalKeys; self.current = current
        self.permitsRead = permitsRead; self.unauthorized = unauthorized
    }
    public var isCurrent: Bool { active && current() }
    public var visibleEntries: [Entry] { isCurrent ? entries : [] }

    /// Local protected reads only. Never dispatches a GET or POST on entry/restart.
    public func reload() {
        generation &+= 1; entries = []; hasUnreadableRecords = false
        guard isCurrent else { state = .unavailable; return }
        let ticket = generation
        do {
            let keys = try journalKeys()
            guard isCurrent else { state = .unavailable; return }
            let conversations = Set(keys.compactMap { NativeChannelReportJournalLocator.conversationID(in: $0, context: context) })
            guard conversations.count <= 4096 else { throw NativeChannelTextJournalError.unavailable }
            for conversationID in conversations.sorted() {
                let live: () -> Bool = { [weak self] in
                    guard let self else { return false }
                    return self.isCurrent && self.generation == ticket
                }
                let owner = try NativeChannelReportFlow(context: context, conversationID: conversationID,
                    transport: transport, storage: storage, current: live,
                    permitsWrite: { false }, permitsRead: permitsRead, unauthorized: unauthorized)
                guard live() else { entries = []; state = .unavailable; return }
                if owner.state == .unavailable { hasUnreadableRecords = true }
                else if owner.hasPending, let requestID = owner.requestID {
                    entries.append(Entry(conversationID: conversationID, requestID: requestID, owner: owner))
                }
                // A journal settled between enumeration and read is simply absent.
                // No absent/corrupt row ever authorizes a replacement request.
            }
            state = .ready
        } catch {
            entries = []; state = .unavailable
        }
    }
    /// A retired directory never revives; foreground/reentry obtains a fresh owner.
    public func retire() {
        active = false; generation &+= 1; entries = []; hasUnreadableRecords = false; state = .unavailable
    }
}
