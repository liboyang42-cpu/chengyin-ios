import SwiftUI
import UIKit
import SceneKit
import Observation

@MainActor @Observable final class OwnMediaModelPreviewModel {
    enum Phase: Equatable { case idle, loading, ready, failed, expired }
    let asset: OwnMediaAsset
    private let access: OwnMediaModelPreviewAccess?
    private let currentAsset: () -> OwnMediaAsset?
    private let source: UUID?
    @ObservationIgnored private let decode: @MainActor (Data) async throws -> SCNScene
    @ObservationIgnored private let makeDevice: @MainActor () -> any OwnMediaModelPreviewRendering
    @ObservationIgnored private let notifications: NotificationCenter
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private(set) var device: (any OwnMediaModelPreviewRendering)?
    private var mounted = false, foreground = false
    private var operation = UUID(), watchGeneration = UUID()
    private var reader: OwnMediaModelPreviewReader?
    private var task: Task<Void, Never>?, expirationTask: Task<Void, Never>?, loadingTask: Task<Void, Never>?
    private var deadline: ContinuousClock.Instant?
    private(set) var presentation: UUID?
    private(set) var phase: Phase = .idle
    var controlRevision: UUID { operation }
    init(asset: OwnMediaAsset, access: OwnMediaModelPreviewAccess?, currentAsset: @escaping () -> OwnMediaAsset?,
         notifications: NotificationCenter = .default,
         decode: @escaping @MainActor (Data) async throws -> SCNScene = { try await PlayKitGLBDecoder().scene(from: $0) },
         makeDevice: @escaping @MainActor () -> any OwnMediaModelPreviewRendering = { OwnMediaModelPreviewDevice() }) {
        self.asset = asset; self.access = access; self.currentAsset = currentAsset; self.notifications = notifications
        self.decode = decode; self.makeDevice = makeDevice; source = access?.sourceRevision(asset)
    }
    deinit { task?.cancel(); expirationTask?.cancel(); loadingTask?.cancel(); for observer in observers { notifications.removeObserver(observer) } }
    var available: Bool {
        guard mounted, foreground, asset.mediaType == .model3D, let source,
              access?.sourceRevision(asset) == source, let row = currentAsset() else { return false }
        return OwnMediaModelPreviewReader.sameAsset(asset, row)
    }
    func appear(foreground: Bool) { mounted = true; self.foreground = foreground }
    func setForeground(_ value: Bool) { foreground = value; if !value, let id = presentation { close(id) } }
    func disappear() { mounted = false; if let id = presentation { close(id) } }
    @discardableResult func open() -> Task<Void, Never>? {
        guard available, presentation == nil else { return nil }; let id = UUID(); presentation = id; return start(id)
    }
    @discardableResult func retry(_ id: UUID, operation: UUID) -> Task<Void, Never>? {
        guard accepts(id, operation), phase == .failed || phase == .expired else { return nil }; return start(id)
    }
    func close(_ id: UUID) {
        guard presentation == id else { return }; clearWork(); phase = .idle; presentation = nil
    }
    private func clearWork() {
        operation = UUID(); watchGeneration = UUID()
        for observer in observers { notifications.removeObserver(observer) }; observers.removeAll()
        task?.cancel(); task = nil; expirationTask?.cancel(); expirationTask = nil; loadingTask?.cancel(); loadingTask = nil
        reader?.onRetired = nil; reader?.retire(); reader = nil
        let old = device; device = nil; deadline = nil; old?.stop()
    }
    private func accepts(_ id: UUID, _ run: UUID) -> Bool { available && presentation == id && operation == run }
    private func renderingIsCurrent(_ id: UUID, _ run: UUID) -> Bool {
        accepts(id, run) && reader?.isConfigured == true && deadline.map { ContinuousClock().now < $0 } == true
    }
    /// Only MainActor-owned external sources are tracked. Retirement clears the actual
    /// viewport synchronously, not merely the value SwiftUI will render next turn.
    private func observeExternal(_ id: UUID, _ run: UUID) {
        watchGeneration = UUID(); let watch = watchGeneration, access = access, currentAsset = currentAsset, asset = asset
        withObservationTracking {
            _ = access?.sourceRevision(asset); _ = currentAsset()
        } onChange: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.watchGeneration == watch, self.presentation == id, self.operation == run else { return }; self.close(id)
            }
        }
    }
    private func start(_ id: UUID) -> Task<Void, Never>? {
        guard available, presentation == id else { return nil }; clearWork(); let run = operation
        guard let next = access?.makeReader(asset), next.sourceRevision == source else { phase = .failed; return nil }
        reader = next; phase = .loading
        next.onRetired = { [weak self] in
            guard let self, self.presentation == id, self.operation == run else { return }; self.close(id)
        }
        observeExternal(id, run)
        for name in [UIApplication.willResignActiveNotification, UIApplication.didEnterBackgroundNotification, UIApplication.significantTimeChangeNotification] {
            observers.append(notifications.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.presentation == id, self.operation == run else { return }; self.close(id)
                }
            })
        }
        let loadLimit = ContinuousClock().now.advanced(by: .seconds(15))
        loadingTask = Task { @MainActor [weak self] in
            do { try await ContinuousClock().sleep(until: loadLimit) } catch { return }
            guard !Task.isCancelled else { return }; self?.loadingTimedOut(id, run)
        }
        let work = Task { @MainActor [weak self] in
            guard let self else { return }; defer { if self.operation == run { self.task = nil } }
            do {
                guard !Task.isCancelled, self.accepts(id, run) else { return }
                let result = try await next.load(asset: self.asset, currentAsset: self.currentAsset,
                    presentationIsCurrent: { [weak self] in self?.accepts(id, run) == true })
                guard !Task.isCancelled, self.accepts(id, run), next.isConfigured else { return }
                guard ContinuousClock().now < result.displayDeadline else { self.expire(id, run); return }
                guard ContinuousClock().now < loadLimit else { self.loadingTimedOut(id, run); return }
                self.deadline = result.displayDeadline
                let displayLimit = result.displayDeadline
                self.expirationTask = Task { @MainActor [weak self] in
                    do { try await ContinuousClock().sleep(until: displayLimit) } catch { return }
                    guard !Task.isCancelled else { return }; self?.expire(id, run)
                }
                // Even injected decoders only receive the bounded, supported static profile.
                _ = try PlayKitGLBPolicy.validate(result.bytes)
                let scene = try await self.decode(result.bytes)
                guard !Task.isCancelled, self.renderingIsCurrent(id, run) else { return }
                guard ContinuousClock().now < loadLimit else { self.loadingTimedOut(id, run); return }
                let renderer = self.makeDevice()
                guard self.renderingIsCurrent(id, run) else { renderer.stop(); return }
                self.device = renderer
                try renderer.prepare(scene, current: { [weak self] in self?.renderingIsCurrent(id, run) == true })
                guard !Task.isCancelled, self.renderingIsCurrent(id, run) else { renderer.stop(); return }
                self.loadingTask?.cancel(); self.loadingTask = nil; self.phase = .ready
            } catch {
                guard !Task.isCancelled, self.accepts(id, run) else { return }; self.fail(id, run)
            }
        }
        task = work; return work
    }
    func loadingTimedOut(_ id: UUID, _ run: UUID) {
        guard presentation == id, operation == run, phase == .loading else { return }; fail(id, run)
    }
    private func fail(_ id: UUID, _ run: UUID) {
        guard presentation == id, operation == run else { return }; clearWork(); phase = .failed
    }
    private func expire(_ id: UUID, _ run: UUID) {
        guard presentation == id, operation == run else { return }; clearWork(); phase = .expired
    }
    func rotate(_ id: UUID, operation run: UUID) {
        guard renderingIsCurrent(id, run), phase == .ready, let device else { return }
        do { try device.rotate() }
        catch { guard accepts(id, run) else { return }; fail(id, run) }
    }
    func binding(_ offered: UUID) -> Binding<UUID?> {
        .init(get: { self.available && self.presentation == offered ? offered : nil }, set: { if $0 == nil { self.close(offered) } })
    }
}

