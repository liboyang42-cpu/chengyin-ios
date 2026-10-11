import SwiftUI
import Observation

@MainActor struct ClubMerchantProfileContext {
    struct Key: Equatable {
        let scope: UUID
        let sessionRevision: UInt64
        let contentRevision: UInt64
    }
    let key: Key
    let home: PublicMerchantHomeContext
    let isCurrent: () -> Bool
    var canRead: Bool { isCurrent() && home.reader.isConfigured && home.reader.scope == key.scope }
}

private struct ClubMerchantProfileKey: EnvironmentKey {
    static let defaultValue: ClubMerchantProfileContext? = nil
}
extension EnvironmentValues {
    var clubMerchantProfile: ClubMerchantProfileContext? {
        get { self[ClubMerchantProfileKey.self] }
        set { self[ClubMerchantProfileKey.self] = newValue }
    }
}

/// The normal club detail host, not a fixture-only callback. Observe session changes
/// while the sheet covers the directory; the captured reader never crosses a session.
@MainActor struct SessionClubMerchantProfileHost<Content: View>: View {
    @ObservedObject var session: AppSession
    @ViewBuilder let content: () -> Content
    var body: some View {
        let home = session.publicMerchantHomeContext
        let key = ClubMerchantProfileContext.Key(scope: home.reader.scope,
            sessionRevision: session.sessionRevision, contentRevision: session.contentDetailRevision)
        let identity = session.clubIdentity
        let profile = ClubMerchantProfileContext(key: key, home: home, isCurrent: {
            session.clubIdentity == identity && session.sessionRevision == key.sessionRevision &&
                session.contentDetailRevision == key.contentRevision &&
                session.publicMerchantHomeContext.reader.scope == key.scope
        })
        content().environment(\.clubMerchantProfile, profile)
    }
}

/// Closing retires callbacks synchronously, including reads suspended in the home
/// service. Reopening the same merchant creates a new presentation lifetime.
@MainActor @Observable final class ClubMerchantProfilePresentation {
    struct Selection: Identifiable {
        let id = UUID()
        let route: ClubMerchantProfileSelection
    }
    private(set) var selection: Selection?
    @ObservationIgnored private var accepted: (() -> Bool)?
    func open(_ selection: ClubMerchantProfileSelection, isCurrent: @escaping () -> Bool) {
        guard self.selection == nil, isCurrent() else { return }
        accepted = isCurrent; self.selection = .init(route: selection)
    }
    func isCurrent(_ selection: Selection) -> Bool {
        self.selection?.id == selection.id && accepted?() == true
    }
    func close() { accepted = nil; selection = nil }
}

/// This entry exposes public merchant information only. It does not synthesize a
/// cooperation intent, invite grant, legacy merchant-row fallback or public URL.
@MainActor struct ClubMerchantProfileReader: PublicMerchantHomeReading {
    let base: any PublicMerchantHomeReading
    let owner: PublicMerchantOwnerID
    let capturedScope: UUID
    let isCurrent: () -> Bool
    var scope: UUID { capturedScope }
    var isConfigured: Bool { isCurrent() && base.isConfigured && base.scope == capturedScope }
    var isOfflineExample: Bool { base.isOfflineExample }
    func home(_ target: PublicMerchantHomeTarget) async throws -> PublicMerchantHome {
        guard isConfigured, target == .ownerMemberID(owner), !Task.isCancelled else {
            throw PublicMerchantHomeFailure.unavailable
        }
        let value = try await base.home(target)
        guard isConfigured, !Task.isCancelled, value.memberId == owner.rawValue,
              value.id.flatMap(PublicMerchantRowID.init) != nil else { throw PublicMerchantHomeFailure.unavailable }
        return value
    }
}

@MainActor struct ClubMerchantProfileDestination: View {
    let selection: ClubMerchantProfilePresentation.Selection
    let profile: ClubMerchantProfileContext
    let presentation: ClubMerchantProfilePresentation
    let close: () -> Void
    private var current: Bool { profile.canRead && presentation.isCurrent(selection) }
    var body: some View {
        NavigationStack {
            Group {
                if current {
                    let reader = ClubMerchantProfileReader(base: profile.home.reader, owner: selection.route.owner,
                        capturedScope: profile.key.scope, isCurrent: { profile.canRead && presentation.isCurrent(selection) })
                    PublicMerchantHomeView(target: .ownerMemberID(selection.route.owner),
                        context: .init(reader: reader, image: profile.home.image))
                        .id(selection.id)
                } else { Color.clear }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.close", action: close).accessibilityIdentifier("club.merchantProfile.close")
                }
            }
        }
        .onChange(of: current, initial: true) { _, valid in if !valid { close() } }
    }
}
