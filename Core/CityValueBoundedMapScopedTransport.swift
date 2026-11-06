import Foundation
import Observation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
/// Independent read-only approval. Never issued by login, role or a current-snapshot response.
@available(macOS 14.0, *)
@MainActor @Observable public final class CityValueBoundedMapApproval {
 public let readApproval: CityPlayerReadApproval
 public let revision = UUID()
 public private(set) var revoked = false
 public init(readApproval: CityPlayerReadApproval) throws {
  guard readApproval.matches(readApproval.context) else { throw APIError.invalidConfiguration }
  self.readApproval = readApproval
 }
 public func revoke() { revoked = true }
 public func matches(_ context: RuntimeDependencyContext) -> Bool { !revoked && readApproval.matches(context) }
}
public enum CityValueBoundedRoute: Equatable {
 case current(String)
 case points(CityReadBoard, CityValueBoundedQuery)
 func request(baseURL: URL, token: String) throws -> URLRequest {
  let api = try APIConfiguration(baseURL: baseURL)
  guard AuthRequestBuilder.isValidToken(token) else { throw APIError.invalidRequest }
  let path: String; var fields: [String:String]
  switch self {
  case .current(let region): guard CityReadRoute.validID(region) else { throw APIError.invalidRequest }; path = "current"; fields = ["regionId":region]
  case .points(let board, let query):
   guard board.valid, board.lifecycle == "FROZEN" else { throw APIError.invalidRequest }
   path = "points"; fields = ["regionId":board.regionId,"boardId":board.boardId,"seasonId":board.seasonId,"rulesReleaseId":board.rulesReleaseId,"revision":String(board.revision)]
   fields.merge(query.fields) { _, new in new }
  }
  guard var components = URLComponents(url: api.baseURL.appendingPathComponent("api/city-game/" + path), resolvingAgainstBaseURL:false) else { throw APIError.invalidRequest }
  components.queryItems = fields.keys.sorted().map { URLQueryItem(name:$0,value:fields[$0]) }
  guard let url = components.url else { throw APIError.invalidRequest }
  var r = URLRequest(url:url); r.httpMethod = "GET"; r.httpShouldHandleCookies = false; r.cachePolicy = .reloadIgnoringLocalCacheData
  r.setValue(token,forHTTPHeaderField:"Authorization"); r.setValue("application/json",forHTTPHeaderField:"Accept"); return r
 }
}
@available(macOS 14.0, *)
@MainActor public final class CityValueBoundedMapScopedTransport {
 private let approval: CityValueBoundedMapApproval?
 private let underlying: any HTTPTransport
 private let context: () -> RuntimeDependencyContext?
 private let currentApproval: () -> CityValueBoundedMapApproval?
 private let unauthorized: () -> Void
 public init(approval: CityValueBoundedMapApproval? = nil, underlying: any HTTPTransport,
             context: @escaping () -> RuntimeDependencyContext?, currentApproval: @escaping () -> CityValueBoundedMapApproval?, unauthorized: @escaping () -> Void = {}) {
  self.approval = approval; self.underlying = underlying; self.context = context; self.currentApproval = currentApproval; self.unauthorized = unauthorized
 }
 public var isCurrent: Bool { guard let approval, currentApproval() === approval, let context = context() else { return false }; return approval.matches(context) }
 func send(_ route: CityValueBoundedRoute) async throws -> (Data,Int) {
  guard isCurrent, let approval else { throw APIError.notConfigured }
  let original = approval.readApproval.context
  switch route { case .current(let region): guard region == approval.readApproval.regionID else { throw APIError.invalidRequest }
  case .points(let board,_): guard board.regionId == approval.readApproval.regionID else { throw APIError.invalidRequest } }
  try Task.checkCancellation()
  let response: (Data,Int)
  do { response = try await underlying.send(route.request(baseURL:original.baseURL,token:original.session.token)) }
  catch { guard isCurrent else { throw APIError.notConfigured }; throw error }
  guard isCurrent else { throw APIError.notConfigured }; try Task.checkCancellation()
  if response.1 == 401 { unauthorized(); throw CityReadError.unauthorized }
  if response.0.count <= 262_144, let envelope = try? JSONDecoder().decode(CityValueBoundedEnvelope.self,from:response.0), envelope.code == 401 { unauthorized(); throw CityReadError.unauthorized }
  return response
 }
}
