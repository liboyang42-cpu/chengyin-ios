import SwiftUI

/// The detail's concrete container owns presentation, not a lazily recycled List row.
@MainActor struct ProfileOrderMeetingPointHost<Content: View>: View {
    let order: ProfileOrder
    let requestedID: Int
    let reader: any ProfileReading
    let open: @MainActor (PlatformMapDestination) async -> Bool
    let content: (ProfileOrderMeetingPointEntry) -> Content
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: ProfileOrderMeetingPointModel
    private var context: ProfileOrderMeetingPointContext? {
        .capture(order: order, requestedID: requestedID, reader: reader)
    }
    init(order: ProfileOrder, requestedID: Int, reader: any ProfileReading,
         open: (@MainActor (PlatformMapDestination) async -> Bool)? = nil,
         @ViewBuilder content: @escaping (ProfileOrderMeetingPointEntry) -> Content) {
        self.order = order; self.requestedID = requestedID; self.reader = reader
        self.open = open ?? NativePlatformMapOpener().open
        self.content = content
        _model = State(initialValue: .init(context: .capture(order: order, requestedID: requestedID, reader: reader)))
    }
    var body: some View {
        ZStack {
            content(ProfileOrderMeetingPointEntry(model: model, current: { context }))
        }
        .background {
            if let review = model.review {
                ProfileOrderMeetingPointReviewOwner(model: model, review: review,
                    current: { context }, open: open).id(review.id)
            }
        }
        .onAppear { model.appear(current: context, sceneActive: scenePhase == .active) }
        .onDisappear { model.disappear() }
        .onChange(of: context) { _, _ in model.retire() }
        .onChange(of: scenePhase) { _, phase in model.sceneChanged(active: phase == .active, current: context) }
    }
}

@MainActor struct ProfileOrderMeetingPointEntry: View {
    let model: ProfileOrderMeetingPointModel
    let current: @MainActor () -> ProfileOrderMeetingPointContext?
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button("profile.orderMap.open", systemImage: "map") { model.prepare(current: current()) }
                .disabled(!model.canPrepare(current: current()))
                .frame(minHeight: 44).accessibilityIdentifier("profile.orderMap.open")
            if !model.matches(current()) {
                Text("profile.orderMap.unavailable").font(.footnote).foregroundStyle(.secondary)
            } else if model.isOpening {
                ProgressView("profile.orderMap.opening").accessibilityIdentifier("profile.orderMap.opening")
            } else if let outcome = model.outcome {
                Text(LocalizedStringKey(outcome == .opened ? "profile.orderMap.opened" : "profile.orderMap.failed"))
                    .font(.footnote).accessibilityIdentifier("profile.orderMap.result")
            }
        }
    }
}

@MainActor extension ProfileOrderMeetingPointModel {
    func presentation(for offered: ProfileOrderMeetingPointReview?,
        current: @escaping @MainActor () -> ProfileOrderMeetingPointContext?) -> Binding<ProfileOrderMeetingPointReview?> {
        Binding(get: {
            guard let offered, self.owns(offered, current: current()) else { return nil }
            return offered
        }, set: { value in
            if value == nil, let offered { self.cancel(id: offered.id) }
        })
    }
}

@MainActor private struct ProfileOrderMeetingPointReviewOwner: View {
    let model: ProfileOrderMeetingPointModel
    let review: ProfileOrderMeetingPointReview
    let current: @MainActor () -> ProfileOrderMeetingPointContext?
    let open: @MainActor (PlatformMapDestination) async -> Bool
    var body: some View {
        Color.clear.frame(width: 0, height: 0)
            .sheet(item: model.presentation(for: review, current: current),
                   onDismiss: { model.cancel(id: review.id) }) { offered in
                NavigationStack {
                    Form {
                        Section {
                            Text("profile.orderMap.disclosure")
                            if !offered.context.destination.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text(verbatim: offered.context.destination.name).textSelection(.enabled)
                            }
                            if let latitude = offered.context.destination.latitude, let longitude = offered.context.destination.longitude {
                                Text(verbatim: "\(latitude), \(longitude)").monospacedDigit()
                            }
                        }
                        Button("profile.orderMap.confirm") {
                            Task { await model.confirm(offered, current: current, open: open) }
                        }.disabled(!model.owns(offered, current: current()))
                            .accessibilityIdentifier("profile.orderMap.confirm")
                    }
                    .navigationTitle("profile.orderMap.review")
                    .toolbar { ToolbarItem(placement: .cancellationAction) {
                        Button("action.cancel") { model.cancel(id: offered.id) }
                            .accessibilityIdentifier("profile.orderMap.cancel")
                    } }
                }
            }
    }
}
