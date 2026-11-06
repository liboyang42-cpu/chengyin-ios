import Foundation

public enum QRHandshakePayloadKind: String, Sendable, Equatable, CaseIterable {
    case teamMeetingHandshake
    case merchantStoreStampScan
    case clubCheckInCode
    case passportFriendCardQR
}

public struct QRHandshakeSecurityCheck: Sendable, Equatable, Identifiable {
    public let id: String
    public let payloadKind: QRHandshakePayloadKind
    public let maxTokenTTLSeconds: Int
    public let requiresSingleUseNonce: Bool
    public let validatesHostAllowlistBeforeRoute: Bool

    public var isCompliant: Bool {
        (30...300).contains(maxTokenTTLSeconds) &&
            requiresSingleUseNonce &&
            validatesHostAllowlistBeforeRoute
    }

    public init(
        id: String,
        payloadKind: QRHandshakePayloadKind,
        maxTokenTTLSeconds: Int,
        requiresSingleUseNonce: Bool,
        validatesHostAllowlistBeforeRoute: Bool
    ) {
        self.id = id
        self.payloadKind = payloadKind
        self.maxTokenTTLSeconds = maxTokenTTLSeconds
        self.requiresSingleUseNonce = requiresSingleUseNonce
        self.validatesHostAllowlistBeforeRoute = validatesHostAllowlistBeforeRoute
    }
}

public struct AppClipAndQRCodeHandshakeParityAudit: Sendable, Equatable {
    public static let canonicalChecks: [QRHandshakeSecurityCheck] = [
        QRHandshakeSecurityCheck(
            id: "qr-team-meeting-handshake",
            payloadKind: .teamMeetingHandshake,
            maxTokenTTLSeconds: 180,
            requiresSingleUseNonce: true,
            validatesHostAllowlistBeforeRoute: true
        ),
        QRHandshakeSecurityCheck(
            id: "qr-merchant-store-stamp-scan",
            payloadKind: .merchantStoreStampScan,
            maxTokenTTLSeconds: 120,
            requiresSingleUseNonce: true,
            validatesHostAllowlistBeforeRoute: true
        ),
        QRHandshakeSecurityCheck(
            id: "qr-club-check-in-code",
            payloadKind: .clubCheckInCode,
            maxTokenTTLSeconds: 300,
            requiresSingleUseNonce: true,
            validatesHostAllowlistBeforeRoute: true
        ),
        QRHandshakeSecurityCheck(
            id: "qr-passport-friend-card",
            payloadKind: .passportFriendCardQR,
            maxTokenTTLSeconds: 240,
            requiresSingleUseNonce: true,
            validatesHostAllowlistBeforeRoute: true
        )
    ]

    public init() {}

    public static func evaluate(
        checks: [QRHandshakeSecurityCheck] = canonicalChecks
    ) -> (totalPayloads: Int, compliantPayloads: Int, coversAllPayloadKinds: Bool, isQRHandshakeSafe: Bool) {
        let totalPayloads = checks.count
        let compliantPayloads = checks.filter(\.isCompliant).count
        let coveredKinds = Set(checks.map(\.payloadKind))
        let coversAllPayloadKinds = coveredKinds == Set(QRHandshakePayloadKind.allCases)
        let isQRHandshakeSafe = totalPayloads > 0 &&
            compliantPayloads == totalPayloads &&
            coversAllPayloadKinds
        return (
            totalPayloads: totalPayloads,
            compliantPayloads: compliantPayloads,
            coversAllPayloadKinds: coversAllPayloadKinds,
            isQRHandshakeSafe: isQRHandshakeSafe
        )
    }
}
