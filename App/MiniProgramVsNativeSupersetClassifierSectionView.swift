import SwiftUI
#if canImport(QuestifyCore)
import QuestifyCore
#endif

/// Self-contained classification row for `MiniProgramVsNativeSupersetClassifierSectionView`.
public struct ScopeClassificationRow: Sendable, Equatable, Identifiable {
    public enum ClassificationBucket: String, CaseIterable, Sendable, Equatable {
        case strictAPIAndCopyAlignment = "1:1 MINI-PROGRAM API/COPY ALIGNMENT"
        case nativeSupersetPreserved = "IOS NATIVE SUPERSET PRESERVED"
    }

    public let id: String
    public let scopeRange: String
    public let title: String
    public let detail: String
    public let bucket: ClassificationBucket
    public let preservesBackendContract: Bool
    public let preservesNativeSuperset: Bool

    public init(
        id: String? = nil,
        scopeRange: String,
        title: String,
        detail: String,
        bucket: ClassificationBucket,
        preservesBackendContract: Bool = true,
        preservesNativeSuperset: Bool = true
    ) {
        self.id = id ?? scopeRange
        self.scopeRange = scopeRange
        self.title = title
        self.detail = detail
        self.bucket = bucket
        self.preservesBackendContract = preservesBackendContract
        self.preservesNativeSuperset = preservesNativeSuperset
    }

    public var isCompliant: Bool {
        guard preservesBackendContract else { return false }
        switch bucket {
        case .strictAPIAndCopyAlignment:
            return true
        case .nativeSupersetPreserved:
            return preservesNativeSuperset
        }
    }

    public var rowAccessibilityIdentifier: String {
        "mpVsNativeClassifier.row.\(id)"
    }

    public var statusAccessibilityIdentifier: String {
        "mpVsNativeClassifier.status.\(id)"
    }
}

/// Self-contained snapshot summarizing the classification between `1:1 Mini-Program API/Copy Alignment`
/// (`w2-01..w2-21`) and `iOS Native Superset Preserved` (`W02..W20`).
public struct MiniProgramVsNativeClassifierSnapshot: Sendable, Equatable {
    public let rows: [ScopeClassificationRow]

    public init(rows: [ScopeClassificationRow]) {
        self.rows = rows
    }

    public var strictAlignmentCount: Int {
        rows.filter { $0.bucket == .strictAPIAndCopyAlignment && $0.isCompliant }.count
    }

    public var nativeSupersetCount: Int {
        rows.filter { $0.bucket == .nativeSupersetPreserved && $0.isCompliant }.count
    }

    public var downgradedRowIDs: [String] {
        rows.filter { !$0.isCompliant }.map(\.id)
    }

    public var isAllReady: Bool {
        !rows.isEmpty &&
            strictAlignmentCount > 0 &&
            nativeSupersetCount > 0 &&
            rows.allSatisfy(\.isCompliant)
    }

    public static let defaultReady = MiniProgramVsNativeClassifierSnapshot(
        rows: [
            ScopeClassificationRow(
                id: "w2_01_to_w2_08_core_api",
                scopeRange: "w2-01..w2-08",
                title: "Auth, Profile.career, Club Access Form & Roam Readbacks",
                detail: "1:1 backend contract (/api/club/access/me POST form, /api/user/stamps/received, AccountSessionGate)",
                bucket: .strictAPIAndCopyAlignment,
                preservesBackendContract: true,
                preservesNativeSuperset: true
            ),
            ScopeClassificationRow(
                id: "w2_09_to_w2_21_merchant_and_tools",
                scopeRange: "w2-09..w2-21",
                title: "Private Tools, Merchant Decor JSON & Insight Top-Level Keys",
                detail: "1:1 backend contract (/api/merchant/decor/save JSON, /api/merchant/insight, RoamPrivateTools)",
                bucket: .strictAPIAndCopyAlignment,
                preservesBackendContract: true,
                preservesNativeSuperset: true
            ),
            ScopeClassificationRow(
                id: "w02_to_w08_journal_storekit_audio",
                scopeRange: "W02..W08",
                title: "Encrypted <key>:game Journal, StoreKit 2 & Native Audio/TTS",
                detail: "Durable offline command journal, StoreKit 2 entitlements, and AVAudioSession interruption recovery",
                bucket: .nativeSupersetPreserved,
                preservesBackendContract: true,
                preservesNativeSuperset: true
            ),
            ScopeClassificationRow(
                id: "w14_to_w20_mapkit_fog_signpost",
                scopeRange: "W14..W20",
                title: "MapKit 3D + Personal Fog, MV01..MV41 & Signpost 60fps",
                detail: "Native 3D map layers, local personal fog, ReformWorldHostWorkbenchView, and OSSignposter",
                bucket: .nativeSupersetPreserved,
                preservesBackendContract: true,
                preservesNativeSuperset: true
            )
        ]
    )

