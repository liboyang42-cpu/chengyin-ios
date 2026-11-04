import SwiftUI

/// Signed-in order support for one order opened from the existing list.
/// The page calls SupportLookupEntry. It does not own an audit store.
struct ProfileOrderSupportLookup {
    var entry: SupportLookupEntry
    var currentProjection: SupportCurrentProjection?
}

@MainActor
struct ProfileOrdersView: View {
    let reader: any ProfileReading
    var lifecycleCoordinator: OrderLifecycleCoordinator? = nil
    var mediaScope: UUID = UUID()
    var makeExternalMaps: (@MainActor () -> PlatformExternalMaps)? = nil
    var ticketReader: (any TicketWalletReading)? = nil
    /// Source 去发现城市路线 CTA. Nil (the default) renders no CTA and never navigates.
    var discoverRoutes: (@MainActor () -> Void)? = nil
    /// Inert unless the root TabView installed it; mirrors the source switchTab to the home page.
    @Environment(\.rootTabSwitch) private var rootTabSwitch
    var orderSupport: ProfileOrderSupportLookup? = nil
    @State private var filterSelection = ProfileOrderFilterSelection()
    @State private var orderEntry: SupportLookupEntry?
    @State private var lookedUpOrderID: Int64?
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
                            .buttonStyle(.questifyPrimary).frame(minHeight: 44)
                            .accessibilityIdentifier("profile.orders.discover")
                    } else if rootTabSwitch.isAvailable {
                        Button("profile.orderParity.discover") { rootTabSwitch(.home) }
                            .buttonStyle(.questifyPrimary).frame(minHeight: 44)
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
                                NavigationLink { ProfileOrderDetailView(id: order.id, reader: reader, lifecycleCoordinator: lifecycleCoordinator, mediaScope: mediaScope, makeExternalMaps: makeExternalMaps, ticketReader: ticketReader, orderSupport: orderSupport, lookedUpOrderID: lookedUpOrderID, onOpenedOrder: { [owner = filterOwner] in lookupOpenedOrder($0, expectedOwner: owner) }) } label: {
                                    ProfileOrderRow(order: order, historyState: order.historyState(now: clock.date))
                                }.accessibilityIdentifier("profile.order.\(order.id)")
                            }
                        } footer: { Text("profile.readOnly") }
                    }
                }
            }
        }
        .appNavigationTitle("profile.orders.title")
        .onAppear { appearOrderSupport() }
        .onChange(of: filterOwner) { _, _ in
            filterSelection.retire(); orderEntry = nil; lookedUpOrderID = nil
        }
    }
    /// Appearance records the entry only. It does not look up and does not send.
    private func appearOrderSupport() {
        guard orderEntry == nil, var entry = orderSupport?.entry else { return }
        entry.appear()
        orderEntry = entry
    }
    /// The request's first ORDER id must equal the order the user opened.
    /// A different id is original-missing and is not shown as this order.
    private func lookupOpenedOrder(_ openedID: Int, expectedOwner: ProfileOrderFilterOwner) {
        guard expectedOwner == filterOwner, reader.identity != nil, reader.isConfigured else { return }
        appearOrderSupport()
        guard openedID > 0, var entry = orderEntry else {
            lookedUpOrderID = nil
            return
        }
        let requested = Int64(openedID)
        guard requested > 0 else {
            lookedUpOrderID = nil
            return
        }
        do {
            let composition = try entry.lookupByOrderId(
                requested,
                currentProjection: orderSupport?.currentProjection,
                withdrawal: nil,
                orderRead: .detail(openedID))
            guard expectedOwner == filterOwner else { return }
            orderEntry = entry
            guard let composition, composition.located.orderId == requested,
                  Self.firstOrderID(composition.located.originalEvents) == requested,
                  OrderPageReadback.openedID(requested: requested, events: composition.located.originalEvents) == requested else {
                lookedUpOrderID = nil
                return
            }
            lookedUpOrderID = requested
        } catch {
            guard expectedOwner == filterOwner else { return }
            orderEntry = entry
            lookedUpOrderID = nil
        }
    }
    private static func firstOrderID(_ events: [OriginalAuditEvent]) -> Int64? {
        for event in events {
            guard event.targetType == "ORDER" else { continue }
            return event.targetId
        }
        return nil
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
    /// Existing locator only. Nil stays quiet and does not invent an order id.
    var orderLocator: SupportEventLocator? = nil
    var orderSupport: ProfileOrderSupportLookup? = nil
    var lookedUpOrderID: Int64? = nil
    var onOpenedOrder: ((Int) -> Void)? = nil
    @State private var ticketTarget: ProfileOrderTicketTarget?
    @State private var ticketEntryVisible = false
    @State private var ticketPresentationID = UUID()
    @State private var readBackForID: Int?
    @State private var openedOrderID: Int64?
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
                    ProfileOrderTicketScheduleRows(order: order)
                    ProfileOptionalRow(key: "profile.orders.location", value: order.addressName)
                    if let makeExternalMaps {
                        PlatformExternalMapHost(destination: .init(name: order.meetingPoint ?? "", address: order.meetingPoint, latitude: order.gatherLatitude, longitude: order.gatherLongitude), scope: mediaScope, makeModel: makeExternalMaps)
                    } else {
                        meetingPointEntry
                    }
                }
                Section("profile.orders.records") {
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
                ProfileOrderSourceDetailSections(order: order)
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
                // Source 退款与客服 (报名与客服 when free): 联系客服 opens the read-only support page.
                Section(LocalizedStringKey(order.isSourceFreeOrder ? "profile.orderP2.supportSection.free" : "profile.orderP2.supportSection")) {
                    NavigationLink { ParticipationSupportView() } label: {
                        Label("profile.orderP2.contactSupport", systemImage: "message")
                    }.accessibilityIdentifier("profile.order.detail.support")
                }
                if orderSupport != nil, order.id == id {
                    Section {
                        LabeledContent("profile.orders.number") {
                            if let lookedUpOrderID, lookedUpOrderID == Int64(id) {
                                Text(verbatim: String(lookedUpOrderID))
                            } else { Text("profile.orders.unknown") }
                        }.accessibilityIdentifier("profile.orders.supportLookup")
                    }
                }
                Section { Text("profile.readOnly").foregroundStyle(.secondary) }
            }
            }
        }
        .appNavigationTitle("profile.orders.detail")
        .navigationBarTitleDisplayMode(.inline)
        .background {
            if orderLocator != nil {
                Color.clear.frame(width: 0, height: 0)
                    .accessibilityIdentifier(openedOrderID == Int64(id) ? "profile.order.readback.opened.\(id)" : "profile.order.readback.closed")
            }
        }
        .task(id: id) {
            readBackHeldOrder()
            if orderLocator == nil { onOpenedOrder?(id) }
        }
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
    /// One locateByOrderId for the id this page already holds. The returned first
    /// ORDER id must equal that id. A different id is not opened.
    private func readBackHeldOrder() {
        guard readBackForID != id else { return }
        readBackForID = id
        openedOrderID = nil
        guard let locator = orderLocator else { return }
        let requested: Int64? = id > 0 ? Int64(id) : nil
        do {
            let located = try locator.locateByOrderId(requested, currentProjection: nil)
            guard let requested, let located, located.orderId == requested else { return }
            openedOrderID = OrderPageReadback.openedID(requested: requested, events: located.originalEvents)
        } catch {
            openedOrderID = nil
        }
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
    @Environment(\.locale) private var locale
    var body: some View {
        if let amount {
            RevolutAmountView(figure: OwnedOrderMoneyText.string(amount), label: appLocalized("activity.currencyUnconfirmed", locale: locale))
        } else { Text("activity.priceUnknown").foregroundStyle(.secondary) }
    }
}
