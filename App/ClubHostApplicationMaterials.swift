import SwiftUI
import UIKit

@MainActor final class ClubHostApplicationMaterials: ObservableObject {
    struct Context: Hashable {
        let formID: UUID
        let read: ClubGovernanceReadContext
        let namespace: String
    }
    struct Item: Identifiable { let image: RetainedSelectedImage; var id: UUID { image.id } }
    struct Presentation: Identifiable, Equatable {
        enum Kind: Equatable { case picker, preview(UUID) }
        let id = UUID()
        let context: Context
        let attachment: UUID
        let kind: Kind
    }
    static let maximumCount = 9
    static let maximumBytes = MerchantGalleryBatchLimits.maximumRetainedBytes
    @Published private(set) var items: [Item] = []
    @Published private(set) var presentation: Presentation?
    @Published private(set) var selectionFailed = false
    private(set) var context: Context?
    private(set) var attachment: UUID?
    @Published private(set) var hostVisible = false
    var blocksSubmission: Bool { !items.isEmpty || presentation != nil }
    var remaining: Int { Self.maximumCount - items.count }
    var remainingBytes: Int { Self.maximumBytes - items.reduce(0) { $0 + $1.image.jpeg.count } }

    static func context(formID: UUID, scope: ClubGovernanceScope, identity: ClubReadIdentity?, access: any ClubGovernanceAccess) -> Context {
        .init(formID: formID, read: .init(operation: .hostStatus, scope: scope, identity: identity,
            viewerRevision: 0, authorizationGeneration: access.authorizationGeneration, accessIdentity: ObjectIdentifier(access)),
            namespace: access.storageNamespace)
    }
    func appear(_ value: Context) { hostVisible = true; activate(value) }
    func hide() { hostVisible = false }
    func depart(_ expected: Context, attachment expectedAttachment: UUID) {
        guard context == expected, attachment == expectedAttachment else { return }
        hostVisible = false; retire(expected, attachment: expectedAttachment)
    }
    func activate(_ value: Context) {
        if context != value { retire(); context = value }
        guard hostVisible else { return }
        if attachment == nil { attachment = UUID() }
    }
    func retire(_ expected: Context? = nil, attachment expectedAttachment: UUID? = nil) {
        if let expected, context != expected { return }
        if let expectedAttachment, attachment != expectedAttachment { return }
        presentation = nil; items = []; selectionFailed = false; attachment = nil
    }
    func isCurrent(_ expected: Context, allowed: () -> Bool) -> Bool {
        context == expected && attachment != nil && (hostVisible || presentation != nil) && expected.read.identity?.isSignedIn == true && allowed()
    }
    @discardableResult func open(_ kind: Presentation.Kind, context expected: Context, allowed: () -> Bool) -> Bool {
        guard hostVisible, isCurrent(expected, allowed: allowed), presentation == nil, let attachment else { return false }
        switch kind {
        case .picker: guard remaining > 0, remainingBytes > 0 else { return false }
        case .preview(let id): guard items.contains(where: { $0.id == id }) else { return false }
        }
        selectionFailed = false
        presentation = .init(context: expected, attachment: attachment, kind: kind)
        return true
    }
    func current(_ value: Presentation, allowed: () -> Bool) -> Bool {
        presentation == value && attachment == value.attachment && isCurrent(value.context, allowed: allowed)
    }
    func binding(_ value: Presentation, allowed: @escaping () -> Bool) -> Binding<Presentation?> {
        Binding(get: { self.current(value, allowed: allowed) ? value : nil }, set: { next in
            guard next == nil, self.presentation?.id == value.id else { return }
            self.close(value)
        })
    }
    func close(_ value: Presentation) {
        guard presentation?.id == value.id, attachment == value.attachment else { return }
        presentation = nil
    }
    @discardableResult func accept(_ images: [RetainedSelectedImage]?, for value: Presentation, allowed: () -> Bool) -> Bool {
        guard current(value, allowed: allowed), value.kind == .picker else { return false }
        guard let images else { close(value); return false }
        let ids = items.map(\.id) + images.map(\.id)
        guard images.count <= remaining, Set(ids).count == ids.count,
              images.reduce(0, { $0 + $1.jpeg.count }) <= remainingBytes else {
            fail(value, allowed: allowed); return false
        }
        items.append(contentsOf: images.map { .init(image: $0) }); close(value)
        return !images.isEmpty
    }
    func fail(_ value: Presentation, allowed: () -> Bool) {
        guard current(value, allowed: allowed) else { return }
        selectionFailed = true; close(value)
    }
    @discardableResult func remove(_ id: UUID, context expected: Context, allowed: () -> Bool) -> Bool {
        guard isCurrent(expected, allowed: allowed), presentation == nil, items.contains(where: { $0.id == id }) else { return false }
        items.removeAll { $0.id == id }; return true
    }
}

