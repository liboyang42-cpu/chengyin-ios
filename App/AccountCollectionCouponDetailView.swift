import SwiftUI

/// Owned metadata stays separate from the explicitly reviewed, short-lived code screen.
@MainActor struct AccountCollectionCouponDetailView: View {
    let id: Int
    let reader: any AccountCollectionReading
    @Environment(\.couponCodeFactory) private var makeCode
    @StateObject private var model = AccountCollectionScreenModel<AccountCollectionCoupon>()
    private var key: AccountCollectionLoadKey { AccountCollectionLoadKey(reader: reader, id: id) }
    var body: some View {
        List {
            if reader.isOfflineExample { Text("accountCollection.offlineExample").font(.caption) }
            if !reader.isAuthenticated { AccountCollectionIssueView(issue: .login) }
            else if !reader.isConfigured { AccountCollectionIssueView(issue: .notConfigured) }
            else if model.isLoading || model.loadedScope != key.scope { ProgressView("accountCollection.loading") }
            else if let issue = model.issue(scope: key.scope) {
                AccountCollectionIssueView(issue: issue, retry: { Task { await load() } })
            } else if let coupon = model.value(scope: key.scope), coupon.id == id {
                Section {
                    AccountCollectionCouponRow(coupon: coupon)
                        .questifyCardListRow()
                        .accessibilityIdentifier("accountCollection.coupon.detail.header")
                }
                if coupon.status == .unused, let makeCode {
                    Section {
                        NavigationLink { CouponCodeView(model: makeCode(coupon.id)).id(reader.scope) } label: {
                            Label("couponCode.show", systemImage: "qrcode")
                        }.accessibilityIdentifier("couponCode.open")
                    }
                }
                Section("accountCollection.coupon.validity") {
                    AccountCollectionCouponDate(label: "accountCollection.coupon.validFrom", value: coupon.startTime)
                    AccountCollectionCouponDate(label: "accountCollection.coupon.validUntil", value: coupon.endTime)
                    if AccountCollectionCoupon.calendarDay(coupon.startTime) == nil,
                       AccountCollectionCoupon.calendarDay(coupon.endTime) == nil {
                        Text("accountCollection.coupon.validityUnknown")
                    }
                    Text("accountCollection.coupon.calendarHint").font(.footnote).foregroundStyle(.secondary)
                }
                if AccountCollectionCoupon.calendarDay(coupon.receivedTime) != nil || AccountCollectionCoupon.calendarDay(coupon.usedTime) != nil {
                    Section("accountCollection.coupon.history") {
                        AccountCollectionCouponDate(label: "accountCollection.coupon.received", value: coupon.receivedTime)
                        AccountCollectionCouponDate(label: "accountCollection.coupon.used", value: coupon.usedTime)
                    }
                }
                Section {
                    Label {
                        Text("accountCollection.coupon.readOnly")
                            .accessibilityIdentifier("accountCollection.coupon.readOnly")
                    } icon: { Image(systemName:"info.circle").accessibilityHidden(true) }
                    .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.insetGrouped)
        .appNavigationTitle("accountCollection.coupon.detail")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { Task { await load() } } label: { Label("accountCollection.refresh", systemImage: "arrow.clockwise") }
                    .disabled(model.isLoading || !reader.isAuthenticated || !reader.isConfigured)
                    .accessibilityIdentifier("accountCollection.coupon.detail.refresh")
            }
        }
        .modifier(AccountCollectionReadLifecycle(key: key, refresh: load, cancel: model.cancelPending))
    }
    private func load() async {
        guard reader.isAuthenticated, reader.isConfigured else { model.invalidate(); return }
        let captured = key.scope
        await model.load(scope: captured, currentScope: { reader.scope }) { try await reader.ownedCoupon(id: id) }
    }
}
