import SwiftUI

struct MerchantLedgerNetSummary: View {
    let presentation: MerchantLedgerNetPresentation
    var body: some View {
        LabeledContent {
            if let amount = presentation.amount { Text(verbatim: amount).monospacedDigit() }
            else { Text("merchant.business.amountPending").foregroundStyle(.secondary) }
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text("merchant.business.field.personalArrivedThisMonthNet")
                Text(LocalizedStringKey(presentation.titleKey)).font(.caption).foregroundStyle(.secondary)
            }
        }.font(.subheadline)
    }
}

struct MerchantLedgerRefundPreviewSections<Row: View, More: View>: View {
    let preview: MerchantLedgerRefundPreview
    let row: (MerchantBusinessRecord) -> Row
    let more: (MerchantAftercareBucket) -> More
    var body: some View {
        Section("merchant.refundPreview.title") {
            Text("merchant.refundPreview.boundary").font(.footnote).foregroundStyle(.secondary)
            if !preview.included { Text("merchant.refundPreview.notIncluded") }
            if preview.loading { ProgressView("merchant.loading") }
        }
        ForEach(preview.pages) { page in
            Section(LocalizedStringKey("merchant.business.bucket." + page.bucket.rawValue)) {
                if page.failed { Text("merchant.refundPreview.failed").foregroundStyle(.secondary) }
                else {
                    if page.rows.isEmpty { Text("merchant.refundPreview.empty") }
                    ForEach(page.rows, id: \.id) { value in
                        row(value).id(page.rowIdentity(value))
                    }
                    if page.hasMore { Text("merchant.refundPreview.moreAvailable").font(.footnote) }
                }
                more(page.bucket)
            }
        }
    }
}