@MainActor struct ClubHostApplicationMaterialsRows: View {
    @ObservedObject var model: ClubHostApplicationMaterials
    let context: ClubHostApplicationMaterials.Context
    let allowed: () -> Bool
    let changed: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("club.materials.title", tableName: "ClubHostApplicationMaterials").font(.headline)
            Text("club.materials.optional", tableName: "ClubHostApplicationMaterials").font(.footnote)
            Text("club.materials.unavailable", tableName: "ClubHostApplicationMaterials").font(.footnote)
            Button { _ = model.open(.picker, context: context, allowed: allowed) } label: {
                Label { Text("club.materials.select", tableName: "ClubHostApplicationMaterials") } icon: { Image(systemName: "photo.on.rectangle") }
            }.disabled(!model.isCurrent(context, allowed: allowed) || model.remaining == 0 || model.remainingBytes == 0 || model.presentation != nil)
                .accessibilityIdentifier("club.materials.select")
            if model.isCurrent(context, allowed: allowed) {
                ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                    HStack {
                        Button { _ = model.open(.preview(item.id), context: context, allowed: allowed) } label: {
                            if let image = UIImage(data: item.image.jpeg) {
                                Image(uiImage: image).resizable().scaledToFit().frame(width: 64, height: 64)
                            }
                            Text("club.materials.preview \(index + 1)", tableName: "ClubHostApplicationMaterials")
                        }.accessibilityIdentifier("club.materials.preview." + String(index))
                        Spacer()
                        Button(role: .destructive) {
                            if model.remove(item.id, context: context, allowed: allowed) { changed() }
                        } label: { Text("club.materials.remove", tableName: "ClubHostApplicationMaterials") }
                            .accessibilityIdentifier("club.materials.remove." + String(index))
                    }
                }
                if model.blocksSubmission { Text("club.materials.pending", tableName: "ClubHostApplicationMaterials").accessibilityIdentifier("club.materials.pending") }
                if model.selectionFailed { Text("club.materials.selectionFailed", tableName: "ClubHostApplicationMaterials").accessibilityIdentifier("club.materials.selectionFailed") }
            }
        }.buttonStyle(.borderless).accessibilityElement(children: .contain).privacySensitive()
    }
}

/// The normal form, never a recycled row, owns this concrete presentation.
@MainActor struct ClubHostApplicationMaterialsOwner: View {
    @ObservedObject var model: ClubHostApplicationMaterials
    let value: ClubHostApplicationMaterials.Presentation
    let allowed: () -> Bool
    let changed: () -> Void
    var body: some View {
        Color.clear.frame(width: 0, height: 0)
            .sheet(item: model.binding(value, allowed: allowed), onDismiss: { model.close(value) }) { item in
                Group {
                    if model.current(item, allowed: allowed) {
                        switch item.kind {
                        case .picker:
                            ClubHostApplicationMaterialPicker(limit: model.remaining, byteLimit: model.remainingBytes,
                                isCurrent: { model.current(item, allowed: allowed) }) { result in
                                switch result {
                                case .success(let images): if model.accept(images, for: item, allowed: allowed) { changed() }
                                case .failure: model.fail(item, allowed: allowed)
                                }
                            }
                        case .preview(let id):
                            NavigationStack {
                                if let image = model.items.first(where: { $0.id == id }).flatMap({ UIImage(data: $0.image.jpeg) }) {
                                    Image(uiImage: image).resizable().scaledToFit().padding().privacySensitive()
                                        .navigationTitle(Text("club.materials.title", tableName: "ClubHostApplicationMaterials"))
                                        .toolbar { ToolbarItem(placement: .cancellationAction) {
                                            Button { model.close(item) } label: { Text("club.materials.close", tableName: "ClubHostApplicationMaterials") }
                                        } }
                                }
                            }
                        }
                    }
                }
            }
    }
}

