import Foundation
import Observation

public struct NativeChannelMessagePin: Decodable, Equatable, Identifiable {
    public let id: NativeChannelMessageID
    public let message_id: NativeChannelMessageID
    public let conversation_id: NativeChannelMessageID
    public let summary: String
    public let sort_no: Int
}
public struct NativeChannelMessagePinPage: Decodable {
    public let list: [NativeChannelMessagePin]
    public let total: Int
    public let limit: Int
    func verify(_ binding: NativeChannelMessageBinding) throws {
        guard limit == 20, total == list.count, list.count <= 20,
              Set(list.map(\.id)).count == list.count, Set(list.map(\.message_id)).count == list.count,
              list.allSatisfy({ $0.conversation_id == binding.conversationID }) else { throw APIError.malformedResponse }
    }
}

/// Ephemeral confirmation only, not a writer, authority grant, or receipt store.
/// The source version is frozen for UI revalidation; PIN/UNPIN do not accept a CAS field.
@MainActor public struct NativeChannelMessagePinSelection {
    public let command: NativeChannelMessageCommand
    public let identity: MessagingReadIdentity
    public let snapshot: NativeChannelMessageSnapshot
    public let sourcePin: NativeChannelMessagePin?
    public init(snapshot: NativeChannelMessageSnapshot, client: any NativeChannelMessageAccess,
                sourcePin: NativeChannelMessagePin? = nil) throws {
        guard let identity = client.identity, let pinned = snapshot.pinned,
              snapshot.status == 0, snapshot.version > 0,
              snapshot.conversationID == client.binding.conversationID,
              sourcePin == nil || (pinned && sourcePin?.message_id == snapshot.id
                  && sourcePin?.conversation_id == snapshot.conversationID),
              client.allows(.mutate(pinned ? .unpin : .pin)),
              client.allows(.receipt) else { throw APIError.invalidRequest }
        self.identity = identity; self.snapshot = snapshot; self.sourcePin = sourcePin
        command = try .init(operation: pinned ? .unpin : .pin, requestID: UUID().uuidString,
                            binding: client.binding, messageID: snapshot.id)
    }
    public func isCurrent(_ client: any NativeChannelMessageAccess) -> Bool {
        client.identity == identity && client.binding == command.binding
            && client.allows(.mutate(command.operation)) && client.allows(.receipt)
    }
}

/// A current-list observation made AFTER the original same-UUID APPLIED receipt.
/// Neither an absent pin nor a failed list read proves any request outcome.
public struct NativeChannelMessagePinReadback: Equatable {
    public enum State: Equatable { case reading, matches, differs, failed }
    public let requestID: String
    public let operation: NativeChannelMessageOperation
    public let messageID: NativeChannelMessageID
    public let state: State
}

