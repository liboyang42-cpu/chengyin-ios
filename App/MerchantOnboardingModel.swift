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
    @Published var confirmation: MerchantOnboardingConfirmation?
    @Published var errorKey: String?
    @Published private(set) var isBusy = false
    @Published private(set) var revision = 0
    private(set) var identity: ProfileReadIdentity?
    private var generation = 0
    init(coordinator: MerchantOnboardingCoordinator) { self.coordinator = coordinator }
    func reset() {
        generation += 1; draft = .init(); step = 1; isEditing = false; selectedImage = nil
        confirmation = nil; errorKey = nil; isBusy = false
        coordinator.synchronizeSession()
        coordinator.leaveScreen() // Fresh presentation cancels any obsolete, unsubmitted confirmation.
        identity = coordinator.identity; revision += 1
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
        guard !isBusy, !coordinator.submission.isLocked else { return }
        do { draft = try .init(reapplying: application); isEditing = true; step = 1; errorKey = nil }
        catch { errorKey = "merchant.onboarding.stateChanged" }
    }
    func next() {
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
    func prepare() {
        guard !isBusy else { return }
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
    func leave() { reset() }
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