private struct OwnMediaModelPreviewViewIdentity: Hashable {
    let id: Int64, state: String, reason: [UInt8], source: UUID?
    @MainActor init(asset: OwnMediaAsset, access: OwnMediaModelPreviewAccess?) {
        id = asset.id; state = asset.reviewState.rawValue; reason = Array(asset.reviewReason.utf8); source = access?.sourceRevision(asset)
    }
}
@MainActor struct OwnMediaModelPreviewButton: View {
    let asset: OwnMediaAsset
    let access: OwnMediaModelPreviewAccess?
    let currentAsset: () -> OwnMediaAsset?
    var body: some View {
        if asset.mediaType == .model3D {
            OwnMediaModelPreviewOwner(asset: asset, access: access, currentAsset: currentAsset)
                .id(OwnMediaModelPreviewViewIdentity(asset: asset, access: access))
        }
    }
}
@MainActor private struct OwnMediaModelPreviewOwner: View {
    @State private var model: OwnMediaModelPreviewModel
    @Environment(\.scenePhase) private var scenePhase
    init(asset: OwnMediaAsset, access: OwnMediaModelPreviewAccess?, currentAsset: @escaping () -> OwnMediaAsset?) {
        _model = State(initialValue: OwnMediaModelPreviewModel(asset: asset, access: access, currentAsset: currentAsset))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { model.open() } label: { Text("open", tableName: "OwnMediaModelPreview") }
                .disabled(!model.available || model.presentation != nil).frame(minHeight: 44)
                .accessibilityIdentifier("member.media.modelPreview.\(model.asset.id)")
            if !model.available { Text("unavailable", tableName: "OwnMediaModelPreview").font(.footnote).foregroundStyle(.secondary) }
        }
        .onAppear { model.appear(foreground: scenePhase == .active) }
        .onDisappear { model.disappear() }
        .onChange(of: scenePhase) { _, phase in model.setForeground(phase == .active) }
        .onChange(of: model.available) { _, live in if !live, let id = model.presentation { model.close(id) } }
        .background { if let id = model.presentation { OwnMediaModelPreviewPresenter(model: model, offered: id).id(id) } }
    }
}
@MainActor private struct OwnMediaModelPreviewPresenter: View {
    let model: OwnMediaModelPreviewModel
    let offered: UUID
    private struct Item: Identifiable { let id: UUID }
    var body: some View {
        Color.clear.frame(width: 0, height: 0).sheet(item: Binding<Item?>(
            get: { model.binding(offered).wrappedValue.map { Item(id: $0) } }, set: { if $0 == nil { model.close(offered) } }),
            onDismiss: { model.close(offered) }) { item in
            OwnMediaModelPreviewSheet(model: model, offered: item.id)
        }
    }
}
@MainActor private struct OwnMediaModelPreviewSheet: View {
    let model: OwnMediaModelPreviewModel
    let offered: UUID
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        NavigationStack {
            Form {
                Text("privateOnly", tableName: "OwnMediaModelPreview")
                Text("staticOnly", tableName: "OwnMediaModelPreview").font(.footnote).foregroundStyle(.secondary)
                if model.available, model.presentation == offered {
                    OwnMediaModelPreviewControls(model: model, offered: offered, operation: model.controlRevision)
                } else { Text("unavailable", tableName: "OwnMediaModelPreview") }
                Text("limits", tableName: "OwnMediaModelPreview").font(.footnote).foregroundStyle(.secondary)
            }
            .navigationTitle(Text("title", tableName: "OwnMediaModelPreview"))
            .toolbar { ToolbarItem(placement: .cancellationAction) {
                Button { model.close(offered) } label: { Text("close", tableName: "OwnMediaModelPreview") }.frame(minWidth: 44, minHeight: 44)
            } }
        }.privacySensitive()
        .onChange(of: scenePhase) { _, value in if value != .active { model.close(offered) } }
        .onDisappear { model.close(offered) }
    }
}
@MainActor private struct OwnMediaModelPreviewControls: View {
    let model: OwnMediaModelPreviewModel
    let offered: UUID, operation: UUID
    var body: some View {
        switch model.phase {
        case .loading: ProgressView { Text("loading", tableName: "OwnMediaModelPreview") }
        case .ready:
            if let device = model.device {
                OwnMediaModelPreviewViewport(device: device).id(operation).frame(height: 300)
                    .accessibilityLabel(Text("viewport", tableName: "OwnMediaModelPreview"))
                Button { model.rotate(offered, operation: operation) } label: { Text("rotate", tableName: "OwnMediaModelPreview") }
                    .frame(minHeight: 44).accessibilityIdentifier("member.media.modelPreview.rotate")
            }
        case .failed, .expired:
            Text(LocalizedStringKey(model.phase == .expired ? "expired" : "failed"), tableName: "OwnMediaModelPreview")
            Button { model.retry(offered, operation: operation) } label: { Text("retry", tableName: "OwnMediaModelPreview") }.frame(minHeight: 44)
        case .idle: Text("unavailable", tableName: "OwnMediaModelPreview")
        }
    }
}
@MainActor private struct OwnMediaModelPreviewViewport: UIViewRepresentable {
    let device: any OwnMediaModelPreviewRendering
    func makeCoordinator() -> Coordinator { Coordinator(device: device) }
    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero); view.isHidden = true
        let surface = OwnMediaModelSceneSurface(view: view); context.coordinator.surface = surface
        context.coordinator.attachment = device.attach(surface)
        return view
    }
    func updateUIView(_ view: SCNView, context: Context) {}
    static func dismantleUIView(_ view: SCNView, coordinator: Coordinator) {
        if let stamp = coordinator.attachment { coordinator.device.detach(stamp) }
        coordinator.attachment = nil; coordinator.surface = nil
    }
    @MainActor final class Coordinator {
        let device: any OwnMediaModelPreviewRendering
        var surface: OwnMediaModelSceneSurface?, attachment: UUID?
        init(device: any OwnMediaModelPreviewRendering) { self.device = device }
    }
}
