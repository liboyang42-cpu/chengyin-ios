import Foundation

/// Descriptor for a single in-app customer support, after-sales, safety report, or settlement inquiry channel.
public struct CustomerSupportChannelDescriptor: Sendable, Equatable, Identifiable {
    public let id: String
    public let channelName: String
    public let supportsOfflineDraftPreservation: Bool
    public let redactsDiagnosticsBeforeAttachment: Bool
    public let providesExpectedResponseSLAHint: Bool

    public init(
        id: String,
        channelName: String,
        supportsOfflineDraftPreservation: Bool = true,
        redactsDiagnosticsBeforeAttachment: Bool = true,
        providesExpectedResponseSLAHint: Bool = true
    ) {
        self.id = id
        self.channelName = channelName
        self.supportsOfflineDraftPreservation = supportsOfflineDraftPreservation
        self.redactsDiagnosticsBeforeAttachment = redactsDiagnosticsBeforeAttachment
        self.providesExpectedResponseSLAHint = providesExpectedResponseSLAHint
    }

    public var isCompliant: Bool {
        supportsOfflineDraftPreservation &&
        redactsDiagnosticsBeforeAttachment &&
        providesExpectedResponseSLAHint
    }
}

/// Pure audit contract for in-app customer support, order after-sales, UGC safety follow-up,
/// merchant/club settlement inquiry channels, and redacted diagnostic attachment opt-in.
public struct InAppCustomerSupportAndFeedbackParityAudit: Sendable, Equatable {
    public static let canonicalChannels: [CustomerSupportChannelDescriptor] = [
        CustomerSupportChannelDescriptor(
            id: "profile-general-feedback",
            channelName: "Profile General Feedback & Bug Report",
            supportsOfflineDraftPreservation: true,
            redactsDiagnosticsBeforeAttachment: true,
            providesExpectedResponseSLAHint: true
        ),
        CustomerSupportChannelDescriptor(
            id: "order-after-sales-and-refund-support",
            channelName: "Order After-Sales & Refund Support",
            supportsOfflineDraftPreservation: true,
            redactsDiagnosticsBeforeAttachment: true,
            providesExpectedResponseSLAHint: true
        ),
        CustomerSupportChannelDescriptor(
            id: "ugc-and-safety-report-followup",
            channelName: "UGC Moderation & Safety Report Follow-Up",
            supportsOfflineDraftPreservation: true,
            redactsDiagnosticsBeforeAttachment: true,
            providesExpectedResponseSLAHint: true
        ),
        CustomerSupportChannelDescriptor(
            id: "merchant-and-club-settlement-inquiry",
            channelName: "Merchant & Club Settlement Inquiry",
            supportsOfflineDraftPreservation: true,
            redactsDiagnosticsBeforeAttachment: true,
            providesExpectedResponseSLAHint: true
        )
    ]

    public static func evaluate(
        channels: [CustomerSupportChannelDescriptor] = canonicalChannels
    ) -> (totalChannels: Int, compliantChannels: Int, isSupportParityReady: Bool) {
        let total = channels.count
        let compliant = channels.filter(\.isCompliant).count
        let canonicalIDs = Set(canonicalChannels.map(\.id))
        let providedIDs = Set(channels.map(\.id))
        let ready = total == canonicalChannels.count &&
            compliant == total &&
            providedIDs == canonicalIDs
        return (totalChannels: total, compliantChannels: compliant, isSupportParityReady: ready)
    }
}
