import SwiftUI

@MainActor struct AccountCollectionCouponsView: View {
    let reader: any AccountCollectionReading
    @StateObject private var model = OwnedCouponReadScreenModel()
    @State private var viewPresentation = OwnedCouponReadViewPresentation()
    @Environment(\.scenePhase) private var scenePhase
    @State private var filter = AccountCollectionCouponFilter.all
    @State private var searchText = ""
    @State private var submittedQuery = ""
    private var key: AccountCollectionLoadKey { AccountCollectionLoadKey(reader: reader, query: submittedQuery) }
    private var request: OwnedCouponReadRequest { .list(ownerScope: key.scope, keyword: submittedQuery.isEmpty ? nil : submittedQuery) }
    var body: some View {
        let appearance = viewPresentation
        let presentation = appearance.permit
        let offeredRequest = request
        return List {
            if reader.isOfflineExample { Text("accountCollection.offlineExample").font(.caption) }
            if !reader.isAuthenticated { AccountCollectionIssueView(issue: .login) }
            else if !reader.isConfigured { AccountCollectionIssueView(issue: .notConfigured) }
            else {
                Picker("accountCollection.coupons.filter", selection: $filter) {
                    ForEach(AccountCollectionCouponFilter.allCases) { option in
                        Text(LocalizedStringKey("accountCollection.coupons.filter." + option.rawValue)).tag(option)
                    }
                }.pickerStyle(.menu).accessibilityIdentifier("accountCollection.coupons.filter")
                if model.isLoading || model.loadedRequest != offeredRequest { ProgressView("accountCollection.loading") }
                else if let issue = model.issue(for: offeredRequest) {
                    AccountCollectionIssueView(issue: issue, retry: { model.schedule(request: offeredRequest, reader: reader, presentation: presentation) })
                } else if let coupons = model.rows(for: offeredRequest) {
                    let rows = coupons.filter { filter.includes($0) }
                    if rows.isEmpty {
                        if filter == .all, submittedQuery.isEmpty {
                            ContentUnavailableView("accountCollection.coupons.empty", systemImage: "ticket",
                                                   description: Text("accountCollection.coupons.emptyHint"))
                        } else {
                            ContentUnavailableView("accountCollection.coupons.filteredEmpty", systemImage: "line.3.horizontal.decrease.circle",
                                                   description: Text("accountCollection.coupons.filteredEmptyHint"))
                        }
                    }
                    let selections = model.selections(for: offeredRequest, filter: filter)
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, coupon in
                        let selection = selections[index]
                        NavigationLink {
                            AccountCollectionCouponDetailView(selection: selection, reader: reader).id(selection.id)
                        } label: { AccountCollectionCouponRow(coupon: coupon) }
                        .buttonStyle(QuestifyCardButtonStyle())
                        .accessibilityIdentifier("accountCollection.coupon.\(coupon.id)")
                        .questifyCardListRow()
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .appNavigationTitle("accountCollection.coupons.title")
        .searchable(text: $searchText, prompt: Text("accountCollection.coupons.search"))
        .onSubmit(of: .search) { submittedQuery = searchText }
        .onChange(of: searchText) { _, text in
            if text.isEmpty, !submittedQuery.isEmpty { submittedQuery = "" }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { model.schedule(request: offeredRequest, reader: reader, presentation: presentation) } label: { Label("accountCollection.refresh", systemImage: "arrow.clockwise") }
                    .disabled(model.isLoading || !reader.isAuthenticated || !reader.isConfigured)
                    .accessibilityIdentifier("accountCollection.coupons.refresh")
            }
        }
        .onAppear {
            guard let permit = appearance.begin(model: model, request: offeredRequest, foreground: scenePhase == .active) else { return }
            model.schedule(request: offeredRequest, reader: reader, presentation: permit)
        }
        .onChange(of: key) { _, _ in
            guard let permit = appearance.replace(model: model, request: offeredRequest, foreground: scenePhase == .active) else { return }
            model.schedule(request: offeredRequest, reader: reader, presentation: permit)
        }
        .refreshable { await model.refresh(request: offeredRequest, reader: reader, presentation: presentation) }
        .onChange(of: scenePhase) { _, phase in
            model.setForeground(phase == .active, request: offeredRequest, reader: reader, presentation: presentation)
        }
        .onDisappear {
            appearance.end(model: model)
            if viewPresentation === appearance { viewPresentation = OwnedCouponReadViewPresentation() }
        }
    }
}

struct AccountCollectionCouponRow: View {
    let coupon: AccountCollectionCoupon
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                AccountCollectionCouponBadge(status: coupon.status)
                Spacer(minLength: 0)
                Image(systemName: "ticket").font(.title2).foregroundStyle(QuestifyPalette.accent).accessibilityHidden(true)
            }
            AccountCollectionTitle(value: coupon.name, fallback: "accountCollection.coupon.untitled")
                .font(.title3.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
            if let description = coupon.displayDescription, !description.isEmpty {
                Text(verbatim: description).font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if coupon.status == .invalid {
                Label("accountCollection.coupon.invalidHint", systemImage: "xmark.circle").font(.footnote)
            } else if let day = AccountCollectionCoupon.calendarDay(coupon.endTime) {
                QuestifyMetadataLine(label: "accountCollection.coupon.validUntil", value: day, systemImage: "calendar")
            } else { Text("accountCollection.coupon.validityUnknown").font(.footnote).foregroundStyle(.secondary) }
        }.questifyCardSurface()
    }
}
