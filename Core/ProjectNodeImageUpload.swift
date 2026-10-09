import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum ProjectNodeImageFailure: Error, Equatable { case notConfigured, changedContext, invalidResponse, notSent, outcomeUnknown, persistenceUnavailable }
/// Explicit deployment limits, narrower than the existing sanitizer. These are local
/// acceptance restrictions, not an invented backend NodeDTO or OSS size contract.
public struct ProjectNodeImageMediaPolicy: Equatable {
    public let maximumJPEGBytes: Int, maximumDimension: Int, maximumReferenceBytes: Int
    public init(maximumJPEGBytes: Int, maximumDimension: Int, maximumReferenceBytes: Int) throws {
        guard (1...RetainedSelectedImage.maximumBytes).contains(maximumJPEGBytes),
              (4...RetainedSelectedImage.maximumDimension).contains(maximumDimension),
              (1...96 * 1024).contains(maximumReferenceBytes) else { throw ProjectNodeImageFailure.notConfigured }
        self.maximumJPEGBytes=maximumJPEGBytes;self.maximumDimension=maximumDimension;self.maximumReferenceBytes=maximumReferenceBytes
    }
    public func permits(_ image: RetainedSelectedImage) -> Bool {
        image.width > 0 && image.height > 0 && image.width <= maximumDimension && image.height <= maximumDimension &&
        image.width * 3 == image.height * 4 && image.jpeg.count <= maximumJPEGBytes && image.jpeg.starts(with: [255,216,255])
    }
}
public struct ProjectNodeImageUploadApproval: Equatable {
    public let id: UUID, baseURL: URL, namespace: String, accountID: Int
    public let approvedOrigins: Set<String>, nativePicker: Bool, policy: ProjectNodeImageMediaPolicy
    public init(baseURL: URL, namespace: String, accountID: Int, approvedOrigins: Set<String>,
                policy: ProjectNodeImageMediaPolicy, nativePicker: Bool = false, id: UUID = UUID()) throws {
        _ = try APIConfiguration(baseURL: baseURL)
        guard accountID > 0, !namespace.isEmpty, namespace.utf8.count <= 4096, !approvedOrigins.isEmpty,
              approvedOrigins.allSatisfy({ raw in
                  guard raw.utf8.allSatisfy({ $0 >= 33 && $0 < 127 }), let u=URL(string:raw), let host=u.host,
                        u.scheme=="https",u.user==nil,u.password==nil,u.query==nil,u.fragment==nil,u.path.isEmpty else{return false}
                  return raw == "https://"+host.lowercased()+(u.port.map{":\($0)"} ?? "")
              }) else { throw ProjectNodeImageFailure.notConfigured }
        self.id=id;self.baseURL=baseURL;self.namespace=namespace;self.accountID=accountID
        self.approvedOrigins=approvedOrigins;self.policy=policy;self.nativePicker=nativePicker
    }
    public static func ==(a:Self,b:Self)->Bool {
        a.id==b.id && Data(a.baseURL.absoluteString.utf8)==Data(b.baseURL.absoluteString.utf8) &&
        Data(a.namespace.utf8)==Data(b.namespace.utf8) && a.accountID==b.accountID && a.approvedOrigins==b.approvedOrigins && a.nativePicker==b.nativePicker && a.policy==b.policy
    }
    public func matches(configuration: APIConfiguration, session: ProjectEditSession)->Bool {
        Data(baseURL.absoluteString.utf8)==Data(configuration.baseURL.absoluteString.utf8) &&
        Data(namespace.utf8)==Data(session.storageNamespace.utf8) && accountID==session.accountID
    }
}
public struct ProjectNodeImageContext {
    public let target: ProjectNodeImageTarget, session: ProjectEditSession, identity: ProjectEditDraftIdentity
    public let editorID: UUID, presentationID: UUID, draftRevision: Int
    public init(target: ProjectNodeImageTarget, session: ProjectEditSession, identity: ProjectEditDraftIdentity,
                editorID: UUID, presentationID: UUID, draftRevision: Int) throws {
        guard Data(target.ownerKey.utf8)==Data(session.ownerKey.utf8), Data(target.draftBucket.utf8)==Data(identity.bucket.utf8),
              !target.chapterID.isEmpty,!target.nodeID.isEmpty,draftRevision >= 0 else { throw ProjectNodeImageFailure.changedContext }
        self.target=target;self.session=session;self.identity=identity;self.editorID=editorID;self.presentationID=presentationID;self.draftRevision=draftRevision
    }
    func replacingTarget(_ target: ProjectNodeImageTarget) throws -> Self {
        guard self.target.sameField(target) else {throw ProjectNodeImageFailure.changedContext}
        return try .init(target:target,session:session,identity:identity,editorID:editorID,presentationID:presentationID,draftRevision:draftRevision)
    }
}
public struct ProjectNodeImageCredentials: Equatable {
    public let session:ProjectEditSession
    fileprivate let token:String
    public init(session:ProjectEditSession,token:String)throws{guard AuthRequestBuilder.isValidToken(token)else{throw ProjectNodeImageFailure.notConfigured};self.session=session;self.token=token}
    public static func ==(a:Self,b:Self)->Bool{a.session==b.session && Data(a.token.utf8)==Data(b.token.utf8)}
}
/// The injected node-only transport must invoke forward synchronously at request start,
/// after any suspension. There is no fallback to a generic upload/HTTP channel.
@MainActor public final class ProjectNodeImageDispatchAuthorization {
    private let request:URLRequest,validity:()->Bool
    public private(set) var didForward=false
    init(request:URLRequest,validity:@escaping()->Bool){self.request=request;self.validity=validity}
    public func forward(_ request:URLRequest,start:()throws->Void)throws{
        guard !didForward,!Task.isCancelled,validity(),self.request==request,
              self.request.httpBody==request.httpBody,
              self.request.url?.absoluteString.utf8.elementsEqual(request.url?.absoluteString.utf8 ?? "".utf8)==true
        else{throw ProjectNodeImageFailure.notSent}
        didForward=true;try start()
    }
    func isCurrent()->Bool{!Task.isCancelled && validity()}
}
@MainActor public protocol ProjectNodeImageDispatching:AnyObject {
    var isConfigured:Bool{get}
    func send(_ request:URLRequest,authorization:ProjectNodeImageDispatchAuthorization)async throws->(Data,Int)
}
/// A typed legacy URL acknowledgement only, never an immutable ownership/moderation receipt.
public struct ProjectNodeUploadedImage:Equatable {
    public let attemptID:UUID,targetID:UUID,ownerKey:String,reference:String
    fileprivate init(attemptID:UUID,targetID:UUID,ownerKey:String,reference:String){self.attemptID=attemptID;self.targetID=targetID;self.ownerKey=ownerKey;self.reference=reference}
    public static func ==(a:Self,b:Self)->Bool{a.attemptID==b.attemptID && a.targetID==b.targetID && Data(a.ownerKey.utf8)==Data(b.ownerKey.utf8) && Data(a.reference.utf8)==Data(b.reference.utf8)}
    static func validReference(_ raw:String,origins:Set<String>,maximum:Int)->Bool{
        guard !raw.isEmpty,raw.utf8.count<=maximum,
              !raw.unicodeScalars.contains(where:{CharacterSet.whitespacesAndNewlines.contains($0)||CharacterSet.controlCharacters.contains($0)}),
              let url=URL(string:raw)else{return false}
        return RetainedImageOrigin.accepts(url,origins:origins)
    }
    static func restore(attemptID:UUID,targetID:UUID,ownerKey:String,reference:String)throws->Self{
        guard !ownerKey.isEmpty,let u=URL(string:reference),let host=u.host,
              validReference(reference,origins:["https://"+host.lowercased()+(u.port.map{":\($0)"} ?? "")],maximum:96*1024)else{throw ProjectNodeImageFailure.invalidResponse}
        return .init(attemptID:attemptID,targetID:targetID,ownerKey:ownerKey,reference:reference)
    }
}
@MainActor public protocol ProjectNodeImageUploading:AnyObject {
    func isCurrent(context:ProjectNodeImageContext)->Bool
    func policy(context:ProjectNodeImageContext)->ProjectNodeImageMediaPolicy?
    func permitsPicker(context:ProjectNodeImageContext)->Bool
    func permitsReference(_ receipt:ProjectNodeUploadedImage,context:ProjectNodeImageContext)->Bool
    func upload(_ image:RetainedSelectedImage,attemptID:UUID,context:ProjectNodeImageContext,
                isCurrent:@escaping @MainActor()->Bool)async throws->ProjectNodeUploadedImage
}
@MainActor public final class ProjectNodeImageUploadClient:ProjectNodeImageUploading {
    public static let path="api/common/uploadOSS"
    private let configuration:APIConfiguration,approval:ProjectNodeImageUploadApproval?
    private let transport:(any ProjectNodeImageDispatching)?
    private let credentials:()->ProjectNodeImageCredentials?,currentApproval:()->ProjectNodeImageUploadApproval?
    public init(configuration:APIConfiguration,approval:ProjectNodeImageUploadApproval?=nil,transport:(any ProjectNodeImageDispatching)?=nil,
                credentials:@escaping()->ProjectNodeImageCredentials?,currentApproval:@escaping()->ProjectNodeImageUploadApproval?){
        self.configuration=configuration;self.approval=approval;self.transport=transport;self.credentials=credentials;self.currentApproval=currentApproval
    }
    public func isCurrent(context:ProjectNodeImageContext)->Bool{
        guard let approval,currentApproval()==approval,transport?.isConfigured==true,credentials()?.session==context.session,
              Data(context.target.ownerKey.utf8)==Data(context.session.ownerKey.utf8),Data(context.target.draftBucket.utf8)==Data(context.identity.bucket.utf8)else{return false}
        return approval.matches(configuration:configuration,session:context.session)
    }
    public func policy(context:ProjectNodeImageContext)->ProjectNodeImageMediaPolicy?{isCurrent(context:context) ? approval?.policy:nil}
    public func permitsPicker(context:ProjectNodeImageContext)->Bool{isCurrent(context:context) && approval?.nativePicker==true}
    public func permitsReference(_ receipt:ProjectNodeUploadedImage,context:ProjectNodeImageContext)->Bool{
        isCurrent(context:context) && receipt.targetID==context.target.id && Data(receipt.ownerKey.utf8)==Data(context.target.ownerKey.utf8) &&
        ProjectNodeUploadedImage.validReference(receipt.reference,origins:approval?.approvedOrigins ?? [],maximum:approval?.policy.maximumReferenceBytes ?? 0)
    }
    public func upload(_ image:RetainedSelectedImage,attemptID:UUID,context:ProjectNodeImageContext,
                       isCurrent:@escaping @MainActor()->Bool)async throws->ProjectNodeUploadedImage{
        guard let transport,let approval,let original=credentials(),original.session==context.session,
              self.isCurrent(context:context),approval.policy.permits(image),isCurrent()else{throw ProjectNodeImageFailure.notConfigured}
        try Task.checkCancellation()
        let boundary="ProjectNodeImage-"+UUID().uuidString
        var body=Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"bizType\"\r\n\r\nimage_4_3\r\n--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"node.jpg\"\r\nContent-Type: image/jpeg\r\n\r\n".utf8)
        body.append(image.jpeg);body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        var request=URLRequest(url:configuration.baseURL.appendingPathComponent(Self.path));request.httpMethod="POST";request.httpBody=body
        request.httpShouldHandleCookies=false;request.cachePolicy = .reloadIgnoringLocalCacheData;request.timeoutInterval=30
        request.setValue(original.token,forHTTPHeaderField:"Authorization");request.setValue("multipart/form-data; boundary=\(boundary)",forHTTPHeaderField:"Content-Type")
        let authorization=ProjectNodeImageDispatchAuthorization(request:request){[weak self]in
            guard let self else{return false};return transport.isConfigured && self.credentials()==original && self.isCurrent(context:context) && isCurrent()
        }
        let bytes:Data,status:Int
        do{(bytes,status)=try await transport.send(request,authorization:authorization)}
        catch{throw authorization.didForward ? ProjectNodeImageFailure.outcomeUnknown:ProjectNodeImageFailure.notSent}
        guard authorization.didForward,authorization.isCurrent()else{throw ProjectNodeImageFailure.outcomeUnknown}
        if status==401 || status==403{throw APIError.unauthorized}
        guard status==200,bytes.count<=64*1024,let row=try? ApprovedTopicReleaseWire.envelope(bytes)else{throw ProjectNodeImageFailure.outcomeUnknown}
        if row["code"]?.integer==401 || row["code"]?.integer==403{throw APIError.unauthorized}
        guard row["code"]?.integer==200,let reference=row["url"]?.text else{throw ProjectNodeImageFailure.outcomeUnknown}
        let receipt=ProjectNodeUploadedImage(attemptID:attemptID,targetID:context.target.id,ownerKey:context.target.ownerKey,reference:reference)
        // Comma-bearing approved references remain real unapplied receipts. The separate
        // CSV target rejects them rather than discarding evidence or inventing escaping.
        guard permitsReference(receipt,context:context)else{throw ProjectNodeImageFailure.invalidResponse};return receipt
    }
}

