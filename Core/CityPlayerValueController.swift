import Foundation
import Observation

@available(macOS 14.0, *)
@MainActor @Observable public final class CityPlayerValueController {
    public let read: CityValueBoundedCapture
    private let service: CityPlayerValueService
    private var generation = UUID()
    private var references: [CityPlayerValueServiceReference] = []
    private var selectedReference: CityPlayerValueServiceReference?
    private var visitValue: CityPlayerValueVisit?
    private var requestIDs: [Int64: String] = [:]
    private var pendingFeedback: (String, CityPlayerValueFeedback)?
    private var loading = false
    private var pageVerified = false
    private var issueValue: String?
    public var configured: Bool { service.isCurrent }
    public var services: [CityPlayerValueServiceReference] { configured ? references : [] }
    public var selected: CityPlayerValueServiceReference? { configured ? selectedReference : nil }
    public var visit: CityPlayerValueVisit? { configured ? visitValue : nil }
    public var busy: Bool { configured && loading }
    public var issue: String? { configured ? issueValue : "NOT_CONFIGURED" }
    public var canBegin: Bool { (pageVerified || (issueValue == "BIND_UNKNOWN" && selected.map { requestIDs[$0.poiId] != nil } == true)) && !busy && selected?.canBegin == true && service.allows(.begin) && read.board.lifecycle == "FROZEN" && service.mapPage != nil }
    public var canOpenSource: Bool { pageVerified && !busy && configured && visit?.closed == false && selected != nil }
    public var canFeedback: Bool { !busy && visit?.closed == false && pendingFeedback == nil && service.allows(.feedback) }
    public var canRetryFeedback: Bool { !busy && pendingFeedback != nil && service.allows(.feedback) }
    public init(read: CityValueBoundedCapture, service: CityPlayerValueService) { self.read = read; self.service = service }
    public func suspend() { generation = UUID(); loading = false; pageVerified = false }
    private func valid(_ ticket: UUID) -> Bool { ticket == generation && service.isCurrent && !Task.isCancelled }
    public func load() async {
        guard service.allows(.services), let page = service.mapPage, !Task.isCancelled, !loading else { return }
        let ticket = generation; loading = true; pageVerified = false; issueValue = nil
        defer { if valid(ticket) { loading = false } }
        do {
            let response = try await service.send(.services(service.scope, page: page), as: CityPlayerValueServices.self)
            try response.validate(read, page: page); guard valid(ticket) else { return }
            references = response.services; pageVerified = true
            if let selectedReference { self.selectedReference = references.first { $0.poiId == selectedReference.poiId && $0.pointId == selectedReference.pointId } }
            if self.selectedReference == nil { visitValue = nil }
            if let reference = selectedReference, let id = reference.visitId { try await readVisit(reference, id: id, ticket: ticket) }
        } catch { if valid(ticket) { issueValue = "READ_FAILED" } }
    }
    public func select(_ reference: CityPlayerValueServiceReference) async {
        guard !busy, configured, references.contains(reference), pendingFeedback == nil, !Task.isCancelled else { return }
        generation = UUID(); let ticket = generation; selectedReference = reference; visitValue = nil; issueValue = nil
        if let id = reference.visitId {
            loading = true; defer { if valid(ticket) { loading = false } }
            do { try await readVisit(reference, id: id, ticket: ticket) } catch { if valid(ticket) { issueValue = "READ_FAILED" } }
        }
    }
    /// Called only after the explicit bind confirmation. Opening/scrolling a page never calls this method.
    public func begin() async {
        guard canBegin, let reference = selectedReference, let page = service.mapPage, !Task.isCancelled else { return }
        let ticket = generation; loading = true; pageVerified = false; issueValue = nil
        let requestID = requestIDs[reference.poiId] ?? UUID().uuidString
        requestIDs[reference.poiId] = requestID // Unknown outcome retries exactly this intent; restart discovers server's unique member+POI binding.
        defer { if valid(ticket) { loading = false } }
        do {
            let binding = try await service.send(.begin(requestID: requestID, scope: service.scope,
                page: page, pointID: reference.pointId, poiID: reference.poiId), as: CityPlayerValueBinding.self)
            guard ["ENTERED", "REPLAYED", "ALREADY_BOUND"].contains(binding.status), CityReadRoute.validID(binding.visitId),
                  binding.rulesReleaseId == service.scope.rulesReleaseId else { throw APIError.malformedResponse }
            guard valid(ticket) else { return }
            try await readVisit(reference, id: binding.visitId, ticket: ticket)
            // Refresh only the binding projection; never submit another business action.
            let response = try await service.send(.services(service.scope, page: page), as: CityPlayerValueServices.self)
            try response.validate(read, page: page); guard valid(ticket) else { return }
            references = response.services; pageVerified = true; selectedReference = references.first { $0.poiId == reference.poiId && $0.pointId == reference.pointId }
        } catch { if valid(ticket) { issueValue = "BIND_UNKNOWN" } }
    }
    /// Dismissal is not a success event. Read the original binding, then its same-page projection.
    public func sourceClosed(visitID: String) async {
        guard configured, !busy, visitValue?.visitId == visitID, selectedReference != nil, !Task.isCancelled else { return }
        await refreshVisit()
        guard configured, visitValue?.visitId == visitID, !Task.isCancelled else { return }
        await load()
    }
    public func refreshVisit() async {
        guard !busy, let reference = selectedReference, let id = visitValue?.visitId ?? reference.visitId, !Task.isCancelled else { return }
        let ticket = generation; loading = true; issueValue = nil
        defer { if valid(ticket) { loading = false } }
        do { try await readVisit(reference, id: id, ticket: ticket) } catch { if valid(ticket) { issueValue = "READ_FAILED" } }
    }
    public func feedback(_ value: CityPlayerValueFeedback) async {
        guard canFeedback, value.valid, let visit else { return }
        if case .rating = value { guard visit.serviceSuccess == "OBSERVED", visit.rating == nil else { return } }
        pendingFeedback = (visit.visitId, value); await retryFeedback()
    }
    public func retryFeedback() async {
        guard canRetryFeedback, let pendingFeedback, let reference = selectedReference, !Task.isCancelled else { return }
        let ticket = generation; loading = true; issueValue = nil
        defer { if valid(ticket) { loading = false } }
        do {
            let reply = try await service.send(.feedback(visitID: pendingFeedback.0, pendingFeedback.1), as: CityPlayerValueBinding.self)
            guard reply.visitId == pendingFeedback.0, reply.rulesReleaseId == service.scope.rulesReleaseId,
                  ["ACCEPTED", "REPLAYED"].contains(reply.status) else { throw APIError.malformedResponse }
            guard valid(ticket) else { return }; self.pendingFeedback = nil
            try await readVisit(reference, id: pendingFeedback.0, ticket: ticket)
        } catch { if valid(ticket) { issueValue = "FEEDBACK_UNKNOWN" } }
    }
    private func readVisit(_ reference: CityPlayerValueServiceReference, id: String, ticket: UUID) async throws {
        let value = try await service.send(.visit(id), as: CityPlayerValueVisit.self)
        try value.validate(scope: service.scope, reference: reference, visitID: id)
        guard valid(ticket) else { throw CancellationError() }; visitValue = value
    }
}
