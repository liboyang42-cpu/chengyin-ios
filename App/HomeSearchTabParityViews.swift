import SwiftUI

/// Hero greeting, city badge, and 3 fixed action banners (`成为俱乐部`, `成为商家`, `和朋友报名活动`) for Home (`pages/index/index`).
@MainActor
struct HomeHeroHeaderSectionView: View {
    @Environment(\.locale) private var locale
    var nickname: String? = nil
    var selectedCity: String? = nil
    var isNationwide: Bool = false
    var onSelectBanner: ((HomeIndexParityPresentation.ActionBanner) -> Void)? = nil

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(verbatim: HomeIndexParityPresentation.greetingText(nickname: nickname, locale: locale))
                        .font(.title3.weight(.semibold))
                        .accessibilityIdentifier("homeIndex.hero.greeting")
                    Spacer()
                    Label {
                        Text(verbatim: HomeIndexParityPresentation.citySelectorLabel(selectedCity: selectedCity, isNationwide: isNationwide, locale: locale))
                    } icon: {
                        Image(systemName: "location.fill")
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("homeIndex.hero.city")
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(HomeIndexParityPresentation.fixedActionBanners) { banner in
                            Button {
                                onSelectBanner?(banner)
                            } label: {
                                HStack(spacing: 6) {
                                    Text(verbatim: banner.title(locale: locale))
                                        .font(.subheadline.weight(.semibold))
                                    Image(systemName: "arrow.up.right")
                                        .font(.caption)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                            }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("homeIndex.actionBanner.\(banner.id)")
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }
}

/// Home continuation banner (`继续游戏` / `继续探索`) backed by `HomeIndexParityPresentation.ContinuationCard`.
@MainActor
struct PlayContinuationBannerView: View {
    @Environment(\.locale) private var locale
    let cards: [HomeIndexParityPresentation.ContinuationCard]
    var readAvailability: HomeContinuationReadAvailability = .available
    var onSelectCard: ((HomeIndexParityPresentation.ContinuationCard) -> Void)? = nil
    var onOpen: ((HomeFeedDestination) -> Void)? = nil
    var onRetry: (() -> Void)? = nil

    var body: some View {
        Section {
            if let messageKey = readAvailability.messageKey, readAvailability != .unauthenticated {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: readAvailability == .failed ? "exclamationmark.triangle" : "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(LocalizedStringKey(messageKey))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("homeIndex.continuation.availability.\(readAvailability.rawValue)")
                    Spacer()
                    if readAvailability == .failed, let onRetry {
                        Button("homeFeed.retry", action: onRetry)
                            .font(.caption.weight(.semibold))
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .accessibilityIdentifier("homeIndex.continuation.retry")
                    }
                }
            }
            ForEach(cards) { card in
                Button {
                    if let onSelectCard {
                        onSelectCard(card)
                    } else {
                        onOpen?(card.destination)
                    }
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(verbatim: card.kind.badgeTitle(locale: locale))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(QuestifyPalette.accent)
                            Text(verbatim: card.localizedTitle(locale: locale))
                                .font(.headline)
                                .foregroundStyle(.primary)
                            if let subtitle = card.localizedSubtitle(locale: locale) {
                                Text(verbatim: subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Image(systemName: "play.circle.fill")
                            .font(.title3)
                            .foregroundStyle(QuestifyPalette.accent)
                    }
                    .questifyCardSurface()
                }
                .buttonStyle(QuestifyCardButtonStyle())
                .accessibilityIdentifier("homeIndex.continuation.\(card.id)")
                .questifyCardListRow()
            }
        } header: {
            Text(verbatim: HomeIndexParityPresentation.continuationSectionTitle(locale: locale))
        }
    }
}

/// Shelf header view for Home (`pages/index`) sections (`精选路线`, `近期活动`, `热门主题`, `现成玩法`).
@MainActor
struct HomeIndexShelfHeaderView: View {
    @Environment(\.locale) private var locale
    let shelf: HomeIndexParityPresentation.ShelfKind
    var onAction: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(verbatim: shelf.title(locale: locale))
                .font(.headline)
                .accessibilityIdentifier("homeIndex.shelfHeader.\(shelf.rawValue)")
            Spacer()
            if let onAction {
                Button(action: onAction) {
                    HStack(spacing: 4) {
                        Text(verbatim: shelf.actionHint(locale: locale))
                        Image(systemName: "chevron.right")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("homeIndex.shelfAction.\(shelf.rawValue)")
            }
        }
    }
}

/// Horizontal result tabs bar with count badges for Global Search (`pages/search2`).
@MainActor
struct GlobalSearchResultTabsBar: View {
    let tabs: [GlobalSearchParityPresentation.ResultTabDescriptor]
    @Binding var selectedKind: GlobalSearchParityPresentation.ResultTabKind

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(tabs) { tab in
                    let isSelected = tab.kind == selectedKind
                    Button {
                        selectedKind = tab.kind
                    } label: {
                        HStack(spacing: 4) {
                            Text(verbatim: tab.title)
                            if let badge = tab.badgeText {
                                Text(verbatim: badge)
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.secondary.opacity(0.16), in: Capsule())
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.bordered)
                    .tint(isSelected ? .accentColor : .secondary)
                    .accessibilityIdentifier("globalSearch.tab.\(tab.kind.rawValue)")
                }
            }
        }
    }
}

