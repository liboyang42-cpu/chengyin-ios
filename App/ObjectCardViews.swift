import SwiftUI
import ImageIO

/// Host must observe the session revision and mount this destination with .id(reader.scope).
/// Both live reader and media loader default to unconfigured in host integration.
@MainActor struct ObjectCardsView: View {
    let reader: any ObjectCardReading
    var media: (any ObjectCardImageLoading)? = nil
    @State private var model = ObjectCardCollectionModel()
    private var scope: UUID { reader.scope }
    var body: some View {
        List {
            if !reader.isAuthenticated { Text("objects.login") }
            else if !reader.isConfigured { Text("objects.disabled") }
            else {
                Section {
                    Menu {
                        ForEach(ObjectCardCategory.allCases) { category in
                            Button(LocalizedStringKey(category.localizationKey)) { Task { await model.load(category: category, reader: reader) } }
                                .accessibilityIdentifier("objects.category.\(category.localizationKey)")
                        }
                    } label: { Label(LocalizedStringKey(model.category.localizationKey), systemImage: "line.3.horizontal.decrease.circle") }
                        .disabled(model.loading).accessibilityIdentifier("objects.filter")
                    Text("objects.limit").font(.caption).foregroundStyle(.secondary)
                    if model.loading { ProgressView("objects.loading") }
                    if model.failed {
                        Text(model.collection == nil ? "objects.failed" : "objects.filterFailed")
                            .accessibilityIdentifier("objects.failed")
                        Button("objects.retry") { Task { await model.load(category: model.category, reader: reader) } }
                    }
                }
                if model.loadedScope == scope, let collection = model.collection {
                    Section {
                        LabeledContent("objects.total", value: collection.total.formatted())
                        if collection.cards.isEmpty { Text("objects.empty").accessibilityIdentifier("objects.empty") }
                        // Preserve duplicate source rows safely rather than accidentally conflating IDs.
                        ForEach(Array(collection.cards.enumerated()), id: \.offset) { _, card in
                            let capturedScope = model.loadedScope ?? scope
                            NavigationLink {
                                ObjectCardDetailView(card: card, reader: reader, expectedScope: capturedScope, media: media)
                            } label: {
                                QuestifyImageEntityCard(imageSource: nil, title: card.title, subtitle: card.caption,
                                    fallbackTitle: "objects.item", minimumHeight: 210) {
                                    Text(verbatim: card.category)
                                    if card.generating { Label("objects.generating", systemImage: "hourglass") }
                                    if !card.place.isEmpty { Text(verbatim: card.place) }
                                }
                                .overlay(alignment: .topLeading) {
                                    ObjectCardArtwork(url: card.thumbnail, label: card.title, media: media,
                                        expectedScope: capturedScope, currentScope: { reader.scope })
                                        .frame(width: 96, height: 96).padding(16)
                                }
                            }.buttonStyle(QuestifyCardButtonStyle()).questifyCardListRow()
                                .accessibilityIdentifier("objects.card.\(card.id)")
                        }
                    }
                }
            }
        }
        .appNavigationTitle("objects.title").privacySensitive()
        .task(id: scope) {
            if model.loadedScope != scope { model.invalidate() }
            if model.collection == nil && reader.isAuthenticated && reader.isConfigured {
                await model.load(category: model.category, reader: reader)
            }
        }
        .refreshable { await model.load(category: model.category, reader: reader) }
        .onDisappear { model.cancel() }
        .accessibilityIdentifier("objects.collection")
    }
}

