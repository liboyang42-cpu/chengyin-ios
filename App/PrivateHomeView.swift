import SwiftUI

@MainActor struct PrivateHomeAccountLink: View {
    let coordinator: PrivateHomeCoordinator?
    var mapAdapter: (any PrivateHomeMapPointPicking)? = nil
    var body: some View {
        NavigationLink {
            if let coordinator { PrivateHomeView(model: coordinator, mapAdapter: mapAdapter) }
            else { ContentUnavailableView("privateHome.disabled", systemImage: "house", description: Text("privateHome.gate")) }
        } label: { Label("privateHome.title", systemImage: "house") }
        .accessibilityIdentifier("account.privateHome")
    }
}
/// Identity wraps every private field, picker model and sheet in the actual account destination.
/// SwiftUI State initialization alone does not reset when a new coordinator occupies this route.
@MainActor struct PrivateHomeView: View {
    let model: PrivateHomeCoordinator
    var mapAdapter: (any PrivateHomeMapPointPicking)? = nil
    var body: some View {
        PrivateHomeOwnerForm(model: model, mapAdapter: mapAdapter)
            .id(ObjectIdentifier(model))
    }
}
@MainActor private struct PrivateHomeOwnerForm: View {
    @Bindable var model: PrivateHomeCoordinator
    @State private var label = ""
    @State private var latitude = ""
    @State private var longitude = ""
    @State private var invalidInput = false
    @State private var picker: PrivateHomeMapPickerModel
    @Environment(\.scenePhase) private var scenePhase
    init(model: PrivateHomeCoordinator, mapAdapter: (any PrivateHomeMapPointPicking)? = nil) {
        self.model = model
        _picker = State(initialValue: PrivateHomeMapPickerModel(owner: model, adapter: mapAdapter ?? PrivateHomeInactiveMapKitAdapter()))
    }
    var body: some View {
        Form {
            Section {
                Text("privateHome.boundary").font(.footnote)
                Text(LocalizedStringKey("privateHome.phase." + model.phase.rawValue)).accessibilityIdentifier("privateHome.phase")
                if let home = model.home {
                    Text(LocalizedStringKey(home.status == .active ? "privateHome.active" : "privateHome.empty"))
                    if let label = home.label { Text(verbatim: label).privacySensitive() }
                }
                if let decision = model.decision { Text(LocalizedStringKey("privateHome.decision." + decision.rawValue)) }
                if model.issue != nil { Text("privateHome.issue").accessibilityIdentifier("privateHome.issue") }
                if let issue = picker.confirmationIssue {
                    Text(LocalizedStringKey("privateHome.map.issue." + issue.rawValue))
                        .accessibilityIdentifier("privateHome.map.confirmationIssue")
                }
                Button("privateHome.refresh") { Task { await model.load() } }
                    .disabled(model.isBusy || model.phase == .review).accessibilityIdentifier("privateHome.refresh")
            }
            if model.canEdit {
                Section("privateHome.set") {
                    TextField("privateHome.label", text: $label).accessibilityIdentifier("privateHome.label")
                    TextField("privateHome.latitude", text: $latitude).keyboardType(.numbersAndPunctuation).accessibilityIdentifier("privateHome.latitude")
                    TextField("privateHome.longitude", text: $longitude).keyboardType(.numbersAndPunctuation).accessibilityIdentifier("privateHome.longitude")
                    Text("privateHome.datum").font(.footnote)
                    Text("privateHome.gamePoint").font(.footnote)
                    Button("privateHome.map.open") { picker.open() }.accessibilityIdentifier("privateHome.map.open")
                    Button("privateHome.reviewSet") { prepare() }.accessibilityIdentifier("privateHome.reviewSet")
                    if invalidInput { Text("privateHome.invalid") }
                    if model.home?.status == .active {
                        Button("privateHome.reviewDelete", role: .destructive) { model.prepareDelete(); clearInput() }
                            .accessibilityIdentifier("privateHome.reviewDelete")
                    }
                }
            }
            if let review = model.review, model.canConfirm {
                Section("privateHome.review") {
                    Text(LocalizedStringKey(review.method == "DELETE" ? "privateHome.deletePurpose" : "privateHome.setPurpose"))
                    if let label = review.label { Text(verbatim: label) }
                    if let lat = review.latitude, let lon = review.longitude,
                       let point = try? PrivateHomePoint(latitude: lat, longitude: lon) {
                        PrivateHomeCoordinateReview(point: point)
                    }
                    Button("privateHome.confirm") {
                        clearInput()
                        Task {
                            guard picker.authorizeOwnerConfirmation() else { return }
                            await model.confirm()
                        }
                    }.accessibilityIdentifier("privateHome.confirm")
                    Button("privateHome.cancel") { model.cancelReview(); clearInput() }.accessibilityIdentifier("privateHome.cancel")
                }
            }
            if model.canRetry {
                Section {
                    Text("privateHome.unknownPurpose")
                    Button("privateHome.retry") { Task { await model.retryExact() } }.accessibilityIdentifier("privateHome.retry")
                }
            }
        }
        .navigationTitle("privateHome.title").privacySensitive().accessibilityIdentifier("privateHome.host")
        .task { await model.load() }
        .sheet(isPresented: Binding(get: { picker.isPresented }, set: { if !$0 { picker.close() } })) {
            PrivateHomeMapPickerView(picker: picker, initialLabel: label)
                .id(picker.selection.generation)
        }
        .onDisappear { picker.close(); clearInput(); model.cancelReview() }
        .onChange(of: model.phase) { _, phase in
            if phase != .ready { picker.close() }
            if phase == .invalidated { clearInput() }
        }
        .onChange(of: scenePhase) { _, phase in if phase != .active { picker.close() } }
        .overlay { if scenePhase != .active { Color(.systemBackground).overlay(Text("privateHome.title")) } }
    }
    private func clearInput() { label = ""; latitude = ""; longitude = ""; invalidInput = false }
    private func prepare() {
        guard let point = try? PrivateHomePoint.parse(latitude: latitude, longitude: longitude) else { invalidInput = true; return }
        model.prepareSet(label: label, point: point); invalidInput = model.issue != nil
    }
}
