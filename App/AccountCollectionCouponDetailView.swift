import SwiftUI

/// Owned metadata stays separate from the explicitly reviewed, short-lived code screen.
@MainActor struct AccountCollectionCouponDetailView: View {
    let selection: OwnedCouponDetailSelection
    private var id: Int { selection.historyID }
    let reader: any AccountCollectionReading
    @Environment(\.couponCodeFactory) private var makeCode
    @StateObject private var model = OwnedCouponReadScreenModel()
    @State private var viewPresentation = OwnedCouponReadViewPresentation()
    @Environment(\.scenePhase) private var scenePhase
    private var key: AccountCollectionLoadKey { AccountCollectionLoadKey(reader: reader, id: id) }
    private var request: OwnedCouponReadRequest { .detail(selection) }
    var body: some View {
        let appearance = viewPresentation
        let presentation = appearance.permit
        let offeredRequest = request
        return List {
            if reader.isOfflineExample { Text("accountCollection.offlineExample").font(.caption) }
            if !reader.isAuthenticated { AccountCollectionIssueView(issue: .login) }
            else if !reader.isConfigured { AccountCollectionIssueView(issue: .notConfigured) }
            else if selection.ownerScope != reader.scope { Text("couponCode.stale") }
            else if model.isLoading || model.loadedRequest != offeredRequest { ProgressView("accountCollection.loading") }
            else if let issue = model.issue(for: offeredRequest) {
                AccountCollectionIssueView(issue: issue, retry: { model.schedule(request: offeredRequest, reader: reader, presentation: presentation) })
            } else if let coupon = model.detail(for: offeredRequest), coupon.id == id {
                Section {
                    AccountCollectionCouponRow(coupon: coupon)
                        .questifyCardListRow()
                        .accessibilityIdentifier("accountCollection.coupon.detail.header")
                }
                if coupon.status == .unused, let makeCode {
                    Section {
                        let destination = OwnedCouponCodeDestination(selection: selection)
                        NavigationLink {
                            OwnedCouponCodeDestinationView(destination: destination, reader: reader, factory: makeCode).id(destination.id)
                        } label: {
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
                        if coupon.status == .unused, makeCode != nil {
                            Text("couponCode.authority")
                                .accessibilityIdentifier("accountCollection.coupon.codeAuthority")
                        } else {
                            Text("accountCollection.coupon.readOnly")
                                .accessibilityIdentifier("accountCollection.coupon.readOnly")
                        }
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
                Button { model.schedule(request: offeredRequest, reader: reader, presentation: presentation) } label: { Label("accountCollection.refresh", systemImage: "arrow.clockwise") }
                    .disabled(model.isLoading || !reader.isAuthenticated || !reader.isConfigured)
                    .accessibilityIdentifier("accountCollection.coupon.detail.refresh")
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