@MainActor struct ObjectCardDetailView: View {
    let card: ObjectCard
    let reader: any ObjectCardReading
    let expectedScope: UUID
    var media: (any ObjectCardImageLoading)? = nil
    @State private var frame = 0
    @State private var drag: CGFloat = 0
    var body: some View {
        List {
            if reader.scope != expectedScope || !reader.isAuthenticated { Text("objects.sessionChanged") }
            else {
                Section {
                    ObjectCardArtwork(url: card.frame(at: frame), label: card.title, media: media,
                        expectedScope: expectedScope, currentScope: { reader.scope })
                        .frame(maxWidth: .infinity, minHeight: 240)
                        .accessibilityValue(card.hasRotationFrames ? "\(frame + 1) / \(card.frames.count)" : "")
                        .accessibilityAdjustableAction { direction in
                            guard card.hasRotationFrames else { return }
                            switch direction { case .increment: move(1); case .decrement: move(-1); @unknown default: break }
                        }
                        .gesture(DragGesture().onChanged { value in
                            guard card.hasRotationFrames else { return }
                            let delta = value.translation.width - drag
                            let steps = Int(delta / 8)
                            if steps != 0 { drag += CGFloat(steps * 8); move(steps) }
                        }.onEnded { _ in drag = 0 })
                    if card.hasRotationFrames {
                        Text("objects.framesHint").font(.caption)
                        HStack {
                            Button("objects.previous") { move(-1) }.accessibilityIdentifier("objects.frame.previous")
                            Spacer()
                            Text("\(frame + 1) / \(card.frames.count)").monospacedDigit()
                            Spacer()
                            Button("objects.next") { move(1) }.accessibilityIdentifier("objects.frame.next")
                        }.buttonStyle(.bordered).frame(minHeight: 44)
                    }
                    if !card.caption.isEmpty { Text(verbatim: card.caption) }
                }
                Section("objects.information") {
                    LabeledContent("objects.name", value: card.title)
                    if !card.category.isEmpty {
                        LabeledContent("objects.category") {
                            if let category = ObjectCardCategory(rawValue: card.category) { Text(LocalizedStringKey(category.localizationKey)) }
                            else { Text(verbatim: card.category) }
                        }
                    }
                    if !card.place.isEmpty { LabeledContent("objects.place", value: card.place) }
                    LabeledContent("objects.style") { Text(card.cardStyle == "plain" ? "objects.plain" : "objects.foil") }
                    if !card.generationStatus.isEmpty { LabeledContent("objects.status", value: card.generationStatus) }
                    if card.generating { Label("objects.generating", systemImage: "hourglass") }
                    if let origin = ObjectCardMediaPolicy.origin(card.sourceURL) {
                        LabeledContent("objects.source", value: origin)
                    }
                }
            }
        }.appNavigationTitle("objects.item").privacySensitive()
            .accessibilityIdentifier("objects.detail")
    }
    private func move(_ step: Int) {
        guard card.hasRotationFrames else { return }
        frame = ((frame + step) % card.frames.count + card.frames.count) % card.frames.count
    }
}

/// No AsyncImage bypass: optional loader enforces exact origin, stream size and redirect limits.
/// Retained pixels are never shown after a scope or URL change, including same-account relogin.
@MainActor struct ObjectCardArtwork: View {
    let url: String
    let label: String
    let media: (any ObjectCardImageLoading)?
    let expectedScope: UUID
    let currentScope: () -> UUID
    @State private var image: UIImage?
    @State private var loadedKey: Key?
    @State private var failed = false
    @State private var loading = false
    @State private var generation = UUID()
    private struct Key: Hashable { let url: String; let scope: UUID }
    private var key: Key { Key(url: url, scope: expectedScope) }
    var body: some View {
        VStack(spacing: 8) {
            if currentScope() != expectedScope { Text("objects.sessionChanged") }
            else if let image, loadedKey == key { Image(uiImage: image).resizable().scaledToFit() }
            else {
                Image(systemName: "photo").font(.largeTitle)
                if loading { ProgressView("objects.loading") }
                else { Text(media == nil ? "objects.mediaDisabled" : failed ? "objects.mediaFailed" : "objects.noImage").font(.caption) }
            }
        }.accessibilityElement(children: .combine).accessibilityLabel(Text(verbatim: label))
            .accessibilityValue(Text(loading ? "objects.loading" : media == nil ? "objects.mediaDisabled" : failed ? "objects.mediaFailed" : image == nil ? "objects.noImage" : ""))
            .task(id: key) { await load() }
            .onDisappear { generation = UUID(); image = nil; loadedKey = nil; loading = false }
    }
    private func load() async {
        generation = UUID(); let run = generation
        image = nil; loadedKey = nil; failed = false; loading = false
        guard let media, !url.isEmpty, currentScope() == expectedScope else { return }
        let captured = key; loading = true
        defer { if run == generation { loading = false } }
        do {
            let data = try await media.image(url: url)
            try Task.checkCancellation()
            guard data.count <= ObjectCardMediaPolicy.maximumBytes,
                  let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
                  let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
                  width.doubleValue > 0, height.doubleValue > 0,
                  width.doubleValue * height.doubleValue <= 32_000_000,
                  let decoded = UIImage(data: data) else { throw ObjectCardMediaFailure.unsupportedImage }
            guard !Task.isCancelled, run == generation, captured == key, currentScope() == expectedScope else { return }
            loadedKey = captured; image = decoded
        } catch is CancellationError { }
        catch { if run == generation, captured == key, currentScope() == expectedScope { failed = true } }
    }
}
