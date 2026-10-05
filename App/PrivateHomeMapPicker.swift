import SwiftUI
import Observation

/// A renderer supplies explicit selections only after the owner opens the picker.
/// An accepted provider/output/region contract is required before any candidate can be used.
@MainActor protocol PrivateHomeMapPointPicking: AnyObject {
    var approvedSource: PrivateHomeMapSource? { get }
    func start(receive: @escaping (PrivateHomeMapCandidate) -> Void)
    func cancel()
}

/// Intentionally inactive. The existing MapKit renderers do not establish an approved
/// private-home provider/region datum contract, especially for Mainland China. Do not mount
/// a Map, load tiles, guess a datum, or reuse the public SearchMapCanvas for this private point.
@MainActor final class PrivateHomeInactiveMapKitAdapter: PrivateHomeMapPointPicking {
    let approvedSource: PrivateHomeMapSource? = nil
    func start(receive: @escaping (PrivateHomeMapCandidate) -> Void) {}
    func cancel() {}
}

@MainActor @Observable final class PrivateHomeMapPickerModel {
    private(set) var selection = PrivateHomeMapSelection()
    let adapter: any PrivateHomeMapPointPicking
    let owner: PrivateHomeCoordinator
    private var ownerVersion: Int64?
    private var sourceAtOpen: PrivateHomeMapSource?
    private var reviewedRequestID: String?
    private var reviewedSource: PrivateHomeMapSource?
    private(set) var confirmationIssue: PrivateHomeMapIssue?
    init(owner: PrivateHomeCoordinator, adapter: any PrivateHomeMapPointPicking) {
        self.owner = owner; self.adapter = adapter
    }
    var isPresented: Bool { selection.generation != nil }
    var visiblePoint: PrivateHomePoint? { currentOwner && currentSource ? selection.point : nil }
    var canUsePoint: Bool { visiblePoint != nil }
    private var currentOwner: Bool { owner.canEdit && owner.home?.version == ownerVersion }
    private var currentSource: Bool { sourceAtOpen?.isReviewedWGS84 == true && adapter.approvedSource == sourceAtOpen }
    func open() {
        close()
        guard owner.canEdit else { return }
        confirmationIssue = nil
        ownerVersion = owner.home?.version
        sourceAtOpen = adapter.approvedSource
        let ticket = selection.open(approvedSource: sourceAtOpen)
        // The inactive production adapter is not even started. Synthetic tests explicitly
        // inject their source contract and recorder; normal composition has no override.
        guard adapter.approvedSource?.isReviewedWGS84 == true else { return }
        adapter.start { [weak self] candidate in
            guard let self, self.selection.generation == ticket else { return }
            guard self.currentOwner, self.currentSource else { self.close(); return }
            self.selection.select(candidate, generation: ticket)
        }
    }
    @discardableResult func review(label: String) -> Bool {
        guard canUsePoint, let point = selection.point else { if !currentOwner || !currentSource { close() }; return false }
        owner.prepareSet(label: label, point: point)
        guard owner.canConfirm else { return false }
        reviewedRequestID = owner.review?.requestId
        reviewedSource = sourceAtOpen
        close(); return true
    }
    /// Called inside the final confirmation Task, immediately before the unchanged owner
    /// starts its durable transaction. Revocation must not turn a map review into manual input.
    func authorizeOwnerConfirmation() -> Bool {
        guard owner.canConfirm else { return false }
        guard let reviewedRequestID, owner.review?.requestId == reviewedRequestID else {
            // A later independently prepared manual review has its own request identity.
            self.reviewedRequestID = nil; reviewedSource = nil; confirmationIssue = nil
            return true
        }
        guard reviewedSource?.isReviewedWGS84 == true, adapter.approvedSource == reviewedSource else {
            owner.cancelReview()
            self.reviewedRequestID = nil; reviewedSource = nil
            confirmationIssue = .providerUnverified
            close(); return false
        }
        return true
    }
    func close() { selection.close(); ownerVersion = nil; sourceAtOpen = nil; adapter.cancel() }
}

@MainActor struct PrivateHomeMapPickerView: View {
    @Bindable var picker: PrivateHomeMapPickerModel
    @State private var label: String
    @Environment(\.scenePhase) private var scenePhase
    init(picker: PrivateHomeMapPickerModel, initialLabel: String) {
        self.picker = picker
        _label = State(initialValue: initialLabel)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("privateHome.gamePoint").font(.footnote)
                    Text("privateHome.map.noLocation").font(.footnote)
                    if let issue = picker.selection.issue {
                        Text(LocalizedStringKey("privateHome.map.issue." + issue.rawValue))
                            .accessibilityIdentifier("privateHome.map.issue")
                    }
                }
                #if DEBUG
                if let fixture = picker.adapter as? PrivateHomeFixtureMapAdapter {
                    Section("privateHome.map.synthetic") {
                        ForEach(PrivateHomeFixtureMapAdapter.Choice.allCases, id: \.self) { choice in
                            Button(LocalizedStringKey("privateHome.map.fixture." + choice.rawValue)) { fixture.select(choice) }
                                .accessibilityIdentifier("privateHome.map.fixture.\(choice.rawValue)")
                        }
                        Button { fixture.replaceOwner?() } label: { Text(verbatim: "Synthetic: replace owner") }
                            .accessibilityIdentifier("privateHome.map.fixture.replaceOwner")
                        Button { fixture.emitCancelledCandidate() } label: { Text(verbatim: "Synthetic: late callback") }
                            .accessibilityIdentifier("privateHome.map.fixture.late")
                        Button("privateHome.map.fixture.invalidate") { picker.owner.invalidate(); picker.close() }
                            .accessibilityIdentifier("privateHome.map.fixture.invalidate")
                    }
                }
                #endif
                if let point = picker.visiblePoint {
                    Section("privateHome.map.preview") {
                        PrivateHomeCoordinateReview(point: point)
                        TextField("privateHome.label", text: $label).accessibilityIdentifier("privateHome.map.label")
                        if picker.owner.issue == .invalid { Text("privateHome.invalid") }
                    }
                }
                Section {
                    Button("privateHome.map.review") { picker.review(label: label) }
                        .disabled(!picker.canUsePoint).accessibilityIdentifier("privateHome.map.review")
                    Button("privateHome.map.manual") { picker.close() }.accessibilityIdentifier("privateHome.map.manual")
                    Button("privateHome.map.cancel", role: .cancel) { picker.close() }.accessibilityIdentifier("privateHome.map.cancel")
                }
            }
            .navigationTitle("privateHome.map.title").privacySensitive().accessibilityIdentifier("privateHome.map.host")
            .onChange(of: scenePhase) { _, phase in if phase != .active { picker.close() } }
            .overlay { if scenePhase != .active { Color(.systemBackground).overlay(Text("privateHome.title")) } }
        }
    }
}

/// The exact endpoint Decimal values, in latitude/longitude order, with no locale rounding.
struct PrivateHomeCoordinateReview: View {
    let point: PrivateHomePoint
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("privateHome.map.exact").font(.footnote)
            Text(verbatim: "\(point.latitude), \(point.longitude) · WGS84")
                .textSelection(.disabled).privacySensitive().accessibilityIdentifier("privateHome.coordinateReview")
        }
    }
}