/// Real ephemeral network adapter. Reuses the existing byte-bounded response exchange,
/// but interposes the node authorization at the actual suspended URLSession task resume.
/// No cookie jar, credential persistence, redirect replay or other upload grant is added.
@MainActor public final class ProjectNodeImageNetworkTransport:ProjectNodeImageDispatching {
    public let isConfigured:Bool
    public init(enabled:Bool=false){isConfigured=enabled}
    public func send(_ request:URLRequest,authorization:ProjectNodeImageDispatchAuthorization)async throws->(Data,Int){
        guard isConfigured else{throw ProjectNodeImageFailure.notSent}
        let bounded=ResponseLimitedHTTPTransport(enabled:true,maximumResponseBytes:64*1024,makeTask:{request,delegate in
            ProjectNodeImageAuthorizedTask(request:request,delegate:delegate,authorization:authorization)
        })
        return try await bounded.send(request)
    }
}
private final class ProjectNodeImageAuthorizedTask:ResponseLimitedHTTPTask,@unchecked Sendable {
    private let session:URLSession,task:URLSessionDataTask,request:URLRequest
    private let delegate:ResponseLimitedHTTPExchange,authorization:ProjectNodeImageDispatchAuthorization
    private let lock=NSLock()
    private var cancelled=false
    init(request:URLRequest,delegate:ResponseLimitedHTTPExchange,authorization:ProjectNodeImageDispatchAuthorization){
        self.request=request;self.delegate=delegate;self.authorization=authorization
        let queue=OperationQueue();queue.maxConcurrentOperationCount=1
        let session=URLSession(configuration:ResponseLimitedHTTPTransport.makeSessionConfiguration(),delegate:delegate,delegateQueue:queue)
        self.session=session;task=session.dataTask(with:request) // Suspended; no request yet.
    }
    func resume(){
        Task{@MainActor [self] in
            do{try authorization.forward(request){try startExactTask()}}
            catch{delegate.complete(error:error)}
        }
    }
    private func startExactTask()throws{
        lock.lock();defer{lock.unlock()}
        guard !cancelled else{throw ProjectNodeImageFailure.notSent}
        task.resume() // Synchronous final boundary, under the cancellation lock.
    }
    func invalidateAndCancel(){
        lock.lock();cancelled=true;lock.unlock();task.cancel();session.invalidateAndCancel()
    }
}