@MainActor @Observable public final class NativeChannelMessagePins {
    public private(set) var rows: [NativeChannelMessagePin] = []
    public private(set) var loading = false
    public private(set) var failed = false
    private let client: any NativeChannelMessageAccess
    private let expected: MessagingReadIdentity?
    private var generation = 0
    private var active = false
    private var appliedCommand: NativeChannelMessageCommand?
    private var readbackValue: NativeChannelMessagePinReadback?
    private var readbackGeneration = 0
    public init(client: any NativeChannelMessageAccess) { self.client = client; expected = client.identity }
    public var isCurrent: Bool { active && expected != nil && client.identity == expected && client.allows(.pins) }
    private var canRead: Bool { expected != nil && client.identity == expected && client.allows(.pins) }
    public var appliedReadback: NativeChannelMessagePinReadback? { canRead ? readbackValue : nil }
    public func activate() async {
        guard !Task.isCancelled else { return }
        active = true
        await reload()
    }
    public func retire() {
        active = false; generation += 1; rows = []; loading = false; failed = false
        if readbackValue?.state == .reading, let command = appliedCommand {
            readbackValue = observation(command, state: .failed)
        }
    }
    /// Called by the original coordinator on session retirement/redacted receipt, not sheet dismissal.
    public func retireAppliedReadback() {
        readbackGeneration += 1; appliedCommand = nil; readbackValue = nil
    }
    public func observeApplied(_ command: NativeChannelMessageCommand) async {
        guard command.operation == .pin || command.operation == .unpin,
              command.binding.sameTarget(as: client.binding) else { return }
        appliedCommand = command
        readbackValue = observation(command, state: .failed)
        await refreshAppliedReadback()
    }
    /// Read-only retry. It cannot settle a journal, infer APPLIED, or re-dispatch a command.
    public func refreshAppliedReadback() async {
        guard let command = appliedCommand, canRead, !Task.isCancelled else { return }
        readbackGeneration += 1; let run = readbackGeneration
        generation += 1; let listRun = generation
        if active { rows = []; failed = false; loading = true }
        readbackValue = observation(command, state: .reading)
        defer { if listRun == generation { loading = false } }
        do {
            let page = try await client.pins()
            guard run == readbackGeneration, canRead, !Task.isCancelled else { return }
            try page.verify(client.binding)
            if listRun == generation || !active { readbackValue = observation(command, page: page) }
            if active && listRun == generation { rows = page.list }
        } catch {
            guard run == readbackGeneration, canRead, !Task.isCancelled else { return }
            if listRun == generation || !active { readbackValue = observation(command, state: .failed) }
            if active && listRun == generation { rows = []; failed = true }
        }
    }
    private func observation(_ command: NativeChannelMessageCommand, state: NativeChannelMessagePinReadback.State) -> NativeChannelMessagePinReadback? {
        guard let id = command.messageID else { return nil }
        return .init(requestID: command.requestID, operation: command.operation, messageID: id, state: state)
    }
    private func observation(_ command: NativeChannelMessageCommand, page: NativeChannelMessagePinPage) -> NativeChannelMessagePinReadback? {
        let present = page.list.contains { $0.message_id == command.messageID }
        return observation(command, state: present == (command.operation == .pin) ? .matches : .differs)
    }
    /// The original event vetoes a summary, never supplies its replacement text.
    /// Invalidate synchronously so another original-reader await cannot retain old bodies.
    public func invalidateOriginalRows() {
        guard active else { return }
        generation += 1; rows = []; failed = false; loading = true
        if let command = appliedCommand { readbackValue = observation(command, state: .reading) }
    }
    public func refreshIfActive() async {
        guard active else { return }
        await reload()
    }
    public func reload() async {
        guard isCurrent, !Task.isCancelled else { retire(); return }
        generation += 1; let run = generation; rows = []; failed = false; loading = true
        if let command = appliedCommand { readbackValue = observation(command, state: .reading) }
        defer { if run == generation { loading = false } }
        do {
            let page = try await client.pins()
            guard run == generation, isCurrent, !Task.isCancelled else { return }
            try page.verify(client.binding)
            rows = page.list
            if let command = appliedCommand { readbackValue = observation(command, page: page) }
        } catch {
            guard run == generation else { return }
            if !isCurrent || Task.isCancelled { retire(); return }
            rows = []; failed = true
            if let command = appliedCommand { readbackValue = observation(command, state: .failed) }
        }
    }
    public func orderedIDs(_ indices: IndexSet, to destination: Int) throws -> [NativeChannelMessageID] {
        guard isCurrent, !loading, client.allows(.mutate(.sort)),
              (0...rows.count).contains(destination), indices.allSatisfy({ rows.indices.contains($0) }) else { throw APIError.invalidRequest }
        var ordered = rows.map(\.id)
        let moving = indices.sorted().map { ordered[$0] }
        for i in indices.sorted(by: >) { ordered.remove(at: i) }
        let target = destination - indices.filter { $0 < destination }.count
        ordered.insert(contentsOf: moving, at: target); return ordered
    }
}