/// Empty, loading, or error state view for Home (`pages/index`).
@MainActor
struct HomeIndexEmptyStateView: View {
    enum Phase: Equatable {
        case loading
        case empty
        case error
    }

    @Environment(\.locale) private var locale
    let phase: Phase
    var onRetry: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            switch phase {
            case .loading:
                ProgressView()
                Text(verbatim: HomeIndexParityPresentation.loadingCopy(locale: locale))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("homeIndex.state.loading")
            case .empty:
                Image(systemName: "tray")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text(verbatim: HomeIndexParityPresentation.emptyStateTitle(locale: locale))
                    .font(.headline)
                Text(verbatim: HomeIndexParityPresentation.emptyStateHint(locale: locale))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                .accessibilityIdentifier("homeIndex.state.empty")
            case .error:
                Image(systemName: "exclamationmark.triangle")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text(verbatim: HomeIndexParityPresentation.errorCopy(locale: locale))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                .accessibilityIdentifier("homeIndex.state.error")
                if let onRetry {
                    Button(action: onRetry) {
                        Text(verbatim: HomeIndexParityPresentation.retryButtonTitle(locale: locale))
                    }
                    .buttonStyle(.bordered)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("homeIndex.state.retry")
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

/// Role-aware consumer (`玩家视角`) ↔ merchant (`商家工作台`) root container switch banner (`components/tabBar`).
@MainActor
struct MerchantRootModeSwitchBannerView: View {
    let state: RootTabBarParity.TabBarState
    var canSwitchToMerchant: Bool = false
    var onSelectMode: ((RootTabBarParity.RoleMode) -> Void)? = nil
    var onSelectTab: ((RootTab) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Button {
                    onSelectMode?(.consumer)
                } label: {
                    Text(verbatim: RootTabBarParity.consumerModeTitle)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
                .tint(state.mode == .consumer ? QuestifyPalette.accent : .secondary)
                .accessibilityIdentifier("rootTabBar.mode.consumer")

                if canSwitchToMerchant || state.mode == .merchant {
                    Button {
                        onSelectMode?(.merchant)
                    } label: {
                        Text(verbatim: RootTabBarParity.merchantModeTitle)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.bordered)
                    .tint(state.mode == .merchant ? QuestifyPalette.accent : .secondary)
                    .accessibilityIdentifier("rootTabBar.mode.merchant")
                }
                Spacer()
            }

            HStack(spacing: 6) {
                ForEach(state.tabs) { descriptor in
                    let isSelected = descriptor.rootTab == state.selectedTab
                    Button {
                        onSelectTab?(descriptor.rootTab)
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: descriptor.systemImage)
                                .font(.subheadline)
                            Text(verbatim: descriptor.primaryTitle)
                                .font(.caption2.weight(isSelected ? .semibold : .regular))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(isSelected ? QuestifyPalette.accent : .secondary)
                    .accessibilityIdentifier("rootTabBar.tab.\(state.mode.rawValue).\(descriptor.index)")
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityIdentifier("rootTabBar.containerSwitch")
    }
}

/// Merchant 5-tab business entries (`工作台`, `营销`, `模板`, `合作`, `我的`) mapped 1:1 with `RootTabBarParity.merchantTabs`.
enum MerchantRootBusinessTab: Int, CaseIterable, Hashable, Sendable, Identifiable {
    case workbench = 0
    case marketing = 1
    case templates = 2
    case cooperation = 3
    case mine = 4

    var id: Int { rawValue }

    init(rootTab: RootTab) {
        switch rootTab {
        case .home: self = .workbench
        case .roam: self = .marketing
        case .publish: self = .templates
        case .club: self = .cooperation
        case .mine: self = .mine
        }
    }

    var rootTab: RootTab {
        switch self {
        case .workbench: return .home
        case .marketing: return .roam
        case .templates: return .publish
        case .cooperation: return .club
        case .mine: return .mine
        }
    }

    var descriptor: RootTabBarParity.TabDescriptor {
        RootTabBarParity.merchantTabs[rawValue]
    }

    var containerRoute: RootTabBarParity.RootContainerRoute {
        RootTabBarParity.containerRoute(for: rootTab, mode: .merchant)
    }
}

/// Environment action for requesting a consumer ↔ merchant root container mode switch.
struct MerchantRootModeSwitch {
    let isAvailable: Bool
    let activeMode: RootTabBarParity.RoleMode
    let isVerifying: Bool
    let errorKey: String?
    let selectedTab: RootTab
    private let requestMode: @MainActor (RootTabBarParity.RoleMode) -> Void
    private let selectTab: @MainActor (RootTab) -> Void

    init(
        activeMode: RootTabBarParity.RoleMode = .consumer,
        isVerifying: Bool = false,
        errorKey: String? = nil,
        selectedTab: RootTab = .home,
        requestMode: @escaping @MainActor (RootTabBarParity.RoleMode) -> Void,
        selectTab: @escaping @MainActor (RootTab) -> Void = { _ in }
    ) {
        self.isAvailable = true
        self.activeMode = activeMode
        self.isVerifying = isVerifying
        self.errorKey = errorKey
        self.selectedTab = selectedTab
        self.requestMode = requestMode
        self.selectTab = selectTab
    }

    private init() {
        self.isAvailable = false
        self.activeMode = .consumer
        self.isVerifying = false
        self.errorKey = nil
        self.selectedTab = .home
        self.requestMode = { _ in }
        self.selectTab = { _ in }
    }

    static let unavailable = MerchantRootModeSwitch()

    @MainActor func callAsFunction(_ mode: RootTabBarParity.RoleMode) {
        requestMode(mode)
    }

    @MainActor func select(_ tab: RootTab) {
        selectTab(tab)
    }
}

/// Token captured at the moment a child merchant surface begins an access reload.
/// Ensures late/out-of-order observations cannot resurrect a revoked or exited merchant grant.
struct MerchantAccessObservationToken: Equatable, Sendable {
    let verificationGeneration: UInt64
    let containerGeneration: UUID
    let accountID: Int
    let sessionRevision: UInt64
}

/// Environment hook allowing child merchant surfaces (such as `MerchantHomeView`) to capture an observation token
/// before `await reader.merchantAccess()` and report the result back only if the token still matches.
struct MerchantAccessObservationHook {
    var begin: @MainActor () -> MerchantAccessObservationToken?
    var complete: @MainActor (MerchantAccessObservationToken, MerchantAccess?, String?) -> Void

    static let noop = MerchantAccessObservationHook(
        begin: { nil },
        complete: { _, _, _ in }
    )
}

private struct MerchantRootModeSwitchKey: EnvironmentKey {
    static let defaultValue = MerchantRootModeSwitch.unavailable
}

private struct MerchantAccessObserverKey: EnvironmentKey {
    static let defaultValue = MerchantAccessObservationHook.noop
}

extension EnvironmentValues {
    var merchantRootModeSwitch: MerchantRootModeSwitch {
        get { self[MerchantRootModeSwitchKey.self] }
        set { self[MerchantRootModeSwitchKey.self] = newValue }
    }
    var merchantAccessObserver: MerchantAccessObservationHook {
        get { self[MerchantAccessObserverKey.self] }
        set { self[MerchantAccessObserverKey.self] = newValue }
    }
}

/// Authoritative coordinator for switching between Consumer Mode (`玩家视角`) and Merchant Root Mode (`商家工作台`).
/// UI mode selection never manufactures merchant authorization: `.merchantTabs` is entered only when
/// `reader.merchantAccess()` succeeds with `active == true && (merchantID ?? 0) > 0` for the current account and session revision.
@MainActor
final class MerchantRootModeCoordinator: ObservableObject {
    enum ResolvedRoute: Equatable {
        case consumerTabs
        case merchantTabs(MerchantAccess)
    }

    @Published private(set) var requestedMode: RootTabBarParity.RoleMode = .consumer
    @Published private(set) var verifiedAccess: MerchantAccess? = nil
    @Published private(set) var verifiedAccountID: Int? = nil
    @Published private(set) var verifiedSessionRevision: UInt64? = nil
    @Published private(set) var isVerifying: Bool = false
    @Published private(set) var statusErrorKey: String? = nil
    @Published var selectedMerchantTab: MerchantRootBusinessTab = .workbench
    @Published private(set) var merchantContainerGeneration = UUID()

    private var verificationGeneration: UInt64 = 0

    var selectedRootTab: RootTab {
        get { selectedMerchantTab.rootTab }
        set { selectedMerchantTab = MerchantRootBusinessTab(rootTab: newValue) }
    }

    /// Evaluates whether a specific merchant business tab has read/entry permission under a verified `MerchantAccess`.
    static func allowsBusinessTab(_ tab: MerchantRootBusinessTab, access: MerchantAccess) -> Bool {
        guard access.active, let merchantID = access.merchantID, merchantID > 0, access.role != nil else {
            return false
        }
        switch tab {
        case .workbench:
            return true
        case .marketing:
            return access.isOwner || access.role == .manager || access.role == .marketing || access.allows(.couponManage) || access.allows(.basicRead)
        case .templates:
            return access.allows(.projects)
        case .cooperation:
            return access.isOwner || access.allows(.coopManage)
        case .mine:
            return true
        }
    }

    func resolvedRoute(
        accountID: Int?,
        isSignedIn: Bool,
        isConfigured: Bool,
        revision: UInt64
    ) -> ResolvedRoute {
        guard isConfigured, isSignedIn, let accountID, accountID > 0 else {
            return .consumerTabs
        }
        guard requestedMode == .merchant,
              verifiedAccountID == accountID,
              verifiedSessionRevision == revision,
              let access = verifiedAccess,
              access.active,
              let merchantID = access.merchantID,
              merchantID > 0,
              access.role != nil else {
            return .consumerTabs
        }
        return .merchantTabs(access)
    }

    func activeMerchantAccess(
        accountID: Int?,
        isSignedIn: Bool,
        isConfigured: Bool,
        revision: UInt64
    ) -> MerchantAccess? {
        if case .merchantTabs(let access) = resolvedRoute(
            accountID: accountID,
            isSignedIn: isSignedIn,
            isConfigured: isConfigured,
            revision: revision
        ) {
            return access
        }
        return nil
    }

    func isMerchantModeActive(
        accountID: Int?,
        isSignedIn: Bool = true,
        isConfigured: Bool = true,
        revision: UInt64
    ) -> Bool {
        activeMerchantAccess(
            accountID: accountID,
            isSignedIn: isSignedIn,
            isConfigured: isConfigured,
            revision: revision
        ) != nil
    }

    func tabBarState(
        accountID: Int?,
        isSignedIn: Bool,
        isConfigured: Bool,
        revision: UInt64
    ) -> RootTabBarParity.TabBarState {
        let active = isMerchantModeActive(
            accountID: accountID,
            isSignedIn: isSignedIn,
            isConfigured: isConfigured,
            revision: revision
        )
        return RootTabBarParity.TabBarState(
            mode: active ? .merchant : .consumer,
            selectedTab: active ? selectedMerchantTab.rootTab : .mine,
            isAuthenticated: isSignedIn
        )
    }

    func selectBusinessTab(_ tab: MerchantRootBusinessTab) {
        guard requestedMode == .merchant, let access = verifiedAccess, access.active, (access.merchantID ?? 0) > 0 else {
            return
        }
        selectedMerchantTab = tab
    }

    func selectRootTab(_ tab: RootTab) {
        selectBusinessTab(MerchantRootBusinessTab(rootTab: tab))
    }

    /// Requests switching into Merchant Root Mode by freshly verifying `reader.merchantAccess()`.
    /// Never grants merchant mode from UI intent or unverified role strings.
    @discardableResult
    func requestMerchantMode<Reader: MerchantReading>(
        reader: Reader,
        accountID: Int?,
        initialTab: MerchantRootBusinessTab = .workbench
    ) async -> Bool {
        verificationGeneration &+= 1
        let generation = verificationGeneration

        guard reader.isConfigured else {
            clearMerchantGrant(errorKey: "auth.notConfigured")
            return false
        }
        guard reader.isSignedIn, let accountID, accountID > 0 else {
            clearMerchantGrant(errorKey: "merchant.signIn")
            return false
        }

        let revision = reader.sessionRevision
        // Previous grant is never usable while access is being verified.
        verifiedAccess = nil
        verifiedAccountID = nil
        verifiedSessionRevision = nil
        requestedMode = .consumer
        selectedMerchantTab = .workbench
        isVerifying = true
        statusErrorKey = nil
        merchantContainerGeneration = UUID()

        do {
            let access = try await reader.merchantAccess()
            try Task.checkCancellation()
            guard generation == verificationGeneration,
                  reader.isConfigured,
                  reader.isSignedIn,
                  reader.sessionRevision == revision else {
                if generation == verificationGeneration { isVerifying = false }
                return false
            }
            guard access.active, let merchantID = access.merchantID, merchantID > 0, access.role != nil else {
                clearMerchantGrant(errorKey: access.application?.titleKey ?? "merchant.access.inactive")
                return false
            }
            verifiedAccess = access
            verifiedAccountID = accountID
            verifiedSessionRevision = revision
            requestedMode = .merchant
            selectedMerchantTab = Self.allowsBusinessTab(initialTab, access: access) ? initialTab : .workbench
            isVerifying = false
            statusErrorKey = nil
            merchantContainerGeneration = UUID()
            return true
        } catch is CancellationError {
            if generation == verificationGeneration {
                isVerifying = false
            }
            return false
        } catch {
            guard generation == verificationGeneration, reader.sessionRevision == revision else {
                if generation == verificationGeneration { isVerifying = false }
                return false
            }
            let key: String
            if error as? MerchantReadError == .accessDenied {
                key = "merchant.access.denied"
            } else if error as? APIError == .unauthorized {
                key = "auth.expired"
            } else if error as? APIError == .malformedResponse {
                key = "merchant.invalidResponse"
            } else {
                key = "merchant.loadFailed"
            }
            clearMerchantGrant(errorKey: key)
            return false
        }
    }

    /// Re-verifies current merchant access and immediately tears down merchant mode if revoked or expired.
    /// When Merchant Root Mode is already active for `(accountID, reader.sessionRevision)`, a cancelled
    /// revalidation read never revokes the active grant, whereas a completed revocation/denial closes it immediately.
    @discardableResult
    func revalidateMerchantMode<Reader: MerchantReading>(
        reader: Reader,
        accountID: Int?
    ) async -> Bool {
        guard reader.isConfigured else {
            clearMerchantGrant(errorKey: "auth.notConfigured")
            return false
        }
        guard reader.isSignedIn, let accountID, accountID > 0 else {
            clearMerchantGrant(errorKey: "merchant.signIn")
            return false
        }
        if let verifiedAccountID, verifiedAccountID != accountID {
            switchToConsumerMode()
            return false
        }
        if let verifiedSessionRevision, verifiedSessionRevision != reader.sessionRevision {
            switchToConsumerMode()
            return false
        }
        guard let token = beginAccessObservation(accountID: accountID, revision: reader.sessionRevision) else {
            let preservedTab = selectedMerchantTab
            return await requestMerchantMode(reader: reader, accountID: accountID, initialTab: preservedTab)
        }
        do {
            let access = try await reader.merchantAccess()
            try Task.checkCancellation()
            applyObservedMerchantAccess(
                token: token,
                access: access,
                errorKey: nil,
                currentAccountID: accountID,
                currentRevision: reader.sessionRevision
            )
            return isMerchantModeActive(
                accountID: accountID,
                isSignedIn: reader.isSignedIn,
                isConfigured: reader.isConfigured,
                revision: reader.sessionRevision
            )
        } catch is CancellationError {
            return isMerchantModeActive(
                accountID: accountID,
                isSignedIn: reader.isSignedIn,
                isConfigured: reader.isConfigured,
                revision: reader.sessionRevision
            )
        } catch {
            guard !Task.isCancelled else {
                return isMerchantModeActive(
                    accountID: accountID,
                    isSignedIn: reader.isSignedIn,
                    isConfigured: reader.isConfigured,
                    revision: reader.sessionRevision
                )
            }
            let key: String
            if error as? MerchantReadError == .accessDenied {
                key = "merchant.access.denied"
            } else if error as? APIError == .unauthorized {
                key = "auth.expired"
            } else if error as? APIError == .notConfigured {
                key = "auth.notConfigured"
            } else if error as? APIError == .malformedResponse {
                key = "merchant.invalidResponse"
            } else {
                key = "merchant.loadFailed"
            }
            applyObservedMerchantAccess(
                token: token,
                access: nil,
                errorKey: key,
                currentAccountID: accountID,
                currentRevision: reader.sessionRevision
            )
            return false
        }
    }

    /// Captures a strict observation lease at the moment a child merchant surface initiates an access reload.
    /// Returns `nil` when Merchant Root Mode is not currently active for `(accountID, revision)`.
    func beginAccessObservation(accountID: Int?, revision: UInt64) -> MerchantAccessObservationToken? {
        guard requestedMode == .merchant,
              !isVerifying,
              let verifiedAccess,
              verifiedAccess.active,
              (verifiedAccess.merchantID ?? 0) > 0,
              let verifiedAccountID,
              let verifiedSessionRevision,
              let accountID,
              accountID > 0,
              verifiedAccountID == accountID,
              verifiedSessionRevision == revision else {
            return nil
        }
        verificationGeneration &+= 1
        return MerchantAccessObservationToken(
            verificationGeneration: verificationGeneration,
            containerGeneration: merchantContainerGeneration,
            accountID: verifiedAccountID,
            sessionRevision: verifiedSessionRevision
        )
    }

    /// Applies an authoritative merchant access snapshot observed by a child merchant surface (e.g., workbench reload)
    /// using the `token` captured when that reload started.
    /// Rejects late/out-of-order observations and never restores merchant mode after a switch to `.consumer` or revocation.
    func applyObservedMerchantAccess(
        token: MerchantAccessObservationToken,
        access: MerchantAccess?,
        errorKey: String?,
        currentAccountID: Int?,
        currentRevision: UInt64
    ) {
        guard requestedMode == .merchant,
              !isVerifying,
              verifiedAccess != nil,
              let verifiedAccountID,
              let verifiedSessionRevision,
              let currentAccountID,
              currentAccountID > 0,
              verifiedAccountID == currentAccountID,
              verifiedSessionRevision == currentRevision,
              token.accountID == verifiedAccountID,
              token.sessionRevision == verifiedSessionRevision,
              token.containerGeneration == merchantContainerGeneration,
              token.verificationGeneration == verificationGeneration else {
            return
        }
        verificationGeneration &+= 1
        guard errorKey == nil,
              let access,
              access.active,
              let merchantID = access.merchantID,
              merchantID > 0,
              access.role != nil else {
            clearMerchantGrant(errorKey: errorKey ?? access?.application?.titleKey ?? "merchant.access.inactive")
            return
        }
        let previousAccess = verifiedAccess
        verifiedAccess = access
        self.verifiedAccountID = currentAccountID
        self.verifiedSessionRevision = currentRevision
        requestedMode = .merchant
        isVerifying = false
        statusErrorKey = nil
        if !Self.allowsBusinessTab(selectedMerchantTab, access: access) {
            selectedMerchantTab = .workbench
        }
        if previousAccess != access {
            merchantContainerGeneration = UUID()
        }
    }

    /// Switches back to Player/Consumer Mode and destroys all merchant container navigation state.
    func switchToConsumerMode() {
        verificationGeneration &+= 1
        isVerifying = false
        requestedMode = .consumer
        verifiedAccess = nil
        verifiedAccountID = nil
        verifiedSessionRevision = nil
        selectedMerchantTab = .workbench
        statusErrorKey = nil
        merchantContainerGeneration = UUID()
    }

    /// Cleans up merchant mode whenever account identity, sign-in state, or session revision changes.
    func handleSessionChange(
        accountID: Int?,
        isSignedIn: Bool,
        isConfigured: Bool,
        revision: UInt64
    ) {
        if !isConfigured || !isSignedIn || accountID == nil {
            if requestedMode != .consumer || verifiedAccess != nil || isVerifying || statusErrorKey != nil || selectedMerchantTab != .workbench {
                switchToConsumerMode()
            }
            return
        }
        if let verifiedAccountID, verifiedAccountID != accountID {
            switchToConsumerMode()
            return
        }
        if let verifiedSessionRevision, verifiedSessionRevision != revision {
            switchToConsumerMode()
            return
        }
    }

    func makeModeSwitch(session: AppSession) -> MerchantRootModeSwitch {
        let isActive = isMerchantModeActive(
            accountID: session.account?.id,
            isSignedIn: session.isSignedIn,
            isConfigured: session.isConfigured,
            revision: session.sessionRevision
        )
        return MerchantRootModeSwitch(
            activeMode: isActive ? .merchant : .consumer,
            isVerifying: isVerifying,
            errorKey: statusErrorKey,
            selectedTab: isActive ? selectedMerchantTab.rootTab : .mine,
            requestMode: { [weak self] mode in
                guard let self else { return }
                switch mode {
                case .consumer:
                    self.switchToConsumerMode()
                case .merchant:
                    Task {
                        await self.requestMerchantMode(reader: session, accountID: session.account?.id)
                    }
                }
            },
            selectTab: { [weak self] tab in
                self?.selectRootTab(tab)
            }
        )
    }

    private func clearMerchantGrant(errorKey: String?) {
        isVerifying = false
        requestedMode = .consumer
        verifiedAccess = nil
        verifiedAccountID = nil
        verifiedSessionRevision = nil
        selectedMerchantTab = .workbench
        statusErrorKey = errorKey
        merchantContainerGeneration = UUID()
    }
}

/// Account row and banner for switching between Player Mode (`玩家视角`) and Merchant Root Mode (`商家工作台`).
@MainActor
struct MerchantAccountModeSwitchRow: View {
    let modeSwitch: MerchantRootModeSwitch

    private var bannerState: RootTabBarParity.TabBarState {
        RootTabBarParity.TabBarState(
            mode: modeSwitch.activeMode,
            selectedTab: modeSwitch.selectedTab,
            isAuthenticated: true
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if modeSwitch.activeMode == .merchant {
                Button {
                    modeSwitch(.consumer)
                } label: {
                    Label(RootTabBarParity.consumerModeTitle, systemImage: "arrow.uturn.backward.circle")
                }
                .accessibilityIdentifier("account.consumerRootSwitch")
            } else {
                Button {
                    modeSwitch(.merchant)
                } label: {
                    Label(RootTabBarParity.merchantModeTitle, systemImage: "square.grid.2x2")
                }
                .disabled(modeSwitch.isVerifying)
                .accessibilityIdentifier("account.merchantRootSwitch")
            }

            if modeSwitch.isVerifying {
                ProgressView("merchant.checkingAccess")
                    .font(.caption)
                    .accessibilityIdentifier("merchant.rootMode.verifying")
            }

            if let errorKey = modeSwitch.errorKey {
                Text(LocalizedStringKey(errorKey))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("merchant.rootMode.error")
            }

            MerchantRootModeSwitchBannerView(
                state: bannerState,
                canSwitchToMerchant: true,
                onSelectMode: { modeSwitch($0) },
                onSelectTab: { tab in
                    if modeSwitch.activeMode == .merchant {
                        modeSwitch.select(tab)
                    }
                }
            )
        }
    }
}

/// Verified Merchant 5-tab Root Container (`工作台`, `营销`, `模板`, `合作`, `我的`) with return/revocation cleanup.
@MainActor
struct SessionMerchantRootContainerView: View {
    @ObservedObject var session: AppSession
    @ObservedObject var coordinator: MerchantRootModeCoordinator
    let access: MerchantAccess
    var onReturnToConsumer: (RootTab?) -> Void

    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedMarketingSuggestion: MerchantInsightDestination?

    private var recommendationOrigin: MerchantInsightOrigin? {
        .init(merchantID: access.merchantID, readerScope: session.merchantOperationsReader.scope)
    }

    var body: some View {
        TabView(selection: $coordinator.selectedMerchantTab) {
            NavigationStack {
                MerchantHomeView(
                    reader: session,
                    marketingModel: session.merchantMarketingCoordinator,
                    marketingDestination: { AnyView(SessionMerchantMarketingDestination(session: session, destination: $0)) },
                    openApplication: { onReturnToConsumer(.mine) },
                    operationsReader: session.merchantOperationsReader,
                    operationsDestinationFactory: { session.merchantOperationsDestination($0, access: $1) },
                    businessReader: session.merchantBusinessReader,
                    businessJournal: session.merchantBusinessJournal,
                    contentService: session.merchantContentService,
                    cooperationFlowReader: session.cooperationFlowReader,
                    engagementReader: session.merchantEngagementReader,
                    exportRecovery: session.merchantExportRecovery,
                    predictionReader: session.merchantPredictionReader
                )
                .environment(\.merchantPredictionWorkbenchEntry, { AnyView(SessionMerchantPredictionEntry(session: session)) })
                .environment(\.merchantAccessObserver, MerchantAccessObservationHook(
                    begin: {
                        coordinator.beginAccessObservation(
                            accountID: session.account?.id,
                            revision: session.sessionRevision
                        )
                    },
                    complete: { token, observedAccess, errorKey in
                        coordinator.applyObservedMerchantAccess(
                            token: token,
                            access: observedAccess,
                            errorKey: errorKey,
                            currentAccountID: session.account?.id,
                            currentRevision: session.sessionRevision
                        )
                    }
                ))
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        switchToConsumerToolbarButton
                    }
                }
            }
            .tabItem { merchantTabLabel(.workbench) }
            .tag(MerchantRootBusinessTab.workbench)

            NavigationStack {
                Group {
                    if MerchantRootModeCoordinator.allowsBusinessTab(.marketing, access: access) {
                        MerchantMarketingView(
                            model: session.merchantMarketingCoordinator,
                            recommendationOrigin: recommendationOrigin,
                            onSuggestion: { route in selectedMarketingSuggestion = route }
                        )
                        .navigationDestination(item: $selectedMarketingSuggestion) { route in
                            if case .recommendation(let target) = route, target.origin != recommendationOrigin {
                                AnyView(Text("merchantMarketing.stale"))
                            } else if case .cooperationSettings(let origin) = route, origin != recommendationOrigin {
                                AnyView(Text("merchantMarketing.stale"))
                            } else if case .cooperationCenter(let origin) = route, origin != recommendationOrigin {
                                AnyView(Text("merchantMarketing.stale"))
                            } else {
                                AnyView(SessionMerchantMarketingDestination(session: session, destination: route))
                            }
                        }
                    } else {
                        MerchantFailureView(
                            errorKey: "merchant.access.denied",
                            identifier: "merchant.marketing",
                            retry: { Task { _ = await coordinator.revalidateMerchantMode(reader: session, accountID: session.account?.id) } }
                        )
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        switchToConsumerToolbarButton
                    }
                }
            }
            .tabItem { merchantTabLabel(.marketing) }
            .tag(MerchantRootBusinessTab.marketing)

            NavigationStack {
                Group {
                    if MerchantRootModeCoordinator.allowsBusinessTab(.templates, access: access) {
                        MerchantProjectsView(
                            reader: session,
                            contentService: session.merchantContentService,
                            workspaceReadFactory: session.merchantProjectWorkspaceReadFactory
                        )
                    } else {
                        SessionMerchantProjectBrowseView(session: session)
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        switchToConsumerToolbarButton
                    }
                }
            }
            .tabItem { merchantTabLabel(.templates) }
            .tag(MerchantRootBusinessTab.templates)

            NavigationStack {
                Group {
                    if MerchantRootModeCoordinator.allowsBusinessTab(.cooperation, access: access) {
                        CooperationFlowWorkbench(reader: session.cooperationFlowReader, operationScope: "MERCHANT")
                    } else {
                        MerchantFailureView(
                            errorKey: "merchant.access.denied",
                            identifier: "merchant.cooperation",
                            retry: { Task { _ = await coordinator.revalidateMerchantMode(reader: session, accountID: session.account?.id) } }
                        )
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        switchToConsumerToolbarButton
                    }
                }
            }
            .tabItem { merchantTabLabel(.cooperation) }
            .tag(MerchantRootBusinessTab.cooperation)

            Group {
                if let account = session.account {
                    AccountView(
                        account: account,
                        privateHomeCoordinator: session.privateHomeCoordinator,
                        onOpenGuideDestination: { destination in
                            onReturnToConsumer(destination == .roam ? .roam : .home)
                        }
                    )
                    .id(session.sessionRevision)
                } else {
                    WelcomeView()
                }
            }
            .tabItem { merchantTabLabel(.mine) }
            .tag(MerchantRootBusinessTab.mine)
        }
        .id(coordinator.merchantContainerGeneration)
        .onChange(of: recommendationOrigin) { _, _ in selectedMarketingSuggestion = nil }
        .onChange(of: session.merchantMarketingCoordinator.scopeIdentity) { _, _ in selectedMarketingSuggestion = nil }
        .onChange(of: selectedMarketingSuggestion) { oldValue, newValue in
            if oldValue != nil && newValue == nil {
                Task { _ = await coordinator.revalidateMerchantMode(reader: session, accountID: session.account?.id) }
            }
        }
        .onChange(of: coordinator.selectedMerchantTab) { _, _ in
            Task { _ = await coordinator.revalidateMerchantMode(reader: session, accountID: session.account?.id) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { _ = await coordinator.revalidateMerchantMode(reader: session, accountID: session.account?.id) }
            }
        }
    }

    private var switchToConsumerToolbarButton: some View {
        Button {
            onReturnToConsumer(nil)
        } label: {
            Label(RootTabBarParity.consumerModeTitle, systemImage: "arrow.uturn.backward.circle")
        }
        .accessibilityIdentifier("merchant.rootMode.switchToConsumer")
    }

    private func merchantTabLabel(_ tab: MerchantRootBusinessTab) -> some View {
        let descriptor = tab.descriptor
        return Label(descriptor.primaryTitle, systemImage: descriptor.systemImage)
    }
}

/// Floating publish button (`+ 发布`) for the Publish/Template tab (`pages/template`).
@MainActor
struct PublishTabFloatingButton: View {
    var title: String = PublishTabFloatingSheetParity.fabButtonTitle
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label {
                Text(verbatim: title)
                    .font(.subheadline.weight(.semibold))
            } icon: {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(QuestifyPalette.accent, in: Capsule())
            .foregroundStyle(.white)
            .shadow(radius: 4, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("publishTab.floatingButton")
    }
}

/// Floating publish capability sheet (`pages/template` + `/api/publish/home`).
@MainActor
struct PublishTabFloatingSheetView: View {
    let presentation: PublishTabFloatingSheetParity.SheetPresentation
    var onSelectAction: ((PublishTabFloatingSheetParity.ActionKind) -> Void)? = nil
    var onClose: (() -> Void)? = nil

    var body: some View {
        NavigationStack {
            List {
                if let quotaBadgeText = presentation.quotaBadgeText {
                    Section {
                        Label {
                            Text(verbatim: quotaBadgeText)
                                .font(.subheadline.weight(.medium))
                        } icon: {
                            Image(systemName: "sparkles")
                                .foregroundStyle(QuestifyPalette.accent)
                        }
                        .accessibilityIdentifier("publishTab.sheet.quotaBadge")
                    }
                }

                Section {
                    ForEach(presentation.actions) { item in
                        Button {
                            guard item.isEnabled else { return }
                            onSelectAction?(item.kind)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: item.systemImage)
                                    .font(.title3)
                                    .foregroundStyle(item.isEnabled ? QuestifyPalette.accent : .secondary)
                                    .frame(width: 28)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(verbatim: item.title)
                                        .font(.headline)
                                        .foregroundStyle(item.isEnabled ? .primary : .secondary)
                                    Text(verbatim: item.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    if let reason = item.disabledReason, !item.isEnabled {
                                        Text(verbatim: reason)
                                            .font(.caption2)
                                            .foregroundStyle(.orange)
                                            .accessibilityIdentifier("publishTab.sheet.disabledReason.\(item.id)")
                                    }
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 4)
                        }
                        .disabled(!item.isEnabled)
                        .accessibilityIdentifier("publishTab.sheet.action.\(item.id)")
                    }
                }
            }
            .navigationTitle(Text(verbatim: presentation.sheetTitle))
            .toolbar {
                if let onClose {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("关闭", action: onClose)
                            .accessibilityIdentifier("publishTab.sheet.close")
                    }
                }
            }
        }
    }
}
