import SwiftUI

/// Mini-program reviews header: score, five stars and "{total} 条已核销评价 · 商家不能改用户原评",
/// followed by the four manage-mode metric captions. Server summary fields remain below.
struct MerchantReviewSummaryHeader: View {
    let presentation: MerchantReviewSummaryPresentation
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("merchant.reviewSummary.title").font(.headline)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(presentation.averageText ?? "—").font(.largeTitle.weight(.semibold)).monospacedDigit()
                    .accessibilityIdentifier("merchant.reviewSummary.average")
                HStack(spacing: 2) {
                    ForEach(1...5, id: \.self) { star in
                        Image(systemName: star <= presentation.filledStars ? "star.fill" : "star")
                            .foregroundStyle(star <= presentation.filledStars ? Color.orange : Color.secondary)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("merchant.reviewSummary.stars \(presentation.filledStars)"))
            }
            Text("merchant.reviewSummary.total \(presentation.total)")
                .font(.footnote).foregroundStyle(.secondary)
                .accessibilityIdentifier("merchant.reviewSummary.total")
        }
        .padding(.vertical, 4)
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 12) {
            metric(Text(presentation.pendingReplyCount.map { String($0) } ?? "—"), "merchant.reviewSummary.pending", "merchant.reviewSummary.pendingHint")
            metric(Text(presentation.monthNewCount.map { String($0) } ?? "—"), "merchant.reviewSummary.month", "merchant.reviewSummary.monthHint")
            metric(Text(presentation.replyRatePct.map { "\($0)%" } ?? "—"), "merchant.reviewSummary.rate", "merchant.reviewSummary.rateHint")
            metric(Text(presentation.averageText ?? "—"), "merchant.reviewSummary.average30", "merchant.reviewSummary.average30Hint")
        }
        .accessibilityIdentifier("merchant.reviewSummary.metrics")
    }
    private func metric(_ value: Text, _ title: LocalizedStringKey, _ hint: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            value.font(.title3.weight(.semibold)).monospacedDigit()
            Text(title).font(.subheadline)
            Text(hint).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
