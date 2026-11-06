import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor public final class CityActionBudgetReader {
    enum Receipt { case unknown, complete(Int, CityActionBudgetResult?) }
    private let api: APIConfiguration
    private let transport: any HTTPTransport
    private let current: () -> CityActionBudgetScope?
    private let grant: () -> CityActionBudgetReadGrant?
    private var displayedStateGrant: CityActionBudgetReadGrant?
    private let receiptGrant: (CityOriginalReceiptReference) -> CityOriginalReceiptReadGrant?
    public init(configuration: APIConfiguration, transport: any HTTPTransport, current: @escaping () -> CityActionBudgetScope?,
                grant: @escaping () -> CityActionBudgetReadGrant? = { nil },
                receiptGrant: @escaping (CityOriginalReceiptReference) -> CityOriginalReceiptReadGrant? = { _ in nil }) {
        api = configuration; self.transport = transport; self.current = current; self.grant = grant; self.receiptGrant = receiptGrant
    }
    private func check(_ scope: CityActionBudgetScope) throws {
        try Task.checkCancellation()
        guard current() == scope, api.baseURL == scope.session.baseURL, scope.session.market == .china else { throw CityActionBudgetFailure.stale }
    }
    public func state(_ scope: CityActionBudgetScope, region: String) async throws -> CityActionBudgetState {
        displayedStateGrant = nil
        try check(scope)
        guard CityParticipationCommand.id(region), let issued = grant(), issued.scope == scope, issued.region == region, !issued.isRevoked else { throw CityActionBudgetFailure.disabled }
        var parts = URLComponents(url: api.baseURL.appendingPathComponent("api/city-game/action-budget/state"), resolvingAgainstBaseURL: false)
        parts?.queryItems = [.init(name: "regionId", value: region)]
        guard let url = parts?.url else { throw CityActionBudgetFailure.invalid }
        let (body, status) = try await transport.send(request(url, scope))
        try check(scope)
        guard grant() === issued, !issued.isRevoked, status == 200, body.count <= 1_048_576 else { throw CityActionBudgetFailure.unknown }
        let envelope = try JSONDecoder().decode(StateEnvelope.self, from: body)
        guard envelope.code == 200, envelope.errorCode == nil || envelope.errorCode == "" else { throw CityActionBudgetFailure.unknown }
        try envelope.data.validate(region: region); displayedStateGrant = issued; return envelope.data
    }
    func isStateCurrent(_ scope: CityActionBudgetScope, region: String) -> Bool {
        guard current() == scope, let issued = displayedStateGrant, grant() === issued,
              !issued.isRevoked, issued.scope == scope, issued.region == region else { return false }; return true
    }
    func receipt(_ scope: CityActionBudgetScope, prepared: CityActionBudgetPrepared) async throws -> (Data, Int) {
        try check(scope)
        let reference = try CityOriginalReceiptReference(session: scope.session, domain: .actionBudget, requestID: prepared.command.requestId)
        guard let issued = receiptGrant(reference), issued.reference == reference, !issued.isRevoked else { throw CityActionBudgetFailure.disabled }
        let url = api.baseURL.appendingPathComponent("api/city-game/action-budget/request/\(reference.requestID)")
        let response = try await transport.send(request(url, scope)); try check(scope)
        guard receiptGrant(reference) === issued, !issued.isRevoked else { throw CityActionBudgetFailure.disabled }
        _ = try Self.decodeReceipt(response.0, status: response.1, prepared: prepared); return response
    }
    private func request(_ url: URL, _ scope: CityActionBudgetScope) -> URLRequest {
        var r = URLRequest(url: url); r.httpMethod = "GET"; r.httpShouldHandleCookies = false; r.cachePolicy = .reloadIgnoringLocalCacheData; r.timeoutInterval = 20
        r.setValue(scope.token, forHTTPHeaderField: "Authorization"); r.setValue("application/json", forHTTPHeaderField: "Accept"); return r
    }
    static func decodeReceipt(_ body: Data, status: Int, prepared: CityActionBudgetPrepared) throws -> Receipt {
        guard body.count <= 1_048_576, ![401,403,404].contains(status) else { throw CityActionBudgetFailure.unknown }
        let envelope = try JSONDecoder().decode(ReceiptEnvelope.self, from: body), d = envelope.data, c = prepared.command
        guard envelope.code == status, d.requestId == c.requestId else { throw CityActionBudgetFailure.unknown }
        if status == 202, d.requestStatus == "UNKNOWN", envelope.errorCode == "OUTCOME_UNKNOWN" { return .unknown }
        guard d.requestStatus == "COMPLETE", [200,400,409].contains(status) else { throw CityActionBudgetFailure.unknown }
        if status != 200 {
            guard let code = envelope.errorCode, !code.isEmpty, d.result == nil else { throw CityActionBudgetFailure.unknown }
            return .complete(status, nil)
        }
        guard envelope.errorCode == nil || envelope.errorCode == "", let result = d.result,
              d.contract == prepared.contract, d.scope == "CITY",
              d.teamId == c.teamId, d.sessionId == prepared.sessionID, let binding = d.binding,
              binding.releaseId == c.releaseId, binding.regionId == c.regionId, binding.contentHash == c.contentHash,
              result.requestId == c.requestId, result.budgetVersion == c.expectedVersion + 1,
              result.rollNumber == prepared.expectedRollNumber, result.beforeUnits == prepared.expectedBeforeUnits else { throw CityActionBudgetFailure.unknown }
        try result.validate(dice: prepared.dice, cost: prepared.cost, total: prepared.total)
        return .complete(status, result)
    }
    private struct StateEnvelope: Decodable { let code: Int; let errorCode: String?; let data: CityActionBudgetState }
    private struct ReceiptEnvelope: Decodable {
        let code: Int; let errorCode: String?; let data: Payload
        struct Payload: Decodable {
            let requestId: String, requestStatus: String
            let contract: String?, scope: String?, teamId: String?, sessionId: String?
            let binding: CityParticipationState.Binding?
            let result: CityActionBudgetResult?
        }
    }
}
