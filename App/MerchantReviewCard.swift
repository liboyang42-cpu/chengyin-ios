import SwiftUI

/// Local, display-only status strip for a merchant review row. Actions stay in the
/// existing `rowActions` (reply editor → review → cancel keeps draft / readback).
struct MerchantReviewCard: View {
    let presentation: MerchantReviewCardPresentation
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if let rating = presentation.rating {
                    Text(verbatim: "★ \(rating)/5").font(.subheadline.bold())
                }
                if presentation.verifiedRedemption {
                    Label {
                        Text("merchant.review.verifiedRedemption", tableName: "MerchantReviewAndCustomerDetail")
                    } icon: {
                        Image(systemName: "checkmark.seal")
                    }
                    .font(.footnote)
                }
                if presentation.photoCount > 0 {
                    Label {
                        Text(
                            "merchant.review.photoCount \(presentation.photoCount)",
                            tableName: "MerchantReviewAndCustomerDetail"
                        )
                    } icon: {
                        Image(systemName: "photo")
                    }
                    .font(.footnote)
                }
            }
            HStack(spacing: 8) {
                Text(
                    LocalizedStringKey(presentation.visibilityTitleKey),
                    tableName: "MerchantReviewAndCustomerDetail"
                )
                .font(.footnote).padding(.horizontal, 8).padding(.vertical, 2)
                .background(.quaternary, in: Capsule())
                .accessibilityIdentifier("merchant.business.review.visibility")
                Text(
                    LocalizedStringKey(presentation.replyTitleKey),
                    tableName: "MerchantReviewAndCustomerDetail"
                )
                .font(.footnote).foregroundStyle(.secondary)
                .accessibilityIdentifier("merchant.business.review.replyState")
            }
        }.accessibilityElement(children: .combine)
    }
}
