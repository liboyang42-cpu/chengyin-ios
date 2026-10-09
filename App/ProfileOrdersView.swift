import SwiftUI

@MainActor
struct ProfileOrdersView: View {
    let reader: any ProfileReading
    var lifecycleCoordinator: OrderLifecycleCoordinator? = nil
    var mediaScope: UUID = UUID()
    var makeExternalMaps: (@MainActor () -> PlatformExternalMaps)? = nil
    var body: some View {
        ProfileReadScreen(reader: reader, accessibilityPrefix: "profile.orders", load: { try await reader.profileOrders() }) { orders in
            if orders.isEmpty {
                ProfileEmptyState(title: "profile.orders.empty", hint: "profile.orders.emptyHint", symbol: "ticket", identifier: "profile.orders.empty")
            } else {
                List {
                    Section {
                        ForEach(orders) { order in
                            NavigationLink { ProfileOrderDetailView(id: order.id, reader: reader, lifecycleCoordinator: lifecycleCoordinator, mediaScope: mediaScope, makeExternalMaps: makeExternalMaps) } label: {
                                ProfileOrderRow(order: order)
                            }.accessibilityIdentifier("profile.order.\(order.id)")
                        }
                    } footer: { Text("profile.readOnly") }
                }
            }
        }
        .appNavigationTitle("profile.orders.title")
    }
}

private struct ProfileOrderRow: View {
    let order: ProfileOrder
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title = order.title, !title.isEmpty { Text(verbatim: title).font(.headline) }
            else { Text("profile.orders.untitled").font(.headline) }
            ProfileOrderStatus(order: order).font(.subheadline)
            if let date = order.participateDate ?? order.startDate, !date.isEmpty {
                Label { Text(verbatim: date) } icon: { Image(systemName: "calendar") }.font(.subheadline)
            }
            if let location = order.addressName, !location.isEmpty {
                Label { Text(verbatim: location) } icon: { Image(systemName: "mappin.and.ellipse") }.font(.subheadline)
            }
            ProfileOrderAmountLabel(amount: order.payableAmount)
        }.padding(.vertical, 6)
    }
}

