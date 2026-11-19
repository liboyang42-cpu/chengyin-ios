import SwiftUI

@MainActor struct ProfileSelfOrdersAccess {
    let reader: any ProfileReading
    let owner: SocialAccountIdentity
    let ordersOwner: ProfileReadIdentity?
    let ticketReader: (any TicketWalletReading)?
    init(reader: any ProfileReading, owner: SocialAccountIdentity, ticketReader: (any TicketWalletReading)? = nil) {
        self.reader = reader; self.owner = owner; ordersOwner = reader.identity; self.ticketReader = ticketReader
    }
    /// No legacy profileReader fallback and no lease issuance. Default-nil owner read
    /// approval means the public-profile fragment cannot expose a usable preview yet.
    init(session: AppSession) {
        self.init(reader: session.ownedOrderReader, owner: session.socialAccountReader.identity,
                  ticketReader: session.ticketWalletReader)
    }
    func context(memberID: Int, social: any SocialAccountReading, isCurrent: Bool) -> ProfileSelfOrdersContext? {
        .capture(memberID: memberID, social: social, orders: reader, owner: owner,
                 ordersOwner: ordersOwner, isCurrent: isCurrent)
    }
}

@MainActor struct ProfileSelfOrdersEntry: View {
    let memberID: Int
    let social: any SocialAccountReading
    let access: ProfileSelfOrdersAccess
    var isCurrent: @MainActor () -> Bool = { true }
    var body: some View {
        if let context = access.context(memberID: memberID, social: social, isCurrent: isCurrent()) {
            ProfileSelfOrdersSection(context: context, social: social, access: access, isCurrent: isCurrent)
                .id(context)
        }
    }
}
struct ProfileSelfOrderSelection: Identifiable, Hashable {
    let id = UUID()
    let orderID: Int
}

@MainActor struct ProfileSelfOrdersSection: View {
    @State private var reader: ProfileSelfOrdersScopedReader
    @State private var model = ProfileSelfOrdersController()
    @State private var selected: ProfileSelfOrderSelection?
    @Environment(\.scenePhase) private var scenePhase
    private let ticketReader: (any TicketWalletReading)?
    init(context: ProfileSelfOrdersContext, social: any SocialAccountReading,
         access: ProfileSelfOrdersAccess, isCurrent: @escaping @MainActor () -> Bool) {
        _reader = State(initialValue: .init(context: context, social: social, orders: access.reader, isCurrent: isCurrent))
        ticketReader = access.ticketReader
    }
    var body: some View {
        Group {
            if reader.isCurrentContext {
                Section("profile.selfOrders.title") {
                    if model.isLoading || model.loadedScope == nil { ProgressView("profile.loading") }
                    if let issue = model.issue {
                        Text(LocalizedStringKey(issue.titleKey)).accessibilityIdentifier("profile.selfOrders.issue")
                        if model.rows != nil { Text("profile.selfOrders.stale").font(.caption) }
                        if issue == .readFailed {
                            Button("action.retry") { Task { await model.load(reader: reader) } }
                                .disabled(model.isLoading).accessibilityIdentifier("profile.selfOrders.retry")
                        }
                    }
                    if let rows = model.rows {
                        if rows.isEmpty && model.issue == nil && !model.isLoading {
                            Text("profile.selfOrders.empty").accessibilityIdentifier("profile.selfOrders.empty")
                        }
                        ForEach(ProfileSelfOrdersPreview(rows: rows).rows) { order in
                            Button {
                                guard selected == nil, model.canOpen(order, reader: reader) else { return }
                                selected = .init(orderID: order.id)
                            } label: { previewRow(order) }
                                .disabled(model.isLoading || model.issue != nil)
                                .accessibilityIdentifier("profile.selfOrders.order.\(order.id)")
                        }
                    }
                    Button("profile.refresh") { Task { await model.load(reader: reader) } }
                        .disabled(model.isLoading).accessibilityIdentifier("profile.selfOrders.refresh")
                    NavigationLink {
                        ProfileSelfOrdersBrowser(reader: reader, ticketReader: ticketReader)
                    } label: { Label("profile.selfOrders.all", systemImage: "list.bullet.rectangle") }
                        .disabled(model.isLoading || model.issue != nil || model.rows == nil)
                        .accessibilityIdentifier("profile.selfOrders.all")
                    Text("profile.selfOrders.previewNote").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .navigationDestination(item: $selected) { target in
            ProfileSelfOrderDestination(selection: target, reader: reader, ticketReader: ticketReader)
        }
        .task { await model.load(reader: reader) }
        .refreshable { await model.load(reader: reader) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.load(reader: reader) } } else { model.suspend() }
        }
        .onDisappear { model.suspend() }
        .privacySensitive()
    }
    private func previewRow(_ order: ProfileOrder) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title = order.title, !title.isEmpty { Text(verbatim: title) }
            else { Text("profile.orders.untitled") }
            if let created = ProfileSelfOrdersPreview.createdLabel(order.createTime) {
                Text(verbatim: created).font(.caption).foregroundStyle(.secondary)
            }
        }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    }
}
@MainActor struct ProfileSelfOrdersBrowser: View {
    let reader: ProfileSelfOrdersScopedReader
    let ticketReader: (any TicketWalletReading)?
    var body: some View {
        if reader.isCurrentContext { ProfileOrdersView(reader: reader, ticketReader: ticketReader) }
        else { Text("social.changed") }
    }
}
@MainActor struct ProfileSelfOrderDestination: View {
    let selection: ProfileSelfOrderSelection
    let reader: ProfileSelfOrdersScopedReader
    let ticketReader: (any TicketWalletReading)?
    var body: some View {
        if reader.isCurrentContext {
            ProfileOrderDetailView(id: selection.orderID, reader: reader, ticketReader: ticketReader)
        } else { Text("social.changed") }
    }
}
