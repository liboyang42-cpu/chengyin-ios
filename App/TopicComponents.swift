import SwiftUI

struct TopicPrice: View {
    let value: Decimal?
    let label: LocalizedStringKey
    var body: some View {
        LabeledContent(label) {
            if let value { Text(verbatim: NSDecimalNumber(decimal: value).stringValue) }
            else { Text("topic.priceUnknown") }
        }
        // Source supplies an amount but no currency code; never infer a currency symbol.
    }
}
enum TopicScreenIssue {
    case notConfigured, unauthorized, unavailable, failed
    init(_ error: Error) {
        if error as? APIError == .notConfigured { self = .notConfigured }
        else if error as? APIError == .unauthorized { self = .unauthorized }
        else if error as? TopicReadFailure == .unavailable { self = .unavailable }
        else { self = .failed }
    }
    var key: LocalizedStringKey {
        switch self {
        case .notConfigured: return "topic.notConfigured"
        case .unauthorized: return "topic.unauthorized"
        case .unavailable: return "topic.unavailable"
        case .failed: return "topic.failed"
        }
    }
}
struct TopicIssueView: View {
    let issue: TopicScreenIssue
    var retry: (() -> Void)? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(issue.key, systemImage: "exclamationmark.circle")
            if let retry { Button("topic.retry", action: retry) }
        }.accessibilityIdentifier("topic.error")
    }
}

/// Full-route metadata remains separate from the visible per-chapter projection.
struct TopicTotalStops: View {
    let count: Int?
    let identifier: String
    var body: some View {
        LabeledContent("topic.totalStops") {
            if let count { Text(verbatim: String(count)).accessibilityIdentifier(identifier) }
            else { Text("topic.countUnknown").accessibilityIdentifier(identifier) }
        }
    }
}