@MainActor
struct ProfileOrderDetailView: View {
    let id: Int
    let reader: any ProfileReading
    var lifecycleCoordinator: OrderLifecycleCoordinator? = nil
    var mediaScope: UUID = UUID()
    var makeExternalMaps: (@MainActor () -> PlatformExternalMaps)? = nil
    var body: some View {
        ProfileReadScreen(reader: reader, accessibilityPrefix: "profile.order.detail", load: { try await reader.profileOrder(id: id) }) { order in
            List {
                Section("profile.orders.summary") {
                    ProfileOptionalRow(key: "profile.orders.name", value: order.title)
                    ProfileOptionalRow(key: "profile.orders.number", value: order.registrationNo)
                    LabeledContent("profile.orders.state") { ProfileOrderStatus(order: order) }
                    ProfileOptionalRow(key: "profile.orders.serverHint", value: order.orderHint)
                    LabeledContent("profile.orders.amount") { ProfileOrderAmountLabel(amount: order.payableAmount) }
                    ProfileOptionalRow(key: "profile.orders.ticket", value: order.ticketName)
                    if let count = order.orderNum { LabeledContent("profile.orders.quantity", value: String(count)) }
                    ProfileOptionalRow(key: "profile.orders.organizer", value: order.organizerName)
                }
                Section("profile.orders.schedule") {
                    ProfileOptionalRow(key: "profile.orders.participateDate", value: order.participateDate)
                    ProfileOrderTicketScheduleRows(order: order)
                    ProfileOptionalRow(key: "profile.orders.location", value: order.addressName)
                    PlatformExternalMapHost(destination: .init(name: order.meetingPoint ?? "", address: order.meetingPoint, latitude: order.gatherLatitude, longitude: order.gatherLongitude), scope: mediaScope, makeModel: makeExternalMaps)
                    ProfileOptionalRow(key: "profile.orders.expires", value: order.expiresAt)
                }
                if order.realName?.isEmpty == false || order.phone?.isEmpty == false {
                    Section("profile.orders.contact") {
                        ProfileOptionalRow(key: "profile.participants.name", value: order.realName)
                        ProfileOptionalRow(key: "profile.participants.phone", value: order.phone)
                    }
                }
                Section("profile.orders.records") {
                    ProfileOptionalRow(key: "profile.orders.created", value: order.createTime)
                    ProfileOptionalRow(key: "profile.orders.paymentTime", value: order.paymentTime)
                    ProfileOptionalRow(key: "profile.orders.paymentType", value: order.paymentTypeLabel)
                    ProfileOptionalRow(key: "profile.orders.verifiedTime", value: order.verificationTime)
                    if let code = order.verificationStatus {
                        LabeledContent("profile.orders.verification") {
                            if code == 1 { Text("profile.orders.verified") }
                            else if code == 0 { Text("profile.orders.notVerified") }
                            else { Text("profile.orders.unknown") }
                        }
                    }
                    // Keep status dimensions distinct; never infer settlement/refund from registration.
                    if let code = order.paymentStatus { LabeledContent("profile.orders.paymentCode", value: String(code)) }
                    if let code = order.refundPayoutStatus {
                        LabeledContent("profile.orders.refund") { ProfileRefundStatus(code: code) }
                        LabeledContent("profile.orders.refundCode", value: String(code))
                    }
                }
                Section("profile.orders.moneyFacts") {
                    if let amount = order.wechatPaymentAmount { LabeledContent("profile.orders.cashAmount") { ProfileOrderAmountLabel(amount: amount) } }
                    if let count = order.pointUsed { LabeledContent("profile.orders.pointsUsed", value: String(count)) }
                    if let amount = order.pointDeductAmount { LabeledContent("profile.orders.pointsDeduction") { ProfileOrderAmountLabel(amount: amount) } }
                    if let amount = order.pointPaymentAmount { LabeledContent("profile.orders.pointsMoney") { ProfileOrderAmountLabel(amount: amount) } }
                    if let code = order.pointsReturned { LabeledContent("profile.orders.pointsReturnedCode", value: String(code)) }
                    if let code = order.paymentType { LabeledContent("profile.orders.paymentTypeCode", value: String(code)) }
                    if let amount = order.refundAmount { LabeledContent("profile.orders.refundAmount") { ProfileOrderAmountLabel(amount: amount) } }
                    if let code = order.refundApplicationStatus { LabeledContent("profile.orders.refundApplicationCode", value: String(code)) }
                    ProfileOptionalRow(key: "profile.orders.manualRefund", value: order.manualRefundCaseStatus)
                    ProfileOptionalRow(key: "profile.orders.refundDeadline", value: order.refundDeadlineDisplay)
                    Text("profile.orders.moneyFactsHint").foregroundStyle(.secondary)
                }
                if let lifecycleCoordinator {
                    Section {
                        NavigationLink { OrderLifecycleView(id: id, coordinator: lifecycleCoordinator).id(lifecycleCoordinator.scope) } label: {
                            Label("orderLifecycle.title", systemImage: "list.bullet.rectangle")
                        }.accessibilityIdentifier("profile.order.lifecycle")
                    }
                }
                Section { Text("profile.readOnly").foregroundStyle(.secondary) }
            }
        }
        .appNavigationTitle("profile.orders.detail")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Presentation only; the enclosing ProfileReadScreen owns the existing reader/scope lifetime.
struct ProfileOrderTicketScheduleRows: View {
    let order: ProfileOrder
    var body: some View {
        let schedule = ProfileOrderSchedulePresentation(order)
        if schedule.isTicket {
            Text("profileTicketSchedule.title").font(.subheadline.weight(.semibold))
                .accessibilityIdentifier("profile.order.ticketSchedule")
            ProfileOrderTicketTimeRow(label: "profile.orders.start", value: schedule.start)
            ProfileOrderTicketTimeRow(label: "profile.orders.end", value: schedule.end)
            Text("profileTicketSchedule.phoneTimeZone").font(.caption).foregroundStyle(.secondary)
        } else {
            if schedule.start != .absent || schedule.end != .absent {
                Text("profileTicketSchedule.ownerTimes").font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("profile.order.ownerSchedule")
            }
            if schedule.start != .absent { ProfileOrderTicketTimeRow(label: "profile.orders.start", value: schedule.start) }
            if schedule.end != .absent { ProfileOrderTicketTimeRow(label: "profile.orders.end", value: schedule.end) }
        }
    }
}
struct ProfileOrderSchedulePresentation {
    let isTicket: Bool
    let start: ProfileOrderTicketTime
    let end: ProfileOrderTicketTime
    init(_ order: ProfileOrder) {
        if let schedule = order.ticketSchedule {
            isTicket = true; start = schedule.start; end = schedule.end
        } else {
            func source(_ value: String?) -> ProfileOrderTicketTime {
                guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .absent }
                return .source(value)
            }
            isTicket = false; start = source(order.startDate); end = source(order.endDate)
        }
    }
}
struct ProfileOrderTicketTimeRow: View {
    let label: LocalizedStringKey
    let value: ProfileOrderTicketTime
    @Environment(\.timeZone) private var phoneTimeZone
    var body: some View {
        LabeledContent(label) {
            if let display = value.display(phoneTimeZone: phoneTimeZone) {
                Text(verbatim: display).textSelection(.enabled).monospacedDigit()
            } else if case .source(let raw) = value {
                VStack(alignment: .trailing, spacing: 4) {
                    Text(verbatim: raw).textSelection(.enabled)
                    Text("profileTicketSchedule.unparsed").font(.caption).foregroundStyle(.secondary)
                }.fixedSize(horizontal: false, vertical: true)
            } else { Text("profile.orders.unknown") }
        }
    }
}

private struct ProfileOrderStatus: View {
    let order: ProfileOrder
    private var stateKey: LocalizedStringKey {
        switch order.registrationState {
        case .awaitingPayment: return "profile.orders.awaitingPayment"
        case .registered: return "profile.orders.registered"
        case .cancelled: return "profile.orders.cancelled"
        case .expired: return "profile.orders.expired"
        case .unknown: return "profile.orders.unknown"
        }
    }
    var body: some View {
        if let status = order.statusText, !status.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { Text(verbatim: status) }
        else { Text(stateKey) }
    }
}
private struct ProfileRefundStatus: View {
    let code: Int
    var body: some View {
        switch code {
        case 0: Text("profile.orders.refunding")
        case 1, 4: Text("profile.orders.refunded")
        case 2: Text("profile.orders.refundManualPending")
        case 3: Text("profile.orders.refundManualReview")
        case 5: Text("profile.orders.refundQueued")
        case 6: Text("profile.orders.refundDispatching")
        default: Text("profile.orders.unknown")
        }
    }
}

private struct ProfileOrderAmountLabel: View {
    let amount: Decimal?
    var body: some View {
        if let amount {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: OwnedOrderMoneyText.string(amount)).monospacedDigit()
                Text("activity.currencyUnconfirmed").font(.caption)
            }
        } else { Text("activity.priceUnknown").foregroundStyle(.secondary) }
    }
}
