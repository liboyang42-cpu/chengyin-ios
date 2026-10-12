import Foundation

/// Presentation-only review. Stores no name, phone, address, identity or writer.
/// The existing draft remains the single source for validation and serialization.
public struct ProfileParticipantValidationReview: Equatable {
    public private(set) var hasRequestedReview = false

    public init() {}

    public mutating func request(in draft: ParticipantFormDraft) -> ProfileParticipantValidationField? {
        hasRequestedReview = true
        return draft.validation.map { ProfileParticipantValidationField($0) }
    }

    public func issue(in draft: ParticipantFormDraft) -> ProfileParticipantValidationField? {
        guard let validation = draft.validation else { return nil }
        // Preserve the existing live phone hint before the first explicit review.
        guard hasRequestedReview || (validation == .invalidPhone && !draft.mobilePhone.isEmpty) else { return nil }
        return ProfileParticipantValidationField(validation)
    }
}

public enum ProfileParticipantValidationField: String, Equatable, Hashable {
    case name, phone

    public init(_ validation: ParticipantFormValidation) {
        switch validation {
        case .nameRequired: self = .name
        case .invalidPhone: self = .phone
        }
    }

    public var messageKey: String { "profile.participantValidation." + rawValue }
}
