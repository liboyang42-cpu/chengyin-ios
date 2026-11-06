import SwiftUI
import UIKit
import Observation

@MainActor @Observable final class OwnMediaAudioPreviewModel {
    enum Phase: Equatable { case idle, loading, ready, playing, paused, ended, failed, expired }
    let asset: OwnMediaAsset
    private let access: OwnMediaAudioPreviewAccess?
    private let currentAsset: () -> OwnMediaAsset?
    private let source: UUID?
    @ObservationIgnored private let makeDevice: @MainActor () -> any OwnMediaAudioPreviewPlaying
    @ObservationIgnored private let lifecycle: NativeAudioLifecycleObservation
    @ObservationIgnored private let notifications: NotificationCenter
    @ObservationIgnored private var timeObserver: NSObjectProtocol?
    @ObservationIgnored private var device: (any OwnMediaAudioPreviewPlaying)?
    private var mounted = false, foreground = false
    private var operation = UUID(), watchGeneration = UUID()
    private var reader: OwnMediaAudioPreviewReader?
    private var task: Task<Void, Never>?, expirationTask: Task<Void, Never>?, progressTask: Task<Void, Never>?
    private var deadline: ContinuousClock.Instant?
    private(set) var presentation: UUID?
    private(set) var phase: Phase = .idle
    private(set) var duration: TimeInterval = 0, position: TimeInterval = 0
    var controlRevision: UUID { operation }
    init(asset: OwnMediaAsset, access: OwnMediaAudioPreviewAccess?, currentAsset: @escaping () -> OwnMediaAsset?,
         notifications: NotificationCenter = .default, makeDevice: @escaping @MainActor () -> any OwnMediaAudioPreviewPlaying = { OwnMediaAudioPreviewDevice() }) {
        self.asset = asset; self.access = access; self.currentAsset = currentAsset; self.makeDevice = makeDevice; self.notifications = notifications
        source = access?.sourceRevision(asset)
        lifecycle = .init(notifications: notifications, enqueue: { action in MainActor.assumeIsolated { action() } })
    }
    deinit { task?.cancel(); expirationTask?.cancel(); progressTask?.cancel(); if let timeObserver { notifications.removeObserver(timeObserver) } }
    var available: Bool {
        guard mounted, foreground, asset.mediaType == .audio, let source,
              access?.sourceRevision(asset) == source, let row = currentAsset() else { return false }
        return OwnMediaAudioPreviewReader.sameAsset(asset, row)
    }
    func appear(foreground: Bool) { mounted = true; self.foreground = foreground }
    func setForeground(_ value: Bool) { foreground = value; if !value, let id = presentation { close(id) } }
    func disappear() { mounted = false; if let id = presentation { close(id) } }
    @discardableResult func open() -> Task<Void, Never>? {
        guard available, presentation == nil else { return nil }; let id = UUID(); presentation = id; return start(id)
    }
    @discardableResult func retry(_ id: UUID, operation: UUID) -> Task<Void, Never>? {
        guard accepts(id, operation), phase == .failed || phase == .expired || phase == .ended else { return nil }; return start(id)
    }
    func close(_ id: UUID) {
        guard presentation == id else { return }; clearWork(); phase = .idle; presentation = nil
    }
    private func clearWork() {
        operation = UUID(); watchGeneration = UUID(); lifecycle.invalidate()
        if let timeObserver { notifications.removeObserver(timeObserver) }; timeObserver = nil
        task?.cancel(); task = nil; expirationTask?.cancel(); expirationTask = nil; progressTask?.cancel(); progressTask = nil
        reader?.onRetired = nil; reader?.retire(); reader = nil
        device?.stop(); device = nil; deadline = nil; duration = 0; position = 0
    }
    private func accepts(_ id: UUID, _ run: UUID) -> Bool { available && presentation == id && operation == run }
    private func playbackIsCurrent(_ id: UUID, _ run: UUID) -> Bool {
        accepts(id, run) && reader?.isConfigured == true && deadline.map { ContinuousClock().now < $0 } == true
    }
    /// All tracked sources here are MainActor-owned. Observation willSet stops sound before
    /// a row/list/lease changes, rather than waiting for SwiftUI onChange to render it away.
    private func observeExternal(_ id: UUID, _ run: UUID) {
        watchGeneration = UUID(); let watch = watchGeneration, access = access, currentAsset = currentAsset, asset = asset
        withObservationTracking {
            _ = access?.sourceRevision(asset); _ = currentAsset()
        } onChange: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.watchGeneration == watch, self.presentation == id, self.operation == run else { return }
                self.close(id)
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
        timeObserver = notifications.addObserver(forName: UIApplication.significantTimeChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.presentation == id, self.operation == run else { return }; self.close(id)
            }
        }
        lifecycle.observe { [weak self] signal in
            guard let self, self.presentation == id, self.operation == run,
                  PlatformAudioLifecyclePolicy.action(for: signal, ownsConfiguration: false) == .stop else { return }; self.close(id)
        }
        let work = Task { @MainActor [weak self] in
            guard let self else { return }; defer { if self.operation == run { self.task = nil } }
            do {
                guard !Task.isCancelled, self.accepts(id, run) else { return }
                let result = try await next.load(asset: self.asset, currentAsset: self.currentAsset,
                    presentationIsCurrent: { [weak self] in self?.accepts(id, run) == true })
                guard !Task.isCancelled, self.accepts(id, run), next.isConfigured else { return }
                guard ContinuousClock().now < result.displayDeadline else { self.expire(id, run); return }
                self.deadline = result.displayDeadline
                let player = self.makeDevice(); self.device = player
                let duration = try player.prepare(result.bytes, current: { [weak self] in self?.playbackIsCurrent(id, run) == true }, event: { [weak self] event in
                    guard let self, self.accepts(id, run) else { return }
                    self.device?.stop(); self.device = nil; self.progressTask?.cancel(); self.progressTask = nil
                    self.phase = event == .ended ? .ended : .failed
                })
                guard !Task.isCancelled, self.playbackIsCurrent(id, run) else { player.stop(); self.expire(id, run); return }
                guard duration.isFinite, duration > 0, duration < TimeInterval(Int.max) else { throw OwnMediaAudioPreviewFailure.invalidResponse }
                self.duration = duration; self.position = 0; self.phase = .ready
                let limit = result.displayDeadline
                self.expirationTask = Task { @MainActor [weak self] in
                    do { try await ContinuousClock().sleep(until: limit) } catch { return }
                    guard !Task.isCancelled else { return }; self?.expire(id, run)
                }
            } catch {
                guard !Task.isCancelled, self.accepts(id, run) else { return }
                self.device?.stop(); self.device = nil; self.deadline = nil; self.phase = .failed
            }
        }
        task = work; return work
    }
    private func expire(_ id: UUID, _ run: UUID) {
        guard presentation == id, operation == run else { return }
        device?.stop(); device = nil; progressTask?.cancel(); progressTask = nil
        reader?.onRetired = nil; reader?.retire(); reader = nil; deadline = nil; position = 0; duration = 0; phase = .expired
    }
    func toggle(_ id: UUID, operation run: UUID) {
        guard playbackIsCurrent(id, run), let device, phase == .ready || phase == .playing || phase == .paused else { return }
        if phase == .playing { device.pause(); if accepts(id, run) { phase = .paused }; return }
        do {
            try device.play(); guard playbackIsCurrent(id, run) else { device.stop(); return }; phase = .playing
            progressTask?.cancel()
            progressTask = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    do { try await Task.sleep(nanoseconds: 250_000_000) } catch { return }
                    guard let self else { return }
                    guard self.playbackIsCurrent(id, run), self.phase == .playing || self.phase == .paused else {
                        if self.presentation == id, self.operation == run { self.close(id) }; return
                    }
                    let position = self.device?.position ?? 0
                    self.position = position.isFinite ? min(max(0, position), self.duration) : 0
                }
            }
        } catch { guard accepts(id, run) else { return }; device.stop(); self.device = nil; phase = .failed }
    }
    func seek(_ id: UUID, operation run: UUID, to value: Double) {
        guard playbackIsCurrent(id, run), value.isFinite, (0...duration).contains(value),
              phase == .ready || phase == .playing || phase == .paused else { return }
        do { try device?.seek(value); if accepts(id, run) { position = value } }
        catch { guard accepts(id, run) else { return }; device?.stop(); device = nil; phase = .failed }
    }
    func binding(_ offered: UUID) -> Binding<UUID?> {
        .init(get: { self.available && self.presentation == offered ? offered : nil }, set: { if $0 == nil { self.close(offered) } })
    }
}
private struct OwnMediaAudioPreviewViewIdentity: Hashable {
    let id: Int64, state: String, reason: [UInt8], source: UUID?
    @MainActor init(asset: OwnMediaAsset, access: OwnMediaAudioPreviewAccess?) {
        id = asset.id; state = asset.reviewState.rawValue; reason = Array(asset.reviewReason.utf8); source = access?.sourceRevision(asset)
    }
}
@MainActor struct OwnMediaAudioPreviewButton: View {
    let asset: OwnMediaAsset
    let access: OwnMediaAudioPreviewAccess?
    let currentAsset: () -> OwnMediaAsset?
    var body: some View {
        if asset.mediaType == .audio {
            OwnMediaAudioPreviewOwner(asset: asset, access: access, currentAsset: currentAsset)
                .id(OwnMediaAudioPreviewViewIdentity(asset: asset, access: access))
        }
    }
}
@MainActor private struct OwnMediaAudioPreviewOwner: View {
    @State private var model: OwnMediaAudioPreviewModel
    @Environment(\.scenePhase) private var scenePhase
    init(asset: OwnMediaAsset, access: OwnMediaAudioPreviewAccess?, currentAsset: @escaping () -> OwnMediaAsset?) {
        _model = State(initialValue: OwnMediaAudioPreviewModel(asset: asset, access: access, currentAsset: currentAsset))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { model.open() } label: { Text("open", tableName: "OwnMediaAudioPreview") }
                .disabled(!model.available || model.presentation != nil).frame(minHeight: 44)
                .accessibilityIdentifier("member.media.audioPreview.\(model.asset.id)")
            if !model.available { Text("unavailable", tableName: "OwnMediaAudioPreview").font(.footnote).foregroundStyle(.secondary) }
        }
        .onAppear { model.appear(foreground: scenePhase == .active) }
        .onDisappear { model.disappear() }
        .onChange(of: scenePhase) { _, phase in model.setForeground(phase == .active) }
        .onChange(of: model.available) { _, live in if !live, let id = model.presentation { model.close(id) } }
        .background { if let id = model.presentation { OwnMediaAudioPreviewPresenter(model: model, offered: id).id(id) } }
    }
}
@MainActor private struct OwnMediaAudioPreviewPresenter: View {
    let model: OwnMediaAudioPreviewModel
    let offered: UUID
    private struct Item: Identifiable { let id: UUID }
    var body: some View {
        Color.clear.frame(width: 0, height: 0).sheet(item: Binding<Item?>(
            get: { model.binding(offered).wrappedValue.map { Item(id: $0) } }, set: { if $0 == nil { model.close(offered) } }),
            onDismiss: { model.close(offered) }) { item in
            OwnMediaAudioPreviewSheet(model: model, offered: item.id)
        }
    }
}
@MainActor private struct OwnMediaAudioPreviewSheet: View {
    let model: OwnMediaAudioPreviewModel
    let offered: UUID
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        NavigationStack {
            Form {
                Text("privateOnly", tableName: "OwnMediaAudioPreview")
                if model.available, model.presentation == offered {
                    OwnMediaAudioPreviewControls(model: model, offered: offered, operation: model.controlRevision)
                } else { Text("unavailable", tableName: "OwnMediaAudioPreview") }
                Text("limits", tableName: "OwnMediaAudioPreview").font(.footnote).foregroundStyle(.secondary)
            }
            .navigationTitle(Text("title", tableName: "OwnMediaAudioPreview"))
            .toolbar { ToolbarItem(placement: .cancellationAction) {
                Button { model.close(offered) } label: { Text("close", tableName: "OwnMediaAudioPreview") }.frame(minWidth: 44, minHeight: 44)
            } }
        }.privacySensitive()
        .onChange(of: scenePhase) { _, value in if value != .active { model.close(offered) } }
        .onDisappear { model.close(offered) }
    }
}
@MainActor private struct OwnMediaAudioPreviewControls: View {
    let model: OwnMediaAudioPreviewModel
    let offered: UUID, operation: UUID
    var body: some View {
        switch model.phase {
        case .loading: ProgressView { Text("loading", tableName: "OwnMediaAudioPreview") }
        case .ready, .playing, .paused:
            Button { model.toggle(offered, operation: operation) } label: {
                Text(LocalizedStringKey(model.phase == .playing ? "pause" : "play"), tableName: "OwnMediaAudioPreview")
            }.frame(minHeight: 44).accessibilityIdentifier("member.media.audioPreview.playPause")
            Slider(value: Binding(get: { model.position }, set: { model.seek(offered, operation: operation, to: $0) }), in: 0...max(1, model.duration)) {
                Text("position", tableName: "OwnMediaAudioPreview")
            }.accessibilityIdentifier("member.media.audioPreview.position")
            Text(verbatim: "\(Int(model.position)) / \(Int(model.duration)) s").monospacedDigit()
        case .failed, .expired, .ended:
            Text(LocalizedStringKey(model.phase == .expired ? "expired" : model.phase == .ended ? "ended" : "failed"), tableName: "OwnMediaAudioPreview")
            Button { model.retry(offered, operation: operation) } label: { Text("retry", tableName: "OwnMediaAudioPreview") }.frame(minHeight: 44)
        case .idle: Text("unavailable", tableName: "OwnMediaAudioPreview")
        }
    }
}
