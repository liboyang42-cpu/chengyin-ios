import Foundation

/// Only a local display permit. It cannot grant VERIFY or invoke a request.
struct MerchantCityPosterReadLifetime<Source: Equatable> {
    private struct Request {
        let id: UUID
        let owner: ObjectIdentifier
        let scope: UUID
        let source: Source
        let poiID: Int
    }
    private var request: Request?
    var ticket: UUID? { request?.id }
    mutating func retire() { request = nil }
    mutating func begin(owner: ObjectIdentifier, scope: UUID, source: Source, poiID: Int,
                        active: Bool, authorized: Bool) -> UUID? {
        retire()
        guard active, authorized, poiID > 0 else { return nil }
        let value = Request(id: UUID(), owner: owner, scope: scope, source: source, poiID: poiID)
        request = value
        return value.id
    }
    func allows(_ ticket: UUID?, owner: ObjectIdentifier, scope: UUID, source: Source, poiID: Int,
                active: Bool, authorized: Bool) -> Bool {
        guard active, authorized, let request, let ticket else { return false }
        return ticket == request.id && owner == request.owner && scope == request.scope &&
            source == request.source && poiID == request.poiID
    }
}
