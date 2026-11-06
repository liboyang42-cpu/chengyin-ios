import SwiftUI

/// Real-data consumer only. No fixture, transport, factory, or production entry is installed here.
@MainActor struct FreeExploreBundleLaunchView: View {
    @Bindable var model: FreeExploreBundleLaunchModel
    @State private var unitID: FreeExploreLaunchID?
    @State private var offerID: FreeExploreLaunchID?
    @State private var date = Date()
    private let table = "FreeExploreBundleLaunch"
    private func text(_ key: String) -> Text { Text(LocalizedStringKey(key), tableName: table) }
    var body: some View {
        Form {
            if !model.current { text("stale") }
            else {
                if model.busy { ProgressView { text("loading") } }
                if model.failure != nil { text("error").accessibilityIdentifier("freeBundle.error") }
                if model.state == .outcomeUnknown {
                    Section {
                        text("unknown")
                        Button { Task { await model.recover() } } label: { text("recover") }
                            .disabled(model.busy)
                        Button { Task { await model.retryOriginal() } } label: { text("retry") }
                            .disabled(!model.canRetry)
                    }
                }
                if let catalog = model.catalog {
                    Section {
                        if let name = catalog.topicName { Text(verbatim: name) }
                        if catalog.items.isEmpty { text("empty") }
                        ForEach(catalog.items, id: \.chapterId) { item in
                            if let name = item.name { Text(verbatim: name).font(.headline) }
                            if let terms = item.termsMode { Text(verbatim: terms).font(.footnote) }
                            ForEach(item.stores, id: \.offerId) { store in
                                VStack(alignment: .leading) {
                                    if let name = store.merchantName { Text(verbatim: name) }
                                    Text(verbatim: store.offerId.text).font(.caption).textSelection(.enabled)
                                    if let end = store.validEnd { Text(verbatim: end).font(.footnote) }
                                }
                            }
                        }
                    } header: { text("catalog") }
                }
                if let order = model.order {
                    Section {
                        LabeledContent { Text(verbatim: order.registrationId.text) } label: { text("order") }
                        if let number = order.registrationNo { Text(verbatim: number).textSelection(.enabled) }
                        if let bundle = order.bundle {
                            ForEach(bundle.reservations, id: \.id) { reservation in
                                VStack(alignment: .leading) {
                                    Text(verbatim: reservation.status)
                                    Text(verbatim: reservation.startAt)
                                    Text(verbatim: reservation.id.text).font(.caption)
                                }
                            }
                            Picker(selection: $unitID) {
                                text("choose").tag(Optional<FreeExploreLaunchID>.none)
                                ForEach(bundle.units.filter { $0.status == "AVAILABLE" }, id: \.id) { unit in
                                    Text(verbatim: unit.id.text).tag(Optional(unit.id))
                                }
                            } label: { text("unit") }
                            Picker(selection: $offerID) {
                                text("choose").tag(Optional<FreeExploreLaunchID>.none)
                                if let unit = bundle.units.first(where: { $0.id == unitID }),
                                   let item = model.catalog?.items.first(where: { $0.chapterId == unit.chapterId }) {
                                    ForEach(item.stores, id: \.offerId) { store in
                                        Text(verbatim: store.merchantName ?? store.offerId.text).tag(Optional(store.offerId))
                                    }
                                }
                            } label: { text("offer") }
                            DatePicker(selection: $date) { text("date") }
                            Button {
                                guard let unitID, let offerID else { return }
                                let millis = date.timeIntervalSince1970 * 1_000
                                guard millis.isFinite, millis > 0, millis < Double(Int64.max) else { return }
                                model.prepare(unitID: unitID, offerID: offerID, startAt: Int64(millis))
                            } label: { text("review") }
                                .disabled(!model.canReserve || unitID == nil || offerID == nil)
                        } else { text("legacy") }
                        if !model.canReserve { text("disabled").font(.footnote) }
                    }
                }
                if model.state == .confirmed { text("confirmed") }
            }
        }
        .navigationTitle(text("title"))
        .privacySensitive()
        .task { await model.load() }
        .refreshable { await model.load() }
        .onChange(of: unitID) { _, _ in offerID = nil; model.cancelReview() }
        .onChange(of: offerID) { _, _ in model.cancelReview() }
        .onChange(of: date) { _, _ in model.cancelReview() }
        .sheet(item: Binding(get: { model.review }, set: { if $0 == nil { model.cancelReview() } })) { review in
            NavigationStack {
                Form {
                    text("notice")
                    LabeledContent { Text(verbatim: review.command.registrationId.text) } label: { text("order") }
                    LabeledContent { Text(verbatim: review.command.unitId.text) } label: { text("unit") }
                    LabeledContent { Text(verbatim: review.command.offerId.text) } label: { text("offer") }
                    LabeledContent {
                        Text(Date(timeIntervalSince1970: Double(review.command.startAt) / 1_000), style: .date)
                        Text(Date(timeIntervalSince1970: Double(review.command.startAt) / 1_000), style: .time)
                    } label: { text("date") }
                    Button { Task { await model.confirm(review) } } label: { text("confirm") }
                        .disabled(!model.canReserve)
                    Button(role: .cancel) { model.cancelReview() } label: { text("cancel") }
                }.navigationTitle(text("review"))
            }
        }
        // A reopened destination must receive a fresh model from its authorized host.
        .onDisappear { model.cancelReview() }
    }
}
