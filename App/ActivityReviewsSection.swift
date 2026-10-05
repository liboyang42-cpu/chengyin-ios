import SwiftUI

/// Reads only the loaded detail snapshot; no extra fetch, author route or write action.
struct ActivityReviewsSection: View {
    let reviews: ActivityReviews

    var body: some View {
        Section("activity.reviews.title") {
            VStack(alignment: .leading, spacing: 12) {
                if !reviews.hasConfirmedNoReviews {
                    LabeledContent("activity.reviews.average") {
                        if let average = reviews.averageRating {
                            (Text(average, format: .number.precision(.fractionLength(0...1))) + Text(verbatim: " / 5"))
                                .accessibilityIdentifier("activity.reviews.average")
                        } else {
                            Text("activity.reviews.ratingUnknown")
                                .accessibilityIdentifier("activity.reviews.averageUnknown")
                        }
                    }
                }
                LabeledContent("activity.reviews.total") {
                    if let count = reviews.commentCount {
                        Text(count, format: .number)
                            .accessibilityIdentifier("activity.reviews.count")
                    } else {
                        Text("activity.reviews.countUnknown")
                            .accessibilityIdentifier("activity.reviews.countUnknown")
                    }
                }
                if reviews.preview.isEmpty {
                    if reviews.hasConfirmedNoReviews {
                        Text("activity.reviews.empty")
                            .accessibilityIdentifier("activity.reviews.empty")
                    } else {
                        Text("activity.reviews.previewUnavailable")
                            .accessibilityIdentifier("activity.reviews.previewUnavailable")
                    }
                } else {
                    Text("activity.reviews.previewHint")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .questifyCardSurface()
            .questifyCardListRow()
            ForEach(Array(reviews.preview.enumerated()), id: \.offset) { index, review in
                ActivityReviewCard(review: review, index: index)
                    .questifyCardListRow()
            }
        }
    }
}

private struct ActivityReviewCard: View {
    let review: ActivityReview
    let index: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Group {
                if let name = review.authorName { Text(verbatim: name) }
                else { Text("activity.reviews.authorUnknown") }
            }
            .font(.headline)
            .accessibilityIdentifier("activity.reviews.author.\(index)")
            if let date = review.createTime {
                Text(verbatim: date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            LabeledContent("activity.reviews.rating") {
                if let rating = review.rating { Text(verbatim: "\(rating) / 5") }
                else { Text("activity.reviews.ratingUnknown") }
            }
            .font(.subheadline)
            .accessibilityIdentifier("activity.reviews.rating.\(index)")
            Group {
                if let contents = review.contents { Text(verbatim: contents) }
                else { Text("activity.reviews.textUnavailable").foregroundStyle(.secondary) }
            }
            .textSelection(.enabled)
            .accessibilityIdentifier("activity.reviews.text.\(index)")
        }
        .fixedSize(horizontal: false, vertical: true)
        .questifyCardSurface()
    }
}
