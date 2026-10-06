import SwiftUI
import UIKit

@MainActor final class OwnedTopicCoverImagePresentation: ObservableObject {
    struct Presentation: Identifiable {
        let flow: OwnedTopicCoverImageFlow
        var id: UUID { flow.id }
    }
    @Published private(set) var presentation: Presentation?
    func open(asset: OwnedTopicCoverAsset, session: ProjectEditSession, source: any OwnedTopicCoverServing, parentCurrent: @escaping () -> Bool) {
        guard presentation == nil, parentCurrent(), source.permits(.readAsset, session: session) else { return }
        let target = UUID()
        activeTarget = target
        let flow = OwnedTopicCoverImageFlow(asset: asset, session: session, source: source, stillPresented: { [weak self] in
            self?.activeTarget == target && parentCurrent()
        })
        presentation = .init(flow: flow)
    }
    private var activeTarget: UUID?
    func close(_ original: Presentation) {
        original.flow.close(); guard presentation?.id == original.id else { return }
        presentation = nil; activeTarget = nil
    }
    func retire() { if let original = presentation { close(original) } }
    func binding(_ original: Presentation?) -> Binding<Presentation?> {
        .init(get: { guard let original, self.presentation?.id == original.id, original.flow.isCurrent else { return nil }; return original }, set: { next in
            guard next == nil, let original else { return }; self.close(original)
        })
    }
}

@MainActor private final class OwnedTopicCoverImageModel: ObservableObject {
    let flow: OwnedTopicCoverImageFlow
    @Published private(set) var image: UIImage?
    @Published private(set) var revision = 0
    @Published private(set) var invalidImage = false
    init(flow: OwnedTopicCoverImageFlow) { self.flow = flow }
    func load() async {
        image = nil; invalidImage = false; revision += 1
        await flow.load()
        guard flow.isCurrent else { close(); return }
        if case .ready(let exactBytes) = flow.state {
            do {
                // Client verified SHA against exact server asset first. Rendering uses a fresh bounded decode.
                let safe = try RetainedImageSanitizer.sanitize(exactBytes)
                guard flow.isCurrent, !Task.isCancelled else { close(); return }
                image = UIImage(data: safe.jpeg); invalidImage = image == nil
            } catch { invalidImage = true }
        }
        revision += 1
    }
    func close() { flow.close(); image = nil; revision += 1 }
}

@MainActor struct OwnedTopicCoverImageView: View {
    let original: OwnedTopicCoverImagePresentation.Presentation
    let close: () -> Void
    @StateObject private var model: OwnedTopicCoverImageModel
    @Environment(\.locale) private var locale
    init(original: OwnedTopicCoverImagePresentation.Presentation, close: @escaping () -> Void) {
        self.original = original; self.close = close; _model = StateObject(wrappedValue: .init(flow: original.flow))
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(String(localized: LocalizedStringResource("ownedCover.authorImageScope", defaultValue: "Only this account can read this selected asset. This image is not a player grant or a publication receipt.", locale: locale)))
                        .accessibilityIdentifier("ownedCover.image.scope")
                    if original.flow.isCurrent, let image = model.image {
                        Image(uiImage: image).resizable().scaledToFit()
                            .accessibilityLabel(String(localized: LocalizedStringResource("ownedCover.authorImage", defaultValue: "Verified selected cover", locale: locale)))
                            .accessibilityIdentifier("ownedCover.image.content")
                    } else if original.flow.state == .loading || original.flow.state == .idle {
                        ProgressView().accessibilityIdentifier("ownedCover.image.loading")
                    } else {
                        Text(String(localized: LocalizedStringResource("ownedCover.imageUnavailable", defaultValue: "This exact image is unavailable. No other version or image URL will be substituted.", locale: locale)))
                            .accessibilityIdentifier("ownedCover.image.unavailable")
                        if original.flow.isCurrent {
                            Button(String(localized: LocalizedStringResource("ownedCover.retryImage", defaultValue: "Read this exact image again", locale: locale))) { Task { await model.load() } }
                                .buttonStyle(.borderless).accessibilityIdentifier("ownedCover.image.retry")
                        }
                    }
                    Text(verbatim: original.flow.asset.assetID).textSelection(.enabled).accessibilityIdentifier("ownedCover.image.asset")
                    Text(verbatim: original.flow.asset.sourceVersion).textSelection(.enabled).accessibilityIdentifier("ownedCover.image.version")
                }.padding()
            }
            .navigationTitle(String(localized: LocalizedStringResource("ownedCover.imageTitle", defaultValue: "Selected cover image", locale: locale)))
            .toolbar { ToolbarItem(placement: .cancellationAction) {
                Button(String(localized: LocalizedStringResource("ownedCover.close", defaultValue: "Close", locale: locale))) { model.close(); close() }
                    .accessibilityIdentifier("ownedCover.image.close")
            } }
        }
        .task { await model.load() }
        .onDisappear { model.close(); close() }
    }
}
