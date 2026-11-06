import SwiftUI

/// Pure presentation of verified original-request facts. This layer cannot grant a
/// channel, settle a pending UUID, or turn a historical event into current consent.
struct MarketingConsentOriginalPresentation {
    let locale: Locale
    func text(_ key: String) -> String {
        String(localized: LocalizedStringResource(String.LocalizationValue(stringLiteral: key),
                                                 table: "MarketingConsentOriginalPresentation", locale: locale))
    }
    func outcome(_ value: String) -> String { text(Self.outcomeKey(value)) }
    static func outcomeKey(_ value: String) -> String {
        switch value {
        case "RECORDED": return "marketingOriginal.outcome.recorded"
        case "NOT_OBSERVED": return "marketingOriginal.outcome.notObserved"
        default: return "marketingOriginal.outcome.unknown"
        }
    }
    func event(_ value: String?) -> String { text(Self.eventKey(value)) }
    static func eventKey(_ value: String?) -> String {
        switch value {
        case "OPT_IN": return "marketingOriginal.event.optIn"
        case "OPT_OUT": return "marketingOriginal.event.optOut"
        default: return "marketingOriginal.event.unknown"
        }
    }
    func channel(_ value: String) -> String { text(Self.channelKey(value)) }
    static func channelKey(_ value: String) -> String {
        switch value {
        case "IN_APP": return "marketingOriginal.channel.inApp"
        case "COUPON": return "marketingOriginal.channel.coupon"
        default: return "marketingOriginal.channel.unknown"
        }
    }
}

/// Shared by the original order shortcut and the existing Settings opt-out screen.
/// No navigation, task, lifecycle callback or mutation is introduced by this view.
@MainActor struct MarketingConsentOriginalReceiptView: View {
    let receipt: MerchantMarketingConsentOriginalReceipt
    @Environment(\.locale) private var locale
    private var presentation: MarketingConsentOriginalPresentation { .init(locale: locale) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("marketingOriginal.receipt.title", tableName: "MarketingConsentOriginalPresentation")
                .font(.subheadline).foregroundStyle(.secondary)
            Text(verbatim: presentation.outcome(receipt.outcome)).font(.headline)
            Text(verbatim: presentation.channel(receipt.channel))
            if receipt.recorded {
                Text(verbatim: presentation.event(receipt.eventType))
            } else {
                Text("marketingOriginal.receipt.unconfirmed", tableName: "MarketingConsentOriginalPresentation")
            }
            Text("marketingOriginal.receipt.historyOnly", tableName: "MarketingConsentOriginalPresentation")
                .font(.callout).foregroundStyle(.secondary)
            DisclosureGroup {
                reference("marketingOriginal.reference.request", value: receipt.requestId)
                reference("marketingOriginal.reference.merchant", value: String(receipt.merchantRowId))
                if receipt.recorded, let id = receipt.consentId, id > 0 {
                    reference("marketingOriginal.reference.record", value: String(id))
                }
            } label: {
                Text("marketingOriginal.reference.title", tableName: "MarketingConsentOriginalPresentation")
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .privacySensitive()
        .accessibilityIdentifier("marketing.original.receipt.\(receipt.requestId)")
    }
    private func reference(_ key: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: presentation.text(key)).foregroundStyle(.secondary)
            Text(verbatim: value).textSelection(.enabled)
        }
        .font(.caption)
        .accessibilityElement(children: .combine)
    }
}
