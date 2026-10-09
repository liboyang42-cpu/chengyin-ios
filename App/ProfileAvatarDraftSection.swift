import SwiftUI
import UIKit

/// Optional injection only. No AppSession/composition factory supplies this capability.
@MainActor struct ProfileAvatarDependencies {
    let source: ProfileAvatarUploadClient
    let journal: any ProfileAvatarJournaling
    let pickerHost: RetainedImagePickerHost?
    init(source: ProfileAvatarUploadClient, journal: any ProfileAvatarJournaling, pickerHost: RetainedImagePickerHost? = nil) {
        self.source = source; self.journal = journal; self.pickerHost = pickerHost
    }
}
@MainActor private final class ProfileAvatarPresentation: ObservableObject {
    @Published private(set) var flow: ProfileAvatarFlow?
    @Published private(set) var crop: MerchantImageCropDraft?
    @Published private(set) var preview: RetainedSelectedImage?
    @Published private(set) var revision: UInt64 = 0
    @Published private(set) var selecting = false
    private weak var model: ProfileEditModel?
    private let dependencies: ProfileAvatarDependencies
    private var picker: RetainedNativeImagePicker?
    private var selectionTask: Task<Void, Never>?
    init(model: ProfileEditModel, dependencies: ProfileAvatarDependencies) {
        self.model = model; self.dependencies = dependencies
        model.observeAvatarRetirement { [weak self] in self?.retire() }
    }
    var canOpen: Bool {
        guard flow == nil, dependencies.pickerHost != nil, let model, let target = model.avatarTarget(source: dependencies.source) else { return false }
        return dependencies.source.permitsPicker(target.scope)
    }
    func open() {
        guard canOpen, let model, let target = model.avatarTarget(source: dependencies.source) else { return }
        preview = nil; crop = nil
        flow = ProfileAvatarFlow(target: target, source: dependencies.source, journal: dependencies.journal,
            currentSnapshot: { [weak model] in guard let model, !model.busy, !model.coordinator.isBusy else { return nil }; return model.coordinator.snapshot },
            currentDraft: { [weak model] in model?.draft }, currentRevision: { [weak model] in model?.avatarDraftRevision ?? 0 },
            ownerCurrent: { [weak model] in model?.ownsAvatarScope(target.scope) == true },
            apply: { [weak model, weak self] replacement in model?.stageAvatar(replacement, preview: self?.preview) })
        model.avatarPresentationActive = true; revision &+= 1
    }
    func pick(_ original: ProfileAvatarFlow) {
        guard flow === original, let id = original.beginPicking(), let host = dependencies.pickerHost else { return }
        let source = dependencies.source
        let picker = host.makePicker { [weak original] in
            guard let original else { return false }
            return original.ownsTarget && source.permitsPicker(original.target.scope)
        }
        self.picker = picker; selecting = true
        selectionTask = Task { [weak self, weak original] in
            guard let self, let original else { return }
            let image = try? await picker.select()
            original.endPicking(id)
            guard self.flow === original, original.ownsTarget, !Task.isCancelled else { return }
            self.selecting = false; self.picker = nil; self.selectionTask = nil
            if let image { self.crop = .init(source: image, aspect: .logo) }
            self.revision &+= 1
        }
    }
    func acceptCrop(_ id: UUID, rect: MerchantImageCropRect, flow original: ProfileAvatarFlow) {
        guard flow === original, original.ownsTarget, let crop, crop.id == id,
              let image = try? MerchantImageCropRenderer.render(crop.source, rect: rect), image.width == image.height else { return }
        self.crop = nil; preview = image; original.prepare(image); revision &+= 1
    }
    func cancelCrop() { crop = nil; revision &+= 1 }
    func upload(_ review: ProfileAvatarFlow.Review, flow original: ProfileAvatarFlow) async {
        guard flow === original else { return }; revision &+= 1
        let task = Task { await original.confirm(review) }
        await Task.yield(); revision &+= 1
        await task.value; guard flow === original else { return }; revision &+= 1
    }
    func stage(_ original: ProfileAvatarFlow) {
        guard flow === original else { return }; original.stage(); revision &+= 1
        if original.state == .staged { close(original) }
    }
    func close(_ original: ProfileAvatarFlow) {
        guard flow === original else { return }
        selectionTask?.cancel(); selectionTask = nil; picker?.cancel(); picker = nil
        original.close(); flow = nil; crop = nil; preview = nil; selecting = false
        model?.avatarPresentationActive = false; revision &+= 1
    }
    func retire() { if let flow { close(flow) } }
}

