import SwiftUI

@MainActor private final class MerchantBrandImagesModel: ObservableObject, Identifiable {
    let id = UUID()
    let session: MerchantBrandImagesSession
    let isExample: Bool
    @Published private(set) var revision = 0
    init?(document: MerchantOperationsViewModel) {
        guard let session = MerchantBrandImagesSession(owner: document.coordinator) else { return nil }
        self.session = session; isExample = document.coordinator.reader.isOfflineExample
    }
    func reload() async { revision += 1; await session.reload(); revision += 1 }
    func select(_ index: Int) { _ = session.select(index); revision += 1 }
    func closeImage() { session.closeImage(); revision += 1 }
    func zoom(_ value: Double, ticket: UUID, index: Int) { _ = session.setZoom(value, ticket: ticket, index: index); revision += 1 }
    func retry(_ ticket: UUID, index: Int) { session.retryImage(ticket: ticket, index: index); revision += 1 }
    func retire() { session.retire(); revision += 1 }
}

@MainActor struct MerchantBrandImagesEntry: View {
    @ObservedObject var document: MerchantOperationsViewModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var presentation: MerchantBrandImagesModel?
    var body: some View {
        Section("merchant.brandImages.title") {
            Button("merchant.brandImages.open", systemImage: "photo.on.rectangle") {
                guard scenePhase == .active, presentation == nil else { return }
                presentation = .init(document: document)
            }.disabled(!document.coordinator.isCurrent || document.coordinator.isBusy || document.coordinator.isLocked || document.coordinator.confirmation != nil)
                .accessibilityIdentifier("merchant.brandImages.open")
            Text("merchant.brandImages.sourceHint").font(.footnote).foregroundStyle(.secondary)
        }
        .sheet(item: $presentation) { value in MerchantBrandImagesSheet(model: value) { close() } }
        .onChange(of: document.coordinator.reader.scope) { _, _ in close() }
        .onChange(of: document.coordinator.draftIdentity) { _, _ in close() }
        .onChange(of: document.coordinator.draft) { _, _ in close() }
        .onChange(of: document.coordinator.confirmation) { _, _ in close() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { close() } }
        .onDisappear { close() }
    }
    private func close() { presentation?.retire(); presentation = nil }
}

