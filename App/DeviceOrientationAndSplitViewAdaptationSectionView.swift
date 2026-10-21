import SwiftUI
#if canImport(QuestifyCore)
import QuestifyCore
#endif

/// Self-contained presentation row for one device orientation, Safe Area, keyboard, or size-class adaptation group.
public struct DeviceLayoutGroupRow: Sendable, Equatable, Identifiable {
    public let id: String
    public let groupCode: String
    public let title: String
    public let adaptationSummary: String
    public let isCompliant: Bool

    public init(
        id: String,
        groupCode: String,
        title: String,
        adaptationSummary: String,
        isCompliant: Bool = true
    ) {
        self.id = id
        self.groupCode = groupCode
        self.title = title
        self.adaptationSummary = adaptationSummary
        self.isCompliant = isCompliant
    }

    public var statusBadgeText: String {
        isCompliant ? "ADAPTED • VERIFIED" : "OVERLAP • REVIEW REQUIRED"
    }
}

/// Self-contained presentation snapshot for Dynamic Island / Home Indicator Safe Area preservation,
/// keyboard avoidance, and compact/regular size class adaptation.
public struct DeviceLayoutAdaptationSnapshot: Sendable, Equatable {
    public let rows: [DeviceLayoutGroupRow]
    public let safeAreaInsetsPreserved: Bool
    public let keyboardAvoidanceVerified: Bool
    public let compactAndRegularAdapted: Bool

    public init(
        rows: [DeviceLayoutGroupRow] = Self.defaultRows,
        safeAreaInsetsPreserved: Bool = true,
        keyboardAvoidanceVerified: Bool = true,
        compactAndRegularAdapted: Bool = true
    ) {
        self.rows = rows
        self.safeAreaInsetsPreserved = safeAreaInsetsPreserved
        self.keyboardAvoidanceVerified = keyboardAvoidanceVerified
        self.compactAndRegularAdapted = compactAndRegularAdapted
    }

    public static let defaultRows: [DeviceLayoutGroupRow] = [
        DeviceLayoutGroupRow(
            id: "layout-01-safe-area",
            groupCode: "LAYOUT-01",
            title: "Dynamic Island & Home Indicator Safe Area",
            adaptationSummary: "Full-bleed artwork and map canvases preserve interactive HUD controls and bottom booking bars inside Safe Area insets"
        ),
        DeviceLayoutGroupRow(
            id: "layout-02-keyboard-avoidance",
            groupCode: "LAYOUT-02",
            title: "Form & Composer Keyboard Avoidance",
            adaptationSummary: "Long forms (projectEditor, registration, IM composer) support bounded scroll reveal and unobscured confirmation buttons"
        ),
        DeviceLayoutGroupRow(
            id: "layout-03-size-classes",
            groupCode: "LAYOUT-03",
            title: "Compact & Regular Size Class Adaptation",
            adaptationSummary: "Supports iPhone (Portrait/Landscape) and iPad (4 orientations, Split View) with alert/sheet resilience under regular width"
        )
    ]

    public static let defaultReady = DeviceLayoutAdaptationSnapshot()

    public var isAllAdapted: Bool {
        rows.count == 3 &&
        safeAreaInsetsPreserved &&
        keyboardAvoidanceVerified &&
        compactAndRegularAdapted &&
        rows.allSatisfy(\.isCompliant)
    }
}

/// SwiftUI Section View displaying Dynamic Island / Home Indicator Safe Area preservation,
/// keyboard avoidance, and compact/regular size class adaptation using `Text(verbatim:)` throughout.
@MainActor
public struct DeviceOrientationAndSplitViewAdaptationSectionView: View {
    public let snapshot: DeviceLayoutAdaptationSnapshot

    public init(snapshot: DeviceLayoutAdaptationSnapshot = .defaultReady) {
        self.snapshot = snapshot
    }

    public var statusBadgeText: String {
        snapshot.isAllAdapted
            ? "Device Layout Gate: READY (3/3 Groups Adapted)"
            : "Device Layout Gate: WARNING (Safe Area / Keyboard Overlap)"
    }

    public var safeAreaSummaryText: String {
        snapshot.safeAreaInsetsPreserved
            ? "Safe Area Preservation: Verified (Dynamic Island & Home Indicator insets respected)"
            : "Safe Area Preservation: WARNING — interactive control clipped by system inset"
    }

    public var keyboardAvoidanceSummaryText: String {
        snapshot.keyboardAvoidanceVerified
            ? "Keyboard Avoidance: Verified (Unobscured Form rows & bounded off-screen reveal)"
            : "Keyboard Avoidance: WARNING — primary input or review CTA obscured by keyboard"
    }

    public var sizeClassSummaryText: String {
        snapshot.compactAndRegularAdapted
            ? "Size Class & Split View: Compact/Regular iPhone & iPad orientations adapted"
            : "Size Class & Split View: WARNING — regular-width popover/split layout mismatch"
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: "Device Orientation, Safe Area & Split View Adaptation")
                    .font(.headline)
                    .accessibilityIdentifier("deviceLayoutAdaptation.title")
                Spacer()
                Text(verbatim: statusBadgeText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(snapshot.isAllAdapted ? Color.green : Color.orange)
                    .accessibilityIdentifier("deviceLayoutAdaptation.statusBadge")
            }

            Text(verbatim: safeAreaSummaryText)
                .font(.footnote)
                .foregroundStyle(snapshot.safeAreaInsetsPreserved ? Color.secondary : Color.red)
                .accessibilityIdentifier("deviceLayoutAdaptation.safeAreaSummary")

            Text(verbatim: keyboardAvoidanceSummaryText)
                .font(.footnote)
                .foregroundStyle(snapshot.keyboardAvoidanceVerified ? Color.secondary : Color.red)
                .accessibilityIdentifier("deviceLayoutAdaptation.keyboardAvoidanceSummary")

            Text(verbatim: sizeClassSummaryText)
                .font(.footnote)
                .foregroundStyle(snapshot.compactAndRegularAdapted ? Color.secondary : Color.orange)
                .accessibilityIdentifier("deviceLayoutAdaptation.sizeClassSummary")

            VStack(alignment: .leading, spacing: 8) {
                ForEach(snapshot.rows) { row in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(verbatim: "[\(row.groupCode)] \(row.title)")
                                .font(.subheadline.weight(.medium))
                            Spacer()
                            Text(verbatim: row.statusBadgeText)
                                .font(.caption2.monospaced())
                                .foregroundStyle(row.isCompliant ? Color.green : Color.orange)
                        }
                        Text(verbatim: row.adaptationSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(8)
                    .background(Color.secondary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            .accessibilityIdentifier("deviceLayoutAdaptation.rowList")
        }
        .padding(12)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("deviceLayoutAdaptation.section")
    }
}
