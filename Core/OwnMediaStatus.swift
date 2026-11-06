import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Explicit status-only read. Returned URL fields are deliberately not decoded or consumed.
public struct OwnMediaStatus: Equatable {
    public let asset: OwnMediaAsset
    public static func decode(_ data: Data, requestedID: Int64) throws -> Self {
        struct Envelope: Decodable { let code: Int; let data: Row? }
        struct Row: Decodable {
            let assetId: Int64
            let reviewState: String
            let reviewReason: String?
            let mediaType: String?
            enum CodingKeys: String, CodingKey { case assetId, reviewState, reviewReason, mediaType }
            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                if let raw = try? c.decode(String.self, forKey: .assetId), let id = OwnMediaPage.identifier(raw) {
                    assetId = id
                } else { assetId = try c.decode(Int64.self, forKey: .assetId) }
                reviewState = try c.decode(String.self, forKey: .reviewState)
                reviewReason = try c.decodeIfPresent(String.self, forKey: .reviewReason)
                mediaType = try c.decodeIfPresent(String.self, forKey: .mediaType)
            }
        }
        guard data.count <= 128 * 1024, requestedID > 0 else { throw APIError.malformedResponse }
        // Decode the application status independently of a missing/error data payload.
        struct Code: Decodable { let code: Int }
        guard let code = try? JSONDecoder().decode(Code.self, from: data).code else { throw APIError.malformedResponse }
        if code == 401 || code == 2 { throw APIError.unauthorized }
        guard code == 200 else { throw OwnMediaReadFailure.rejected(code: code) }
        guard let row = (try? JSONDecoder().decode(Envelope.self, from: data))?.data,
              row.assetId == requestedID, let state = OwnMediaAsset.ReviewState(rawValue: row.reviewState)
        else { throw APIError.malformedResponse }
        let type: OwnMediaAsset.MediaType
        switch row.mediaType {
        case "IMAGE": type = .image
        case "AUDIO": type = .audio
        case "MODEL3D": type = .model3D
        default: type = .other
        }
        return .init(asset: .init(id: row.assetId, reviewState: state,
            reviewReason: String((row.reviewReason ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(200)), mediaType: type))
    }
}

public enum OwnMediaStatusRoute {
    public static func assetID(_ request: URLRequest, baseURL: URL) -> Int64? {
        guard request.httpMethod == "GET", request.httpBody == nil, request.httpBodyStream == nil,
              request.value(forHTTPHeaderField: "Content-Type") == nil,
              let token = request.value(forHTTPHeaderField: "Authorization"), AuthRequestBuilder.isValidToken(token),
              let url = request.url, url.query == nil, url.fragment == nil,
              let id = OwnMediaPage.identifier(url.lastPathComponent),
              url.absoluteString.utf8.elementsEqual(baseURL.appendingPathComponent("api/media/asset/\(id)").absoluteString.utf8)
        else { return nil }
        return id
    }
    static func request(baseURL: URL, id: Int64, token: String) throws -> URLRequest {
        guard id > 0, AuthRequestBuilder.isValidToken(token) else { throw APIError.invalidRequest }
        var request = URLRequest(url: baseURL.appendingPathComponent("api/media/asset/\(id)"))
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(token, forHTTPHeaderField: "Authorization")
        return request
    }
}

@MainActor public protocol OwnMediaStatusReading: OwnMediaReading {
    var isStatusAvailable: Bool { get }
    func status(id: Int64) async throws -> OwnMediaStatus
}

public struct OwnMediaStatusService {
    let configuration: APIConfiguration
    let transport: any HTTPTransport
    public init(configuration: APIConfiguration, transport: any HTTPTransport) {
        self.configuration = configuration; self.transport = transport
    }
    public func status(id: Int64, token: String) async throws -> OwnMediaStatus {
        try Task.checkCancellation()
        let request = try OwnMediaStatusRoute.request(baseURL: configuration.baseURL, id: id, token: token)
        let (data, status) = try await transport.send(request)
        try Task.checkCancellation()
        if status == 401 { throw APIError.unauthorized }
        if status == 403 { throw OwnMediaReadFailure.rejected(code: 403) }
        guard (200..<300).contains(status) else { throw APIError.httpStatus(status) }
        return try OwnMediaStatus.decode(data, requestedID: id)
    }
}
