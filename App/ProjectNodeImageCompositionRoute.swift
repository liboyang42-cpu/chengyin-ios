import Foundation

/// An independent node-photo command, never an image_free/topic/merchant fallback.
enum ProjectNodeImageCompositionRoute {
    static func accepts(_ request:URLRequest,baseURL:URL,policy:ProjectNodeImageMediaPolicy)->Bool{
        guard request.url==baseURL.appendingPathComponent(ProjectNodeImageUploadClient.path),request.httpMethod=="POST",
              request.httpBodyStream==nil,let body=request.httpBody,let type=request.value(forHTTPHeaderField:"Content-Type")else{return false}
        let prefix="multipart/form-data; boundary=ProjectNodeImage-"
        guard type.hasPrefix(prefix),let id=UUID(uuidString:String(type.dropFirst(prefix.count))),id.uuidString==String(type.dropFirst(prefix.count))else{return false}
        let boundary="ProjectNodeImage-"+id.uuidString
        let first=Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"bizType\"\r\n\r\nimage_4_3\r\n--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"node.jpg\"\r\nContent-Type: image/jpeg\r\n\r\n".utf8)
        let last=Data("\r\n--\(boundary)--\r\n".utf8)
        return body.starts(with:first) && body.suffix(last.count)==last && body.count>first.count+last.count &&
            body.count-first.count-last.count<=policy.maximumJPEGBytes && body.dropFirst(first.count).starts(with:[255,216,255])
    }
}
/// Does not create a transport. Only an expressly injected checked node transport
/// can forward the final single-use authorization. The default approval remains nil.
@MainActor final class ProjectNodeImageScopedTransport:ProjectNodeImageDispatching {
    private let baseURL:URL,policy:ProjectNodeImageMediaPolicy,underlying:any ProjectNodeImageDispatching,current:()->Bool
    init(baseURL:URL,policy:ProjectNodeImageMediaPolicy,underlying:any ProjectNodeImageDispatching,current:@escaping()->Bool){self.baseURL=baseURL;self.policy=policy;self.underlying=underlying;self.current=current}
    var isConfigured:Bool{current() && underlying.isConfigured}
    func send(_ request:URLRequest,authorization:ProjectNodeImageDispatchAuthorization)async throws->(Data,Int){
        guard isConfigured,ProjectNodeImageCompositionRoute.accepts(request,baseURL:baseURL,policy:policy)else{throw ProjectNodeImageFailure.notSent}
        try Task.checkCancellation()
        let result=try await underlying.send(request,authorization:authorization)
        guard isConfigured,!Task.isCancelled else{throw ProjectNodeImageFailure.outcomeUnknown};return result
    }
}
