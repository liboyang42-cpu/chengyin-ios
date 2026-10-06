import Foundation

/// Exact existing producer routes only; path/query/body structure is checked before any forwarding.
struct OwnedTopicCoverCompositionRoute {
    let operation: OwnedTopicCoverOperation
    init?(request: URLRequest, baseURL: URL) {
        guard let url = request.url, var parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.user == nil, parts.password == nil, parts.fragment == nil, request.httpBodyStream == nil else { return nil }
        let query = parts.queryItems ?? []; parts.query = nil
        guard let plain = parts.url else { return nil }
        if request.httpMethod == "GET", request.httpBody == nil {
            if plain == baseURL.appendingPathComponent(OwnedTopicCoverClient.currentPath), query.count == 1,
               query[0].name == "topicId", let text = query[0].value, let id = Int(text), id > 0, text == String(id) {
                operation = .readCurrent; return
            }
            let prefix = baseURL.appendingPathComponent("api/topic/cover").absoluteString + "/"
            guard plain.absoluteString.hasPrefix(prefix), query.count == 2, Set(query.map(\.name)) == ["sourceVersion", "contentHash"] else { return nil }
            let suffix = String(plain.absoluteString.dropFirst(prefix.count)), path = suffix.split(separator: "/").map(String.init)
            guard path.count == 2, path[1] == "content", Self.uuid(path[0]),
                  let version = query.first(where: { $0.name == "sourceVersion" })?.value, Self.uuid(version),
                  let hash = query.first(where: { $0.name == "contentHash" })?.value, Self.hash(hash) else { return nil }
            operation = .readAsset; return
        }
        guard request.httpMethod == "POST", query.isEmpty, let body = request.httpBody else { return nil }
        if plain == baseURL.appendingPathComponent(OwnedTopicCoverClient.uploadPath) {
            let prefix = "multipart/form-data; boundary=Cover-"
            guard let type = request.value(forHTTPHeaderField: "Content-Type"), type.hasPrefix(prefix),
                  let id = UUID(uuidString: String(type.dropFirst(prefix.count))), id.uuidString == String(type.dropFirst(prefix.count)) else { return nil }
            let boundary = "Cover-" + id.uuidString
            let first = Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"cover.jpg\"\r\nContent-Type: image/jpeg\r\n\r\n".utf8)
            let last = Data("\r\n--\(boundary)--\r\n".utf8)
            guard body.starts(with: first), body.suffix(last.count) == last,
                  body.count > first.count + last.count, body.count - first.count - last.count <= RetainedSelectedImage.maximumBytes,
                  body.dropFirst(first.count).starts(with: [255,216,255]) else { return nil }
            operation = .upload; return
        }
        let selecting = plain == baseURL.appendingPathComponent(OwnedTopicCoverClient.selectPath)
        guard selecting || plain == baseURL.appendingPathComponent(OwnedTopicCoverClient.statusPath), body.count <= 2048,
              request.value(forHTTPHeaderField: "Content-Type") == "application/json",
              let row = try? ApprovedTopicReleaseWire.envelope(body),
              Set(row.keys) == ["topicId", "expectedConfigVersion", "expectedSelectionVersion", "expectedContentSlotId", "requestId", "assetId", "sourceVersion", "contentHash"],
              let topic = row["topicId"]?.integer, topic > 0, let slot = row["expectedContentSlotId"]?.integer, slot > 0,
              let config = row["expectedConfigVersion"]?.integer, config >= 0, config < Int.max,
              let selection = row["expectedSelectionVersion"]?.integer, selection >= 0, selection < Int.max,
              let requestID = row["requestId"]?.text, UUID(uuidString: requestID)?.uuidString == requestID,
              let asset = row["assetId"]?.text, Self.uuid(asset), let version = row["sourceVersion"]?.text, Self.uuid(version),
              let hash = row["contentHash"]?.text, Self.hash(hash) else { return nil }
        operation = selecting ? .select : .status
    }
    private static func uuid(_ value: String) -> Bool { UUID(uuidString: value)?.uuidString.lowercased() == value }
    private static func hash(_ value: String) -> Bool { value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) } }
}
