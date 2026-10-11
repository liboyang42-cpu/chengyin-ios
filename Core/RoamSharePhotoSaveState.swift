import Foundation

/// Value-only authority for one prepared share card. It never reads or writes Photos.
public struct RoamSharePhotoSaveState {
    public struct Selection: Equatable {
        public let record: RoamHistoryRecord
        public let includeRoute: Bool
        public init(record: RoamHistoryRecord, includeRoute: Bool) {
            self.record = record; self.includeRoute = includeRoute
        }
    }
    public struct Attempt: Equatable {
        fileprivate let selection: Selection
        fileprivate let generation: UUID
    }
    public enum Authorization: Sendable { case notDetermined, authorized, denied, restricted, unavailable }
    public enum Phase: Equatable, Sendable {
        case ready, requestingPermission, saving, saved, permissionDenied, restricted, unavailable, sourceChanged, failed
    }
    public private(set) var phase: Phase = .ready
    public private(set) var selection: Selection?
    private var generation = UUID()
    public init() {}

    public mutating func prepare(_ selection: Selection) {
        guard self.selection != selection else { return }
        invalidate(); self.selection = selection
    }
    public mutating func invalidate() {
        generation = UUID(); selection = nil; phase = .ready
    }
    public mutating func rejectSource() {
        invalidate(); phase = .sourceChanged
    }
    public mutating func begin(for current: Selection) -> Attempt? {
        guard selection == current, phase != .requestingPermission,
              phase != .saving, phase != .saved else { return nil }
        generation = UUID(); phase = .requestingPermission
        return Attempt(selection: current, generation: generation)
    }
    public func accepts(_ attempt: Attempt) -> Bool {
        selection == attempt.selection && generation == attempt.generation
    }
    @discardableResult public mutating func authorize(_ status: Authorization, for attempt: Attempt) -> Bool {
        guard accepts(attempt), phase == .requestingPermission else { return false }
        switch status {
        case .authorized: phase = .saving; return true
        case .denied: phase = .permissionDenied
        case .restricted: phase = .restricted
        case .unavailable: phase = .unavailable
        case .notDetermined: phase = .failed
        }
        return false
    }
    public mutating func complete(saved: Bool, for attempt: Attempt) {
        guard accepts(attempt), phase == .saving else { return }
        phase = saved ? .saved : .failed
    }
}
