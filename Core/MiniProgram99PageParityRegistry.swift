import Foundation

public enum MiniProgramAlignmentDomain: String, CaseIterable, Sendable, Equatable {
    case domainB = "B"
    case domainC = "C"
    case domainD = "D"
    case domainE = "E"

    public var alignmentDocPath: String {
        switch self {
        case .domainB:
            return "docs/alignment/xcx-ios-B-20261019.md"
        case .domainC:
            return "docs/alignment/xcx-ios-C-20261019.md"
        case .domainD:
            return "docs/alignment/xcx-ios-D-20261019.md"
        case .domainE:
            return "docs/alignment/xcx-ios-E-20261019.md"
        }
    }

    public var title: String {
        switch self {
        case .domainB:
            return "Entry/Login, Home, Primary Tab Bar, Member/Profile, Favorites/Participants, Settings/Compliance & Global Search"
        case .domainC:
            return "Official Events, Activity Detail/Signup, Orders/Tickets, Topics & Creative Square"
        case .domainD:
            return "Roam, SubpackageRoam, Play, Team, Templates & SearchMap"
        case .domainE:
            return "Merchant Workbench/Ledger/Marketing/Operations/Coupons, Club/Governance/Ops, Cooperation/Finance, Wallet/Withdrawals, Publishing/MyProject & IM/Messaging"
        }
    }
}

public enum MiniProgramWriteGatePosture: String, Sendable, Equatable {
    case readOnlyFailClosed = "read_only_fail_closed"
    case explicitOptInWriteGate = "explicit_opt_in_write_gate"

    public var isWriteGateEnabledByDefault: Bool {
        false
    }
}

public struct MiniProgramWave2ScopeDescriptor: Sendable, Equatable, Identifiable {
    public let scopeID: String
    public let domain: MiniProgramAlignmentDomain
    public let summary: String
    public let representativePagePaths: [String]
    public let nativeContracts: [String]
    public let writeGatePosture: MiniProgramWriteGatePosture

    public var id: String { scopeID }

    public init(
        scopeID: String,
        domain: MiniProgramAlignmentDomain,
        summary: String,
        representativePagePaths: [String],
        nativeContracts: [String],
        writeGatePosture: MiniProgramWriteGatePosture = .readOnlyFailClosed
    ) {
        self.scopeID = scopeID
        self.domain = domain
        self.summary = summary
        self.representativePagePaths = representativePagePaths
        self.nativeContracts = nativeContracts
        self.writeGatePosture = writeGatePosture
    }
}

public struct MiniProgramPageParityEntry: Sendable, Equatable, Identifiable {
    public let pagePath: String
    public let domain: MiniProgramAlignmentDomain?
    public let wave2ScopeID: String
    public let nativeReaderOrPresentationContract: String
    public let verifiedSourceFile: String
    public let verifiedHostSymbol: String
    public let writeGatePosture: MiniProgramWriteGatePosture

    public var id: String { pagePath }

    public init(
        pagePath: String,
        domain: MiniProgramAlignmentDomain? = nil,
        wave2ScopeID: String = "",
        nativeReaderOrPresentationContract: String = "",
        verifiedSourceFile: String = "",
        verifiedHostSymbol: String = "",
        writeGatePosture: MiniProgramWriteGatePosture = .readOnlyFailClosed
    ) {
        self.pagePath = pagePath
        self.domain = domain
        self.wave2ScopeID = wave2ScopeID
        self.nativeReaderOrPresentationContract = nativeReaderOrPresentationContract
        self.verifiedSourceFile = verifiedSourceFile
        self.verifiedHostSymbol = verifiedHostSymbol
        self.writeGatePosture = writeGatePosture
    }

    /// True only when an entry maps to a verified source file, real Swift symbol (never a decision-mode string),
    /// verified host container, and Wave-2 scope ID. Unverified routes leave those fields blank and return `false`.
    public var isSourceMappingVerified: Bool {
        let symbol = nativeReaderOrPresentationContract.trimmingCharacters(in: .whitespacesAndNewlines)
        let file = verifiedSourceFile.trimmingCharacters(in: .whitespacesAndNewlines)
        let host = verifiedHostSymbol.trimmingCharacters(in: .whitespacesAndNewlines)
        let scope = wave2ScopeID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard domain != nil,
              !scope.isEmpty,
              !symbol.isEmpty,
              !file.isEmpty,
              !host.isEmpty else {
            return false
        }
        return symbol != MiniProgram99PageDecisionMode.strictMiniProgramParity.rawValue
            && symbol != MiniProgram99PageDecisionMode.nativeSupersetEnhanced.rawValue
    }
}

