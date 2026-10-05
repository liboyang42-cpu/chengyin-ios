import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Only these source filter styles may be burned into the uploaded image.
public enum PlayPhotoFilter: String, CaseIterable {
    case nightVision = "night_vision", petPOV = "pet_pov"
}

extension PlayExperienceService {
    /// Source play_api.dart uploadImage: one multipart `file`, top-level `url`.
    /// Upload is not node completion, receipt evidence, or a reward.
    @MainActor public func uploadPhoto(_ bytes: Data, mimeType: String, token: String) async throws -> String {
        try checkReadLifetime()
        guard enabled.contains(.mediaUpload) else { throw PlayExperienceError.disabled }
        guard AuthRequestBuilder.isValidToken(token), !bytes.isEmpty, bytes.count <= 20 * 1024 * 1024,
              ["image/jpeg", "image/png"].contains(mimeType) else { throw APIError.invalidRequest }
        let boundary = "PlayPhoto-" + UUID().uuidString
        let ext = mimeType == "image/png" ? "png" : "jpg"
        var body = Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"capture.\(ext)\"\r\nContent-Type: \(mimeType)\r\n\r\n".utf8)
        body.append(bytes); body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        var request = URLRequest(url: configuration.baseURL.appendingPathComponent("api/common/uploadOSS"))
        request.httpMethod = "POST"; request.httpBody = body; request.timeoutInterval = 30
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        try Task.checkCancellation()
        let data: Data, status: Int
        do {
            try checkReadLifetime()
            (data, status) = try await transport.send(request)
        } catch { try checkReadLifetime(); throw error }
        try checkReadLifetime()
        try Task.checkCancellation()
        let envelope = try? JSONDecoder().decode(PlayWireValue.self, from: data)
        if status == 401 || envelope?["code"].tolerantInteger == 401 { throw PlayExperienceError.unauthorized }
        guard (200..<300).contains(status) else { throw PlayExperienceError.unknownResult }
        guard let code = envelope?["code"].tolerantInteger else { throw PlayExperienceError.malformed }
        guard code == 200 else { throw PlayExperienceError.rejected(code, envelope?["msg"].text) }
        guard let url = envelope?["url"].text, Self.validHTTPS(url) else { throw PlayExperienceError.malformed }
        return url
    }
}
