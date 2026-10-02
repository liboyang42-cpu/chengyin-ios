import SwiftUI

@MainActor struct AccountCollectionCouponsView: View {
    let reader: any AccountCollectionReading
    @StateObject private var model = AccountCollectionScreenModel<[AccountCollectionCoupon]>()
    @State private var filter = AccountCollectionCouponFilter.all
    @State private var searchText = ""
    @State private var submittedQuery = ""
    private var key: AccountCollectionLoadKey { AccountCollectionLoadKey(reader: reader, query: submittedQuery) }
    var body: some View {
        List {
            if reader.isOfflineExample { Text("accountCollection.offlineExample").font(.caption) }
            if !reader.isAuthenticated { AccountCollectionIssueView(issue: .login) }
            else if !reader.isConfigured { AccountCollectionIssueView(issue: .notConfigured) }
            else {
                Picker("accountCollection.coupons.filter", selection: $filter) {
                    ForEach(AccountCollectionCouponFilter.allCases) { option in
                        Text(LocalizedStringKey("accountCollection.coupons.filter." + option.rawValue)).tag(option)
                    }
                }.pickerStyle(.menu).accessibilityIdentifier("accountCollection.coupons.filter")
                if model.isLoading || model.loadedScope != key.scope { ProgressView("accountCollection.loading") }
                else if let issue = model.issue(scope: key.scope) {
                    AccountCollectionIssueView(issue: issue, retry: { Task { await load() } })
                } else if let coupons = model.value(scope: key.scope) {
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
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, coupon in
                        NavigationLink {
                            AccountCollectionCouponDetailView(id: coupon.id, reader: reader)
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
                Button { Task { await load() } } label: { Label("accountCollection.refresh", systemImage: "arrow.clockwise") }
                    .disabled(model.isLoading || !reader.isAuthenticated || !reader.isConfigured)
                    .accessibilityIdentifier("accountCollection.coupons.refresh")
            }
        }
        .modifier(AccountCollectionReadLifecycle(key: key, refresh: load, cancel: model.cancelPending))
    }
    private func load() async {
        guard reader.isAuthenticated, reader.isConfigured else { model.invalidate(); return }
        let captured = key.scope
        let keyword = submittedQuery.isEmpty ? nil : submittedQuery
        await model.load(scope: captured, currentScope: { reader.scope }) { try await reader.ownedCoupons(keyword: keyword) }
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