    public static func withDowngradedNativeSuperset(
        rowIDs: Set<String>
    ) -> MiniProgramVsNativeClassifierSnapshot {
        let updated = defaultReady.rows.map { row in
            guard rowIDs.contains(row.id) || rowIDs.contains(row.scopeRange) else {
                return row
            }
            return ScopeClassificationRow(
                id: row.id,
                scopeRange: row.scopeRange,
                title: row.title,
                detail: row.detail,
                bucket: row.bucket,
                preservesBackendContract: row.preservesBackendContract,
                preservesNativeSuperset: false
            )
        }
        return MiniProgramVsNativeClassifierSnapshot(rows: updated)
    }
}

@MainActor
public struct MiniProgramVsNativeSupersetClassifierSectionView: View {
    public let snapshot: MiniProgramVsNativeClassifierSnapshot
    public var onSelectRow: ((ScopeClassificationRow) -> Void)?

    public init(
        snapshot: MiniProgramVsNativeClassifierSnapshot = .defaultReady,
        onSelectRow: ((ScopeClassificationRow) -> Void)? = nil
    ) {
        self.snapshot = snapshot
        self.onSelectRow = onSelectRow
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerRow
            summaryPillsRow
            ForEach(snapshot.rows) { row in
                rowCard(row)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("mpVsNativeClassifier.section")
    }

    private var headerRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "square.stack.3d.up.badge.a.fill")
                .foregroundStyle(.teal)
            Text(verbatim: "Mini-Program vs Native Superset Classifier")
                .font(.headline)
                .accessibilityIdentifier("mpVsNativeClassifier.header")
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
                .accessibilityIdentifier("mpVsNativeClassifier.summaryBadge")
        }
    }

    private var summaryPillsRow: some View {
        HStack(spacing: 8) {
            pill(
                text: "1:1 API/Copy: \(snapshot.strictAlignmentCount)",
                tint: .blue
            )
            pill(
                text: "Native Superset Preserved: \(snapshot.nativeSupersetCount)",
                tint: snapshot.downgradedRowIDs.isEmpty ? .green : .red
            )
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("mpVsNativeClassifier.bucketSummary")
    }

    private func rowCard(_ row: ScopeClassificationRow) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(verbatim: "[\(row.scopeRange)] \(row.title)")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(verbatim: row.isCompliant ? "PRESERVED" : "DOWNGRADE WARNING")
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

            Text(verbatim: row.bucket.rawValue)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(row.bucket == .strictAPIAndCopyAlignment ? .blue : .teal)

            Text(verbatim: row.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onSelectRow?(row)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(row.rowAccessibilityIdentifier)
    }

    private func pill(text: String, tint: Color) -> some View {
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
            return "CLASSIFICATION VERIFIED"
        }
        return "WARNING: \(snapshot.downgradedRowIDs.count) DOWNGRADED"
    }

    private var headerBadgeTint: Color {
        snapshot.isAllReady ? .green : .red
    }
}
