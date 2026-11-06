import SwiftUI
import UIKit
import Observation

@MainActor protocol MemberIdentityAvatarSurface: AnyObject {
    func display(_ image: UIImage)
    func clear()
}
/// A distinct view instance is the attachment capability. An old dismantle cannot clear its successor.
@MainActor final class MemberIdentityAvatarImageView: UIImageView, MemberIdentityAvatarSurface {
    func display(_ value: UIImage) { image = value; isHidden = false }
    func clear() { isHidden = true; image = nil }
}
private final class MemberIdentityAvatarLifecycle: @unchecked Sendable {
    private let center: NotificationCenter
    private var observers: [NSObjectProtocol] = []
    init(center: NotificationCenter, stop: @escaping @MainActor () -> Void) {
        self.center = center
        for name in [UIApplication.willResignActiveNotification, UIApplication.didEnterBackgroundNotification,
                     UIApplication.significantTimeChangeNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { stop() }
            })
        }
    }
    deinit { observers.forEach { center.removeObserver($0) } }
}

/// No shared image cache or URL-based UIKit loader. Only sanitized, bounded memory bytes reach this surface.
@MainActor @Observable final class MemberIdentityAvatarModel {
    enum Phase: Equatable { case idle, loading, ready, failed }
    let observation: MemberIdentityAvatarObservation
    private let owner: MemberIdentityCardReadOwner
    private let access: MemberIdentityAvatarAccess?
    private let source: UUID?
    private let decode: (Data) throws -> UIImage
    private var lifecycle: MemberIdentityAvatarLifecycle?
    private var mounted = false, foreground = false
    private var operation = UUID()
    private var reader: MemberIdentityAvatarReader?
    private var work: Task<Void, Never>?, timer: Task<Void, Never>?
    private var storedImage: UIImage?
    private var deadline: ContinuousClock.Instant?
    private weak var surface: (any MemberIdentityAvatarSurface)?
    private(set) var phase: Phase = .idle
    init(observation: MemberIdentityAvatarObservation, owner: MemberIdentityCardReadOwner,
         access: MemberIdentityAvatarAccess?, notifications: NotificationCenter = .default,
         decode: @escaping (Data) throws -> UIImage = { data in
             let clean = try RetainedImageSanitizer.sanitize(data)
             guard let image = UIImage(data: clean.jpeg) else { throw RetainedImageFailure.invalid }; return image
         }) {
        self.observation = observation; self.owner = owner; self.access = access
        source = access?.sourceRevision(); self.decode = decode
        lifecycle = MemberIdentityAvatarLifecycle(center: notifications, stop: { [weak self] in
            guard let self else { return }; self.foreground = false; self.stop()
        })
    }
    deinit { work?.cancel(); timer?.cancel() }
    var available: Bool {
        mounted && foreground && owner.observation == observation && source != nil && access?.sourceRevision() == source
    }
    @discardableResult func appear(active: Bool) -> Task<Void, Never>? { mounted = true; foreground = active; return start() }
    func scene(active: Bool) { foreground = active; if active { start() } else { stop() } }
    func disappear() { mounted = false; foreground = false; stop() }
    func attach(_ value: any MemberIdentityAvatarSurface) {
        if let old = surface, old !== value { old.clear() }
        surface = value; updateSurface(value)
    }
    func detach(_ value: any MemberIdentityAvatarSurface) {
        value.clear()
        guard surface === value else { return }; surface = nil; stop()
    }
    func updateSurface(_ value: any MemberIdentityAvatarSurface) {
        guard surface === value else { value.clear(); return }
        guard available, reader?.isConfigured == true, phase == .ready,
              let deadline, ContinuousClock().now < deadline, let storedImage else { value.clear(); return }
        value.display(storedImage)
    }
    func stop() {
        operation = UUID(); work?.cancel(); work = nil; timer?.cancel(); timer = nil
        let old = reader; reader = nil; old?.onRetire = nil; old?.retire()
        storedImage = nil; deadline = nil; phase = .idle; surface?.clear()
    }
    @discardableResult func start() -> Task<Void, Never>? {
        guard available, phase != .loading && phase != .ready else { return nil }
        stop(); let run = operation
        guard available, let next = access?.makeReader(), next.sourceRevision == source, next.accepts(observation) else { return nil }
        reader = next; owner.register(next)
        next.onRetire = { [weak self, weak next] in
            guard let self, self.operation == run, self.reader === next else { return }; self.stop()
        }
        phase = .loading
        let limit = next.deadline(for: observation)
        schedule(min(limit, ContinuousClock().now.advanced(by: .seconds(20))), run: run)
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { if self.operation == run { self.work = nil } }
            do {
                guard !Task.isCancelled, self.operation == run, self.available else { return }
                let bytes = try await next.image(self.observation, currentObservation: { [weak self] in
                    guard let self, self.operation == run, self.available else { return nil }; return self.owner.observation
                })
                guard !Task.isCancelled, self.operation == run, self.available,
                      next.isConfigured, ContinuousClock().now < limit else { return }
                let image = try self.decode(bytes)
                guard !Task.isCancelled, self.operation == run, self.available,
                      next.isConfigured, ContinuousClock().now < limit else { return }
                self.storedImage = image; self.deadline = limit; self.phase = .ready
                if let surface = self.surface { self.updateSurface(surface) }
                self.schedule(limit, run: run)
            } catch {
                guard self.operation == run else { return }; self.stop(); self.phase = .failed
            }
        }
        work = task; return task
    }
    private func schedule(_ limit: ContinuousClock.Instant, run: UUID) {
        timer?.cancel()
        timer = Task { [weak self] in
            do { try await ContinuousClock().sleep(until: limit) } catch { return }
            guard !Task.isCancelled, let self, self.operation == run else { return }; self.stop()
        }
    }
}

@MainActor struct MemberIdentityAvatarView: View {
    @State private var model: MemberIdentityAvatarModel
    @Environment(\.scenePhase) private var scenePhase
    init(observation: MemberIdentityAvatarObservation, owner: MemberIdentityCardReadOwner, access: MemberIdentityAvatarAccess?) {
        _model = State(initialValue: .init(observation: observation, owner: owner, access: access))
    }
    var body: some View {
        MemberIdentityAvatarSurfaceView(model: model)
            .frame(width: 56, height: 56).clipShape(Circle()).accessibilityHidden(true).privacySensitive()
            .onAppear { model.appear(active: scenePhase == .active) }
            .onDisappear { model.disappear() }
            .onChange(of: scenePhase) { _, value in model.scene(active: value == .active) }
            .onChange(of: model.available) { _, value in if !value { model.stop() } }
    }
}
@MainActor private struct MemberIdentityAvatarSurfaceView: UIViewRepresentable {
    let model: MemberIdentityAvatarModel
    final class Coordinator {
        let model: MemberIdentityAvatarModel
        init(_ model: MemberIdentityAvatarModel) { self.model = model }
    }
    func makeCoordinator() -> Coordinator { .init(model) }
    func makeUIView(context: Context) -> MemberIdentityAvatarImageView {
        let view = MemberIdentityAvatarImageView(); view.contentMode = .scaleAspectFill; view.clipsToBounds = true
        view.isAccessibilityElement = false; view.clear(); model.attach(view); return view
    }
    func updateUIView(_ view: MemberIdentityAvatarImageView, context: Context) { model.updateSurface(view) }
    static func dismantleUIView(_ view: MemberIdentityAvatarImageView, coordinator: Coordinator) { coordinator.model.detach(view) }
}
