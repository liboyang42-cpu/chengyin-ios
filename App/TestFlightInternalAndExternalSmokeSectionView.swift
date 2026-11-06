import SwiftUI
#if canImport(QuestifyCore)
import QuestifyCore
#endif

/// Self-contained presentation row for one Day-5 real-device TestFlight internal/external smoke journey.
public struct TestFlightSmokeJourneyRow: Sendable, Equatable, Identifiable {
    public let id: String
    public let journeyCode: String
    public let title: String
    public let verificationSteps: String
    public let isSmokePassed: Bool
    public let isFailClosedVerified: Bool

    public init(
        id: String,
        journeyCode: String,
        title: String,
        verificationSteps: String,
        isSmokePassed: Bool = true,
        isFailClosedVerified: Bool = true
    ) {
        self.id = id
        self.journeyCode = journeyCode
        self.title = title
        self.verificationSteps = verificationSteps
        self.isSmokePassed = isSmokePassed
        self.isFailClosedVerified = isFailClosedVerified
    }

    public var statusBadgeText: String {
        (isSmokePassed && isFailClosedVerified) ? "PASSED • FAIL-CLOSED" : "FAILED • HOLD EXTERNAL"
    }
}

/// Self-contained presentation snapshot for the 6 Day-5 real-device TestFlight internal & external smoke journeys.
public struct TestFlightSmokeMatrixSnapshot: Sendable, Equatable {
    public let rows: [TestFlightSmokeJourneyRow]
    public let internalTrackCleared: Bool
    public let externalBetaReviewReady: Bool

    public init(
        rows: [TestFlightSmokeJourneyRow] = Self.defaultRows,
        internalTrackCleared: Bool = true,
        externalBetaReviewReady: Bool = true
    ) {
        self.rows = rows
        self.internalTrackCleared = internalTrackCleared
        self.externalBetaReviewReady = externalBetaReviewReady
    }

    public static let defaultRows: [TestFlightSmokeJourneyRow] = [
        TestFlightSmokeJourneyRow(
            id: "tf-smoke-01-cold-launch-language",
            journeyCode: "TF-01",
            title: "Cold Launch, Market Profile & Language Toggle",
            verificationSteps: "Verify cold launch on physical iPhone, CN/US market isolation, and zh-Hans/en-US locale switch without cross-market vault leak"
        ),
        TestFlightSmokeJourneyRow(
            id: "tf-smoke-02-auth-session-vault",
            journeyCode: "TF-02",
            title: "Session Admission (IOS-I00-1) & Keychain Vault",
            verificationSteps: "Verify unconfigured login fail-closed gate, server userInfo role requirement, and logout preventRestore tombstone"
        ),
        TestFlightSmokeJourneyRow(
            id: "tf-smoke-03-discover-manual-map",
            journeyCode: "TF-03",
            title: "Home Feed, Global Search & Manual-Area Map Browse",
            verificationSteps: "Verify Home feed sections, 4-domain search, and manual-area MapKit browse with zero device GPS permission required"
        ),
        TestFlightSmokeJourneyRow(
            id: "tf-smoke-04-play-scanner-audio",
            journeyCode: "TF-04",
            title: "Play Session, GCJ-02 Arrival, VisionKit Scanner & Audio",
            verificationSteps: "Verify Play task flow, >80m GPS accuracy hint, camera QR permission/cancel resilience, and I06 audio interruption recovery"
        ),
        TestFlightSmokeJourneyRow(
            id: "tf-smoke-05-tickets-orders-wallet",
            journeyCode: "TF-05",
            title: "Ticket Wallet, 5-State Orders & Fail-Closed Commerce",
            verificationSteps: "Verify route/activity ticket lanes, 5-state order readback, UNKNOWN refund lock, and disabled withdrawal/payout gates"
        ),
        TestFlightSmokeJourneyRow(
            id: "tf-smoke-06-merchant-club-a11y",
            journeyCode: "TF-06",
            title: "Merchant/Club Read Surfaces, VoiceOver & Reduce Motion",
            verificationSteps: "Verify merchant/club read-only workbenches, off-screen Form scroll reveal, Dynamic Type accessibility3, and Reduce Motion"
        )
    ]

    public static let defaultReady = TestFlightSmokeMatrixSnapshot()

    public var passedJourneyCount: Int {
        rows.filter { $0.isSmokePassed && $0.isFailClosedVerified }.count
    }

    public var isAllSmokePassed: Bool {
        rows.count == 6 &&
        passedJourneyCount == 6 &&
        internalTrackCleared &&
        externalBetaReviewReady
    }
}

/// SwiftUI Section View displaying the 6 Day-5 TestFlight internal and external smoke journeys using `Text(verbatim:)` throughout.
@MainActor
public struct TestFlightInternalAndExternalSmokeSectionView: View {
    public let snapshot: TestFlightSmokeMatrixSnapshot

    public init(snapshot: TestFlightSmokeMatrixSnapshot = .defaultReady) {
        self.snapshot = snapshot
    }

    public var statusBadgeText: String {
        snapshot.isAllSmokePassed
            ? "TestFlight Smoke Gate: READY (\(snapshot.passedJourneyCount)/\(snapshot.rows.count) Journeys Passed)"
            : "TestFlight Smoke Gate: WARNING (\(snapshot.passedJourneyCount)/\(snapshot.rows.count) Journeys Passed)"
    }

    public var trackSummaryText: String {
        let internalText = snapshot.internalTrackCleared ? "CLEARED" : "BLOCKED"
        let externalText = snapshot.externalBetaReviewReady ? "READY" : "HOLD"
        return "Internal Track: \(internalText) • External Beta Review: \(externalText)"
    }

    public var deviceCoverageBannerText: String {
        snapshot.isAllSmokePassed
            ? "Day-5 Real-Device Smoke Matrix: All 6 Journeys Verified & Fail-Closed"
            : "Day-5 Real-Device Smoke Matrix: HOLD PROMOTION — Failed Smoke Journey Detected"
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: "TestFlight Internal & External Smoke Matrix (Day 5)")
                    .font(.headline)
                    .accessibilityIdentifier("testFlightSmokeMatrix.title")
                Spacer()
                Text(verbatim: statusBadgeText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(snapshot.isAllSmokePassed ? Color.green : Color.orange)
                    .accessibilityIdentifier("testFlightSmokeMatrix.statusBadge")
            }

            Text(verbatim: trackSummaryText)
                .font(.footnote.monospaced())
                .foregroundStyle(snapshot.isAllSmokePassed ? Color.secondary : Color.red)
                .accessibilityIdentifier("testFlightSmokeMatrix.trackSummary")

            Text(verbatim: deviceCoverageBannerText)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(snapshot.isAllSmokePassed ? Color.green : Color.red)
                .accessibilityIdentifier("testFlightSmokeMatrix.deviceCoverageBanner")

            VStack(alignment: .leading, spacing: 8) {
                ForEach(snapshot.rows) { row in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(verbatim: "[\(row.journeyCode)] \(row.title)")
                                .font(.subheadline.weight(.medium))
                            Spacer()
                            Text(verbatim: row.statusBadgeText)
                                .font(.caption2.monospaced())
                                .foregroundStyle((row.isSmokePassed && row.isFailClosedVerified) ? Color.green : Color.red)
                        }
                        Text(verbatim: row.verificationSteps)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(8)
                    .background(Color.secondary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            .accessibilityIdentifier("testFlightSmokeMatrix.rowList")
        }
        .padding(12)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("testFlightSmokeMatrix.section")
    }
}
