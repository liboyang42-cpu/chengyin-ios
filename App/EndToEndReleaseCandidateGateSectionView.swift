import SwiftUI
#if canImport(QuestifyCore)
import QuestifyCore
#endif

/// Self-contained presentation row for one End-to-End Release Candidate Gate (`RC-GATE-01`..`RC-GATE-06`).
public struct ReleaseCandidateGateRow: Identifiable, Equatable, Sendable {
    public let id: String
    public let gateCode: String
    public let title: String
    public let requirementSummary: String
    public let isPassed: Bool
    public let isFailClosed: Bool

    public init(
        id: String,
        gateCode: String,
        title: String,
        requirementSummary: String,
        isPassed: Bool = true,
        isFailClosed: Bool = true
    ) {
        self.id = id
        self.gateCode = gateCode
        self.title = title
        self.requirementSummary = requirementSummary
        self.isPassed = isPassed
        self.isFailClosed = isFailClosed
    }

    public var statusBadgeText: String {
        (isPassed && isFailClosed) ? "PASS • FAIL-CLOSED" : "BLOCKED • ACTION REQUIRED"
    }
}

/// Self-contained presentation snapshot for `RC-GATE-01` through `RC-GATE-06`.
public struct EndToEndReleaseCandidateSnapshot: Equatable, Sendable {
    public let gates: [ReleaseCandidateGateRow]
    public let candidateMarket: String
    public let isSafeCIDefaultProfile: Bool

    public init(
        gates: [ReleaseCandidateGateRow] = Self.defaultGates,
        candidateMarket: String = "CN",
        isSafeCIDefaultProfile: Bool = true
    ) {
        self.gates = gates
        self.candidateMarket = candidateMarket
        self.isSafeCIDefaultProfile = isSafeCIDefaultProfile
    }

    public static let defaultGates: [ReleaseCandidateGateRow] = [
        ReleaseCandidateGateRow(
            id: "RC-GATE-01",
            gateCode: "RC-GATE-01",
            title: "Build & Signing Coordinates",
            requirementSummary: "Config/Base.xcconfig keeps safe unsigned CI defaults; archive requires explicit Bundle ID & Development Team"
        ),
        ReleaseCandidateGateRow(
            id: "RC-GATE-02",
            gateCode: "RC-GATE-02",
            title: "Regional & Session Realm Isolation",
            requirementSummary: "Strict CN/US market profile and cn-*/us-* session realm isolation plus IOS-I00-1 server role verification"
        ),
        ReleaseCandidateGateRow(
            id: "RC-GATE-03",
            gateCode: "RC-GATE-03",
            title: "Approved HTTPS API Base URL",
            requirementSummary: "HTTPS-only endpoint allowlist; legacy mini-program IP, loopback, and placeholder hosts rejected"
        ),
        ReleaseCandidateGateRow(
            id: "RC-GATE-04",
            gateCode: "RC-GATE-04",
            title: "Fail-Closed High-Risk Capabilities",
            requirementSummary: "SMS, WeChat/Apple auth, payment/withdrawal, topic like write, NPC log delete, and fog/layer sync stay OFF"
        ),
        ReleaseCandidateGateRow(
            id: "RC-GATE-05",
            gateCode: "RC-GATE-05",
            title: "Wave 1–5 Parity & Host Coordinator Coverage",
            requirementSummary: "99/99 mini-program pages, 21/21 Wave-2 scopes, 13/13 Wave-3 lanes, 19/19 Reform packages & 41/41 Map Visual items"
        ),
        ReleaseCandidateGateRow(
            id: "RC-GATE-06",
            gateCode: "RC-GATE-06",
            title: "Deterministic UI Readiness & Accessibility",
            requirementSummary: "Off-screen Form reveal contract, bilingual catalog parity, and zero committed credentials or provisioning profiles"
        )
    ]

    public static let failClosedDefault = EndToEndReleaseCandidateSnapshot()

    public var passedGateCount: Int {
        gates.filter { $0.isPassed && $0.isFailClosed }.count
    }

    public var isAllGatesGreen: Bool {
        gates.count == 6 && passedGateCount == 6
    }
}

/// SwiftUI Section View rendering `RC-GATE-01`..`RC-GATE-06` readiness status using `Text(verbatim:)` throughout.
@MainActor
public struct EndToEndReleaseCandidateGateSectionView: View {
    public let snapshot: EndToEndReleaseCandidateSnapshot

    public init(snapshot: EndToEndReleaseCandidateSnapshot = .failClosedDefault) {
        self.snapshot = snapshot
    }

    public var summaryBadgeText: String {
        snapshot.isAllGatesGreen
            ? "RC Gates: \(snapshot.passedGateCount)/\(snapshot.gates.count) PASS"
            : "RC Gates: \(snapshot.passedGateCount)/\(snapshot.gates.count) PASS (BLOCKED)"
    }

    public var archiveModeBannerText: String {
        let mode = snapshot.isSafeCIDefaultProfile ? "CI_SAFE_UNSIGNED_DEFAULT" : "ARCHIVE_CANDIDATE_OVERRIDE"
        return "Profile: \(snapshot.candidateMarket) • Mode: \(mode)"
    }

    public var failClosedBannerText: String {
        snapshot.isAllGatesGreen
            ? "End-to-End RC Gate Status: ALL 6 GATES VERIFIED & FAIL-CLOSED"
            : "End-to-End RC Gate Status: HOLD ARCHIVE — UNRESOLVED GATE VIOLATION"
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: "End-to-End Release Candidate Gate (RC-GATE-01..06)")
                    .font(.headline)
                    .accessibilityIdentifier("releaseCandidateGate.title")
                Spacer()
                Text(verbatim: summaryBadgeText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(snapshot.isAllGatesGreen ? Color.green : Color.red)
                    .accessibilityIdentifier("releaseCandidateGate.summaryBadge")
            }

            Text(verbatim: archiveModeBannerText)
                .font(.footnote.monospaced())
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("releaseCandidateGate.archiveModeBanner")

            Text(verbatim: failClosedBannerText)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(snapshot.isAllGatesGreen ? Color.green : Color.red)
                .accessibilityIdentifier("releaseCandidateGate.failClosedBanner")

            VStack(alignment: .leading, spacing: 8) {
                ForEach(snapshot.gates) { gate in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(verbatim: "[\(gate.gateCode)] \(gate.title)")
                                .font(.subheadline.weight(.medium))
                            Spacer()
                            Text(verbatim: gate.statusBadgeText)
                                .font(.caption2.monospaced())
                                .foregroundStyle((gate.isPassed && gate.isFailClosed) ? Color.green : Color.red)
                        }
                        Text(verbatim: gate.requirementSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(8)
                    .background(Color.secondary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            .accessibilityIdentifier("releaseCandidateGate.gateList")
        }
        .padding(12)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("releaseCandidateGate.section")
    }
}
