import SwiftUI
#if canImport(QuestifyCore)
import QuestifyCore
#elseif canImport(Core)
import Core
#endif

/// Self-contained row describing a single QR/NFC handshake payload security invariant.
public struct QRHandshakeCheckRow: Sendable, Equatable, Identifiable {
    public enum PayloadKind: String, CaseIterable, Sendable, Equatable {
        case teamMeetingHandshake
        case merchantStoreStampScan
        case clubCheckInCode
        case passportFriendCardQR
    }

    public let id: String
    public let payloadKind: PayloadKind
    public let title: String
    public let ttlSeconds: Int
    public let requiresSingleUseReplayNonce: Bool
    public let validatesCryptographicSignature: Bool

    public init(
        id: String? = nil,
        payloadKind: PayloadKind,
        title: String,
        ttlSeconds: Int = 300,
        requiresSingleUseReplayNonce: Bool = true,
        validatesCryptographicSignature: Bool = true
    ) {
        self.id = id ?? payloadKind.rawValue
        self.payloadKind = payloadKind
        self.title = title
        self.ttlSeconds = ttlSeconds
        self.requiresSingleUseReplayNonce = requiresSingleUseReplayNonce
        self.validatesCryptographicSignature = validatesCryptographicSignature
    }

    public var isWithinTTLWindow: Bool {
        ttlSeconds > 0 && ttlSeconds <= 300
    }

    public var isCompliant: Bool {
        isWithinTTLWindow && requiresSingleUseReplayNonce && validatesCryptographicSignature
    }

    public var statusBadgeText: String {
        isCompliant ? "VERIFIED · <=300s · NONCE-GUARDED" : "WARNING · UNVERIFIED / EXPIRED"
    }

    public var detailSummaryText: String {
        "TTL: \(ttlSeconds)s (<= 300s) · Single-Use Nonce: \(requiresSingleUseReplayNonce ? "YES" : "NO") · Signature: \(validatesCryptographicSignature ? "VALID" : "UNVERIFIED")"
    }

    public static let defaultRows: [QRHandshakeCheckRow] = [
        .init(
            id: PayloadKind.teamMeetingHandshake.rawValue,
            payloadKind: .teamMeetingHandshake,
            title: "Team Meeting Handshake (teamMeetingHandshake)",
            ttlSeconds: 180,
            requiresSingleUseReplayNonce: true,
            validatesCryptographicSignature: true
        ),
        .init(
            id: PayloadKind.merchantStoreStampScan.rawValue,
            payloadKind: .merchantStoreStampScan,
            title: "Merchant Store Stamp Scan (merchantStoreStampScan)",
            ttlSeconds: 300,
            requiresSingleUseReplayNonce: true,
            validatesCryptographicSignature: true
        ),
        .init(
            id: PayloadKind.clubCheckInCode.rawValue,
            payloadKind: .clubCheckInCode,
            title: "Club Activity Check-In Code (clubCheckInCode)",
            ttlSeconds: 240,
            requiresSingleUseReplayNonce: true,
            validatesCryptographicSignature: true
        ),
        .init(
            id: PayloadKind.passportFriendCardQR.rawValue,
            payloadKind: .passportFriendCardQR,
            title: "Passport Friend Card QR (passportFriendCardQR)",
            ttlSeconds: 300,
            requiresSingleUseReplayNonce: true,
            validatesCryptographicSignature: true
        ),
    ]
}

/// Self-contained snapshot for App Clip & QR/NFC handshake payload validation.
public struct QRHandshakeParitySnapshot: Sendable, Equatable {
    public let rows: [QRHandshakeCheckRow]
    public let maxAllowedTTLSeconds: Int
    public let enforcesSingleUseReplayNonce: Bool

    public init(
        rows: [QRHandshakeCheckRow] = QRHandshakeCheckRow.defaultRows,
        maxAllowedTTLSeconds: Int = 300,
        enforcesSingleUseReplayNonce: Bool = true
    ) {
        self.rows = rows
        self.maxAllowedTTLSeconds = maxAllowedTTLSeconds
        self.enforcesSingleUseReplayNonce = enforcesSingleUseReplayNonce
    }

    public static let defaultReady = QRHandshakeParitySnapshot()

    public var totalCount: Int {
        rows.count
    }

    public var compliantCount: Int {
        rows.filter(\.isCompliant).count
    }

    public var coversAllPayloadKinds: Bool {
        Set(rows.map(\.payloadKind)) == Set(QRHandshakeCheckRow.PayloadKind.allCases)
    }

    public var isAllCompliant: Bool {
        coversAllPayloadKinds
            && maxAllowedTTLSeconds <= 300
            && enforcesSingleUseReplayNonce
            && compliantCount == totalCount
            && totalCount > 0
    }

    public var overallStatusBadgeText: String {
        isAllCompliant ? "READY · 4/4 QR PAYLOADS GUARDED" : "WARNING · HANDSHAKE DRIFT"
    }

    public var headerSummaryText: String {
        "Payloads: \(compliantCount)/\(totalCount) · Max TTL: <= \(maxAllowedTTLSeconds)s · Replay Nonce: \(enforcesSingleUseReplayNonce ? "SINGLE-USE" : "DISABLED")"
    }
}

/// SwiftUI diagnostics section displaying QR/NFC payload validation, `<= 300s` TTL,
/// and single-use replay-nonce protection across all 4 canonical QR payload kinds.
@MainActor
public struct AppClipAndQRCodeHandshakeSectionView: View {
    public let snapshot: QRHandshakeParitySnapshot

    public init(snapshot: QRHandshakeParitySnapshot = .defaultReady) {
        self.snapshot = snapshot
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(verbatim: "App Clip & QR Handshake Security")
                    .font(.headline)
                    .accessibilityIdentifier("qrHandshakeSecurity.headerTitle")
                Spacer()
                Text(verbatim: snapshot.overallStatusBadgeText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(snapshot.isAllCompliant ? Color.green : Color.orange)
                    .accessibilityIdentifier("qrHandshakeSecurity.statusBadge")
            }

            Text(verbatim: snapshot.headerSummaryText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("qrHandshakeSecurity.summaryLine")

            if !snapshot.isAllCompliant {
                Text(verbatim: "Warning: Expired (> 300s TTL) or unverified QR/NFC payload detected. Fail-closed replay protection active.")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Color.orange)
                    .accessibilityIdentifier("qrHandshakeSecurity.warningBanner")
            }

            ForEach(snapshot.rows) { row in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(verbatim: row.title)
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Text(verbatim: row.statusBadgeText)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(row.isCompliant ? Color.green : Color.orange)
                    }
                    Text(verbatim: row.detailSummaryText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                .accessibilityIdentifier("qrHandshakeSecurity.row.\(row.id)")
            }
        }
        .padding(12)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("qrHandshakeSecurity.section")
    }
}
