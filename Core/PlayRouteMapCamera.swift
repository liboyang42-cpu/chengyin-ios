import Foundation

/// Read-only inspection and bounded camera hints for the personal route map.
/// Selection never changes the authoritative current stop or starts navigation.
public enum PlayRouteMapCamera {
    public enum Action: Equatable { case overview, current, preview(Int) }
    public struct Read: Equatable {
        private let snapshot: PlaySnapshot
        private let context: PlayInteractionContext
        public let presentation: PlayRouteMapPresentation
        public init?(snapshot: PlaySnapshot?, context: PlayInteractionContext?) {
            guard let snapshot, let context, context.authoritativeMode == .cityOrientation,
                  let presentation = PlayRouteMapPresentation(snapshot: snapshot) else { return nil }
            self.snapshot = snapshot; self.context = context; self.presentation = presentation
        }
    }
    public struct Preview: Equatable {
        private let read: Read
        private let id: Int
        fileprivate init(read: Read, id: Int) { self.read = read; self.id = id }
        public func resolve(current: Read?) -> PlayRouteMapPresentation.Stop? {
            guard read == current else { return nil }
            return read.presentation.stops.first { $0.id == id && $0.state != .locked }
        }
    }
    public enum CameraIssue: String, Equatable {
        case missingCoordinates, unsupportedExtent
        public var labelKey: String { "playRouteCamera.issue." + rawValue }
    }
    public struct Decision {
        public let action: Action
        public let preview: Preview?
        public let fit: MapMarkerDensity.Fit?
        public let issue: CameraIssue?
    }
    /// A rendered button belongs to one visible map lifetime and one exact read.
    /// A consumed request cannot replace a newer choice, even with identical IDs.
    public struct Gate {
        public struct Request {
            fileprivate let revision: UUID
            fileprivate let read: Read
            fileprivate let decision: Decision
        }
        private var revision = UUID()
        private var visible = false
        public init() {}
        public mutating func appear() { visible = true; invalidate() }
        public mutating func disappear() { visible = false; invalidate() }
        public mutating func invalidate() { revision = UUID() }
        public func request(_ action: Action, read: Read?) -> Request? {
            guard visible, let read else { return nil }
            let presentation = read.presentation
            let selected: PlayRouteMapPresentation.Stop?
            let points: [PlayRouteMapPresentation.Coordinate]
            switch action {
            case .overview:
                selected = nil; points = presentation.mappedStops.compactMap(\.coordinate)
            case .current:
                guard let id = presentation.currentNodeID,
                      let stop = presentation.stops.first(where: { $0.id == id && $0.state == .current }) else { return nil }
                selected = stop; points = stop.coordinate.map { [$0] } ?? []
            case .preview(let id):
                guard let stop = presentation.stops.first(where: { $0.id == id && $0.state != .locked }) else { return nil }
                selected = stop; points = stop.coordinate.map { [$0] } ?? []
            }
            let fit = MapMarkerDensity.fit(points.map { .init(latitude: $0.latitude, longitude: $0.longitude) })
            let issue: CameraIssue? = fit == nil ? (points.isEmpty ? .missingCoordinates : .unsupportedExtent) : nil
            let decision = Decision(action: action, preview: selected.map { Preview(read: read, id: $0.id) }, fit: fit, issue: issue)
            return Request(revision: revision, read: read, decision: decision)
        }
        public mutating func consume(_ request: Request, current: Read?) -> Decision? {
            guard visible, request.revision == revision else { return nil }
            invalidate()
            guard request.read == current else { return nil }
            return request.decision
        }
    }
}
