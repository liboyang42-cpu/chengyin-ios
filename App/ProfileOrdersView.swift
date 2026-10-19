import SwiftUI

@MainActor
struct ProfileOrdersView: View {
    let reader: any ProfileReading
    var lifecycleCoordinator: OrderLifecycleCoordinator? = nil
    var mediaScope: UUID = UUID()
    var makeExternalMaps: (@MainActor () -> PlatformExternalMaps)? = nil
    var ticketReader: (any TicketWalletReading)? = nil
    /// Source 去发现城市路线 CTA. Nil (the default) renders no CTA and never navigates.
    var discoverRoutes: (@MainActor () -> Void)? = nil
    @State private var filterSelection = ProfileOrderFilterSelection()
    private var filterOwner: ProfileOrderFilterOwner {
        .init(readerID: ObjectIdentifier(reader), identity: reader.identity, isConfigured: reader.isConfigured)
    }
    var body: some View {
        ProfileReadScreen(reader: reader, accessibilityPrefix: "profile.orders", issueCopy: .orders, load: { try await reader.profileOrders() }) { orders in
            if orders.isEmpty {
                VStack(spacing: 12) {
                    ProfileEmptyState(title: "profile.orders.sourceEmpty", hint: "profile.orders.sourceEmptyHint", symbol: "ticket", identifier: "profile.orders.empty")
                    if let discoverRoutes {
                        Button("profile.orderParity.discover") { discoverRoutes() }
                            .buttonStyle(.borderedProminent).frame(minHeight: 44)
                            .accessibilityIdentifier("profile.orders.discover")
                    }
                }
            } else {
                // Local time may move an already-loaded order between categories.
                // No timer-triggered read or financial action is performed here.
                TimelineView(.periodic(from: .now, by: 60)) { clock in
                    let owner = filterOwner
                    let filter = filterSelection.value(for: owner)
                    let visible = filter.orders(in: orders, now: clock.date)
                    List {
                        ProfileOrderFilterSection(selection: Binding(
                            get: { filterSelection.value(for: filterOwner) },
                            set: { filterSelection.choose($0, rendered: owner, current: filterOwner) }),
                            isEmpty: visible.isEmpty)
                        Section {
                            ForEach(visible) { order in
                                NavigationLink { ProfileOrderDetailView(id: order.id, reader: reader, lifecycleCoordinator: lifecycleCoordinator, mediaScope: mediaScope, makeExternalMaps: makeExternalMaps, ticketReader: ticketReader) } label: {
                                    ProfileOrderRow(order: order, historyState: order.historyState(now: clock.date))
                                }.accessibilityIdentifier("profile.order.\(order.id)")
                            }
                        } footer: { Text("profile.readOnly") }
                    }
                }
            }
        }
        .appNavigationTitle("profile.orders.title")
        .onChange(of: filterOwner) { _, _ in filterSelection.retire() }
    }
}

