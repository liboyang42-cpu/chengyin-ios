import Foundation

/// Exact legacy document multipart only. No extra form field, URL, owner, or file stream is admitted.
enum ProjectStoryAudioCompositionRoute {
    static func accepts(_ request: URLRequest, baseURL: URL) -> Bool {
        guard request.url == baseURL.appendingPathComponent(ProjectStoryAudioUploadClient.path),
              request.httpMethod == "POST", request.httpBodyStream == nil, let body = request.httpBody,
              body.count <= TemplateAudioDocumentInspection.maximumBytes + 4096,
              let type = request.value(forHTTPHeaderField: "Content-Type") else { return false }
        let prefix = "multipart/form-data; boundary=ProjectStoryAudio-"
        guard type.hasPrefix(prefix), let id = UUID(uuidString: String(type.dropFirst(prefix.count))),
              id.uuidString == String(type.dropFirst(prefix.count)) else { return false }
        let boundary = "ProjectStoryAudio-" + id.uuidString
        let end = Data("\r\n--\(boundary)--\r\n".utf8)
        guard body.suffix(end.count) == end else { return false }
        for format in TemplateAudioDocumentMetadata.Format.allCases {
            let ext = format.rawValue, mime: String
            switch format { case .mp3: mime = "audio/mpeg"; case .m4a: mime = "audio/mp4"; case .aac: mime = "audio/aac" }
            let first = Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"fileType\"\r\n\r\n\(ext)\r\n--\(boundary)\r\nContent-Disposition: form-data; name=\"fileName\"\r\n\r\n".utf8)
            guard body.starts(with: first) else { continue }
            let fileHeader = Data("\r\n--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"story.\(ext)\"\r\nContent-Type: \(mime)\r\n\r\n".utf8)
            let limit = min(body.count, first.count + 1024 + fileHeader.count)
            guard limit >= first.count, let range = body.range(of: fileHeader, in: first.count..<limit),
                  let filename = String(data: body.subdata(in: first.count..<range.lowerBound), encoding: .utf8),
                  ProjectStorySelectedAudio.validFilename(filename, format: format),
                  range.upperBound < body.count - end.count else { return false }
            let bytes = body.subdata(in: range.upperBound..<(body.count - end.count))
            return !bytes.isEmpty && bytes.count <= TemplateAudioDocumentInspection.maximumBytes &&
                bytes.range(of: Data("\r\n--\(boundary)".utf8)) == nil
        }
        return false
    }
}
