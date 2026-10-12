import SwiftUI
import PhotosUI
import UIKit

@MainActor struct MerchantOnboardingBrandImagesEditor: View {
    @ObservedObject var model: MerchantOnboardingModel
    @Binding var pickerPresented: Bool
    @Binding var uploadConfirmationPresented: Bool
    @State private var photo: PhotosPickerItem?
    @State private var pickerIdentity: ProfileReadIdentity?
    @State private var pickerDraft: MerchantOnboardingDraft?
    @State private var uploadID: UUID?
    var body: some View {
        let displayed = model.draft.brandImages
        Section("merchant.onboardingBrand.title") {
            Text("merchant.onboardingBrand.hint").font(.footnote)
            if model.draft.brandImagesSourceUnavailable {
                Text("merchant.onboardingBrand.sourceUnavailable").foregroundStyle(.secondary)
            }
            MerchantOnboardingBrandImageRows(images: model.draft.brandImages, canRemove: model.canEditBrandImages && model.selectedBrandImage == nil,
                remove: { model.removeBrandImage(at: $0, expected: displayed) })
            if let image = model.selectedBrandImage {
                if let preview = UIImage(data: image.data) {
                    Image(uiImage: preview).resizable().scaledToFit().frame(maxHeight: 180)
                        .accessibilityLabel(Text("merchant.onboardingBrand.selected"))
                }
                Text("merchant.onboardingBrand.selected").accessibilityIdentifier("merchant.onboardingBrand.selected")
                Button("merchant.onboardingBrand.upload") { uploadID = model.selectedBrandImageID; uploadConfirmationPresented = uploadID != nil }
                    .disabled(!model.canUploadBrandImage).accessibilityIdentifier("merchant.onboardingBrand.upload")
                if model.canEditBrandImages && !model.canUploadBrandImage { Text("merchant.onboardingBrand.changed") }
                Button("merchant.onboardingBrand.discard", role: .destructive) { model.discardBrandImage() }
                    .disabled(model.isBusy).accessibilityIdentifier("merchant.onboardingBrand.discard")
            }
            Button("merchant.onboardingBrand.add") { pickerIdentity = model.identity; pickerDraft = model.draft; pickerPresented = true }
                .disabled(!model.canAddBrandImage).accessibilityIdentifier("merchant.onboardingBrand.add")
        }
        .photosPicker(isPresented: $pickerPresented, selection: $photo, matching: .images, preferredItemEncoding: .compatible)
        .onChange(of: photo) { _, selected in
            guard let selected else { return }
            Task {
                guard pickerIdentity != nil, pickerIdentity == model.coordinator.identity, pickerDraft == model.draft else { photo = nil; return }
                await model.selectBrandImage(selected); photo = nil
            }
        }
        .confirmationDialog("merchant.onboardingBrand.uploadTitle", isPresented: $uploadConfirmationPresented, titleVisibility: .visible) {
            Button("merchant.onboardingBrand.upload") { if let uploadID { Task { await model.uploadSelectedBrandImage(expectedID: uploadID) } } }
            Button("action.cancel", role: .cancel) { }
        } message: { Text("merchant.onboardingBrand.uploadMessage") }
        .onChange(of: model.identity) { _, _ in photo = nil; pickerPresented = false; uploadConfirmationPresented = false }
    }
}
@MainActor struct MerchantOnboardingBrandImageRows: View {
    let images: MerchantOnboardingBrandImages?
    var canRemove = false
    var remove: ((Int) -> Void)? = nil
    var body: some View {
        ForEach(Array((images?.urls ?? []).enumerated()), id: \.offset) { index, url in
            VStack(alignment: .leading, spacing: 8) {
                QuestifyImageEntityCard(imageSource: url, title: String(index + 1), fallbackTitle: "merchant.onboardingBrand.image", minimumHeight: 120) { EmptyView() }
                    .accessibilityIdentifier("merchant.onboardingBrand.image.\(index)")
                if let remove {
                    Button("merchant.onboardingBrand.remove", role: .destructive) { remove(index) }
                        .disabled(!canRemove).accessibilityIdentifier("merchant.onboardingBrand.remove.\(index)")
                }
            }
        }
    }
}
