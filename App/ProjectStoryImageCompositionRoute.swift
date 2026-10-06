import Foundation

/// Only the existing Mini image_free multipart command, never a generic upload proxy.
enum ProjectStoryImageCompositionRoute {
    static func accepts(_ request: URLRequest, baseURL: URL) -> Bool {
        guard request.url == baseURL.appendingPathComponent(ProjectStoryImageUploadClient.path),
              request.httpMethod == "POST", request.httpBodyStream == nil, let body = request.httpBody,
              let type = request.value(forHTTPHeaderField: "Content-Type") else { return false }
        let prefix = "multipart/form-data; boundary=ProjectStoryImage-"
        guard type.hasPrefix(prefix), let id = UUID(uuidString: String(type.dropFirst(prefix.count))),
              id.uuidString == String(type.dropFirst(prefix.count)) else { return false }
        let boundary = "ProjectStoryImage-" + id.uuidString
        let first = Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"bizType\"\r\n\r\nimage_free\r\n--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"story.jpg\"\r\nContent-Type: image/jpeg\r\n\r\n".utf8)
        let last = Data("\r\n--\(boundary)--\r\n".utf8)
        return body.starts(with: first) && body.suffix(last.count) == last &&
            body.count > first.count + last.count && body.count - first.count - last.count <= RetainedSelectedImage.maximumBytes &&
            body.dropFirst(first.count).starts(with: [255, 216, 255])
    }
}
