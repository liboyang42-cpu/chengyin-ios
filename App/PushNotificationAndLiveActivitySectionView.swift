import SwiftUI
#if canImport(QuestifyCore)
import QuestifyCore
#endif

/// Self-contained APNs category parity row for `PushNotificationAndLiveActivitySectionView`.
public struct PushCategoryParityRow: Sendable, Equatable, Identifiable {
    public enum CategoryKind: String, CaseIterable, Sendable, Equatable {
        case imDirectMessage
        case teamInviteHandshake
        case orderLifecycleUpdate
        case clubSettlementNotice
        case roamTaskMilestone
    }

    public let id: String
    public let categoryKind: CategoryKind
    public let title: String
    public let deepLinkRoutePattern: String
    public let isDeepLinkSanitized: Bool
    public let isLockScreenPreviewRedacted: Bool
    public let supportsLiveActivityUpdate: Bool

    public init(
        id: String? = nil,
        categoryKind: CategoryKind,
        title: String,
        deepLinkRoutePattern: String,
        isDeepLinkSanitized: Bool = true,
        isLockScreenPreviewRedacted: Bool = true,
        supportsLiveActivityUpdate: Bool = false
    ) {
        self.id = id ?? categoryKind.rawValue
        self.categoryKind = categoryKind
        self.title = title
        self.deepLinkRoutePattern = deepLinkRoutePattern
        self.isDeepLinkSanitized = isDeepLinkSanitized
        self.isLockScreenPreviewRedacted = isLockScreenPreviewRedacted
        self.supportsLiveActivityUpdate = supportsLiveActivityUpdate
    }

    public var isCompliant: Bool {
        isDeepLinkSanitized && isLockScreenPreviewRedacted && !deepLinkRoutePattern.isEmpty
    }

    public var rowAccessibilityIdentifier: String {
        "pushNotificationParity.category.\(id)"
    }

    public var statusAccessibilityIdentifier: String {
        "pushNotificationParity.status.\(id)"
    }
}

/// Self-contained snapshot covering APNs category routing, deep-link sanitization,
/// lock-screen preview redaction, and Live Activity status.
public struct PushNotificationParitySnapshot: Sendable, Equatable {
    public static let canonicalCategoryIDs: [String] = PushCategoryParityRow.CategoryKind.allCases.map(\.rawValue)

    public let categories: [PushCategoryParityRow]
    public let apnsEnvironmentIsolatedByMarket: Bool
    public let liveActivitiesRedactedWhenLocked: Bool

    public init(
        categories: [PushCategoryParityRow],
        apnsEnvironmentIsolatedByMarket: Bool = true,
        liveActivitiesRedactedWhenLocked: Bool = true
    ) {
        self.categories = categories
        self.apnsEnvironmentIsolatedByMarket = apnsEnvironmentIsolatedByMarket
        self.liveActivitiesRedactedWhenLocked = liveActivitiesRedactedWhenLocked
    }

    public var sanitizedCategoryCount: Int {
        categories.filter(\.isDeepLinkSanitized).count
    }

    public var redactedCategoryCount: Int {
        categories.filter(\.isLockScreenPreviewRedacted).count
    }

    public var unsanitizedCategoryIDs: [String] {
        categories.filter { !$0.isDeepLinkSanitized }.map(\.id)
    }

    public var isAllReady: Bool {
        Set(categories.map(\.categoryKind)) == Set(PushCategoryParityRow.CategoryKind.allCases) &&
            categories.allSatisfy(\.isCompliant) &&
            apnsEnvironmentIsolatedByMarket &&
            liveActivitiesRedactedWhenLocked
    }

    public static let defaultReady = PushNotificationParitySnapshot(
        categories: [
            PushCategoryParityRow(
                categoryKind: .imDirectMessage,
                title: "IM Direct Message",
                deepLinkRoutePattern: "questify://im/session/{conversationId}",
                isDeepLinkSanitized: true,
                isLockScreenPreviewRedacted: true,
                supportsLiveActivityUpdate: false
            ),
            PushCategoryParityRow(
                categoryKind: .teamInviteHandshake,
                title: "Team Invite & Handshake",
                deepLinkRoutePattern: "questify://team/invite/{teamId}",
                isDeepLinkSanitized: true,
                isLockScreenPreviewRedacted: true,
                supportsLiveActivityUpdate: true
            ),
            PushCategoryParityRow(
                categoryKind: .orderLifecycleUpdate,
                title: "Order Lifecycle Update",
                deepLinkRoutePattern: "questify://orders/detail/{orderId}",
                isDeepLinkSanitized: true,
                isLockScreenPreviewRedacted: true,
                supportsLiveActivityUpdate: true
            ),
            PushCategoryParityRow(
                categoryKind: .clubSettlementNotice,
                title: "Club Settlement Notice",
                deepLinkRoutePattern: "questify://club/settlement/{settlementId}",
                isDeepLinkSanitized: true,
                isLockScreenPreviewRedacted: true,
                supportsLiveActivityUpdate: false
            ),
            PushCategoryParityRow(
                categoryKind: .roamTaskMilestone,
                title: "Roam Task Milestone",
                deepLinkRoutePattern: "questify://roam/route/{routeId}",
                isDeepLinkSanitized: true,
                isLockScreenPreviewRedacted: true,
                supportsLiveActivityUpdate: true
            )
        ],
        apnsEnvironmentIsolatedByMarket: true,
        liveActivitiesRedactedWhenLocked: true
    )

