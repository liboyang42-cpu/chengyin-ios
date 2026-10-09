import SwiftUI
import PhotosUI
import UIKit

/// Host in the existing NavigationStack and retain coordinator outside this view.
@MainActor
struct MerchantOnboardingView<Session: MerchantOnboardingObserving>: View {
    @Environment(\.locale) private var locale
    @ObservedObject var session: Session
    @StateObject private var model: MerchantOnboardingModel
    let openMerchant: (() -> Void)?
    @State private var loadedRevision: UInt64?
    @State private var photo: PhotosPickerItem?
    @State private var showPhotos = false
    @State private var showHours = false
    @State private var hoursEditor: MerchantOnboardingHoursSession?
    @State private var showUploadConfirmation = false
    @State private var showSubmitConfirmation = false
    init(session: Session, coordinator: MerchantOnboardingCoordinator, openMerchant: (() -> Void)? = nil) {
        self.session = session; _model = StateObject(wrappedValue: MerchantOnboardingModel(coordinator: coordinator))
        self.openMerchant = openMerchant
    }
    var body: some View {
        ZStack {
            if !session.isConfigured || !model.coordinator.isConfigured {
                ContentUnavailableView("merchant.onboarding.title", systemImage: "network.slash", description: Text("auth.notConfigured"))
            } else if !session.isSignedIn {
                ContentUnavailableView("merchant.onboarding.title", systemImage: "person.crop.circle.badge.exclamationmark", description: Text("merchant.signIn"))
            } else if model.identity != model.coordinator.identity {
                ProgressView("merchant.onboarding.checking")
            } else {
                content
            }
        }
        .appNavigationTitle("merchant.onboarding.title")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: session.sessionRevision) {
            // Returning from a transient sheet may restart .task without a new account.
            guard loadedRevision != session.sessionRevision else { return }
            loadedRevision = session.sessionRevision
            photo = nil; showPhotos = false; showHours = false
            showUploadConfirmation = false; showSubmitConfirmation = false
            model.reset(); await model.load()
        }
        .onDisappear {
            // Presenting a child surface is not leaving the application. Keep the draft
            // and selected item through picker/sheet/confirmation transitions.
            guard !showPhotos, !showHours, !showUploadConfirmation, !showSubmitConfirmation else { return }
            loadedRevision = nil; model.leave(); photo = nil
        }
        .photosPicker(isPresented: $showPhotos, selection: $photo, matching: .images, preferredItemEncoding: .compatible)
        .onChange(of: photo) { _, value in
            guard let value else { return }
            Task { await model.select(value); photo = nil }
        }
        .sheet(isPresented: $showHours) {
            if let hoursEditor {
                MerchantOnboardingHoursEditor(editor: hoursEditor) { hoursEditor.cancel(); showHours = false }
            }
        }
        .onChange(of: showHours) { _, shown in if !shown { hoursEditor?.cancel(); hoursEditor = nil } }
        .confirmationDialog("merchant.onboarding.uploadConfirm.title", isPresented: $showUploadConfirmation, titleVisibility: .visible) {
            Button("merchant.onboarding.uploadConfirm.action") { Task { await model.uploadSelected() } }
            Button("action.cancel", role: .cancel) { }
        } message: { Text("merchant.onboarding.uploadConfirm.message") }
        .alert("merchant.onboarding.submitConfirm.title", isPresented: $showSubmitConfirmation) {
            Button("merchant.onboarding.submitConfirm.action") { model.submitConfirmed() }
            Button("action.cancel", role: .cancel) { model.cancelConfirmation() }
        } message: { Text("merchant.onboarding.submitConfirm.message") }
        .onChange(of: showSubmitConfirmation) { _, shown in
            if !shown, model.confirmation != nil, !model.isBusy { model.cancelConfirmation() }
        }
    }
    @ViewBuilder private var content: some View {
        switch model.coordinator.loadState {
        case .idle, .loading:
            ProgressView("merchant.onboarding.checking").accessibilityIdentifier("merchant.onboarding.loading")
        case .unavailable:
            Form {
                submissionSection
                Section { Text("merchant.onboarding.stateUnavailable"); refreshButton }
            }
        case .loaded(let snapshot):
            if model.coordinator.submission.isLocked && model.coordinator.submission != .awaitingConfirmation {
                Form {
                    submissionSection
                    if case .application(let application) = snapshot { statusSection(application) }
                    else { Section { Text("merchant.onboarding.noApplicationReadback") } }
                    Section { refreshButton }
                }
            } else if case .application(let application) = snapshot, (!model.isEditing || !application.canReapply) {
                Form {
                    submissionSection
                    statusSection(application)
                    Section {
                        if application.canReapply {
                            Button("merchant.onboarding.reapply") { model.reapply(application) }
                                .accessibilityIdentifier("merchant.onboarding.reapply")
                        }
                        if application.status == 1 && application.accountStatus == 1, let openMerchant {
                            Button("merchant.onboarding.openMerchant", action: openMerchant)
                        }
                        refreshButton
                    }
                }
            } else { applicationForm }
        }
    }
    private var applicationForm: some View {
        Form {
            Section {
                Text(LocalizedStringKey("merchant.onboarding.step." + String(model.step))).font(.headline)
                Text("merchant.onboarding.regionalNotice").font(.footnote).foregroundStyle(.secondary)
            }
            submissionSection
            switch model.step {
            case 1: basicSection
            case 2: businessSection
            case 3: licenseSection
            default: reviewSection
            }
            if let error = model.errorKey {
                Section { Text(LocalizedStringKey(error)).foregroundStyle(.red).accessibilityIdentifier("merchant.onboarding.error") }
            }
            Section {
                if model.isBusy { ProgressView("merchant.onboarding.working") }
                if model.step > 1 {
                    Button("merchant.onboarding.previous") { model.step -= 1; model.errorKey = nil }
                }
                if model.step < 4 {
                    Button("merchant.onboarding.next") { model.next() }
                        .accessibilityIdentifier("merchant.onboarding.next")
                } else {
                    Button("merchant.onboarding.reviewSubmit") {
                        model.prepare(); showSubmitConfirmation = model.confirmation != nil
                    }
                    .disabled(model.coordinator.identityGate != .registered || model.draft.blocker() != nil)
                    .accessibilityIdentifier("merchant.onboarding.submit")
                }
            }.disabled(model.isBusy || model.coordinator.submission.isLocked)
        }
        .disabled(model.isBusy)
        .scrollDismissesKeyboard(.interactively)
    }
    private var basicSection: some View {
        Section("merchant.onboarding.step.1") {
            TextField("merchant.onboarding.name", text: $model.draft.name).accessibilityIdentifier("merchant.onboarding.name")
            TextField("merchant.onboarding.preference", text: $model.draft.preference)
            TextField("merchant.onboarding.phone", text: $model.draft.phone).keyboardType(.phonePad)
                .accessibilityIdentifier("merchant.onboarding.phone")
        }
    }
    private var businessSection: some View {
        Section("merchant.onboarding.step.2") {
            TextField("merchant.onboarding.address", text: $model.draft.address, axis: .vertical)
                .accessibilityIdentifier("merchant.onboarding.address")
            LabeledContent("merchant.onboarding.hours", value: model.draft.businessTime.isEmpty ? appLocalized("merchant.onboarding.notSet",locale:locale) : displayHours(model.draft.businessTime))
            Button("merchant.onboarding.chooseHours") {
                hoursEditor = MerchantOnboardingHoursSession(model: model)
                showHours = hoursEditor != nil
            }
                .accessibilityIdentifier("merchant.onboarding.hours")
            TextField("merchant.onboarding.description", text: $model.draft.description, axis: .vertical).lineLimit(3...8)
        }
    }
    private var licenseSection: some View {
        Group {
            identitySection
            Section("merchant.onboarding.step.3") {
                Text("merchant.onboarding.licenseHint").font(.footnote).foregroundStyle(.secondary)
                if model.draft.license != nil {
                    Label("merchant.onboarding.licenseUploaded", systemImage: "checkmark.circle")
                        .accessibilityIdentifier("merchant.onboarding.licenseUploaded")
                }
                if let selectedImage = model.selectedImage {
                    if let preview = UIImage(data: selectedImage.data) {
                        Image(uiImage: preview).resizable().scaledToFit().frame(maxHeight: 200)
                            .accessibilityLabel("merchant.onboarding.licensePreview")
                    }
                    Text("merchant.onboarding.licenseSelected").accessibilityIdentifier("merchant.onboarding.licenseSelected")
                    Button("merchant.onboarding.uploadLicense") { showUploadConfirmation = true }
                    Button("merchant.onboarding.discardPhoto", role: .destructive) { model.selectedImage = nil }
                }
                Button("merchant.onboarding.chooseLicense") { showPhotos = true }
                    .disabled(model.coordinator.identityGate != .registered)
                    .accessibilityIdentifier("merchant.onboarding.chooseLicense")
            }
        }
        .task { if model.coordinator.identityGate == .unchecked { await model.checkIdentity() } }
    }
    private var reviewSection: some View {
        Group {
            Section("merchant.onboarding.step.4") {
                reviewRow("merchant.onboarding.name", model.draft.name)
                reviewRow("merchant.onboarding.preference", model.draft.preference)
                reviewRow("merchant.onboarding.phone", model.draft.phone)
                reviewRow("merchant.onboarding.address", model.draft.address)
                reviewRow("merchant.onboarding.hours", displayHours(model.draft.businessTime))
                reviewRow("merchant.onboarding.description", model.draft.description)
                Label("merchant.onboarding.licenseUploaded", systemImage: "doc.badge.checkmark")
            }
            identitySection
        }
        .task { if model.coordinator.identityGate == .unchecked { await model.checkIdentity() } }
    }
    /// Translate only the exact source-generated weekday grammar; preserve unknown server text.
    private func displayHours(_ value: String) -> String {
        let parts = value.split(separator: " ", maxSplits: 1)
        guard parts.count == 2 else { return value }
        if parts[0] == "周一至周日" { return appLocalized("merchant.onboarding.everyDay",locale:locale) + " " + String(parts[1]) }
        guard parts[0].hasPrefix("周") else { return value }
        let labels = ["一", "二", "三", "四", "五", "六", "日"]
        let names = [appLocalized("merchant.onboarding.day.0",locale:locale), appLocalized("merchant.onboarding.day.1",locale:locale),
                     appLocalized("merchant.onboarding.day.2",locale:locale), appLocalized("merchant.onboarding.day.3",locale:locale),
                     appLocalized("merchant.onboarding.day.4",locale:locale), appLocalized("merchant.onboarding.day.5",locale:locale),
                     appLocalized("merchant.onboarding.day.6",locale:locale)]
        let days = parts[0].dropFirst().split(separator: "、")
        let indexes = days.compactMap { labels.firstIndex(of: String($0)) }
        guard !days.isEmpty, indexes.count == days.count else { return value }
        return indexes.map { names[$0] }.joined(separator: ", ") + " " + String(parts[1])
    }
    private func reviewRow(_ key: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) { Text(key).font(.caption).foregroundStyle(.secondary); Text(value.isEmpty ? "—" : value) }
    }
    private var identitySection: some View {
        Section("merchant.onboarding.identity.title") {
            switch model.coordinator.identityGate {
            case .registered: Label("merchant.onboarding.identity.registered", systemImage: "checkmark.circle")
            case .checking: ProgressView("merchant.onboarding.identity.checking")
            case .required:
                Text("merchant.onboarding.identity.required").accessibilityIdentifier("merchant.onboarding.identityGate")
                Text("merchant.onboarding.identity.regionalGate").font(.footnote).foregroundStyle(.secondary)
                Button("merchant.onboarding.identity.recheck") { Task { await model.checkIdentity() } }
            case .unchecked, .unavailable:
                Text("merchant.onboarding.identity.unavailable")
                Button("merchant.onboarding.identity.recheck") { Task { await model.checkIdentity() } }
            }
        }
    }
    @ViewBuilder private var submissionSection: some View {
        switch model.coordinator.submission {
        case .acknowledged:
            Section { Text("merchant.onboarding.submitted").accessibilityIdentifier("merchant.onboarding.submitted") }
        case .outcomeUnknown:
            Section { Text("merchant.onboarding.outcomeUnknown").accessibilityIdentifier("merchant.onboarding.outcomeUnknown") }
        case .rejected(let failure):
            Section {
                Text("merchant.onboarding.rejectedByServer")
                if let message = failure.message, !message.isEmpty { Text(message) }
            }
        case .notSent: Section { Text("merchant.onboarding.notSent") }
        case .checking, .submitting: Section { ProgressView("merchant.onboarding.working") }
        default: EmptyView()
        }
    }
    private func statusSection(_ application: MerchantOnboardingApplication) -> some View {
        Section("merchant.onboarding.serverStatus") {
            Text(LocalizedStringKey(application.statusKey)).font(.headline).accessibilityIdentifier("merchant.onboarding.status")
            Text(LocalizedStringKey(application.explanationKey))
            if let reason = application.displayedReason { Text(reason) }
            if !application.name.isEmpty { LabeledContent("merchant.onboarding.name", value: application.name) }
            if !application.createTime.isEmpty { LabeledContent("merchant.onboarding.submittedAt", value: application.createTime) }
            Text("merchant.onboarding.statusDoesNotGrantAccess").font(.footnote).foregroundStyle(.secondary)
        }
    }
    private var refreshButton: some View {
        Button("merchant.onboarding.checkAgain") { Task { await model.load() } }
            .disabled(model.isBusy).accessibilityIdentifier("merchant.onboarding.refresh")
    }
}
