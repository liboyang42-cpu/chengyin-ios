import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor public final class CityOrderedMapReader {
    private let selection: CityOrderedMapRuntimeSelection
    private let transport: any HTTPTransport
    private let isCurrent: () -> Bool
    private var issued: CityOrderedMapReadGrant?
    private var state: CityOrderedMapState?
    private var generation = UUID()
    public init(selection: CityOrderedMapRuntimeSelection, transport: any HTTPTransport, current: @escaping () -> Bool = { false }) {
        self.selection = selection; self.transport = transport; isCurrent = current
    }
    private var current: Bool { isCurrent() && issued != nil && selection.issued() === issued }
    public func retire() { generation = UUID(); state = nil; issued = nil }
    private struct Envelope: Decodable { let code: Int; let errorCode: String?; let data: CityOrderedMapReply? }
    private enum Reset: Error { case required }

    public func load() async throws -> CityOrderedMapRead {
        guard let grant = selection.issued(), isCurrent() else { retire(); throw CityOrderedMapFailure.disabled }
        if issued !== grant { retire(); issued = grant }
        let query = selection.scope.query
        guard current, !Task.isCancelled else { retire(); throw CityOrderedMapFailure.disabled }
        let ticket = UUID(); generation = ticket
        do {
            let prior = state
            let started = ProcessInfo.processInfo.systemUptime
            do {
                let reply = try await read(cursor: prior?.cursor)
                guard current, generation == ticket, !Task.isCancelled else { throw CancellationError() }
                var next: CityOrderedMapState
                if var previous = prior { try previous.ingest(reply, requestedSequence: previous.sequence, query: query); next = previous }
                else { next = try .init(reply, query: query) }
                let value = try next.read(reply, started: started)
                guard value.isFresh() else { throw CityOrderedMapFailure.expired }
                state = next; return value
            } catch {
                // One GET-only recovery, never a command/answer/arrival replay. A malformed,
                // conflicting, dropped or aged batch cannot partially mutate the visible map.
                guard prior != nil, current, generation == ticket, !Task.isCancelled,
                      error is Reset || error as? CityOrderedMapFailure == .malformed else { throw error }
                state = nil
                let recoveryStart = ProcessInfo.processInfo.systemUptime
                let reply = try await read(cursor: nil)
                guard current, generation == ticket, !Task.isCancelled else { throw CancellationError() }
                let next = try CityOrderedMapState(reply, query: query)
                let value = try next.read(reply, started: recoveryStart)
                guard value.isFresh() else { throw CityOrderedMapFailure.expired }
                state = next; return value
            }
        } catch {
            if generation == ticket { state = nil }
            throw error
        }
    }
    private func read(cursor: String?) async throws -> CityOrderedMapReply {
        let request = try CityOrderedMapRequest.make(selection.scope, token: selection.context.session.token, cursor: cursor)
        let (data, status) = try await transport.send(request)
        if status == 401 { throw CityOrderedMapFailure.unauthorized }
        guard data.count <= 262_144 else { throw CityOrderedMapFailure.malformed }
        let envelope: Envelope
        do { envelope = try JSONDecoder().decode(Envelope.self, from: data) }
        catch { throw CityOrderedMapFailure.malformed }
        if envelope.code == 401 { throw CityOrderedMapFailure.unauthorized }
        if status == 409, envelope.code == 409, envelope.errorCode == "CITY_SNAPSHOT_CHANGED" { throw CityOrderedMapFailure.snapshotChanged }
        if status == 409, envelope.code == 409, envelope.errorCode == "CITY_ORDERED_RESET_REQUIRED" { throw Reset.required }
        if status == 422, envelope.code == 422, envelope.errorCode == "CITY_QUERY_TOO_BROAD" { throw CityOrderedMapFailure.queryTooBroad }
        guard current, status == 200, envelope.code == 200, let reply = envelope.data else { throw CityOrderedMapFailure.unavailable }
        return reply
    }
}
