import Foundation

/// A map camera observation, never a device location or an arrival fix. MapKit's
/// CLLocationCoordinate2D reference frame is WGS84. Keep that datum attached.
public struct SearchMapViewport: Equatable {
    public let center: RoamCoordinate
    public let latitudeSpan, longitudeSpan: Double
    public let datum: WalkingCoordinateDatum
    public init?(latitude: Double, longitude: Double, latitudeSpan: Double, longitudeSpan: Double,
                 datum: WalkingCoordinateDatum) {
        guard let center = RoamCoordinate(latitude: latitude, longitude: longitude),
              latitudeSpan.isFinite, longitudeSpan.isFinite,
              latitudeSpan > 0, longitudeSpan > 0,
              abs(latitude) + latitudeSpan / 2 <= 85,
              abs(longitude) + longitudeSpan / 2 <= 180 else { return nil }
        self.center = center; self.latitudeSpan = latitudeSpan; self.longitudeSpan = longitudeSpan; self.datum = datum
    }
}

/// A single view-lifetime draft. Panning only replaces this local ticket. Only an
/// explicit user action may consume it, under the same reader/manual-area/lifecycle.
public struct SearchMapViewportSelection {
    public struct Context: Hashable {
        public let readerScope: UUID
        public let manualAreaRevision: UInt64
        public let presentationID: UUID
        public init(readerScope: UUID, manualAreaRevision: UInt64, presentationID: UUID) {
            self.readerScope = readerScope; self.manualAreaRevision = manualAreaRevision; self.presentationID = presentationID
        }
    }
    public struct Ticket: Equatable, Identifiable {
        public let id = UUID()
        public let viewport: SearchMapViewport
        public let context: Context
        fileprivate init(viewport: SearchMapViewport, context: Context) { self.viewport = viewport; self.context = context }
    }
    public private(set) var draft: Ticket?
    public init() {}
    public mutating func invalidate() { draft = nil }
    public mutating func observe(_ viewport: SearchMapViewport?, context: Context) {
        // nil means moving, programmatic positioning, invalid geometry or departure.
        draft = viewport.map { Ticket(viewport: $0, context: context) }
    }
    public func current(in context: Context) -> Ticket? {
        guard draft?.context == context else { return nil }
        return draft
    }
    public func canSearch(_ ticket: Ticket, context: Context, readerConfigured: Bool, active: Bool) -> Bool {
        draft == ticket && ticket.context == context && ticket.viewport.datum == .wgs84 && readerConfigured && active
    }
    public mutating func consume(_ ticket: Ticket, context: Context, readerConfigured: Bool, active: Bool) -> RuntimeLocationProjection.MapCenter? {
        guard canSearch(ticket, context: context, readerConfigured: readerConfigured, active: active) else { return nil }
        // Consume before conversion, including failure; duplicate/late taps cannot replay.
        draft = nil
        return try? RuntimeLocationProjection.gcj02MapCenter(.init(coordinate: ticket.viewport.center, datum: ticket.viewport.datum))
    }
}
