import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Dormant, exact source wire construction. Building is side-effect free. No instance is
/// mounted into AppSession and no live HTTP transport is supplied by this module.
public enum TemplateAuthoringWireRequestBuilder {
    public static func make(_ descriptor: TemplateAuthoringRequest, configuration: APIConfiguration,
                            token: String, boundary: String = "TemplateAuthor-" + UUID().uuidString) throws -> URLRequest {
        guard AuthRequestBuilder.isValidToken(token), descriptor.method == "POST" else { throw APIError.invalidRequest }
        let jsonPaths = Set(["/api/template/draft", "/api/template/publish"])
        let formPaths = Set(["/api/template/my-list", "/api/template/updateLibraryStatus", "/api/template/delete", "/api/common/dict"])
        guard jsonPaths.contains(descriptor.path) || formPaths.contains(descriptor.path) else { throw APIError.invalidRequest }
        switch descriptor.path {
        case "/api/template/my-list":
            if descriptor != TemplateAuthoringContract.listMine() {
                guard case .form(let fields) = descriptor.body,
                      let rawPage = fields["pageNum"], let page = Int(rawPage),
                      let keyword = fields["keyword"],
                      descriptor == (try TemplateOwnShelfPage.request(page: page, keyword: keyword)) else { throw APIError.invalidRequest }
            }
        case "/api/template/delete", "/api/template/updateLibraryStatus":
            guard descriptor.mutates, case .form(let fields) = descriptor.body,
                  let raw = fields["template_id"], let id = Int(raw), id > 0, raw == String(id) else { throw APIError.invalidRequest }
            let expected: Set<String> = descriptor.path.hasSuffix("delete") ? ["template_id"] : ["template_id", "publish_status"]
            guard Set(fields.keys) == expected else { throw APIError.invalidRequest }
            if expected.contains("publish_status") {
                guard ["0", "1"].contains(fields["publish_status"] ?? "") else { throw APIError.invalidRequest }
            }
        case "/api/template/draft", "/api/template/publish":
            // Existing-template edit/hydration has no audited private contract.
            guard descriptor.mutates, case .json(let fields) = descriptor.body,
                  fields["id"] == nil, let title = fields["title"]?.string,
                  !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw APIError.invalidRequest }
        case "/api/common/dict":
            guard !descriptor.mutates, case .form(let fields) = descriptor.body,
                  let type = fields["dictType"], descriptor == (try TemplateAuthoringContract.dictionary(type)) else { throw APIError.invalidRequest }
        default: throw APIError.invalidRequest
        }
        var request = URLRequest(url: configuration.baseURL.appendingPathComponent(String(descriptor.path.dropFirst())))
        request.httpMethod = "POST"; request.timeoutInterval = 30
        request.setValue(token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        switch descriptor.body {
        case .json(let fields):
            guard jsonPaths.contains(descriptor.path), descriptor.mutates else { throw APIError.invalidRequest }
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            request.httpBody = try encoder.encode(fields)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        case .form(let fields):
            guard formPaths.contains(descriptor.path), boundary.range(of: "^[A-Za-z0-9-]{1,70}$", options: .regularExpression) != nil else { throw APIError.invalidRequest }
            // Flutter uses Dio FormData; retain multipart field names/values, including blanks.
            var body = Data()
            for key in fields.keys.sorted() {
                guard key.range(of: "^[A-Za-z_][A-Za-z0-9_]*$", options: .regularExpression) != nil, let value = fields[key], !value.contains(boundary) else { throw APIError.invalidRequest }
                body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(key)\"\r\n\r\n\(value)\r\n".utf8))
            }
            body.append(Data("--\(boundary)--\r\n".utf8)); request.httpBody = body
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        }
        return request
    }
}