public struct MiniProgram99PageParityRegistry: Sendable, Equatable {
    public static let allDomains: [MiniProgramAlignmentDomain] = MiniProgramAlignmentDomain.allCases

    public static let wave2Scopes: [MiniProgramWave2ScopeDescriptor] = [
        MiniProgramWave2ScopeDescriptor(
            scopeID: "w2-01",
            domain: .domainB,
            summary: "Entry, Splash, Phone/WeChat Login & Privacy Consent",
            representativePagePaths: ["pages/index/splash", "pages/login/login", "pages/login/phone"],
            nativeContracts: ["AuthSessionBootstrap", "AuthPhoneLoginPresentation", "PrivacyConsentSheetState"]
        ),
        MiniProgramWave2ScopeDescriptor(
            scopeID: "w2-02",
            domain: .domainB,
            summary: "Home Feed, City Selector, Primary Tab Bar & Global Search",
            representativePagePaths: ["pages/index/index", "pages/index/city", "pages/search/index"],
            nativeContracts: ["HomeFeedPresentation", "CitySelectionState", "GlobalSearchPresentation"]
        ),
        MiniProgramWave2ScopeDescriptor(
            scopeID: "w2-03",
            domain: .domainB,
            summary: "Member Profile, Growth Center, Badges & Equity Cards",
            representativePagePaths: ["pages/my/my", "pages/member/index", "pages/member/badges"],
            nativeContracts: ["MemberProfileReader", "MemberGrowthPresentation", "BadgeWallPresentation"]
        ),
        MiniProgramWave2ScopeDescriptor(
            scopeID: "w2-04",
            domain: .domainB,
            summary: "Profile Edit, Favorites & Frequent Participants Directory",
            representativePagePaths: ["pages/my/edit", "pages/my/favorites", "pages/my/participants"],
            nativeContracts: ["ProfileEditFormState", "FavoritesListReader", "ParticipantDirectoryState"]
        ),
        MiniProgramWave2ScopeDescriptor(
            scopeID: "w2-05",
            domain: .domainB,
            summary: "Settings, Legal Agreements, Compliance & Account Deregistration",
            representativePagePaths: ["pages/my/settings", "pages/my/agreement", "pages/my/deregister"],
            nativeContracts: ["SettingsDiagnosticsState", "LegalDocumentPresentation", "AccountDeregisterGuard"]
        ),
        MiniProgramWave2ScopeDescriptor(
            scopeID: "w2-06",
            domain: .domainC,
            summary: "Official Events List, Official Detail, Event Inbox & Mine",
            representativePagePaths: ["pages/official/index", "pages/official/detail", "pages/official/mine"],
            nativeContracts: ["OfficialEventReader", "OfficialEventDetailPresentation", "OfficialMineState"]
        ),
        MiniProgramWave2ScopeDescriptor(
            scopeID: "w2-07",
            domain: .domainC,
            summary: "Activity Detail, Signup/Tickets, Orders, Topics & Creative Square",
            representativePagePaths: [
                "pages/activity/detail",
                "pages/activity/signup",
                "pages/order/list",
                "pages/order/detail",
                "pages/topic/detail",
                "pages/square/index"
            ],
            nativeContracts: [
                "ActivityDetailReader",
                "OrderTicketDetailPresentation",
                "TopicSquarePresentation"
            ]
        ),
        MiniProgramWave2ScopeDescriptor(
            scopeID: "w2-08",
            domain: .domainD,
            summary: "Roam Hub, Route Detail, Passport, Stamp Book & SubpackageRoam Tools",
            representativePagePaths: [
                "pages/roam/index",
                "pages/roam/detail",
                "subpackageRoam/passport/index",
                "subpackageRoam/stamp/received"
            ],
            nativeContracts: [
                "RoamHubPresentation",
                "RoamRouteDetailReader",
                "RoamReceivedStampPresentation"
            ]
        ),
        MiniProgramWave2ScopeDescriptor(
            scopeID: "w2-09",
            domain: .domainD,
            summary: "Play Hub, Play Session, Merchant Check-in & Play Circle",
            representativePagePaths: ["pages/play/index", "pages/play/detail", "pages/play/session"],
            nativeContracts: ["PlayHubReader", "PlaySessionPresentation", "PlayMerchantCheckinGuard"]
        ),
        MiniProgramWave2ScopeDescriptor(
            scopeID: "w2-10",
            domain: .domainD,
            summary: "Team Home, Team Detail, Join Flow, My Teams & Nearby Teams",
            representativePagePaths: ["pages/team/index", "pages/team/detail", "pages/team/mine"],
            nativeContracts: ["TeamListReader", "TeamDetailPresentation", "TeamJoinFailClosedGate"]
        ),
        MiniProgramWave2ScopeDescriptor(
            scopeID: "w2-11",
            domain: .domainD,
            summary: "Template Browser, Template Detail & Interactive SearchMap",
            representativePagePaths: ["pages/template/index", "pages/template/detail", "pages/map/search"],
            nativeContracts: ["TemplateCatalogReader", "TemplateDetailPresentation", "SearchMapClusterPresentation"]
        ),
        MiniProgramWave2ScopeDescriptor(
            scopeID: "w2-12",
            domain: .domainE,
            summary: "Merchant Onboarding, Qualification Review & Store Profile",
            representativePagePaths: ["pages/merchant/index", "pages/merchant/apply", "pages/merchant/profile"],
            nativeContracts: ["MerchantOnboardingState", "MerchantProfileReader"]
        ),
        MiniProgramWave2ScopeDescriptor(
            scopeID: "w2-13",
            domain: .domainE,
            summary: "Merchant Workbench, Verification Scanner & Todo Queue",
            representativePagePaths: ["pages/merchant/workbench", "pages/merchant/todo", "pages/merchant/verify"],
            nativeContracts: ["MerchantWorkbenchPresentation", "MerchantVerificationGuard"]
        ),
        MiniProgramWave2ScopeDescriptor(
            scopeID: "w2-14",
            domain: .domainE,
            summary: "Merchant Ledger, Settlement Bills & Aftercare Refunds",
            representativePagePaths: ["pages/merchant/ledger", "pages/merchant/settlement", "pages/merchant/aftercare"],
            nativeContracts: ["MerchantLedgerReader", "MerchantSettlementPresentation"]
        ),
        MiniProgramWave2ScopeDescriptor(
            scopeID: "w2-15",
            domain: .domainE,
            summary: "Merchant Reviews, Customer Insights & Operator Roster",
            representativePagePaths: ["pages/merchant/reviews", "pages/merchant/customers", "pages/merchant/operators"],
            nativeContracts: ["MerchantReviewPresentation", "MerchantOperatorRosterState"]
        ),
        MiniProgramWave2ScopeDescriptor(
            scopeID: "w2-16",
            domain: .domainE,
            summary: "Merchant Marketing Campaigns, AI Insight & Coupon Templates",
            representativePagePaths: ["pages/merchant/marketing", "pages/merchant/aiInsight", "pages/merchant/coupons"],
            nativeContracts: ["MerchantMarketingPresentation", "MerchantCouponReader"]
        ),
        MiniProgramWave2ScopeDescriptor(
            scopeID: "w2-17",
            domain: .domainE,
            summary: "Merchant Operations Center, Brand Center & CityNode Dashboard",
            representativePagePaths: ["pages/merchant/operations", "pages/merchant/brand", "pages/merchant/cityNode"],
            nativeContracts: ["MerchantOperationsPresentation", "CityNodeDashboardReader"]
        ),
        MiniProgramWave2ScopeDescriptor(
            scopeID: "w2-18",
            domain: .domainE,
            summary: "Club Home, Club Detail, Governance Rules & Club Operations",
            representativePagePaths: ["pages/club/index", "pages/club/detail", "pages/club/governance"],
            nativeContracts: ["ClubDirectoryReader", "ClubDetailPresentation", "ClubGovernanceState"]
        ),
        MiniProgramWave2ScopeDescriptor(
            scopeID: "w2-19",
            domain: .domainE,
            summary: "Cooperation Directory, Cooperation Detail & Finance Statements",
            representativePagePaths: ["pages/cooperation/index", "pages/cooperation/detail", "pages/cooperation/finance"],
            nativeContracts: ["CooperationListReader", "CooperationFinancePresentation"]
        ),
        MiniProgramWave2ScopeDescriptor(
            scopeID: "w2-20",
            domain: .domainE,
            summary: "Publish Hub, MyProject, Template Authoring, Wallet & Withdrawals",
            representativePagePaths: [
                "pages/publish/index",
                "pages/myProject/index",
                "pages/wallet/index",
                "pages/wallet/withdraw"
            ],
            nativeContracts: [
                "PublishHubPresentation",
                "MyProjectReader",
                "WalletSummaryReader",
                "WithdrawalFailClosedGate"
            ]
        ),
        MiniProgramWave2ScopeDescriptor(
            scopeID: "w2-21",
            domain: .domainE,
            summary: "IM Inbox, Direct/Group Chat Thread & System Notifications",
            representativePagePaths: ["pages/message/index", "pages/message/chat", "pages/message/system"],
            nativeContracts: ["MessageInboxReader", "ChatThreadPresentation", "LocationShareHostCoordinator"]
        )
    ]

