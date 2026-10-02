import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Only source-audited JSON POST reads. No default URL, reward, redemption or check-in mutation.
public struct GrowthCenterService {
    private let configuration: APIConfiguration
    private let transport: any HTTPTransport
    public init(configuration: APIConfiguration, transport: any HTTPTransport) {
        self.configuration = configuration; self.transport = transport
    }
    public func center(token: String) async throws -> GrowthCenterRecord { try await read("api/growth/center", token: token) }
    public func progress(token: String) async throws -> GrowthPlayProgress { try await read("api/play/growth", token: token) }
    public func completed(token: String) async throws -> [GrowthCompletedActivity] { try await read("api/play/my-completed", token: token) }
    public func leaderboard(query: GrowthBoardQuery, limit: Int = 50, token: String) async throws -> GrowthLeaderboard {
        guard (1...50).contains(limit) else { throw APIError.invalidRequest }
        let board: GrowthLeaderboard = try await read("api/growth/leaderboard", fields: ["metric": query.metric.rawValue, "period": query.period.rawValue, "limit": limit], token: token)
        guard board.metric == query.metric, board.period == query.period else { throw APIError.malformedResponse }
        return board
    }
    public func overview(token: String) async throws -> GrowthCenterOverview {
        async let centerResult = outcome { try await center(token: token) }
        async let progressResult = outcome { try await progress(token: token) }
        async let completedResult = outcome { try await completed(token: token) }
        async let rankResult = outcome { try await leaderboard(query: GrowthBoardQuery(), limit: 1, token: token) }
        let result = await (centerResult, progressResult, completedResult, rankResult)
        try Task.checkCancellation()
        // No successful private sibling is retained after any 401 or cancellation.
        try requireAuthorized(result.0); try requireAuthorized(result.1)
        try requireAuthorized(result.2); try requireAuthorized(result.3)
        return GrowthCenterOverview(center: section(result.0), progress: section(result.1), completed: section(result.2), rank: section(result.3))
    }
    private func outcome<T>(_ operation: () async throws -> T) async -> Result<T, Error> {
        do { return .success(try await operation()) } catch { return .failure(error) }
    }
    private func requireAuthorized<T>(_ result: Result<T, Error>) throws {
        if case .failure(let error) = result {
            if error is CancellationError || error as? APIError == .unauthorized { throw error }
        }
    }
    private func section<T>(_ result: Result<T, Error>) -> GrowthCenterSection<T> {
        switch result { case .success(let value): return .content(value); case .failure(let error): return .failure(GrowthCenterIssue(error)) }
    }
    private func read<T: Decodable>(_ path: String, fields: [String: Any] = [:], token: String) async throws -> T {
        guard AuthRequestBuilder.isValidToken(token) else { throw APIError.invalidRequest }
        try Task.checkCancellation()
        var request = try AuthRequestBuilder.makeFormRequest(url: configuration.baseURL.appendingPathComponent(path), fields: [:], token: token)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys])
        let (data, status) = try await transport.send(request)
        try Task.checkCancellation()
        let envelope = try? JSONDecoder().decode(Status.self, from: data)
        if status == 401 || envelope?.code == 401 { throw APIError.unauthorized }
        guard (200..<300).contains(status) else { throw APIError.httpStatus(status) }
        guard let envelope else { throw APIError.malformedResponse }
        guard envelope.code == 200 else { throw GrowthCenterReadFailure.rejected(code: envelope.code, message: envelope.message) }
        do { return try JSONDecoder().decode(Payload<T>.self, from: data).data }
        catch { throw APIError.malformedResponse }
    }
    private struct Payload<T: Decodable>: Decodable { let data: T }
    private struct Status: Decodable {
        let code: Int
        let message: String?
        enum CodingKeys: String, CodingKey { case code, msg }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            code = try c.decode(Int.self, forKey: .code)
            message = try? c.decode(String.self, forKey: .msg)
        }
    }
}
