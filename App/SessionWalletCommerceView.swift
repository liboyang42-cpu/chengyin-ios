import SwiftUI

/// Source wallet/history entry; hidden gamification and shop entry policy is not promoted here.
@MainActor struct SessionWalletCommerceView: View {
    @EnvironmentObject private var session: AppSession
    var visibility: WalletCommerceVisibility = {
        var value = WalletCommerceVisibility()
        value.assets = true; value.income = true; value.withdrawalRecords = true
        return value // points/mall remain false unless existing source gates explicitly supply them.
    }()
    var body: some View {
        // CoopFlowReading has no coop-finance grant. Session presence is not that grant, so this host does not send api/coop/finance.
        WalletCommerceHomeView(reader: session.walletHistoryReader, visibility: visibility,
            onCooperationFinance: {},
            invitationHistory: WalletInvitationHistoryAccess(session: session),
            organizerFinance: WalletOrganizerFinanceAccess(reader: session.cooperationFlowReader, allowsRead: { false }) {
                CoopFlowReadView(reader: session.cooperationFlowReader, resource: .finance, title: "coopflow.finance")
            })
            .id(session.walletHistoryViewIdentity)
    }
}


/// Uses the account invitation grant, never the wallet ledger grant. Construction
/// does not read history; the existing destination owns its request lifetime.
@MainActor struct WalletInvitationHistoryAccess {
    let reader: any SocialAccountReading
    let squareReader: any SquareReading
    let actions: SocialActionCoordinator?
    init(session: AppSession) {
        reader = session.profileInviteHistoryReader
        squareReader = session.squareReader
        actions = session.socialActionCoordinator
    }
}

/// Two independent self-profile reads; neither grants invitation sharing or submissions.
@MainActor struct ProfilePersonalToolsAccess {
    let owner: SocialAccountIdentity
    let wallet: WalletCommerceReader
    let walletScope: WalletCommerceScope?
    let complaint: any CoopFlowReading
    let complaintSession: CoopFlowSession?
    init(owner: SocialAccountIdentity, wallet: WalletCommerceReader, complaint: any CoopFlowReading) {
        self.owner = owner; self.wallet = wallet; walletScope = wallet.scope
        self.complaint = complaint; complaintSession = complaint.session
    }
}

@MainActor final class ProfilePersonalToolsAssociation {
    private let memberID: Int
    private let social: any SocialAccountReading
    private let viewer: SocialAccountIdentity
    private let revision: UInt64
    let access: ProfilePersonalToolsAccess
    private let current: @MainActor () -> Bool
    init(memberID: Int, social: any SocialAccountReading, access: ProfilePersonalToolsAccess,
         isCurrent: @escaping @MainActor () -> Bool) {
        self.memberID = memberID; self.social = social; self.access = access
        viewer = social.identity; revision = social.presentationRevision; current = isCurrent
    }
    var ownerIsCurrent: Bool {
        current() && memberID > 0 && access.owner.accountID == memberID && viewer == access.owner
            && social.identity == viewer && social.presentationRevision == revision && social.isConfigured
            && ["player", "club"].contains(viewer.role ?? "")
    }
    var walletIsCurrent: Bool {
        ownerIsCurrent && access.walletScope?.accountID == memberID
            && access.wallet.scope == access.walletScope && access.wallet.isConfigured
    }
    var complaintIsCurrent: Bool {
        ownerIsCurrent && access.complaintSession?.accountID == memberID
            && access.complaint.session == access.complaintSession
    }
    static func earningsHome(reader: WalletCommerceReader) -> WalletCommerceHomeView {
        var visibility = WalletCommerceVisibility(); visibility.income = true; visibility.withdrawalRecords = true
        return WalletCommerceHomeView(reader: reader, visibility: visibility,
            onCooperationFinance: {}, invitationHistory: nil, showsWithdrawalSupport: false,
            showsCooperationFinance: false)
    }
    func walletReader() -> WalletCommerceReader {
        access.wallet.restrictedToPresentation { [self] in walletIsCurrent }
    }
}

@MainActor final class ProfilePersonalComplaintReader: CoopFlowReading {
    private let association: ProfilePersonalToolsAssociation
    init(_ association: ProfilePersonalToolsAssociation) { self.association = association }
    var session: CoopFlowSession? { association.complaintIsCurrent ? association.access.complaintSession : nil }
    func read(_ resource: CoopFlowRead) async throws -> CoopFlowJSON {
        try await read(resource, isCurrent: { true })
    }
    func read(_ resource: CoopFlowRead, isCurrent: @escaping () -> Bool) async throws -> CoopFlowJSON {
        guard resource == .complaintTopics else { throw APIError.notConfigured }
        let current = { [association] in association.complaintIsCurrent && isCurrent() }
        guard current() else { throw CoopFlowFailure.stale }
        let value = try await association.access.complaint.read(resource, isCurrent: current)
        guard !Task.isCancelled, current() else { throw CoopFlowFailure.stale }
        return value
    }
    func settlement(source: CoopFlowSettlement.Source, id: Int) async throws -> CoopFlowSettlement {
        throw APIError.notConfigured
    }
}

@MainActor struct ProfilePersonalToolsEntry: View {
    let memberID: Int
    let social: any SocialAccountReading
    let access: ProfilePersonalToolsAccess
    let isCurrent: @MainActor () -> Bool
    var body: some View {
        let association = ProfilePersonalToolsAssociation(memberID: memberID, social: social,
            access: access, isCurrent: isCurrent)
        Section {
            if association.walletIsCurrent {
                NavigationLink {
                    ProfilePersonalEarningsDestination(association: association)
                } label: { Label("wallet.income", systemImage: "creditcard") }
                    .accessibilityIdentifier("profile.personalEarnings")
            }
            if association.complaintIsCurrent {
                NavigationLink {
                    ProfilePersonalComplaintDestination(association: association)
                } label: { Label("profile.complaint.title", systemImage: "text.bubble") }
                    .accessibilityIdentifier("profile.personalComplaint")
            }
        }
    }
}

@MainActor private struct ProfilePersonalEarningsDestination: View {
    @EnvironmentObject private var session: AppSession
    @State private var association: ProfilePersonalToolsAssociation
    @State private var reader: WalletCommerceReader
    init(association: ProfilePersonalToolsAssociation) {
        _association = State(initialValue: association)
        _reader = State(initialValue: association.walletReader())
    }
    var body: some View {
        Group {
            if association.walletIsCurrent {
                ProfilePersonalToolsAssociation.earningsHome(reader: reader)
            } else { Text("social.changed") }
        }
        .environment(\.bankWithdrawalDestination, nil)
        .environment(\.withdrawalSupportReader, nil)
        .id(session.walletHistoryViewIdentity)
    }
}

@MainActor private struct ProfilePersonalComplaintDestination: View {
    @EnvironmentObject private var session: AppSession
    @State private var association: ProfilePersonalToolsAssociation
    @State private var reader: ProfilePersonalComplaintReader
    init(association: ProfilePersonalToolsAssociation) {
        _association = State(initialValue: association); _reader = State(initialValue: .init(association))
    }
    var body: some View {
        Group {
            if association.complaintIsCurrent {
                ProfileComplaintPreparationView(reader: reader,
                    isCurrent: { association.complaintIsCurrent })
            } else { Text("social.changed") }
        }.id(session.sessionRevision)
    }
}
