import Foundation
import Observation
@available(macOS 14.0, *)
@MainActor @Observable public final class CityValueBoundedMapReader {
 private let transport: CityValueBoundedMapScopedTransport
 private let regionID: String
 private var generation = UUID()
 private var stored: CityValueBoundedCapture?
 public private(set) var loading = false
 public private(set) var issue: CityReadError?
 public private(set) var notPublished = false
 public var capture: CityValueBoundedCapture? { transport.isCurrent ? stored : nil }
 public init(regionID: String, transport: CityValueBoundedMapScopedTransport) { self.regionID = regionID; self.transport = transport }
 public func suspend() { generation = UUID(); stored = nil; loading = false; issue = nil; notPublished = false }
 private func valid(_ ticket: UUID) -> Bool { generation == ticket && transport.isCurrent && !Task.isCancelled }
 public func load() async {
  guard transport.isCurrent, !Task.isCancelled else { suspend(); return }
  generation = UUID(); let ticket = generation; stored = nil; issue = nil; notPublished = false; loading = true
  defer { if generation == ticket { loading = false } }
  do {
   let current = try await read(.current(regionID))
   guard valid(ticket) else { return }
   if current.status == "NO_CURRENT_BOARD" { guard current.regionId == regionID, current.board == nil else { throw CityReadError.invalidResponse }; notPublished = true; return }
   guard current.status == "AVAILABLE", let board = current.board, board.valid, board.regionId == regionID, board.lifecycle == "FROZEN",
         let membership = current.participationStatus, membership != .unavailable, current.pointsStatus == "AVAILABLE",
         let descriptor = current.mapRead, descriptor.valid else { throw CityReadError.pointsUnavailable }
   let query = try CityValueBoundedQuery(bounds:descriptor.initialViewport,datum:descriptor.datum,zoom:descriptor.initialZoom)
   let payload = try await read(.points(board,query))
   let value = try Self.validate(payload,board:board,descriptor:descriptor,query:query,page:1,watermark:nil)
   guard valid(ticket) else { return }; stored = value
  } catch { if valid(ticket) { stored = nil; issue = (error as? CityReadError) ?? .unavailable } }
 }
 public func nextPage() async {
  guard !loading, let previous = capture, let cursor = previous.nextCursor, previous.page < previous.descriptor.maxPages else { return }
  generation = UUID(); let ticket = generation; loading = true; stored = nil; issue = nil
  defer { if generation == ticket { loading = false } }
  do {
   let query = try previous.query.next(cursor)
   let payload = try await read(.points(previous.board,query))
   let value = try Self.validate(payload,board:previous.board,descriptor:previous.descriptor,query:query,page:previous.page+1,watermark:previous.watermark)
   guard valid(ticket) else { return }; stored = value
  } catch { if valid(ticket) { issue = (error as? CityReadError) ?? .unavailable } }
 }
 private func read(_ route: CityValueBoundedRoute) async throws -> CityValueBoundedPayload {
  let (data,status) = try await transport.send(route)
  guard data.count <= 262_144 else { throw CityReadError.invalidResponse }
  let envelope = try JSONDecoder().decode(CityValueBoundedEnvelope.self,from:data)
  if status == 401 || envelope.code == 401 { throw CityReadError.unauthorized }
  guard status == 200, envelope.code == 200 else {
   if envelope.errorCode == "CITY_SNAPSHOT_CHANGED" || envelope.errorCode == "CITY_MAP_CURSOR_STALE" { throw CityReadError.snapshotChanged }
   throw CityReadError.unavailable
  }
  guard let payload = envelope.data, payload.contract == "CITY_PLAYER_READ_V1", payload.scope == "CITY" else { throw CityReadError.invalidResponse }
  return payload
 }
 static func validate(_ payload: CityValueBoundedPayload, board: CityReadBoard, descriptor: CityValueBoundedDescriptor,
                      query: CityValueBoundedQuery, page: Int, watermark: String?) throws -> CityValueBoundedCapture {
  guard payload.status == "AVAILABLE", payload.board == board, descriptor.valid, query.datum == descriptor.datum,
        query.bounds.bounded(descriptor.maxViewportSpanDegrees), (descriptor.minZoom...descriptor.maxZoom).contains(query.zoom),
        payload.mapContract == descriptor.contract, payload.datum == query.datum, payload.viewport == query.bounds, payload.page == page,
        let stamp = payload.watermark, stamp.range(of:"^[a-f0-9]{64}$",options:.regularExpression) != nil,
        watermark == nil || watermark == stamp, payload.grantsNavigation == false, payload.grantsAction == false,
        let complete = payload.complete, let limited = payload.pageLimitReached, let points = payload.points, points.count <= descriptor.pageSize,
        (1...descriptor.maxPages).contains(page), Set(points.map(\.pointId)).count == points.count,
        points.map(\.pointId) == points.map(\.pointId).sorted(), points.allSatisfy({ $0.boundedValid && $0.datum == query.datum && query.layers.contains($0.domain ?? "") && query.bounds.contains($0) }),
        complete ? payload.nextCursor == nil && !limited : (limited ? payload.nextCursor == nil && page == descriptor.maxPages : payload.nextCursor != nil && page < descriptor.maxPages),
        complete || points.count == descriptor.pageSize else { throw CityReadError.invalidResponse }
  if let cursor = payload.nextCursor { _ = try query.next(cursor) }
  return .init(board:board,descriptor:descriptor,query:query,points:points,watermark:stamp,page:page,nextCursor:payload.nextCursor,complete:complete,pageLimitReached:limited)
 }
}
