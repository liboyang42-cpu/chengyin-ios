import SwiftUI
import UIKit
import Observation

extension ProfileLocalCoverOwner {
    /// Reconstruct only the existing app's validated local storage identity; never a network grant.
    static func make(accountID: Int, configuration: RegionalConfiguration?,
                     build: RegionalLaunchConfiguration.BuildMetadata = .current) -> Self? {
        guard let configuration, build.market == configuration.market.rawValue,
              build.baseURL == configuration.apiConfiguration?.baseURL.absoluteString,
              let scope = try? RegionalSessionStorageScope(configuration: configuration, bundleIdentifier: build.bundleIdentifier, realm: build.realm) else { return nil }
        return try? .init(accountID: accountID, namespace: scope.service)
    }
}

@MainActor @Observable final class ProfileLocalCoverModel {
    let controller: ProfileLocalCoverController
    let pickerHost = RetainedImagePickerHost()
    var crop: MerchantImageCropDraft?
    var isPresented = false
    var selecting = false
    var selectionError = false
    private var generation: UInt64 = 0
    @ObservationIgnored private var picker: RetainedNativeImagePicker?
    @ObservationIgnored private var task: Task<Void, Never>?
#if DEBUG
    /// Only the synthetic fixture installs this bounded event sink.
    @ObservationIgnored var diagnosticEvent: ((String) -> Void)?
#endif
    init(context: ProfileLocalCoverContext, store: any ProfileLocalCoverStoring,
         current: @escaping () -> ProfileLocalCoverContext?) {
        controller = .init(context: context, store: store, current: current)
    }
    func open() {
        guard controller.canEdit else { return }
        selectionError = false; crop = nil; isPresented = true
    }
    func pick() {
        guard isPresented, controller.canEdit, !selecting, controller.review == nil else { return }
        generation &+= 1; let run = generation
        let picker = pickerHost.makePicker { [weak self] in
            self?.isPresented == true && self?.controller.canEdit == true
        }
        self.picker = picker; selecting = true; selectionError = false
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let selected = try await picker.select()
                guard !Task.isCancelled, run == self.generation, self.isPresented, self.controller.canEdit else { return }
                if let selected { self.crop = .init(source: selected, aspect: .gallery) }
            } catch {
                if !Task.isCancelled, run == self.generation, self.isPresented, self.controller.canEdit { self.selectionError = true }
            }
            if run == self.generation { self.selecting = false; self.picker = nil; self.task = nil }
        }
    }
    func acceptCrop(id: UUID, rect: MerchantImageCropRect) {
        guard isPresented, controller.canEdit, let crop, crop.id == id else { return }
        do {
            let image = try MerchantImageCropRenderer.render(crop.source, rect: rect)
            try ProfileLocalCoverController.validate(image)
            controller.prepare(image); self.crop = nil
        } catch { selectionError = true }
    }
    func cancelCrop(id: UUID) {
        guard isPresented, controller.canEdit, crop?.id == id else { return }
        crop = nil
    }
    func confirm(_ review: ProfileLocalCoverReview) {
        guard isPresented, !selecting else { return }
        controller.confirm(review)
        if controller.review == nil, controller.messageKey == "profile.localCover.saved" { close() }
    }
    func close() {
#if DEBUG
        diagnosticEvent?("model.close.begin")
#endif
        generation &+= 1; task?.cancel(); task = nil; picker?.cancel(); picker = nil
        selecting = false; crop = nil; selectionError = false; isPresented = false
        if let review = controller.review { controller.cancel(review) }
#if DEBUG
        diagnosticEvent?("model.close.end")
#endif
    }
    func retire() { close(); controller.retire() }
}

@MainActor struct ProfileLocalCoverSection: View {
    let owner: ProfileLocalCoverOwner?
    let reader: any SocialAccountReading
    var isCurrent: @MainActor () -> Bool = { true }
    var store: (any ProfileLocalCoverStoring)? = nil
    var body: some View {
        if let owner, reader.identity.accountID == owner.accountID, isCurrent() {
            let context = ProfileLocalCoverContext(owner: owner, reader: reader)
            ProfileLocalCoverEnabledSection(context: context, store: store ?? ProfileLocalCoverFileStore(), current: {
                guard isCurrent() else { return nil }
                return .init(owner: owner, reader: reader)
            }).id(context)
        }
    }
}