    public static func withUnsanitizedDeepLinks(
        _ unsanitizedKinds: Set<PushCategoryParityRow.CategoryKind>
    ) -> PushNotificationParitySnapshot {
        let updated = defaultReady.categories.map { row in
            guard unsanitizedKinds.contains(row.categoryKind) else {
                return row
            }
            return PushCategoryParityRow(
                id: row.id,
                categoryKind: row.categoryKind,
                title: row.title,
                deepLinkRoutePattern: row.deepLinkRoutePattern,
                isDeepLinkSanitized: false,
                isLockScreenPreviewRedacted: row.isLockScreenPreviewRedacted,
                supportsLiveActivityUpdate: row.supportsLiveActivityUpdate
            )
        }
        return PushNotificationParitySnapshot(
            categories: updated,
            apnsEnvironmentIsolatedByMarket: defaultReady.apnsEnvironmentIsolatedByMarket,
            liveActivitiesRedactedWhenLocked: defaultReady.liveActivitiesRedactedWhenLocked
        )
    }
}

@MainActor
public struct PushNotificationAndLiveActivitySectionView: View {
    public let snapshot: PushNotificationParitySnapshot
    public var onSelectCategory: ((PushCategoryParityRow) -> Void)?

    public init(
        snapshot: PushNotificationParitySnapshot = .defaultReady,
        onSelectCategory: ((PushCategoryParityRow) -> Void)? = nil
    ) {
        self.snapshot = snapshot
        self.onSelectCategory = onSelectCategory
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerRow
            securitySummaryBanner
            ForEach(snapshot.categories) { row in
                categoryRowCard(row)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pushNotificationParity.section")
    }

    private var headerRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "bell.badge.fill")
                .foregroundStyle(.teal)
            Text(verbatim: "Push Notification & Live Activity Parity")
                .font(.headline)
                .accessibilityIdentifier("pushNotificationParity.header")
            Spacer()
            Text(verbatim: headerBadgeText)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule(style: .continuous)
                        .fill(headerBadgeTint.opacity(0.16))
                )
                .foregroundStyle(headerBadgeTint)
                .accessibilityIdentifier("pushNotificationParity.summaryBadge")
        }
    }

    private var securitySummaryBanner: some View {
        HStack(spacing: 8) {
            statusPill(
                text: "Deep-Link Sanitized: \(snapshot.sanitizedCategoryCount)/\(snapshot.categories.count)",
                tint: snapshot.unsanitizedCategoryIDs.isEmpty ? .green : .red
            )
            statusPill(
                text: "Lock-Screen Redacted: \(snapshot.redactedCategoryCount)/\(snapshot.categories.count)",
                tint: snapshot.redactedCategoryCount == snapshot.categories.count ? .blue : .orange
            )
            statusPill(
                text: snapshot.liveActivitiesRedactedWhenLocked ? "LIVE ACTIVITY REDACTED" : "LIVE ACTIVITY UNREDACTED",
                tint: snapshot.liveActivitiesRedactedWhenLocked ? .teal : .red
            )
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("pushNotificationParity.securityBanner")
    }

    private func categoryRowCard(_ row: PushCategoryParityRow) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(verbatim: row.title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(verbatim: row.isCompliant ? "READY" : "UNSANITIZED WARNING")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(
                        Capsule(style: .continuous)
                            .fill((row.isCompliant ? Color.green : Color.red).opacity(0.16))
                    )
                    .foregroundStyle(row.isCompliant ? Color.green : Color.red)
                    .accessibilityIdentifier(row.statusAccessibilityIdentifier)
            }

            Text(verbatim: "Route: \(row.deepLinkRoutePattern)")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                statusPill(
                    text: row.isDeepLinkSanitized ? "DEEP-LINK SANITIZED" : "UNSANITIZED DEEP-LINK",
                    tint: row.isDeepLinkSanitized ? .green : .red
                )
                statusPill(
                    text: row.isLockScreenPreviewRedacted ? "LOCK PREVIEW REDACTED" : "LOCK PREVIEW EXPOSED",
                    tint: row.isLockScreenPreviewRedacted ? .blue : .orange
                )
                if row.supportsLiveActivityUpdate {
                    statusPill(text: "LIVE ACTIVITY", tint: .purple)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onSelectCategory?(row)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(row.rowAccessibilityIdentifier)
    }

    private func statusPill(text: String, tint: Color) -> some View {
        Text(verbatim: text)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule(style: .continuous)
                    .fill(tint.opacity(0.14))
            )
            .foregroundStyle(tint)
    }

    public var headerBadgeText: String {
        if snapshot.isAllReady {
            return "ALL 5 APNS CATEGORIES READY"
        }
        return "WARNING: \(snapshot.unsanitizedCategoryIDs.count) UNSANITIZED"
    }

    private var headerBadgeTint: Color {
        snapshot.isAllReady ? .green : .red
    }
}
