import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct MerchantAftercareEvidenceReceipt: Equatable {
    public let objectKey: String
    public init(objectKey: String) throws {
        guard objectKey.range(of: #"^upload/merchant-aftercare-evidence/[0-9a-f]{32}\.(?:jpe?g|png|gif)$"#, options: .regularExpression) != nil else { throw MerchantBusinessFailure.malformed }
        self.objectKey = objectKey
    }
}
/// Exact uploadOSS contract, dormant by default. No local file paths enter the request.
/// File selection/camera/provider permission flows remain a separate platform integration gate.
public struct MerchantAftercareEvidenceAdapter {
    private let configuration: APIConfiguration
    private let testTransport: (any MerchantBusinessTestTransport)?
    public init(configuration: APIConfiguration, testingTransport: (any MerchantBusinessTestTransport)? = nil) {
        self.configuration = configuration; testTransport = testingTransport
    }
    public func uploadSynthetic(bytes: Data, filename: String, mimeType: String, access: MerchantBusinessAccess, token: String) async throws -> MerchantAftercareEvidenceReceipt {
        guard let testTransport else { throw MerchantBusinessFailure.disabled }
        try access.require(["merchant:aftercare:evidence"])
        guard AuthRequestBuilder.isValidToken(token), !bytes.isEmpty,
              ["image/jpeg", "image/png", "image/gif"].contains(mimeType),
              filename.range(of: #"^[A-Za-z0-9._-]+\.(?:jpe?g|png|gif)$"#, options: .regularExpression) != nil else { throw MerchantBusinessFailure.invalid }
        let boundary = "MerchantEvidence-" + UUID().uuidString
        var request = URLRequest(url: configuration.baseURL.appendingPathComponent("api/common/uploadOSS"))
        request.httpMethod = "POST"; request.cachePolicy = .reloadIgnoringLocalCacheData; request.timeoutInterval = 30
        request.setValue(token, forHTTPHeaderField: "Authorization"); request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        var data = Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"bizType\"\r\n\r\nmerchant_aftercare_evidence\r\n--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\nContent-Type: \(mimeType)\r\n\r\n".utf8)
        data.append(bytes); data.append(Data("\r\n--\(boundary)--\r\n".utf8)); request.httpBody = data
        try Task.checkCancellation()
        let (response, status) = try await testTransport.send(request)
        if status == 401 { throw APIError.unauthorized }; if status == 403 { throw MerchantBusinessFailure.denied }
        guard (200..<300).contains(status), let body = try JSONDecoder().decode(MerchantBusinessValue.self, from: response).object else { throw MerchantBusinessFailure.malformed }
        let code = try body.mbInt("code")
        guard code == 200 else { throw MerchantBusinessFailure.rejected(code, body.mbText("msg")) }
        return try .init(objectKey: body.mbRequiredText("fileName"))
    }
}