@MainActor struct ProfileAvatarDraftSection: View {
    @ObservedObject var model: ProfileEditModel
    let dependencies: ProfileAvatarDependencies?
    var body: some View {
        if let dependencies { ProfileAvatarEnabledSection(model: model, dependencies: dependencies) }
        else {
            Section("profile.avatar.title") { Text("profile.avatar.unavailable").font(.footnote).foregroundStyle(.secondary) }
        }
    }
}
@MainActor private struct ProfileAvatarEnabledSection: View {
    @ObservedObject var model: ProfileEditModel
    @StateObject private var presentation: ProfileAvatarPresentation
    @Environment(\.scenePhase) private var scenePhase
    @State private var discardID: UUID?
    init(model: ProfileEditModel, dependencies: ProfileAvatarDependencies) {
        self.model = model; _presentation = StateObject(wrappedValue: .init(model: model, dependencies: dependencies))
    }
    private var isPresented: Binding<Bool> {
        let original = presentation.flow
        return .init(get: { scenePhase == .active && presentation.flow === original && original != nil },
                     set: { if !$0, let original { presentation.close(original) } })
    }
    var body: some View {
        Section("profile.avatar.title") {
            if let replacement = model.draft.avatarReplacement {
                if let preview = model.avatarPreview, let image = UIImage(data: preview.jpeg) {
                    Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 120)
                        .accessibilityLabel("profile.avatar.preview")
                }
                Text("profile.avatar.staged").accessibilityIdentifier("profile.avatar.staged")
                Button("profile.avatar.discard", role: .destructive) { discardID = replacement.id }
                    .disabled(model.busy || model.coordinator.isLocked)
            } else {
                Button("profile.avatar.select") { guard scenePhase == .active else { return }; presentation.open() }
                    .disabled(!presentation.canOpen || model.busy || model.coordinator.isLocked || scenePhase != .active)
                    .accessibilityIdentifier("profile.avatar.select")
                Text("profile.avatar.hint").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .confirmationDialog("profile.avatar.discardTitle", isPresented: Binding(get: { discardID != nil }, set: { if !$0 { discardID = nil } }), presenting: discardID) { id in
            Button("profile.avatar.discard", role: .destructive) { model.discardAvatar(id: id); discardID = nil }
            Button("action.cancel", role: .cancel) { discardID = nil }
        }
        .onChange(of: model.avatarLifetimeID) { _, _ in discardID = nil; presentation.retire() }
        .sheet(isPresented: isPresented) {
            if let flow = presentation.flow {
                NavigationStack {
                    Form {
                        if let crop = presentation.crop {
                            ProfileAvatarCropView(draft: crop, confirm: { presentation.acceptCrop($0, rect: $1, flow: flow) }, cancel: presentation.cancelCrop)
                        } else {
                            if let preview = presentation.preview, let image = UIImage(data: preview.jpeg) {
                                Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 240).accessibilityLabel("profile.avatar.preview")
                            }
                            Text("profile.avatar.uploadDisclosure").font(.footnote)
                            if let review = flow.review {
                                Button("profile.avatar.upload") { Task { await presentation.upload(review, flow: flow) } }
                                    .disabled(!flow.ownsTarget).accessibilityIdentifier("profile.avatar.upload")
                                Button("action.cancel") { flow.cancelReview(review); presentation.cancelCrop() }
                            } else if flow.state == .uploaded {
                                Text("profile.avatar.uploaded")
                                Button("profile.avatar.stage") { presentation.stage(flow) }.disabled(!flow.canStage)
                                    .accessibilityIdentifier("profile.avatar.stage")
                            } else if flow.state == .unknown { Text("profile.avatar.unknown") }
                            else if flow.state == .uploading || presentation.selecting { ProgressView("profile.avatar.working") }
                            else {
                                if flow.state == .failed { Text("profile.avatar.failed") }
                                Button("profile.avatar.select") { presentation.pick(flow) }.disabled(!flow.canSelect)
                            }
                        }
                    }
                    .appNavigationTitle("profile.avatar.title")
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("action.done") { presentation.close(flow) } } }
                }
            }
        }
    }
}

/// Actual owner removal retires upload/save leases even if a modal was covering the
/// profile. Merely presenting a picker or review sheet does not dismantle this anchor.
@MainActor struct ProfileAvatarOwnerAnchor: UIViewControllerRepresentable {
    let model: ProfileEditModel
    final class Coordinator {
        weak var model: ProfileEditModel?
        init(_ model: ProfileEditModel) { self.model = model }
    }
    func makeCoordinator() -> Coordinator { Coordinator(model) }
    func makeUIViewController(context: Context) -> UIViewController { UIViewController() }
    func updateUIViewController(_ controller: UIViewController, context: Context) {}
    static func dismantleUIViewController(_ controller: UIViewController, coordinator: Coordinator) { coordinator.model?.retireAvatar() }
}

/// Avatar-specific labels around the existing bounded square-rect and redraw primitives.
@MainActor private struct ProfileAvatarCropView: View {
    let draft: MerchantImageCropDraft
    let confirm: (UUID, MerchantImageCropRect) -> Void
    let cancel: () -> Void
    @State private var horizontal = 0.5
    @State private var vertical = 0.5
    @State private var zoom = 1.0
    private var rect: MerchantImageCropRect? {
        try? .init(sourceWidth: draft.source.width, sourceHeight: draft.source.height, aspect: .logo,
                   horizontal: horizontal, vertical: vertical, zoom: zoom)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("profile.avatar.crop").font(.headline)
            Text("image.crop.localOnly").font(.footnote)
            if let rect, let preview = try? MerchantImageCropRenderer.preview(draft.source, rect: rect) {
                Image(uiImage: preview).resizable().scaledToFit().frame(maxHeight: 240).accessibilityLabel("profile.avatar.preview")
                Text("image.crop.horizontal")
                Slider(value: $horizontal, in: 0...1).accessibilityLabel("image.crop.horizontal")
                Text("image.crop.vertical")
                Slider(value: $vertical, in: 0...1).accessibilityLabel("image.crop.vertical")
                Text("image.crop.zoom")
                Slider(value: $zoom, in: 1...4).accessibilityLabel("image.crop.zoom")
                Button("image.crop.confirm") { confirm(draft.id, rect) }
            } else { Text("profile.avatar.failed") }
            Button("action.cancel", role: .cancel, action: cancel)
        }
    }
}
