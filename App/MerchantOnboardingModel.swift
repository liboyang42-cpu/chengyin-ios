import SwiftUI
import PhotosUI
import UIKit

/// AppSession can adopt this without deriving merchant permission from entry intent.
@MainActor
protocol MerchantOnboardingObserving: ObservableObject {
    var isConfigured: Bool { get }
    var isSignedIn: Bool { get }
    var sessionRevision: UInt64 { get }
}

@MainActor
final class MerchantOnboardingModel: ObservableObject {
    let coordinator: MerchantOnboardingCoordinator
    @Published var draft = MerchantOnboardingDraft()
    @Published var step = 1
    @Published var isEditing = false
    @Published var selectedImage: MerchantOnboardingImage?
    @Published private(set) var selectedBrandImage: MerchantOnboardingImage?
    @Published private(set) var selectedBrandImageID: UUID?
    private var selectedBrandDraft: MerchantOnboardingDraft?
    @Published var confirmation: MerchantOnboardingConfirmation?
    @Published var errorKey: String?
    @Published private(set) var isBusy = false
    @Published private(set) var revision = 0
    private(set) var identity: ProfileReadIdentity?
    private var generation = 0
#if DEBUG
    private let fixtureDiagnostics = MerchantOnboardingFixtureDiagnostics.current
#endif
    init(coordinator: MerchantOnboardingCoordinator) { self.coordinator = coordinator }
    func reset() {
        generation += 1; draft = .init(); step = 1; isEditing = false; selectedImage = nil
        confirmation = nil; errorKey = nil; isBusy = false
        selectedBrandImage = nil; selectedBrandImageID = nil; selectedBrandDraft = nil
        coordinator.synchronizeSession()
        coordinator.leaveScreen() // Fresh presentation cancels any obsolete, unsubmitted confirmation.
        identity = coordinator.identity; revision += 1
#if DEBUG
        fixtureDiagnostics?.record(.reset, busy: isBusy, locked: coordinator.submission.isLocked, editing: isEditing, step: step)
#endif
    }
    func load() async {
        guard !isBusy else { return }
        let request = generation
        isBusy = true; errorKey = nil
        await coordinator.load()
        guard request == generation, identity == coordinator.identity else { return }
        isBusy = false; revision += 1
    }
    func checkIdentity() async {
        guard !isBusy else { return }
        let request = generation
        isBusy = true
        await coordinator.checkIdentity()
        guard request == generation, identity == coordinator.identity else { return }
        isBusy = false; revision += 1
    }
    func reapply(_ application: MerchantOnboardingApplication) {
#if DEBUG
        fixtureDiagnostics?.record(.reapplyEntered, busy: isBusy, locked: coordinator.submission.isLocked, editing: isEditing, step: step)
#endif
#if DEBUG
        if isBusy { fixtureDiagnostics?.record(.reapplyBusy, busy: isBusy, locked: coordinator.submission.isLocked, editing: isEditing, step: step) }
        else if coordinator.submission.isLocked { fixtureDiagnostics?.record(.reapplyLocked, busy: isBusy, locked: true, editing: isEditing, step: step) }
#endif
        guard !isBusy, !coordinator.submission.isLocked else { return }
        do {
            draft = try .init(reapplying: application); isEditing = true; step = 1; errorKey = nil
            selectedBrandImage = nil; selectedBrandImageID = nil; selectedBrandDraft = nil
#if DEBUG
        fixtureDiagnostics?.record(.reapplyEdited, busy: isBusy, locked: coordinator.submission.isLocked, editing: isEditing, step: step)
#endif
        } catch {
            errorKey = "merchant.onboarding.stateChanged"
#if DEBUG
        fixtureDiagnostics?.record(.reapplyInvalid, busy: isBusy, locked: coordinator.submission.isLocked, editing: isEditing, step: step)
#endif
        }
    }
    func next() {
        if step == 3, selectedBrandImage != nil { errorKey = "merchant.onboardingBrand.uploadFirst"; return }
        if step == 3, selectedImage != nil { errorKey = "merchant.onboarding.uploadSelectedFirst"; return }
        errorKey = draft.blocker(step: step)
        guard errorKey == nil else { return }
        step = min(4, step + 1)
    }
    func select(_ item: PhotosPickerItem) async {
        guard !isBusy, coordinator.identityGate == .registered else { return }
        let request = generation, expectedIdentity = identity
        selectedImage = nil; isBusy = true; errorKey = nil
        do {
            let image = try await MerchantOnboardingPhotoAdapter.load(item)
            guard request == generation, expectedIdentity == coordinator.identity, !Task.isCancelled else { return }
            selectedImage = image
        } catch {
            guard request == generation, expectedIdentity == coordinator.identity else { return }
            errorKey = "merchant.onboarding.photoFailed"
        }
        guard request == generation else { return }
        isBusy = false
    }
    struct LicenseRemoval: Identifiable {
        let id = UUID()
        fileprivate let identity: ProfileReadIdentity
        fileprivate let generation: Int
        fileprivate let revision: Int
        fileprivate let draft: MerchantOnboardingDraft
    }
    private var pendingLicenseRemovalID: UUID?
    var canRemoveLicense: Bool {
        guard !isBusy, !coordinator.isUploading, identity != nil, identity == coordinator.identity,
              coordinator.isConfigured, coordinator.identityGate == .registered,
              !coordinator.submission.isLocked, confirmation == nil,
              selectedImage == nil, selectedBrandImage == nil, draft.license != nil else { return false }
        switch coordinator.loadState {
        case .loaded(.none): return true
        case .loaded(.application(let application)): return isEditing && application.canReapply
        default: return false
        }
    }
    func prepareLicenseRemoval() -> LicenseRemoval? {
        guard canRemoveLicense, let identity else { return nil }
        let request = LicenseRemoval(identity: identity, generation: generation, revision: revision, draft: draft)
        pendingLicenseRemovalID = request.id
        return request
    }
    func cancelLicenseRemoval(_ request: LicenseRemoval? = nil) {
        if request == nil || pendingLicenseRemovalID == request?.id { pendingLicenseRemovalID = nil }
    }
    @discardableResult func removeLicense(_ request: LicenseRemoval) -> Bool {
        guard pendingLicenseRemovalID == request.id else { return false }
        pendingLicenseRemovalID = nil
        guard canRemoveLicense, request.identity == identity, request.generation == generation,
              request.revision == revision, request.draft == draft else { return false }
        // Local draft only. Uploaded files remain on the server; replacement uses existing upload flow.
        draft.license = nil; errorKey = draft.blocker(step: 3); revision += 1
        return true
    }
    func uploadSelected() async {
        guard !isBusy, let selectedImage, let identity else { return }
        let request = generation
        isBusy = true; errorKey = nil
        do {
            let license = try await coordinator.uploadLicense(selectedImage, expectedIdentity: identity)
            guard request == generation, identity == coordinator.identity else { return }
            draft.license = license; self.selectedImage = nil
        } catch {
            guard request == generation, identity == coordinator.identity else { return }
            // A timed-out upload may exist remotely. Never fabricate a URL or silently repeat it.
            errorKey = "merchant.onboarding.uploadFailed"
        }
        guard request == generation else { return }
        isBusy = false; revision += 1
    }
    var canEditBrandImages: Bool {
        !isBusy && identity != nil && identity == coordinator.identity &&
        coordinator.identityGate == .registered && !coordinator.submission.isLocked &&
        !draft.brandImagesSourceUnavailable
    }
    var canUploadBrandImage: Bool {
        canEditBrandImages && selectedBrandImage != nil && selectedBrandImageID != nil && selectedBrandDraft == draft
    }
    var canAddBrandImage: Bool {
        canEditBrandImages && selectedBrandImage == nil && (draft.brandImages?.urls.count ?? 0) < MerchantOnboardingBrandImages.limit
    }
    func selectBrandImage(_ item: PhotosPickerItem) async {
        await selectBrandImage(load: { try await MerchantOnboardingPhotoAdapter.load(item) })
    }
    /// Loader injection is local-only; the real picker uses the existing metadata-stripping adapter.
    func selectBrandImage(load: () async throws -> MerchantOnboardingImage) async {
        guard canAddBrandImage else { return }
        let request = generation, original = draft, expectedIdentity = identity
        isBusy = true; errorKey = nil
        defer { if request == generation { isBusy = false; revision += 1 } }
        do {
            let image = try await load()
            guard request == generation, expectedIdentity == coordinator.identity, draft == original,
                  !coordinator.submission.isLocked, coordinator.identityGate == .registered, !Task.isCancelled else { return }
            selectedBrandImage = image; selectedBrandImageID = UUID(); selectedBrandDraft = original
        } catch {
            if request == generation, expectedIdentity == coordinator.identity { errorKey = "merchant.onboarding.photoFailed" }
        }
    }
    func discardBrandImage() {
        guard !isBusy else { return }; selectedBrandImage = nil; selectedBrandImageID = nil; selectedBrandDraft = nil; errorKey = nil
    }
    func removeBrandImage(at index: Int, expected: MerchantOnboardingBrandImages?) {
        guard canEditBrandImages, selectedBrandImage == nil, expected == draft.brandImages, var images = draft.brandImages else { return }
        do { try images.remove(at: index); draft.brandImages = images; errorKey = nil }
        catch { errorKey = "merchant.onboardingBrand.changed" }
    }
    func uploadSelectedBrandImage(expectedID: UUID) async {
        guard canEditBrandImages, selectedBrandImageID == expectedID, let image = selectedBrandImage, let identity,
              selectedBrandDraft == draft, (draft.brandImages?.urls.count ?? 0) < MerchantOnboardingBrandImages.limit else { return }
        let request = generation, original = draft
        isBusy = true; errorKey = nil
        defer { if request == generation { isBusy = false; revision += 1 } }
        do {
            // Existing shared image transport and eligibility checks. This call returns
            // a URL only; it does not assign the business license or submit a form.
            let returned = try await coordinator.uploadLicense(image, expectedIdentity: identity)
            guard request == generation, identity == coordinator.identity, draft == original, !Task.isCancelled else { return }
            var images = try draft.brandImages ?? MerchantOnboardingBrandImages()
            try images.append(serverURL: returned.url)
            draft.brandImages = images; selectedBrandImage = nil; selectedBrandImageID = nil; selectedBrandDraft = nil
        } catch {
            guard request == generation, identity == coordinator.identity else { return }
            // Do not retry an upload automatically: a timed-out file may exist remotely.
            errorKey = "merchant.onboardingBrand.uploadFailed"
        }
    }
    func prepare() {
        guard !isBusy else { return }
        guard selectedBrandImage == nil else { errorKey = "merchant.onboardingBrand.uploadFirst"; return }
        errorKey = draft.blocker()
        guard errorKey == nil else { return }
        do { confirmation = try coordinator.prepare(draft); revision += 1 }
        catch { errorKey = "merchant.onboarding.stateChanged" }
    }
    func cancelConfirmation() {
        if let confirmation { coordinator.cancel(confirmation) }
        confirmation = nil; revision += 1
    }
    func submitConfirmed() {
        guard !isBusy, let confirmation else { return }
        let request = generation
        // Synchronous clearing prevents dialog dismissal from cancelling a confirmed action.
        isBusy = true; self.confirmation = nil; selectedImage = nil
        selectedBrandImage = nil; selectedBrandImageID = nil; selectedBrandDraft = nil
        Task {
            await coordinator.confirm(confirmation)
            guard request == generation, identity == coordinator.identity else { return }
            isBusy = false
            if coordinator.submission == .acknowledged || coordinator.submission == .outcomeUnknown {
                draft = .init(); isEditing = false
            }
            revision += 1
        }
    }
    func leave() {
#if DEBUG
        fixtureDiagnostics?.record(.leave, busy: isBusy, locked: coordinator.submission.isLocked, editing: isEditing, step: step)
#endif
        reset()
    }
}

/// System picker uses explicit selected-item access; no PHPhotoLibrary authorization request.
/// Decode only after selection, re-render to remove metadata, keep all bytes in memory.
@MainActor
private enum MerchantOnboardingPhotoAdapter {
    static func load(_ item: PhotosPickerItem) async throws -> MerchantOnboardingImage {
        guard let bytes = try await item.loadTransferable(type: Data.self),
              bytes.count <= MerchantOnboardingImage.maximumBytes,
              let image = UIImage(data: bytes), image.size.width > 0, image.size.height > 0 else {
            throw APIError.invalidRequest
        }
        try Task.checkCancellation()
        let ratio = min(1, 4096 / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * ratio, height: image.size.height * ratio)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let sanitized = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill(); context.fill(CGRect(origin: .zero, size: size))
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let jpeg = sanitized.jpegData(compressionQuality: 0.92) else { throw APIError.invalidRequest }
        return try MerchantOnboardingImage(jpegData: jpeg)
    }
}
