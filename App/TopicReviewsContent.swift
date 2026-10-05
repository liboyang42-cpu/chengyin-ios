import SwiftUI

/// Reads only the loaded detail snapshot; no extra fetch, author route or write action.
struct TopicReviewsContent: View {
    let reviews: TopicReviews

    var body: some View {
        Group {
            VStack(alignment: .leading, spacing: 12) {
                if !reviews.hasConfirmedNoReviews {
                    LabeledContent("topic.reviews.average") {
                        if let average = reviews.averageRating {
                            (Text(average, format: .number.precision(.fractionLength(0...1))) + Text(verbatim: " / 5"))
                                .accessibilityIdentifier("topic.reviews.average")
                        } else {
                            Text("topic.reviews.ratingUnknown")
                                .accessibilityIdentifier("topic.reviews.averageUnknown")
                        }
                    }
                }
                LabeledContent("topic.reviews.total") {
                    if let count = reviews.commentCount {
                        Text(count, format: .number)
                            .accessibilityIdentifier("topic.reviews.count")
                    } else {
                        Text("topic.reviews.countUnknown")
                            .accessibilityIdentifier("topic.reviews.countUnknown")
                    }
                }
                if reviews.preview.isEmpty {
                    if reviews.hasConfirmedNoReviews {
                        Text("topic.reviews.empty")
                            .accessibilityIdentifier("topic.reviews.empty")
                    } else {
                        Text("topic.reviews.previewUnavailable")
                            .accessibilityIdentifier("topic.reviews.previewUnavailable")
                    }
                } else {
                    Text("topic.reviews.previewHint")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .questifyCardSurface()
            .questifyCardListRow()
            ForEach(Array(reviews.preview.enumerated()), id: \.offset) { index, review in
                TopicReviewCard(review: review, index: index)
                    .questifyCardListRow()
            }
        }
    }
}

private struct TopicReviewCard: View {
    let review: TopicReview
    let index: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Group {
                if let name = review.authorName { Text(verbatim: name) }
                else { Text("topic.reviews.authorUnknown") }
            }
            .font(.headline)
            .accessibilityIdentifier("topic.reviews.author.\(index)")
            if let date = review.createTime {
                Text(verbatim: date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            LabeledContent("topic.reviews.rating") {
                if let rating = review.rating { Text(verbatim: "\(rating) / 5") }
                else {
                    Text("topic.reviews.ratingUnknown")
                        .accessibilityIdentifier("topic.reviews.ratingUnknown.\(index)")
                }
            }
            .font(.subheadline)
            .accessibilityIdentifier("topic.reviews.rating.\(index)")
            Group {
                if let contents = review.contents { Text(verbatim: contents) }
                else { Text("topic.reviews.textUnavailable").foregroundStyle(.secondary) }
            }
            .textSelection(.enabled)
            .accessibilityIdentifier("topic.reviews.text.\(index)")
        }
        .fixedSize(horizontal: false, vertical: true)
        .questifyCardSurface()
    }
}