private struct ProfileOrderRow: View {
    let order: ProfileOrder
    let historyState: OrderLifecycleState
    var body: some View {
        // Source row order: 订单号 + state → mode tag → name → time → place → 实付款.
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                if let number = order.registrationNo, !number.isEmpty {
                    Text("profile.orders.number \(number)").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Text(LocalizedStringKey("orderLifecycle.state." + historyState.rawValue)).font(.subheadline)
            }
            switch order.sourceMode {
            case .cityOrienteering?:
                (Text("profile.orders.mode.city").bold() + Text(verbatim: " · ") + Text("profile.orders.mode.cityHint")).font(.caption)
            case .freeExplore?:
                (Text("profile.orders.mode.free").bold() + Text(verbatim: " · ") + Text("profile.orders.mode.freeHint")).font(.caption)
            case nil: EmptyView()
            }
            if let title = order.title, !title.isEmpty { Text(verbatim: title).font(.headline) }
            else { Text("profile.orders.untitled").font(.headline) }
            // Source row shows the owner's MM.dd HH:mm range; otherwise keep the literal date.
            if let range = ProfileOrderTimeRangeText.text(start: order.startDate, end: order.endDate) {
                Label { Text(verbatim: range).monospacedDigit() } icon: { Image(systemName: "calendar") }.font(.subheadline)
                    .accessibilityIdentifier("profile.orderRow.timeRange")
            } else if let date = order.participateDate ?? order.startDate, !date.isEmpty {
                Label { Text(verbatim: date) } icon: { Image(systemName: "calendar") }.font(.subheadline)
            }
            if let location = order.addressName?.trimmingCharacters(in: .whitespaces), !location.isEmpty, location.lowercased() != "null" {
                Label { Text(verbatim: location) } icon: { Image(systemName: "mappin.and.ellipse") }.font(.subheadline)
            } else {
                Label { Text("profile.orders.placeUnconfirmed") } icon: { Image(systemName: "mappin.and.ellipse") }.font(.subheadline)
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("profile.orders.paid").font(.subheadline)
                ProfileOrderAmountLabel(amount: order.actualPaidAmount)
            }
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
    var ticketReader: (any TicketWalletReading)? = nil
    @State private var ticketTarget: ProfileOrderTicketTarget?
    @State private var ticketEntryVisible = false
    @State private var ticketPresentationID = UUID()
    var body: some View {
        ProfileReadScreen(reader: reader, accessibilityPrefix: "profile.order.detail", issueCopy: .orderDetail, load: { try await reader.profileOrder(id: id) }) { order in
            ProfileOrderMeetingPointHost(order: order, requestedID: id, reader: reader) { meetingPointEntry in
            List {
                ProfileOrderStateNoticeSection(order: order)
                Section(LocalizedStringKey("profile.orderParity.section.order")) {
                    if let title = order.title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        ProfileOptionalRow(key: "profile.orders.name", value: title)
                            .accessibilityElement(children: .combine)
                            .accessibilityValue(Text(verbatim: title))
                            .accessibilityIdentifier("profile.order.detail.name")
                    }
                    ProfileOptionalRow(key: "profile.orders.number", value: order.registrationNo)
                    ProfileOrderNumberCopySection(order: order, requestedID: id, reader: reader)
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
                    if let makeExternalMaps {
                        PlatformExternalMapHost(destination: .init(name: order.meetingPoint ?? "", address: order.meetingPoint, latitude: order.gatherLatitude, longitude: order.gatherLongitude), scope: mediaScope, makeModel: makeExternalMaps)
                    } else {
                        meetingPointEntry
                    }
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
                    if let key = order.sourcePaymentTypeLabelKey {
                        LabeledContent("profile.orders.paymentType") { Text(LocalizedStringKey(key)) }
                    } else {
                        ProfileOptionalRow(key: "profile.orders.paymentType", value: order.paymentTypeLabel)
                    }
                    ProfileOptionalRow(key: "profile.orders.verifiedTime", value: order.verificationTime)
                    if let code = order.verificationStatus {
                        LabeledContent("profile.orders.verification") {
                            if code == 1 { Text("profile.orders.verified") }
                            else if code == 0 { Text("profile.orders.notVerified") }
                            else { Text("profile.orders.unknown") }
                        }
                    }
                    // Keep status dimensions distinct; never infer settlement/refund from registration.
                    if let code = order.paymentStatus {
                        LabeledContent("profile.orderParity.payment") { ProfileOrderCodeText(label: .payment(code)) }
                    }
                    if let code = order.refundPayoutStatus {
                        LabeledContent("profile.orders.refund") { ProfileRefundStatus(code: code) }
                    }
                }
                Section(LocalizedStringKey(order.paymentSectionTitleKey)) {
                    if let amount = order.wechatPaymentAmount { LabeledContent("profile.orders.cashAmount") { ProfileOrderAmountLabel(amount: amount) } }
                    if let count = order.pointUsed { LabeledContent("profile.orders.pointsUsed", value: String(count)) }
                    if let amount = order.pointDeductAmount { LabeledContent("profile.orders.pointsDeduction") { ProfileOrderAmountLabel(amount: amount) } }
                    if let amount = order.pointPaymentAmount { LabeledContent("profile.orders.pointsMoney") { ProfileOrderAmountLabel(amount: amount) } }
                    if let code = order.pointsReturned { LabeledContent("profile.orders.pointsReturnedCode", value: String(code)) }
                    // The source shows only the payment method label; keep the code only when no label exists.
                    if order.sourcePaymentTypeLabelKey == nil, let code = order.paymentType,
                       order.paymentTypeLabel?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
                        LabeledContent("profile.orders.paymentTypeCode", value: String(code))
                    }
                    if let amount = order.refundAmount { LabeledContent("profile.orders.refundAmount") { ProfileOrderAmountLabel(amount: amount) } }
                    if let code = order.refundApplicationStatus {
                        LabeledContent("profile.orderParity.refundApplication") { ProfileOrderCodeText(label: .refundApplication(code)) }
                    }
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
                if let ticketReader {
                    Section { ticketEntry(order: order, tickets: ticketReader) }
                }
                ExploreCompletionEntry(order: order, requestedID: id, origin: reader)
                Section { Text("profile.readOnly").foregroundStyle(.secondary) }
            }
            }
        }
        .appNavigationTitle("profile.orders.detail")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $ticketTarget) { target in
            if let ticketReader, target.registrationID == id, target.matches(origin: reader, tickets: ticketReader) {
                ProfileOrderTicketDestination(target: target, origin: reader, tickets: ticketReader)
                    .id(target.id)
            } else { ProfileOrderTicketUnavailableView() }
        }
        .onAppear { ticketEntryVisible = true; ticketPresentationID = UUID() }
        // A push must not remove its destination. Retire only activation callbacks here.
        .onDisappear { ticketEntryVisible = false; ticketPresentationID = UUID() }
        .onChange(of: reader.identity) { _, _ in retireTicketEntry() }
        .onChange(of: reader.isConfigured) { _, _ in retireTicketEntry() }
        .onChange(of: ObjectIdentifier(reader)) { _, _ in retireTicketEntry() }
        .onChange(of: ticketReader.map { ObjectIdentifier($0) }) { _, _ in retireTicketEntry() }
        .onChange(of: ticketReader?.scope) { _, _ in retireTicketEntry() }
        .onChange(of: ticketReader?.isAuthenticated) { _, _ in retireTicketEntry() }
        .onChange(of: ticketReader?.isConfigured) { _, _ in retireTicketEntry() }
        .onChange(of: id) { _, _ in retireTicketEntry() }
    }
    @ViewBuilder private func ticketEntry(order: ProfileOrder, tickets: any TicketWalletReading) -> some View {
        let renderedPresentation = ticketPresentationID
        let target = ProfileOrderTicketTarget(order: order, requestedID: id, origin: reader, tickets: tickets)
        Button {
            guard ticketEntryVisible, ticketTarget == nil, renderedPresentation == ticketPresentationID,
                  let target, target.matches(origin: reader, tickets: tickets) else { return }
            ticketTarget = target
        } label: { Label("orderTicketEntry.open", systemImage: "ticket") }
            .frame(minHeight: 44).disabled(target == nil || !ticketEntryVisible)
            .accessibilityIdentifier("orderTicketEntry.open")
        Text(target == nil ? "orderTicketEntry.unavailable" : "orderTicketEntry.freshRead")
            .font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
    private func retireTicketEntry() { ticketTarget = nil; ticketPresentationID = UUID() }
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

/// Source STATE_TITLE card: title, server orderHint and the projected state tag.
private struct ProfileOrderStateNoticeSection: View {
    let order: ProfileOrder
    var body: some View {
        // Evaluated on render like the source detail; the card never triggers a read.
        if let notice = order.stateNotice() {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(LocalizedStringKey(notice.titleKey)).font(.headline)
                            .accessibilityIdentifier("profile.order.detail.stateTitle")
                        Spacer(minLength: 8)
                        Text(LocalizedStringKey(notice.tagKey)).font(.caption)
                            .padding(.horizontal, 8).padding(.vertical, 2)
                            .background(Capsule().fill(Color.secondary.opacity(0.15)))
                            .accessibilityIdentifier("profile.order.detail.stateTag")
                    }
                    if let hint = notice.hint { Text(verbatim: hint).font(.subheadline).foregroundStyle(.secondary) }
                }.padding(.vertical, 4).accessibilityElement(children: .contain)
            }
        }
    }
}

/// Known source codes are labeled; any other code stays visible as a raw value.
private struct ProfileOrderCodeText: View {
    let label: ProfileOrderCodeLabel
    var body: some View {
        switch label {
        case .key(let key): Text(LocalizedStringKey(key))
        case .raw(let code): Text("profile.orderParity.rawCode \(String(code))")
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