@MainActor private struct MerchantBrandImagesSheet: View {
    @ObservedObject var model: MerchantBrandImagesModel
    let close: () -> Void
    @Environment(\.scenePhase) private var scenePhase
    private var session: MerchantBrandImagesSession { model.session }
    var body: some View {
        NavigationStack {
            Group {
                if !session.isCurrent || scenePhase != .active { Text("merchant.brandImages.expired") }
                else if let index = session.selectedIndex {
                    viewer(index)
                } else {
                    List {
                        Section { Text("merchant.brandImages.sourceHint"); Text("merchant.brandImages.readOnly") }
                        if session.isLoading { ProgressView("merchant.brandImages.loading") }
                        else if let issue = session.issue {
                            MerchantOperationsIssueView(issue: issue)
                            Button("action.retry") { Task { await model.reload() } }.accessibilityIdentifier("merchant.brandImages.retrySource")
                        } else if session.document != nil {
                            if session.items.isEmpty { Text("merchant.brandImages.empty").accessibilityIdentifier("merchant.brandImages.empty") }
                            ForEach(session.items) { item in
                                VStack(alignment: .leading, spacing: 6) {
                                    Button { model.select(item.id) } label: { Label { Text("merchant.brandImages.image \(item.id + 1)") } icon: { Image(systemName: "photo") } }
                                        .disabled(item.url == nil).accessibilityIdentifier("merchant.brandImages.image." + String(item.id))
                                    if item.url == nil { Text("merchant.brandImages.unsupported").font(.footnote).foregroundStyle(.secondary) }
                                }
                            }
                        }
                    }.refreshable { await model.reload() }
                }
            }
            .appNavigationTitle("merchant.brandImages.title")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if session.selectedIndex != nil { Button("merchant.brandImages.back") { model.closeImage() }.accessibilityIdentifier("merchant.brandImages.back") }
                    else { Button("action.close", action: close).accessibilityIdentifier("merchant.brandImages.close") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("merchant.brandImages.reload", systemImage: "arrow.clockwise") { Task { await model.reload() } }
                        .disabled(session.isLoading || !session.isCurrent).accessibilityIdentifier("merchant.brandImages.reload")
                }
            }
        }
        .privacySensitive()
        .task { await model.reload() }
        .onDisappear { model.retire() }
    }
    private func viewer(_ index: Int) -> some View {
        let ticket = session.imageGeneration
        return VStack(spacing: 12) {
            if let url = session.currentURL {
                MerchantBrandImageCanvas(model: model, url: url, index: index, ticket: ticket).id(ticket)
            }
            ViewThatFits(in: .horizontal) {
                HStack { navigation; zoomControls(ticket, index: index) }
                VStack { navigation; zoomControls(ticket, index: index) }
            }.padding(.horizontal)
            Text("merchant.brandImages.readOnly").font(.footnote).foregroundStyle(.secondary).padding(.horizontal)
        }
    }
    @ViewBuilder private var navigation: some View {
        Button("merchant.brandImages.previous") { if let index = session.previousIndex { model.select(index) } }
            .disabled(session.previousIndex == nil).frame(minHeight: 44).accessibilityIdentifier("merchant.brandImages.previous")
        Text(verbatim: "\((session.selectedIndex ?? 0) + 1) / \(session.items.count)")
            .monospacedDigit().accessibilityIdentifier("merchant.brandImages.position")
            .accessibilityLabel(Text("merchant.brandImages.positionLabel"))
            .accessibilityValue(Text(verbatim: "\((session.selectedIndex ?? 0) + 1) / \(session.items.count)"))
        Button("merchant.brandImages.next") { if let index = session.nextIndex { model.select(index) } }
            .disabled(session.nextIndex == nil).frame(minHeight: 44).accessibilityIdentifier("merchant.brandImages.next")
    }
    private func zoomControls(_ ticket: UUID, index: Int) -> some View {
        HStack {
            Button("merchant.brandImages.zoomIn", systemImage: "plus.magnifyingglass") { model.zoom(session.zoom + 1, ticket: ticket, index: index) }
                .disabled(session.zoom >= 5).frame(minHeight: 44).accessibilityIdentifier("merchant.brandImages.zoomIn")
            Button("merchant.brandImages.resetZoom") { model.zoom(1, ticket: ticket, index: index) }
                .disabled(session.zoom == 1).frame(minHeight: 44).accessibilityIdentifier("merchant.brandImages.resetZoom")
        }
    }
}

@MainActor private struct MerchantBrandImageCanvas: View {
    @ObservedObject var model: MerchantBrandImagesModel
    let url: URL
    let index: Int
    let ticket: UUID
    @Environment(\.scenePhase) private var scenePhase
    @GestureState private var magnification: CGFloat = 1
    var body: some View {
        if scenePhase == .active, model.session.imageIsCurrent(ticket, index: index) {
            if model.isExample {
                // Synthetic screenshots and tests never request even an example URL.
                image(Image(systemName: index == 0 ? "storefront.fill" : "photo.artframe"))
            } else {
                AsyncImage(url: url, transaction: Transaction(animation: nil)) { phase in
                    if scenePhase == .active, model.session.imageIsCurrent(ticket, index: index) {
                        switch phase {
                        case .success(let value): image(value)
                        case .failure:
                            VStack {
                                Label("merchant.brandImages.imageFailed", systemImage: "photo.badge.exclamationmark")
                                Button("action.retry") { model.retry(ticket, index: index) }.accessibilityIdentifier("merchant.brandImages.retryImage")
                            }
                        default: ProgressView("merchant.brandImages.loading")
                        }
                    }
                }
            }
        }
    }
    private func image(_ value: Image) -> some View {
        GeometryReader { geometry in
            let scale = CGFloat(min(5, max(1, model.session.zoom * Double(magnification))))
            ScrollView([.horizontal, .vertical]) {
                value.resizable().scaledToFit()
                    .frame(width: geometry.size.width * scale, height: geometry.size.height * scale)
                    .accessibilityLabel(Text("merchant.brandImages.image \(index + 1)"))
            }.clipped().simultaneousGesture(MagnificationGesture().updating($magnification) { value, state, _ in state = value }
                .onEnded { value in model.zoom(model.session.zoom * Double(value), ticket: ticket, index: index) })
        }
    }
}
