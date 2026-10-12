import Foundation
import Observation

/// Only a real owned detail's displayed registration number is eligible. The reader
/// identity remains complete; an account ID alone is not an accepted-source binding.
public struct ProfileOrderNumberCopyContext: Equatable {
    public let registrationID: Int
    public let registrationNo: String
    public let identity: ProfileReadIdentity
    public let readerID: ObjectIdentifier
    @MainActor public static func capture(order: ProfileOrder, requestedID: Int,
        reader: any ProfileReading) -> Self? {
        guard requestedID > 0, order.id == requestedID, reader.isConfigured,
              let identity = reader.identity, identity.accountID > 0,
              order.memberID == identity.accountID, let number = order.registrationNo,
              !number.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return .init(registrationID: requestedID, registrationNo: number,
            identity: identity, readerID: ObjectIdentifier(reader))
    }
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.registrationID == rhs.registrationID && lhs.identity == rhs.identity && lhs.readerID == rhs.readerID
            && lhs.registrationNo.utf8.elementsEqual(rhs.registrationNo.utf8)
    }
}
public struct ProfileOrderNumberCopyPermit: Equatable {
    public let id: UUID
    fileprivate let context: ProfileOrderNumberCopyContext
    fileprivate init(context: ProfileOrderNumberCopyContext) { id = UUID(); self.context = context }
}
public enum ProfileOrderNumberCopyResult: Equatable { case copied, failed }

/// The accepted source is captured once. Identity changes retire it permanently;
/// returning to the same account cannot rebind an old response before a fresh read.
@MainActor @Observable public final class ProfileOrderNumberCopyModel {
    public let expected: ProfileOrderNumberCopyContext?
    public private(set) var permit: ProfileOrderNumberCopyPermit?
    public private(set) var result: ProfileOrderNumberCopyResult?
    private var presentationID: UUID?
    private var retired = false
    private var copying = false
    public init(context: ProfileOrderNumberCopyContext?) { expected = context }
    public func matches(_ current: ProfileOrderNumberCopyContext?) -> Bool {
        !retired && expected != nil && expected == current
    }
    public func appear(current: ProfileOrderNumberCopyContext?) {
        guard matches(current), let expected else { retire(); return }
        presentationID = UUID(); permit = .init(context: expected); result = nil
    }
    public func suspend() { presentationID = nil; permit = nil; result = nil }
    public func retire() { retired = true; suspend() }
    /// A synchronous sink starts only after a fresh owner/presentation check. Consuming
    /// the rendered permit first prevents queued or reentrant duplicate actions.
    @discardableResult public func copy(_ offered: ProfileOrderNumberCopyPermit,
        current: @MainActor () -> ProfileOrderNumberCopyContext?,
        write: @MainActor (String) throws -> Void) -> ProfileOrderNumberCopyResult? {
        guard !copying, permit == offered, let started = presentationID,
              matches(current()), let expected, offered.context == expected else { return nil }
        permit = .init(context: expected); copying = true; result = nil
        defer { copying = false }
        let outcome: ProfileOrderNumberCopyResult
        do { try write(expected.registrationNo); outcome = .copied }
        catch { outcome = .failed }
        guard presentationID == started, matches(current()) else { return nil }
        result = outcome
        return outcome
    }
}