/// Only selected Photos items pass through the existing bounded metadata-free decoder.
@MainActor private struct ClubHostApplicationMaterialPicker: UIViewControllerRepresentable {
    let limit: Int
    let byteLimit: Int
    let isCurrent: () -> Bool
    let completion: (Result<[RetainedSelectedImage]?, Error>) -> Void
    func makeUIViewController(context: Context) -> Controller { Controller(limit: limit, byteLimit: byteLimit, isCurrent: isCurrent, completion: completion) }
    func updateUIViewController(_ controller: Controller, context: Context) { if !isCurrent() { controller.stop() } }
    static func dismantleUIViewController(_ controller: Controller, coordinator: ()) { controller.stop() }
    @MainActor final class Controller: UIViewController {
        private let limit: Int
        private let byteLimit: Int
        private let isCurrent: () -> Bool
        private let completion: (Result<[RetainedSelectedImage]?, Error>) -> Void
        private var picker: RetainedNativeImagePicker?
        private var task: Task<Void, Never>?
        private var started = false
        init(limit: Int, byteLimit: Int, isCurrent: @escaping () -> Bool, completion: @escaping (Result<[RetainedSelectedImage]?, Error>) -> Void) {
            self.limit = limit; self.byteLimit = byteLimit; self.isCurrent = isCurrent; self.completion = completion
            super.init(nibName: nil, bundle: nil)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            guard !started, isCurrent() else { return }; started = true
            let picker = RetainedNativeImagePicker(enabled: true, present: { [weak self] view in
                guard let self, self.isCurrent(), self.presentedViewController == nil else { return false }
                self.present(view, animated: true); return true
            }, dismiss: { [weak self] in self?.presentedViewController?.dismiss(animated: true) })
            self.picker = picker
            task = Task { [weak self] in
                guard let self else { return }
                let result: Result<[RetainedSelectedImage]?, Error>
                do { result = .success(try await picker.selectBatch(limit: self.limit, byteLimit: self.byteLimit)) }
                catch { result = .failure(error) }
                guard !Task.isCancelled, self.isCurrent() else { return }
                self.completion(result)
            }
        }
        func stop() { task?.cancel(); task = nil; picker?.cancel(); picker = nil }
    }
}

/// A modal cover keeps the form attached. A real navigation departure drops local bytes.
@MainActor struct ClubHostApplicationMaterialsLifetime: UIViewControllerRepresentable {
    let leave: () -> Void
    func makeUIViewController(context: Context) -> Controller { Controller(leave: leave) }
    func updateUIViewController(_ controller: Controller, context: Context) { controller.leave = leave }
    static func dismantleUIViewController(_ controller: Controller, coordinator: ()) { controller.leave() }
    @MainActor final class Controller: UIViewController {
        var leave: () -> Void
        private var wasAttached = false
        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            if parent != nil { wasAttached = true } else if wasAttached { leave() }
        }
        init(leave: @escaping () -> Void) { self.leave = leave; super.init(nibName: nil, bundle: nil) }
        required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }
        override func viewDidDisappear(_ animated: Bool) {
            super.viewDidDisappear(animated)
            var current: UIViewController? = self
            while let controller = current {
                if controller.isBeingDismissed || controller.isMovingFromParent { leave(); return }
                current = controller.parent
            }
        }
    }
}
