import SwiftUI

/// Captures existing editors and their current account context; never grants read or save access.
@MainActor struct ProfileSettingsProfileAccess {
    enum Target: Hashable { case personal, brand }
    struct Key: Hashable {
        let accountID: Int
        let role: String
        let viewerRevision: UInt64
        let dependency: ObjectIdentifier
        let personalIdentity: ProfileReadIdentity?
        let personalRevision: UInt64?
        let merchantScope: UUID?
        let configured: Bool
    }
    let key: Key
    let target: Target
    let coordinator: ProfileEditCoordinator?
    let merchantReader: (any MerchantOperationsReading)?

    init?(accountID: Int, role: String, viewerRevision: UInt64, coordinator: ProfileEditCoordinator) {
        guard accountID > 0, role == "player" || role == "club",
              let identity = coordinator.identity, identity.accountID == accountID,
              coordinator.viewerRevision == viewerRevision else { return nil }
        key = .init(accountID: accountID, role: role, viewerRevision: viewerRevision,
            dependency: ObjectIdentifier(coordinator), personalIdentity: identity,
            personalRevision: coordinator.viewerRevision, merchantScope: nil, configured: coordinator.isConfigured)
        target = .personal; self.coordinator = coordinator; merchantReader = nil
    }
    init?(accountID: Int, role: String, viewerRevision: UInt64, merchantReader: any MerchantOperationsReading) {
        guard accountID > 0, role == "merchant", merchantReader.isAuthenticated else { return nil }
        key = .init(accountID: accountID, role: role, viewerRevision: viewerRevision,
            dependency: ObjectIdentifier(merchantReader), personalIdentity: nil,
            personalRevision: nil, merchantScope: merchantReader.scope, configured: merchantReader.isConfigured)
        target = .brand; coordinator = nil; self.merchantReader = merchantReader
    }
    static func current(_ session: AppSession) -> Self? {
        guard let account = session.account else { return nil }
        if account.effectiveRole == "merchant" {
            return .init(accountID: account.id, role: account.effectiveRole,
                viewerRevision: session.contentDetailRevision, merchantReader: session.merchantOperationsReader)
        }
        return .init(accountID: account.id, role: account.effectiveRole,
            viewerRevision: session.contentDetailRevision, coordinator: session.profileEditCoordinator)
    }
    var titleKey: String { target == .brand ? "merchant.operations.decor" : "profile.edit.title" }
}

/// Owned by the entire Settings NavigationStack, outside its lazy Form rows.
/// A real departure retires this owner permanently; pushed child pages do not own it.
@MainActor final class ProfileSettingsProfileOwner: ObservableObject {
    @Published private(set) var lifetime: UUID?
    private var retired = false
    func appear() {
        guard !retired, lifetime == nil else { return }
        lifetime = UUID()
    }
    func retire() { retired = true; lifetime = nil }
    func route(_ access: ProfileSettingsProfileAccess?) -> ProfileSettingsProfileRoute? {
        guard let lifetime, let access else { return nil }
        return .init(owner: ObjectIdentifier(self), lifetime: lifetime, access: access)
    }
    func accepts(_ route: ProfileSettingsProfileRoute, current: ProfileSettingsProfileAccess?) -> Bool {
        guard !retired, route.owner == ObjectIdentifier(self), lifetime == route.lifetime,
              let current else { return false }
        return route.access.key == current.key && route.access.target == current.target
    }
}

struct ProfileSettingsProfileRoute: Hashable {
    let id = UUID()
    let owner: ObjectIdentifier
    let lifetime: UUID
    let access: ProfileSettingsProfileAccess
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

@MainActor struct ProfileSettingsProfileEntry: View {
    let session: AppSession
    @ObservedObject var owner: ProfileSettingsProfileOwner
    var body: some View {
        if let route = owner.route(.current(session)) {
            Section {
                NavigationLink(value: route) {
                    Label(LocalizedStringKey(route.access.titleKey), systemImage: route.access.target == .brand ? "storefront" : "person.crop.circle")
                }.accessibilityIdentifier("settingsNative.openProfile")
            }
        } else if session.account == nil {
            // pages/shezhi 401 row: protocol and privacy rows below stay readable.
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("member.settings.signedOut", tableName: "MemberProfile")
                    Text("member.settings.signedOutHint", tableName: "MemberProfile").font(.footnote).foregroundStyle(.secondary)
                }.accessibilityElement(children: .combine).accessibilityIdentifier("settingsNative.profileSignedOut")
            }
        }
    }
}

@MainActor struct ProfileSettingsProfileNavigation: ViewModifier {
    let session: AppSession
    @ObservedObject var owner: ProfileSettingsProfileOwner
    func body(content: Content) -> some View {
        content.navigationDestination(for: ProfileSettingsProfileRoute.self) { route in
            ProfileSettingsProfileDestination(route: route, owner: owner, current: { .current(session) },
                categoryReader: session, merchantImages: session.retainedMerchantImages,
                merchantAssist: { [weak session] coordinator in
                    guard let session, owner.accepts(route, current: .current(session)) else {
                        return MerchantTemplateAssistFlow(coordinator: coordinator, client: nil)
                    }
                    return session.merchantTemplateAssistFlow(coordinator: coordinator)
                })
        }
    }
}

@MainActor struct ProfileSettingsProfileDestination: View {
    let route: ProfileSettingsProfileRoute
    @ObservedObject var owner: ProfileSettingsProfileOwner
    let current: () -> ProfileSettingsProfileAccess?
    var categoryReader: (any DiscoveryReading)? = nil
    var merchantImages: MerchantRetainedImageHost? = nil
    var merchantAssist: ((MerchantOperationsCoordinator) -> MerchantTemplateAssistFlow)? = nil
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Group {
            if owner.accepts(route, current: current()) {
                switch route.access.target {
                case .personal:
                    if let coordinator = route.access.coordinator {
                        ProfileEditView(coordinator: coordinator, sessionRevision: route.access.key.viewerRevision,
                            categoryReader: categoryReader).id(route.id)
                    }
                case .brand:
                    if let reader = route.access.merchantReader {
                        MerchantOperationsDocumentView(reader: reader, destination: .decor,
                            imageHost: merchantImages, templateAssistFactory: merchantAssist).id(route.id)
                    }
                }
            } else {
                ContentUnavailableView {
                    Label("profile.selfEdit.changed", systemImage: "person.crop.circle.badge.exclamationmark")
                } actions: {
                    Button("action.close") { dismiss() }.accessibilityIdentifier("settingsNative.profile.closeChanged")
                }
            }
        }.accessibilityIdentifier("settingsNative.profile.destination")
    }
}