    public static let representativePages: [MiniProgramPageParityEntry] = [
        MiniProgramPageParityEntry(
            pagePath: "pages/login/login",
            domain: .domainB,
            wave2ScopeID: "w2-01",
            nativeReaderOrPresentationContract: "AuthPhoneLoginPresentation"
        ),
        MiniProgramPageParityEntry(
            pagePath: "pages/index/index",
            domain: .domainB,
            wave2ScopeID: "w2-02",
            nativeReaderOrPresentationContract: "HomeFeedPresentation"
        ),
        MiniProgramPageParityEntry(
            pagePath: "pages/my/my",
            domain: .domainB,
            wave2ScopeID: "w2-03",
            nativeReaderOrPresentationContract: "MemberProfileReader"
        ),
        MiniProgramPageParityEntry(
            pagePath: "pages/my/favorites",
            domain: .domainB,
            wave2ScopeID: "w2-04",
            nativeReaderOrPresentationContract: "FavoritesListReader"
        ),
        MiniProgramPageParityEntry(
            pagePath: "pages/my/settings",
            domain: .domainB,
            wave2ScopeID: "w2-05",
            nativeReaderOrPresentationContract: "SettingsDiagnosticsState"
        ),
        MiniProgramPageParityEntry(
            pagePath: "pages/official/index",
            domain: .domainC,
            wave2ScopeID: "w2-06",
            nativeReaderOrPresentationContract: "OfficialEventReader"
        ),
        MiniProgramPageParityEntry(
            pagePath: "pages/activity/detail",
            domain: .domainC,
            wave2ScopeID: "w2-07",
            nativeReaderOrPresentationContract: "ActivityDetailReader"
        ),
        MiniProgramPageParityEntry(
            pagePath: "pages/roam/index",
            domain: .domainD,
            wave2ScopeID: "w2-08",
            nativeReaderOrPresentationContract: "RoamHubPresentation"
        ),
        MiniProgramPageParityEntry(
            pagePath: "pages/play/index",
            domain: .domainD,
            wave2ScopeID: "w2-09",
            nativeReaderOrPresentationContract: "PlayHubReader"
        ),
        MiniProgramPageParityEntry(
            pagePath: "pages/team/index",
            domain: .domainD,
            wave2ScopeID: "w2-10",
            nativeReaderOrPresentationContract: "TeamListReader"
        ),
        MiniProgramPageParityEntry(
            pagePath: "pages/template/index",
            domain: .domainD,
            wave2ScopeID: "w2-11",
            nativeReaderOrPresentationContract: "TemplateCatalogReader"
        ),
        MiniProgramPageParityEntry(
            pagePath: "pages/merchant/index",
            domain: .domainE,
            wave2ScopeID: "w2-12",
            nativeReaderOrPresentationContract: "MerchantOnboardingState"
        ),
        MiniProgramPageParityEntry(
            pagePath: "pages/club/index",
            domain: .domainE,
            wave2ScopeID: "w2-18",
            nativeReaderOrPresentationContract: "ClubDirectoryReader"
        ),
        MiniProgramPageParityEntry(
            pagePath: "pages/publish/index",
            domain: .domainE,
            wave2ScopeID: "w2-20",
            nativeReaderOrPresentationContract: "PublishHubPresentation"
        ),
        MiniProgramPageParityEntry(
            pagePath: "pages/message/index",
            domain: .domainE,
            wave2ScopeID: "w2-21",
            nativeReaderOrPresentationContract: "MessageInboxReader"
        )
    ]

