import Foundation
import Observation

/// A confirmed create result may lead only to the same owner's existing album reader.
/// This is a read-navigation ticket, never a create/exchange grant or persisted receipt.
public struct RoamCreatedStampTarget: Hashable {
    public let stampID: Int
    private let readerID: ObjectIdentifier
    private let ownerKey: String
    private let epoch: UInt64
    @MainActor public init?(phase: RoamStampCaptureCoordinator.Phase, origin: RetainedImageScope,
                           reader: any RoamExperienceReading) {
        guard case .created(let id) = phase, id > 0, origin.destination == .stamp,
              let identity = reader.identity, let namespace = origin.namespace,
              origin.accountID == identity.scope.accountID,
              origin.realm.utf8.elementsEqual(identity.scope.deployment.utf8),
              namespace.utf8.elementsEqual(identity.scope.namespace.utf8) else { return nil }
        stampID = id; readerID = ObjectIdentifier(reader)
        ownerKey = identity.scope.storageKey; epoch = identity.epoch
    }
    @MainActor public func isCurrent(reader: any RoamExperienceReading) -> Bool {
        guard let identity = reader.identity else { return false }
        return ObjectIdentifier(reader) == readerID && identity.scope.storageKey == ownerKey && identity.epoch == epoch
    }
}

/// Read one existing stamp/list page per request. Never guesses a photo from the capture,
/// creates another stamp, scans indefinitely, or displays a different/hidden stamp.
@MainActor @Observable public final class RoamCreatedStampLookup {
    public enum Phase: Equatable { case idle, loading, more, found, hidden, missing, failed, unavailable }
    public private(set) var phase: Phase = .idle
    public private(set) var stamp: RoamAlbumStamp?
    public private(set) var error: Error?
    public let target: RoamCreatedStampTarget
    private let reader: any RoamExperienceReading
    private var nextPage = 1
    private var generation = 0
    private let pageSize = 20
    public init(target: RoamCreatedStampTarget, reader: any RoamExperienceReading) {
        self.target = target; self.reader = reader
    }
    public func cancel() {
        generation += 1; nextPage = 1; stamp = nil; error = nil; phase = .idle
    }
    public func refresh() async { cancel(); await loadNext() }
    public func loadNext() async {
        guard phase == .idle || phase == .more || phase == .failed else { return }
        guard target.isCurrent(reader: reader) else { retire(); return }
        guard reader.isConfigured else { error = APIError.notConfigured; phase = .failed; return }
        let ticket = generation, page = nextPage
        phase = .loading; error = nil
        do {
            try Task.checkCancellation()
            let result = try await reader.album(page: page, pageSize: pageSize)
            guard ticket == generation else { return }
            guard target.isCurrent(reader: reader) else { retire(); return }
            try Task.checkCancellation()
            guard reader.isConfigured else { throw APIError.notConfigured }
            guard result.pageNum == page, result.pageSize == pageSize, result.total >= result.list.count else {
                throw APIError.malformedResponse
            }
            let matching = result.list.filter { $0.id == target.stampID }
            guard matching.count <= 1 else { throw APIError.malformedResponse }
            if let value = matching.first {
                if value.isVisible { stamp = value; phase = .found }
                else { stamp = nil; phase = .hidden }
            } else if result.hasMore {
                nextPage += 1; phase = .more
            } else { phase = .missing }
        } catch {
            guard ticket == generation else { return }
            guard target.isCurrent(reader: reader) else { retire(); return }
            if Task.isCancelled || error is CancellationError { cancel(); return }
            stamp = nil; self.error = error
            phase = (error as? APIError) == .unauthorized ? .unavailable : .failed
        }
    }
    private func retire() { cancel(); phase = .unavailable }
}
