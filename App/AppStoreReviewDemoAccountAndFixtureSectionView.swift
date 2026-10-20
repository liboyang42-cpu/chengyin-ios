import SwiftUI
#if canImport(QuestifyCore)
import QuestifyCore
#endif

/// Self-contained reviewer scenario row for App Store Review Guideline 2.1 readiness across
/// `Guest`, `Player`, `Merchant`, and `Club Admin` walkthroughs plus out-of-city LBS preview fallback.
public struct ReviewerScenarioRow: Sendable, Equatable, Identifiable {
    public enum RolePersona: String, CaseIterable, Sendable, Equatable {
        case guest = "GUEST"
        case player = "PLAYER"
        case merchant = "MERCHANT"
        case clubAdmin = "CLUB_ADMIN"
    }

    public let id: String
    public let persona: RolePersona
    public let title: String
    public let walkthroughSummary: String
    public let supportsOutOfCityLBSFallback: Bool
    public let isScenarioReady: Bool
    public let badgeText: String

    public init(
        id: String,
        persona: RolePersona,
        title: String,
        walkthroughSummary: String,
        supportsOutOfCityLBSFallback: Bool = true,
        isScenarioReady: Bool = true,
        badgeText: String = "READY"
    ) {
        self.id = id
        self.persona = persona
        self.title = title
        self.walkthroughSummary = walkthroughSummary
        self.supportsOutOfCityLBSFallback = supportsOutOfCityLBSFallback
        self.isScenarioReady = isScenarioReady
        self.badgeText = badgeText
    }

    public static let defaultRows: [ReviewerScenarioRow] = [
        ReviewerScenarioRow(
            id: "guest-browse-and-map-preview",
            persona: .guest,
            title: "Guest — Public Discovery & Map Preview",
            walkthroughSummary: "Browses public activities, topic previews, and map legend without forced sign-in."
        ),
        ReviewerScenarioRow(
            id: "player-run-and-lbs-fallback",
            persona: .player,
            title: "Player — Activity Run, Orders & Out-of-City LBS Preview",
            walkthroughSummary: "Walks route preview, ticket wallet, and out-of-city reviewer LBS fallback without requiring physical arrival in Shanghai."
        ),
        ReviewerScenarioRow(
            id: "merchant-station-and-redemption",
            persona: .merchant,
            title: "Merchant — Station Verification & Two-Step Staff Redemption",
            walkthroughSummary: "Exercises coupon/order preview -> final confirmation and store point management."
        ),
        ReviewerScenarioRow(
            id: "club-admin-governance-and-settlement",
            persona: .clubAdmin,
            title: "Club Admin — Series Schedule, Enrollment & Settlement Read",
            walkthroughSummary: "Reviews club series schedule dates, member enrollment summary, and readback-verified settlement status."
        ),
    ]
}

/// Self-contained snapshot backing `AppStoreReviewDemoAccountAndFixtureSectionView`.
public struct AppStoreReviewDemoSnapshot: Sendable, Equatable {
    public let guideline21NotesPrepared: Bool
    public let outOfCityLBSPreviewFallbackEnabled: Bool
    public let demoCredentialsRedactedInSource: Bool
    public let scenarios: [ReviewerScenarioRow]

    public init(
        guideline21NotesPrepared: Bool = true,
        outOfCityLBSPreviewFallbackEnabled: Bool = true,
        demoCredentialsRedactedInSource: Bool = true,
        scenarios: [ReviewerScenarioRow] = ReviewerScenarioRow.defaultRows
    ) {
        self.guideline21NotesPrepared = guideline21NotesPrepared
        self.outOfCityLBSPreviewFallbackEnabled = outOfCityLBSPreviewFallbackEnabled
        self.demoCredentialsRedactedInSource = demoCredentialsRedactedInSource
        self.scenarios = scenarios
    }

    public static let defaultReady = AppStoreReviewDemoSnapshot()

    public var readyScenarioCount: Int {
        scenarios.filter { $0.isScenarioReady && $0.supportsOutOfCityLBSFallback }.count
    }

    public var isGuideline21Ready: Bool {
        scenarios.count == 4
            && readyScenarioCount == 4
            && guideline21NotesPrepared
            && outOfCityLBSPreviewFallbackEnabled
            && demoCredentialsRedactedInSource
    }
}

/// SwiftUI section view displaying App Store Review Guideline 2.1 readiness across
/// `Guest`, `Player`, `Merchant`, and `Club Admin` walkthroughs plus out-of-city LBS
/// preview fallback using `Text(verbatim:)` throughout (0 new localization keys).
@MainActor public struct AppStoreReviewDemoAccountAndFixtureSectionView: View {
    public let snapshot: AppStoreReviewDemoSnapshot

    public init(snapshot: AppStoreReviewDemoSnapshot = .defaultReady) {
        self.snapshot = snapshot
    }

    public var body: some View {
        Group {
            summarySection
            scenariosSection
        }
    }

    private var summarySection: some View {
        Section {
            LabeledContent {
                Text(verbatim: snapshot.isGuideline21Ready ? "Ready (4/4 Personas Verified)" : "Attention Required")
            } label: {
                Text(verbatim: "Guideline 2.1 Review Status")
            }
            .accessibilityIdentifier("appStoreReviewDemo.summary.guideline21")

            LabeledContent {
                Text(verbatim: snapshot.outOfCityLBSPreviewFallbackEnabled
                    ? "Enabled (No Physical Geofence Required for Review)"
                    : "Disabled")
            } label: {
                Text(verbatim: "Out-of-City LBS Preview Fallback")
            }
            .accessibilityIdentifier("appStoreReviewDemo.summary.lbsFallback")

            LabeledContent {
                Text(verbatim: snapshot.demoCredentialsRedactedInSource
                    ? "Redacted in Source (App Store Connect Notes Only)"
                    : "Exposed in Source")
            } label: {
                Text(verbatim: "Demo Credential Hygiene")
            }
            .accessibilityIdentifier("appStoreReviewDemo.summary.credentialSafety")

            LabeledContent {
                Text(verbatim: "\(snapshot.readyScenarioCount)/\(snapshot.scenarios.count) Ready")
            } label: {
                Text(verbatim: "Role Walkthrough Coverage")
            }
            .accessibilityIdentifier("appStoreReviewDemo.summary.scenariosReady")
        } header: {
            Text(verbatim: "App Store Review Demo & Fixture Readiness (Guideline 2.1)")
        } footer: {
            Text(verbatim: "Covers Guest, Player, Merchant, and Club Admin review paths with out-of-city LBS preview fallback.")
                .accessibilityIdentifier("appStoreReviewDemo.summary.footer")
        }
    }

    private var scenariosSection: some View {
        Section {
            ForEach(snapshot.scenarios) { row in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .top, spacing: 8) {
                        Text(verbatim: row.title)
                            .font(.subheadline)
                        Spacer()
                        Text(verbatim: row.badgeText)
                            .font(.caption.monospaced())
                            .accessibilityIdentifier("appStoreReviewDemo.scenario.badge.\(row.id)")
                    }
                    Text(verbatim: row.walkthroughSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(verbatim: row.supportsOutOfCityLBSFallback
                        ? "Out-of-City LBS Preview Fallback: Supported"
                        : "Out-of-City LBS Preview Fallback: Missing")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("appStoreReviewDemo.scenario.\(row.id)")
            }
        } header: {
            Text(verbatim: "Reviewer Role Walkthrough Scenarios")
        }
    }
}
