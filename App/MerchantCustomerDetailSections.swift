import SwiftUI

/// No fetches or caches: this view exists only inside the current CRM snapshot.
/// Existing guarded tag/note actions are supplied by the owning page.
@MainActor struct MerchantCustomerDetailSections<Actions: View>: View {
    let detail: MerchantCustomerDetailPresentation
    let access: MerchantBusinessAccess
    let actions: (MerchantBusinessRecord) -> Actions
    @State private var phoneTimeZone = TimeZone.current

    init(detail: MerchantCustomerDetailPresentation, access: MerchantBusinessAccess,
         @ViewBuilder actions: @escaping (MerchantBusinessRecord) -> Actions) {
        self.detail = detail; self.access = access; self.actions = actions
    }
    var canRead: Bool { access.allows("merchant:crm:read") }
    var paidAmount: String? {
        guard canRead, access.allows("merchant:crm:sensitive:read"),
              let amount = try? MerchantBusinessMoney(detail.customer.fields["paidAmount"]), amount.raw != nil else { return nil }
        return amount.display
    }

    var body: some View {
        Group {
            if canRead {
                Section("merchant.customerDetail.identity") {
                    Text(verbatim: detail.customer.title).font(.title3.bold())
                        .fixedSize(horizontal: false, vertical: true)
                    LabeledContent("merchant.customerDetail.lastInteraction") { timestamp(detail.lastInteractionAt) }
                    LabeledContent("merchant.business.field.paidAmount") {
                        if let paidAmount { Text(verbatim: paidAmount).monospacedDigit() }
                        else { Text("merchant.business.sensitiveUnavailable").foregroundStyle(.secondary) }
                    }.accessibilityIdentifier("merchant.customerDetail.paidAmount")
                    ForEach(["arrivedCount", "pendingCount", "refundedCount"], id: \.self) { key in
                        if let value = detail.customer.fields[key] { MerchantBusinessField(key: key, value: value) }
                    }
                }
                Section("merchant.customerDetail.participation") {
                    Text("merchant.customerDetail.recentScope").font(.footnote).foregroundStyle(.secondary)
                    if detail.participation.isEmpty {
                        Text("merchant.customerDetail.participationEmpty").foregroundStyle(.secondary)
                            .accessibilityIdentifier("merchant.customerDetail.participationEmpty")
                    }
                    ForEach(detail.participation) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            if let title = group.title { Text(verbatim: title).font(.headline) }
                            else { Text("merchant.customerDetail.untitledActivity").font(.headline) }
                            if let latest = group.latest {
                                Text(LocalizedStringKey(latest.kind.titleKey))
                                LabeledContent("merchant.customerDetail.recordTime") { timestamp(latest.occurredAt) }
                                if latest.kind == .refunded {
                                    Text("merchant.customerDetail.refundTimeBoundary").font(.footnote).foregroundStyle(.secondary)
                                }
                            } else {
                                Text("merchant.customerDetail.orderUncertain").foregroundStyle(.secondary)
                            }
                            if group.events.count > 1 || group.latest == nil {
                                DisclosureGroup("merchant.customerDetail.sourceEvents") {
                                    ForEach(group.events) { event in eventFacts(event) }
                                }.frame(minHeight: 44)
                            }
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("merchant.customerDetail.participation." + group.id)
                    }
                }
                Section("merchant.customerDetail.tagsAndNotes") {
                    ForEach(detail.systemTags) { tag in
                        Text(verbatim: tag.label).accessibilityIdentifier("merchant.customerDetail.systemTag." + tag.id)
                    }
                    ForEach(detail.merchantTags) { tag in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(verbatim: tag.title)
                            actions(tag)
                        }.accessibilityIdentifier("merchant.business.row.tag." + tag.id)
                    }
                    if let note = detail.latestNote {
                        LabeledContent("merchant.customerDetail.latestNote") {
                            Text(verbatim: note.description ?? "").fixedSize(horizontal: false, vertical: true)
                        }.accessibilityIdentifier("merchant.customerDetail.latestNote")
                    } else if detail.hasNotes {
                        Text("merchant.customerDetail.latestNoteUnknown").foregroundStyle(.secondary)
                    } else if detail.systemTags.isEmpty && detail.merchantTags.isEmpty {
                        Text("merchant.customerDetail.tagsAndNotesEmpty").foregroundStyle(.secondary)
                    }
                }
                Section("merchant.customerDetail.history") {
                    if detail.history.isEmpty {
                        Text("merchant.customerDetail.historyEmpty").foregroundStyle(.secondary)
                    }
                    ForEach(detail.history) { event in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(verbatim: event.record.title).font(.headline)
                            eventFacts(event)
                            actions(event.record)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("merchant.business.row.timeline." + event.record.id)
                    }
                }
            } else { Text("merchant.business.denied") }
        }
        .onAppear { phoneTimeZone = .current }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in phoneTimeZone = .current }
    }
    @ViewBuilder private func timestamp(_ date: Date?) -> some View {
        if let date {
            Text(verbatim: MerchantCustomerDetailTime.display(date, phoneTimeZone: phoneTimeZone))
                .font(.subheadline).monospacedDigit()
        } else { Text("merchant.customerDetail.timeUnknown").font(.subheadline).foregroundStyle(.secondary) }
    }
    private func eventFacts(_ event: MerchantCustomerDetailPresentation.Event) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(LocalizedStringKey(event.kind.titleKey))
            if let description = event.description { Text(verbatim: description) }
            LabeledContent("merchant.customerDetail.recordTime") { timestamp(event.occurredAt) }
            if event.kind == .refunded {
                Text("merchant.customerDetail.refundTimeBoundary").font(.footnote).foregroundStyle(.secondary)
            }
            if let corrects = event.record.fields["correctsNoteId"]?.integer, corrects > 0 {
                LabeledContent("merchant.business.field.correctsNoteId", value: "#\(corrects)")
            }
        }.accessibilityElement(children: .combine)
    }
}