@MainActor struct ProfileLocalCoverEnabledSection: View {
    @State private var model: ProfileLocalCoverModel
    @Environment(\.scenePhase) private var scenePhase
    init(model: ProfileLocalCoverModel) { _model = State(initialValue: model) }
    init(context: ProfileLocalCoverContext, store: any ProfileLocalCoverStoring, current: @escaping () -> ProfileLocalCoverContext?) {
        _model = State(initialValue: ProfileLocalCoverModel(context: context, store: store, current: current))
    }
    var body: some View {
        Section("profile.localCover.title") {
            if model.controller.ownsContext {
                cover(model.controller.saved)
                Text("profile.localCover.deviceOnly").font(.footnote).foregroundStyle(.secondary)
                if let message = model.controller.messageKey {
                    Text(LocalizedStringKey(message)).accessibilityIdentifier("profile.localCover.message")
                }
                Button("profile.localCover.edit") { model.open() }
                    .disabled(!model.controller.canEdit || scenePhase != .active)
                    .accessibilityIdentifier("profile.localCover.edit")
                if !model.controller.loaded || model.controller.messageKey == "profile.localCover.changed" {
                    Button("profile.localCover.reload") { model.controller.load() }
                        .accessibilityIdentifier("profile.localCover.reload")
                }
            }
        }
        .task {
#if DEBUG
            model.diagnosticEvent?("section.task.before-load")
#endif
            model.controller.load()
#if DEBUG
            model.diagnosticEvent?("section.task.after-load")
#endif
        }
        .sheet(isPresented: Binding(get: { model.isPresented && model.controller.ownsContext }, set: { if !$0 {
#if DEBUG
            model.diagnosticEvent?("sheet.binding.false")
#endif
            model.close()
        } })) {
            editor
        }
        .onChange(of: scenePhase) { _, value in
#if DEBUG
            model.diagnosticEvent?("section.scenePhase.\(String(describing: value))")
#endif
            if value != .active { model.close() }
        }
        .onDisappear {
#if DEBUG
            model.diagnosticEvent?("section.owner.disappear.before-retire")
#endif
            model.retire()
#if DEBUG
            model.diagnosticEvent?("section.owner.disappear.after-retire")
#endif
        }
    }
    private var editor: some View {
        NavigationStack {
            Form {
                Section { Text("profile.localCover.deviceOnly").font(.footnote) }
                if let crop = model.crop {
                    Section {
                        ProfileLocalCoverCropView(draft: crop, confirm: model.acceptCrop, cancel: { model.cancelCrop(id: crop.id) },
                            isCurrent: { model.isPresented && model.controller.canEdit && model.crop?.id == crop.id })
                            .id(crop.id)
                    }
                } else if let review = model.controller.review {
                    Section {
                        cover(review.image)
                        Text(LocalizedStringKey(review.image == nil ? "profile.localCover.restoreReview" : "profile.localCover.saveReview"))
                        if let message = model.controller.messageKey { Text(LocalizedStringKey(message)) }
                        Button(LocalizedStringKey(review.image == nil ? "profile.localCover.restoreConfirm" : "profile.localCover.save"), role: review.image == nil ? .destructive : nil) { model.confirm(review) }
                            .disabled(!model.controller.canEdit)
                            .accessibilityIdentifier("profile.localCover.confirm")
                        Button("action.cancel", role: .cancel) { model.controller.cancel(review) }
                            .accessibilityIdentifier("profile.localCover.cancelReview")
                    }
                } else {
                    Section {
                        cover(model.controller.saved)
                        if model.selecting { ProgressView("profile.localCover.selecting") }
                        if model.selectionError { Text("profile.localCover.invalid") }
                        Button("profile.localCover.choose") { model.pick() }
                            .disabled(model.selecting || !model.controller.canEdit)
                            .accessibilityIdentifier("profile.localCover.choose")
                        if model.controller.saved != nil {
                            Button("profile.localCover.restore", role: .destructive) { model.controller.prepareDefault() }
                                .disabled(model.selecting || !model.controller.canEdit)
                                .accessibilityIdentifier("profile.localCover.restore")
                        }
                    }
                }
            }
            .background(RetainedImagePresenterHost(host: model.pickerHost).frame(width: 0, height: 0))
            .appNavigationTitle("profile.localCover.title")
            .toolbar { ToolbarItem(placement: .cancellationAction) {
                Button("action.close") {
#if DEBUG
                    model.diagnosticEvent?("editor.close.tap")
#endif
                    model.close()
                }.accessibilityIdentifier("profile.localCover.close")
            } }
        }
#if DEBUG
        .onAppear { model.diagnosticEvent?("editor.appear") }
        .onDisappear { model.diagnosticEvent?("editor.disappear") }
#endif
    }
    @ViewBuilder private func cover(_ selected: RetainedSelectedImage?) -> some View {
        if let selected {
            if let image = UIImage(data: selected.jpeg), image.imageOrientation == .up, let pixels = image.cgImage,
               pixels.width == selected.width, pixels.height == selected.height {
                Image(uiImage: image).resizable().aspectRatio(16.0 / 9.0, contentMode: .fit)
                    .accessibilityLabel("profile.localCover.preview").accessibilityIdentifier("profile.localCover.preview")
            } else { Text("profile.localCover.invalid") }
        } else {
            ZStack {
                Color.secondary.opacity(0.12)
                Label("profile.localCover.default", systemImage: "photo")
            }.aspectRatio(16.0 / 9.0, contentMode: .fit).accessibilityIdentifier("profile.localCover.default")
        }
    }
}

@MainActor private struct ProfileLocalCoverCropView: View {
    let draft: MerchantImageCropDraft
    let confirm: (UUID, MerchantImageCropRect) -> Void
    let cancel: () -> Void
    let isCurrent: () -> Bool
    @State private var position = ProfileCoverCropPosition()
    private var rect: MerchantImageCropRect? {
        try? position.rect(sourceWidth: draft.source.width, sourceHeight: draft.source.height)
    }
    var body: some View {
        VStack(alignment: .leading) {
            Text("profile.localCover.crop")
            if let rect {
                ProfileCoverGesturePreview(draftID: draft.id, source: draft.source, position: $position, isCurrent: isCurrent)
                    .aspectRatio(16.0 / 9.0, contentMode: .fit).frame(maxHeight: 240)
                Text("profile.localCover.gestureHint").font(.footnote).foregroundStyle(.secondary)
                Slider(value: $position.horizontal, in: 0...1).accessibilityLabel("image.crop.horizontal")
                Slider(value: $position.vertical, in: 0...1).accessibilityLabel("image.crop.vertical")
                Slider(value: $position.zoom, in: 1...4).accessibilityLabel("image.crop.zoom")
                Button("image.crop.confirm") { guard isCurrent() else { return }; confirm(draft.id, rect) }
                    .accessibilityIdentifier("profile.localCover.cropConfirm")
            }
            Button("action.cancel", role: .cancel, action: cancel).accessibilityIdentifier("profile.localCover.cropCancel")
        }
    }
}
