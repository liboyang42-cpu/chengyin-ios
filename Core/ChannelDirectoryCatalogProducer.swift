import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import CoreFoundation

/// Reads the original channel directory detail and builds the current catalog.
/// `version` is the published snapshot. A missing or non-positive version closes
/// this open. It does not invent a version and does not use another domain's permission.
public enum ChannelDirectoryCatalogFailure: Error, Equatable {
    case unpublished
    case wrongSpace
    case malformed
}

public enum ChannelDirectoryCatalogProducer {
    public static func catalog(configuration: APIConfiguration, transport: any HTTPTransport, token: String,
                               channelID: Int, spaceID: Int64, kind: Int) async throws -> ChannelCatalogEntry {
        guard channelID > 0, spaceID > 0, kind == 1 || kind == 3, AuthRequestBuilder.isValidToken(token) else {
            throw ChannelDirectoryCatalogFailure.malformed
        }
        let root = configuration.baseURL.absoluteString.hasSuffix("/")
            ? configuration.baseURL.absoluteString
            : configuration.baseURL.absoluteString + "/"
        guard let url = URL(string: root + "api/channels/\(channelID)"), url.host == configuration.baseURL.host else {
            throw ChannelDirectoryCatalogFailure.malformed
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(token, forHTTPHeaderField: "Authorization")
        let (data, status) = try await transport.send(request)
        guard (200..<300).contains(status),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let code = object["code"] as? NSNumber, code.intValue == 200,
              let payload = object["data"] as? [String: Any] else {
            throw ChannelDirectoryCatalogFailure.malformed
        }
        guard exact(payload["id"]) == Int64(channelID),
              exact(payload["guild_id"]) == spaceID,
              exact(payload["guild_kind"]) == Int64(kind) else {
            throw ChannelDirectoryCatalogFailure.wrongSpace
        }
        guard let version = exact(payload["version"]), version > 0, version <= Int64(Int.max),
              let container = payload["message_container"] as? [String: Any],
              let conversation = exact(container["id"]), conversation > 0, conversation <= Int64(Int.max) else {
            throw ChannelDirectoryCatalogFailure.unpublished
        }
        let rules = try ChannelRulesCAS(publishedVersion: Int(version), pendingVersion: nil, expectedVersion: Int(version))
        return try ChannelCatalogEntry(channelID: channelID, conversationID: Int(conversation), kind: .group, rules: rules)
    }

    private static func exact(_ value: Any?) -> Int64? {
        if let text = value as? String {
            guard text.count <= 19, text.allSatisfy({ $0.isASCII && $0.isNumber }),
                  !(text.count > 1 && text.hasPrefix("0")),
                  let number = Int64(text), String(number) == text, number >= 0 else { return nil }
            return number
        }
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let parsed = number.int64Value
        guard number.doubleValue == Double(parsed), parsed >= 0 else { return nil }
        return parsed
    }
}