    public static func scopes(for domain: MiniProgramAlignmentDomain) -> [MiniProgramWave2ScopeDescriptor] {
        wave2Scopes.filter { $0.domain == domain }
    }

    public static func scope(withID scopeID: String) -> MiniProgramWave2ScopeDescriptor? {
        wave2Scopes.first { $0.scopeID == scopeID }
    }

    public static func entry(forPagePath pagePath: String) -> MiniProgramPageParityEntry? {
        all99BaselinePageEntries.first { $0.pagePath == pagePath }
            ?? representativePages.first { $0.pagePath == pagePath }
    }

    private struct VerifiedBaselineRouteTarget: Sendable, Equatable {
        let domain: MiniProgramAlignmentDomain
        let wave2ScopeID: String
        let nativeSymbol: String
        let sourceFile: String
        let hostSymbol: String
    }

    /// Only routes whose concrete Swift file, symbol, and host container have been directly verified in the repository
    /// are populated here. All other routes in the 99-page baseline subset remain explicitly blank (`""`) rather than
    /// using coarse 5-group placeholders or `decisionMode` strings.
    private static let verifiedBaselineTargetsByRoute: [String: VerifiedBaselineRouteTarget] = [
        "pages/searchmap/index": VerifiedBaselineRouteTarget(
            domain: .domainD,
            wave2ScopeID: "w2-11",
            nativeSymbol: "SearchMapExplorerView",
            sourceFile: "App/SearchMapExplorerView.swift",
            hostSymbol: "MainTabView"
        ),
        "subpackageTools/capsule/index": VerifiedBaselineRouteTarget(
            domain: .domainD,
            wave2ScopeID: "w2-08",
            nativeSymbol: "RoamCapsuleView",
            sourceFile: "App/RoamPassportPrivateToolsViews.swift",
            hostSymbol: "RoamPassportPrivateLinks"
        ),
        "subpackageTools/exploration-goals/index": VerifiedBaselineRouteTarget(
            domain: .domainD,
            wave2ScopeID: "w2-08",
            nativeSymbol: "RoamExplorationGoalsView",
            sourceFile: "App/RoamPassportPrivateToolsViews.swift",
            hostSymbol: "RoamPassportPrivateLinks"
        ),
        "subpackageTools/monthly-recap/index": VerifiedBaselineRouteTarget(
            domain: .domainD,
            wave2ScopeID: "w2-08",
            nativeSymbol: "RoamMonthlyRecapView",
            sourceFile: "App/RoamPassportToolsViews.swift",
            hostSymbol: "RoamPassportView"
        ),
        "subpackageTools/anniversary/index": VerifiedBaselineRouteTarget(
            domain: .domainD,
            wave2ScopeID: "w2-08",
            nativeSymbol: "RoamAnniversaryView",
            sourceFile: "App/RoamPassportToolsViews.swift",
            hostSymbol: "RoamPassportView"
        ),
        "pages/merchant/index/index": VerifiedBaselineRouteTarget(
            domain: .domainE,
            wave2ScopeID: "w2-12",
            nativeSymbol: "SessionMerchantOverviewView",
            sourceFile: "App/MerchantReading.swift",
            hostSymbol: "MerchantContentHomeView"
        ),
        "pages/shezhi/shezhi": VerifiedBaselineRouteTarget(
            domain: .domainB,
            wave2ScopeID: "w2-05",
            nativeSymbol: "SettingsView",
            sourceFile: "App/SettingsView.swift",
            hostSymbol: "AppCompositionRoot"
        )
    ]

