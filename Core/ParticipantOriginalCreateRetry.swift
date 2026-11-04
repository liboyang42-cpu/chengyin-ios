import Foundation

/// Ephemeral capability derived only from the original validated confirmation. It is
/// never Codable, never journaled, never recreated from a list match, and never changes
/// request ID or payload. The form releases it on dismissal, reload or identity change.
public struct ParticipantOriginalCreateRetry: Equatable {
    let confirmation: ParticipantConfirmation
    public var requestID: UUID { confirmation.id }
    public var identity: ProfileReadIdentity { confirmation.identity }
    public let fullName: String
    public let maskedPhone: String

    public init?(confirmation: ParticipantConfirmation) {
        guard case .save(let draft) = confirmation.mutation, draft.id == nil,
              let fields = try? draft.fields(), let name = fields["fullName"],
              let phone = fields["mobilePhone"] else { return nil }
        self.confirmation = confirmation; fullName = name
        maskedPhone = String(phone.prefix(3)) + "****" + String(phone.suffix(4))
    }

    /// Success is the same-owner, same-request writer's authoritative row, not a
    /// successful empty envelope, a similarly named list row or a local draft echo.
    public func accepts(_ row: ProfileParticipant?) -> Bool {
        guard let row, row.id > 0, case .save(let draft) = confirmation.mutation,
              draft.id == nil, let fields = try? draft.fields() else { return false }
        return row.fullName.utf8.elementsEqual((fields["fullName"] ?? "").utf8)
            && row.mobilePhone.utf8.elementsEqual((fields["mobilePhone"] ?? "").utf8)
    }
}
