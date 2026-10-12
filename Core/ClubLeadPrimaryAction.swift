import Foundation

/// P045 onOwnerPrimary navigates to existing screens; it never dispatches an invitation or publication.
public enum ClubLeadPrimaryAction: String, CaseIterable, Equatable {
    case publish, merchants, sentInvitations, topics, events
    public init?(stage: ClubLeadProgressStage) {
        switch stage {
        case .publish: self = .publish
        case .invite: self = .merchants
        case .pending: self = .sentInvitations
        case .accepted: self = .topics
        case .executionAccepted: self = .events
        case .partial: return nil
        }
    }
    public var titleKey: String { "club.leadPrimary." + rawValue }
}