    public static let all99BaselinePageEntries: [MiniProgramPageParityEntry] = {
        MiniProgramPageByPage99DecisionLedgerContract.canonical99PageRows.map { row in
            if let verified = verifiedBaselineTargetsByRoute[row.pagePath] {
                return MiniProgramPageParityEntry(
                    pagePath: row.pagePath,
                    domain: verified.domain,
                    wave2ScopeID: verified.wave2ScopeID,
                    nativeReaderOrPresentationContract: verified.nativeSymbol,
                    verifiedSourceFile: verified.sourceFile,
                    verifiedHostSymbol: verified.hostSymbol,
                    writeGatePosture: .readOnlyFailClosed
                )
            }
            if let rep = representativePages.first(where: { $0.pagePath == row.pagePath }) {
                return MiniProgramPageParityEntry(
                    pagePath: row.pagePath,
                    domain: rep.domain,
                    wave2ScopeID: rep.wave2ScopeID,
                    nativeReaderOrPresentationContract: rep.nativeReaderOrPresentationContract,
                    verifiedSourceFile: "",
                    verifiedHostSymbol: "",
                    writeGatePosture: .readOnlyFailClosed
                )
            }
            return MiniProgramPageParityEntry(
                pagePath: row.pagePath,
                domain: nil,
                wave2ScopeID: "",
                nativeReaderOrPresentationContract: "",
                verifiedSourceFile: "",
                verifiedHostSymbol: "",
                writeGatePosture: .readOnlyFailClosed
            )
        }
    }()

    public static var areAllWriteGatesFailClosedByDefault: Bool {
        wave2Scopes.allSatisfy { !$0.writeGatePosture.isWriteGateEnabledByDefault } &&
            representativePages.allSatisfy { !$0.writeGatePosture.isWriteGateEnabledByDefault } &&
            all99BaselinePageEntries.allSatisfy { !$0.writeGatePosture.isWriteGateEnabledByDefault }
    }
}
