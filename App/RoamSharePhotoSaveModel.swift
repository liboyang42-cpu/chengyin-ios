import Foundation
import Combine
import Photos
import UIKit

@MainActor protocol RoamSharePhotoWriting {
    func authorizationStatus() -> RoamSharePhotoSaveState.Authorization
    func requestAuthorization() async -> RoamSharePhotoSaveState.Authorization
    func add(_ image: UIImage) async throws
}

/// Only writes the already rendered card; never fetches assets or reads the photo library.
@MainActor struct RoamSharePhotoLibraryWriter: RoamSharePhotoWriting {
    private enum Failure: Error { case missingUsageDescription, encoding, write }
    private var isConfigured: Bool {
        guard let usage = Bundle.main.object(forInfoDictionaryKey: "NSPhotoLibraryAddUsageDescription") as? String else { return false }
        return !usage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    func authorizationStatus() -> RoamSharePhotoSaveState.Authorization {
        guard isConfigured else { return .unavailable }
        return Self.map(PHPhotoLibrary.authorizationStatus(for: .addOnly))
    }
    func requestAuthorization() async -> RoamSharePhotoSaveState.Authorization {
        guard isConfigured else { return .unavailable }
        return await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                continuation.resume(returning: Self.map(status))
            }
        }
    }
    func add(_ image: UIImage) async throws {
        guard isConfigured else { throw Failure.missingUsageDescription }
        guard let data = image.pngData() else { throw Failure.encoding }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges({
                PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: nil)
            }, completionHandler: { success, error in
                if success { continuation.resume() }
                else { continuation.resume(throwing: error ?? Failure.write) }
            })
        }
    }
    nonisolated private static func map(_ status: PHAuthorizationStatus) -> RoamSharePhotoSaveState.Authorization {
        switch status {
        case .notDetermined: return .notDetermined
        case .authorized, .limited: return .authorized
        case .denied: return .denied
        case .restricted: return .restricted
        @unknown default: return .restricted
        }
    }
}

@MainActor final class RoamSharePhotoSaveModel: ObservableObject {
    @Published private(set) var state = RoamSharePhotoSaveState()
    @Published private(set) var inFlight = false
    private let writer: any RoamSharePhotoWriting
    private var task: Task<Void, Never>?
    init(writer: (any RoamSharePhotoWriting)? = nil) { self.writer = writer ?? RoamSharePhotoLibraryWriter() }

    func save(_ image: UIImage, selection: RoamSharePhotoSaveState.Selection,
              isCurrent: @escaping @MainActor () -> Bool) {
        guard !inFlight else { return }
        guard isCurrent() else { state.rejectSource(); return }
        state.prepare(selection)
        guard let attempt = state.begin(for: selection) else { return }
        inFlight = true
        task = Task { [weak self] in
            guard let self else { return }
            defer { self.inFlight = false; self.task = nil }
            // Dismissal before this task starts must not even ask for permission.
            guard self.isCurrent(attempt, source: isCurrent) else { return }
            var status = self.writer.authorizationStatus()
            if case .notDetermined = status { status = await self.writer.requestAuthorization() }
            // Permission can outlive a sheet, record, account or route-selection change.
            guard self.isCurrent(attempt, source: isCurrent) else { return }
            guard self.state.authorize(status, for: attempt) else { return }
            do {
                try await self.writer.add(image)
                guard self.isCurrent(attempt, source: isCurrent) else { return }
                self.state.complete(saved: true, for: attempt)
            } catch {
                guard self.isCurrent(attempt, source: isCurrent) else { return }
                self.state.complete(saved: false, for: attempt)
            }
        }
    }
    private func isCurrent(_ attempt: RoamSharePhotoSaveState.Attempt, source: @MainActor () -> Bool) -> Bool {
        guard !Task.isCancelled, state.accepts(attempt) else {
            if state.accepts(attempt) { state.invalidate() }
            return false
        }
        guard source() else { state.rejectSource(); return false }
        return true
    }
    func invalidate() {
        state.invalidate(); task?.cancel()
        // An already submitted PhotoKit transaction cannot be cancelled. Keep the
        // flight lock until its completion; never let an old callback mark a new card saved.
    }
}
