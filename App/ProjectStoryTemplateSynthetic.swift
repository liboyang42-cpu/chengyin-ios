#if DEBUG
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Generated personal draft responses through the bounded production reader.
/// The transport is entirely in memory; no account, image fetch, or network is used.
@MainActor final class ProjectStoryTemplateSynthetic: ProjectStoryTemplateReading {
    @MainActor final class Wire: HTTPTransport {
        let accountID: Int
        private(set) var listCount = 0, detailCount = 0
        init(accountID: Int) { self.accountID = accountID }

        private func row(_ id: Int) -> ProjectEditJSON {
            var fields: [String: ProjectEditJSON] = [
                "id": .number(Decimal(id)), "memberId": .number(Decimal(accountID)),
                "draftStatus": .number(0), "delFlag": .number(0),
                "title": .string(id == 811 ? "Synthetic story game" : "Synthetic album"),
                "validationMethod": .number(1)
            ]
            if id == 812 {
                fields["advancedConfigJson"] = .string(Self.albumConfiguration)
            }
            return .object(fields)
        }

        // Fixed safe references are display-only. The caption intentionally preserves
        // decomposed Unicode and percent-encoded URL bytes across save and restore.
        private static let albumConfiguration = #"{"schemaVersion":1,"album":{"enabled":true,"images":[{"url":"https://example.com/synthetic/story/e%CC%81.jpg?version=1","line":"Synthetic e\u0301 caption"},{"url":"https://example.com/synthetic/story/second.jpg?version=2","line":"Second synthetic caption"}]}}"#

        func send(_ request: URLRequest) async throws -> (Data, Int) {
            guard request.url?.host == "example.com", let path = request.url?.path, request.httpMethod == "POST",
                  let data = request.httpBody, let body = String(data: data, encoding: .utf8),
                  let contentType = request.value(forHTTPHeaderField: "Content-Type"),
                  contentType.hasPrefix("multipart/form-data; boundary=") else { throw APIError.invalidRequest }
            let boundary = String(contentType.dropFirst("multipart/form-data; boundary=".count))
            guard !boundary.isEmpty else { throw APIError.invalidRequest }
            func matches(_ fields: [String: String]) -> Bool {
                var expected = ""
                for key in fields.keys.sorted() {
                    expected += "--\(boundary)\r\nContent-Disposition: form-data; name=\"\(key)\"\r\n\r\n\(fields[key]!)\r\n"
                }
                expected += "--\(boundary)--\r\n"
                return body.utf8.elementsEqual(expected.utf8)
            }
            let value: ProjectEditJSON
            switch path {
            case "/" + ProjectStoryTemplatePath.list:
                guard matches(["draft_status": "0", "scope": "", "pageNum": "1", "pageSize": "20"]) else { throw APIError.invalidRequest }
                listCount += 1
                value = .object(["rows": .array([row(811), row(812)]), "total": .number(2)])
            case "/" + ProjectStoryTemplatePath.detail:
                guard let id = [811, 812].first(where: { matches(["id": String($0)]) }) else { throw APIError.invalidRequest }
                detailCount += 1; value = row(id)
            default: throw APIError.invalidRequest
            }
            return (try JSONEncoder().encode(["code": ProjectEditJSON.number(200), "data": value]), 200)
        }
    }

    let wire: Wire
    private let client: ProjectStoryTemplateClient
    var identity: UUID { client.identity }
    var listCount: Int { wire.listCount }
    var detailCount: Int { wire.detailCount }
    init(session: ProjectEditSession, currentSession: @escaping () -> ProjectEditSession?) throws {
        let wire = Wire(accountID: session.accountID); self.wire = wire
        let configuration = try APIConfiguration(baseURL: URL(string: "https://example.com")!)
        let paths: Set<String> = [ProjectStoryTemplatePath.list, ProjectStoryTemplatePath.detail]
        let approval = try OperationEndpointApproval(baseURL: configuration.baseURL,
            namespace: session.storageNamespace, accountID: session.accountID, paths: paths)
        client = .init(configuration: configuration, approval: approval, transport: wire,
            currentCredentials: {
                guard let current = currentSession(), current == session else { return nil }
                return try? .init(session: current, token: "synthetic-story-template")
            }, currentCapability: { path in currentSession() == session && paths.contains(path) })
    }
    func isCurrent(session: ProjectEditSession) -> Bool { client.isCurrent(session: session) }
    func list(page: Int, session: ProjectEditSession) async throws -> ProjectStoryTemplatePage {
        try await client.list(page: page, session: session)
    }
    func detail(id: MemberPlayTemplateID, session: ProjectEditSession) async throws -> ProjectStoryTemplateDraft {
        try await client.detail(id: id, session: session)
    }
}
#endif
