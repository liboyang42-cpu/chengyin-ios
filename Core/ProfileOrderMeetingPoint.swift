import Foundation
import Observation

/// A destination is derived only from the displayed, currently owned order.
/// Complete reader identity includes approval and viewer revisions.
public struct ProfileOrderMeetingPointContext: Equatable {
    public let registrationID: Int
    public let readerID: ObjectIdentifier
    public let identity: ProfileReadIdentity
    public let destination: PlatformMapDestination

    @MainActor public static func capture(order: ProfileOrder, requestedID: Int,
        reader: any ProfileReading) -> Self? {
        guard requestedID > 0, order.id == requestedID, reader.isConfigured,
              let identity = reader.identity, identity.accountID > 0,
              order.memberID == identity.accountID else { return nil }
        let destination = PlatformMapDestination(name: order.meetingPoint ?? "",
            address: order.meetingPoint, latitude: order.gatherLatitude, longitude: order.gatherLongitude)
        guard destination.hasCoordinates else { return nil }
        return .init(registrationID: requestedID, readerID: ObjectIdentifier(reader),
                     identity: identity, destination: destination)
    }
    public static func == (lhs: Self, rhs: Self) -> Bool {
        func sameText(_ a: String?, _ b: String?) -> Bool {
            switch (a, b) {
            case (nil, nil): return true
            case (.some(let a), .some(let b)): return a.utf8.elementsEqual(b.utf8)
            default: return false
            }
        }
        return lhs.registrationID == rhs.registrationID && lhs.readerID == rhs.readerID && lhs.identity == rhs.identity &&
        lhs.destination.name.utf8.elementsEqual(rhs.destination.name.utf8) &&
        sameText(lhs.destination.address, rhs.destination.address) &&
        lhs.destination.latitude == rhs.destination.latitude && lhs.destination.longitude == rhs.destination.longitude
    }
}

public struct ProfileOrderMeetingPointReview: Identifiable, Equatable {
    public let id: UUID
    public let context: ProfileOrderMeetingPointContext
    fileprivate init(context: ProfileOrderMeetingPointContext) { id = UUID(); self.context = context }
}
public enum ProfileOrderMeetingPointOutcome: Equatable { case opened, failed }

/// This model owns no location manager, backend request, or permission. It only
/// consumes an explicit review before calling the supplied handoff once.
@MainActor @Observable public final class ProfileOrderMeetingPointModel {
    public let expected: ProfileOrderMeetingPointContext?
    public private(set) var review: ProfileOrderMeetingPointReview?
    public private(set) var isOpening = false
    public private(set) var outcome: ProfileOrderMeetingPointOutcome?
    private var visible = false
    private var active = false
    private var retired = false
    private var generation = UUID()
    public init(context: ProfileOrderMeetingPointContext?) { expected = context }

    public func matches(_ current: ProfileOrderMeetingPointContext?) -> Bool {
        !retired && expected != nil && expected == current
    }
    public func appear(current: ProfileOrderMeetingPointContext?, sceneActive: Bool) {
        guard matches(current) else { retire(); return }
        visible = true; active = sceneActive
    }
    public func disappear() { visible = false; clearPresentation() }
    public func sceneChanged(active: Bool, current: ProfileOrderMeetingPointContext?) {
        guard matches(current) else { retire(); return }
        self.active = visible && active
        if !self.active { clearPresentation() }
    }
    public func retire() { retired = true; visible = false; clearPresentation() }
    private func clearPresentation() {
        generation = UUID(); active = false; review = nil; isOpening = false; outcome = nil
    }
    public func canPrepare(current: ProfileOrderMeetingPointContext?) -> Bool {
        visible && active && matches(current) && review == nil && !isOpening
    }
    public func prepare(current: ProfileOrderMeetingPointContext?) {
        guard canPrepare(current: current), let expected else { return }
        outcome = nil; review = .init(context: expected)
    }
    public func owns(_ offered: ProfileOrderMeetingPointReview, current: ProfileOrderMeetingPointContext?) -> Bool {
        visible && active && matches(current) && review == offered && expected == offered.context
    }
    @discardableResult public func cancel(id: UUID) -> Bool {
        guard review?.id == id, !isOpening else { return false }
        review = nil; outcome = nil; return true
    }
    public func confirm(_ offered: ProfileOrderMeetingPointReview,
        current: @MainActor () -> ProfileOrderMeetingPointContext?,
        open: @MainActor (PlatformMapDestination) async -> Bool) async {
        guard !Task.isCancelled, owns(offered, current: current()), !isOpening else { return }
        // Consume before the first suspension: a queued duplicate cannot dispatch.
        review = nil; isOpening = true; outcome = nil
        let request = generation
        let opened = await open(offered.context.destination)
        guard !Task.isCancelled, request == generation, visible, active, matches(current()) else { return }
        isOpening = false; outcome = opened ? .opened : .failed
    }
}
