import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Exact current ChannelImageAttachmentService projection, never inferred from a file extension.
@MainActor public final class NativeChannelAttachmentPreviewFlow {
    public enum State: Equatable { case idle, loading, pending, rejected, expired, unsupported, sourceUnconfirmed, unavailable, unknown, displayed }
    private struct Descriptor: Decodable {
        let messageID: String, conversationID: String, kind: String, source: String, state: String
        let assetID: String?, url: String?
        let assetVersion: Int64?, messageVersion: Int64?, expires: Int?
        enum CodingKeys: String,CodingKey {
            case messageID="message_id",conversationID="conversation_id",kind,source,state,assetID="asset_id",assetVersion="asset_version",messageVersion="message_version",url,expires="expires_in_seconds"
        }
        func sameOriginal(as other: Self) -> Bool {
            messageID==other.messageID && conversationID==other.conversationID && assetID==other.assetID && assetVersion==other.assetVersion && messageVersion==other.messageVersion && source==other.source && kind==other.kind
        }
    }
    public let messageID: Int
    public let scope: IMScope
    private let configuration: APIConfiguration
    private let api: any HTTPTransport
    private let media: any HTTPTransport
    private let origins: Set<String>
    private let token: () -> String?
    private let current: () -> Bool
    private let unauthorized: () -> Void
    public let enabled: Bool
    private var state: State = .idle
    public private(set) var bytes: Data?
    private var descriptor: Descriptor?
    private var deadline: ContinuousClock.Instant?
    private var generation = UUID()
    private var monitoring: Task<Void,Never>?
    private var expiryTask: Task<Void,Never>?
    /// One monotonic clock for authorization lifetime and monitor cadence. Internal
    /// injection lets tests release an already-cancelled sleeper without wall time.
    struct Timing {
        var now: () -> ContinuousClock.Instant
        var sleepUntil: (ContinuousClock.Instant) async throws -> Void
        static var live: Self { .init(now: { ContinuousClock.now }, sleepUntil: {
            try await Task.sleep(until: $0, clock: .continuous)
        }) }
    }
    private var timing = Timing.live
    private enum Failure: Error { case denied }
    /// Storage status belongs to this descriptor-bound preview only. Generic message
    /// media retains its original non-2xx -> unavailable contract.
    private enum MediaFailure: Error { case httpStatus(Int) }
    public var onChange: (() -> Void)?
    public var isCurrent: Bool { current() && token() != nil }
    public var visibleState: State { isCurrent ? state : .unavailable }
    public init(messageID: Int, scope: IMScope, configuration: APIConfiguration, api: any HTTPTransport,
                media: any HTTPTransport, origins: Set<String>, enabled: Bool = false,
                token: @escaping () -> String?, current: @escaping () -> Bool, unauthorized: @escaping () -> Void) {
        self.messageID=messageID;self.scope=scope;self.configuration=configuration;self.api=api;self.media=media
        self.origins=origins;self.enabled=enabled;self.token=token;self.current=current;self.unauthorized=unauthorized
    }
    convenience init(messageID: Int, scope: IMScope, configuration: APIConfiguration, api: any HTTPTransport,
                     media: any HTTPTransport, origins: Set<String>, enabled: Bool = false,
                     token: @escaping () -> String?, current: @escaping () -> Bool,
                     unauthorized: @escaping () -> Void, timing: Timing) {
        self.init(messageID: messageID, scope: scope, configuration: configuration, api: api,
                  media: media, origins: origins, enabled: enabled, token: token,
                  current: current, unauthorized: unauthorized)
        self.timing = timing
    }
    /// Explicit user preview only. No persisted URL or automatic fetch on re-entry.
    public func load() async {
        guard enabled,isCurrent,state != .loading else { return }
        clear();let stamp=generation;state = .loading;onChange?()
        do {
            let started=timing.now()
            let original=try await readDescriptor()
            guard isCurrent,generation==stamp,!Task.isCancelled else{return}
            guard original.state=="READY" else { apply(original);return }
            guard let seconds=original.expires,seconds>0,seconds<=300,let raw=original.url,let url=URL(string:raw),
                  let origin=SocialMessageMediaService.origin(url),origins.contains(origin),
                  let asset=original.assetID,let id=Int64(asset),id>0,original.assetVersion==0,
                  let version=original.messageVersion,version>0 else { throw APIError.malformedResponse }
            let end=started.advanced(by:.seconds(seconds))
            guard timing.now()<end else{retire(to: .expired);return}
            let data:Data
            do {data=try await readMedia(url)}
            catch MediaFailure.httpStatus(let status) where status==401 || status==403 || status==404 {
                guard isCurrent,generation==stamp,!Task.isCancelled else{return}
                let latest=try await readDescriptor()
                guard isCurrent,generation==stamp else{return}
                if latest.state=="READY",latest.sameOriginal(as:original){retire(to: .expired)}else{apply(latest)}
                return
            }
            // Clear/reload may retire an in-flight download that ignores cancellation.
            // It must not initiate another descriptor read for the superseded preview.
            guard isCurrent,generation==stamp,!Task.isCancelled else{return}
            let latest=try await readDescriptor()
            guard isCurrent,generation==stamp,!Task.isCancelled else{return}
            guard latest.state=="READY",latest.sameOriginal(as:original) else{apply(latest);return}
            guard timing.now()<end else{retire(to: .expired);return}
            descriptor=original;deadline=end;bytes=data;state = .displayed;onChange?()
            guard state == .displayed,bytes != nil,generation==stamp else{return}
            monitor(stamp:stamp)
            expiryTask=Task { @MainActor in
                do { try await timing.sleepUntil(end) } catch { return }
                guard !Task.isCancelled, generation==stamp, state == .displayed,
                      let deadline, timing.now() >= deadline else { return }
                retire(to: isCurrent ? .expired : .unavailable)
            }
        } catch {
            guard generation==stamp else{return}
            retire(to: error is Failure ? .unavailable : ((error as? SocialMediaFailure) == .notImage ? .unsupported : (isCurrent ? .unknown : .unavailable)))
        }
    }
    /// This URL is used only after the original descriptor's identity, version,
    /// lifetime and origin checks above. It is not a fabricated normal message row.
    /// Production still supplies the independent, credential-free, no-redirect,
    /// response-limited transport through NativeChannelAttachmentPreviewAssembly.
    private func readMedia(_ url: URL) async throws -> Data {
        guard let parts=URLComponents(url:url,resolvingAgainstBaseURL:false),
              parts.scheme?.lowercased()=="https",let host=parts.host,!host.isEmpty,
              parts.user==nil,parts.password==nil,parts.fragment==nil,
              !host.contains(":"),!host.lowercased().hasSuffix(".local"),host.lowercased() != "localhost",
              !host.split(separator:".").allSatisfy({Int($0) != nil}) else { throw SocialMediaFailure.invalidURL }
        guard let origin=SocialMessageMediaService.origin(url),origins.contains(origin) else { throw SocialMediaFailure.originNotApproved }
        try Task.checkCancellation()
        var request=URLRequest(url:url)
        request.httpMethod="GET";request.httpShouldHandleCookies=false
        request.cachePolicy = .reloadIgnoringLocalCacheData;request.timeoutInterval=20
        request.setValue("image/*",forHTTPHeaderField:"Accept")
        let (data,status)=try await media.send(request)
        try Task.checkCancellation()
        guard (200..<300).contains(status) else { throw MediaFailure.httpStatus(status) }
        guard data.count<=SocialMessageMediaService.maximumBytes else { throw SocialMediaFailure.tooLarge }
        // Retain the existing image signature gate before the separate UI decoder.
        let prefix=Array(data.prefix(12))
        let jpeg=prefix.starts(with:[0xff,0xd8,0xff])
        let png=prefix.starts(with:[137,80,78,71,13,10,26,10])
        let gif=prefix.starts(with:Array("GIF87a".utf8)) || prefix.starts(with:Array("GIF89a".utf8))
        let webp=prefix.count>=12 && Array(prefix[0..<4])==Array("RIFF".utf8) && Array(prefix[8..<12])==Array("WEBP".utf8)
        guard jpeg || png || gif || webp else { throw SocialMediaFailure.notImage }
        return data
    }
    private func readDescriptor() async throws -> Descriptor {
        guard enabled,isCurrent,messageID>0,let credential=token() else{throw APIError.notConfigured}
        var request=try AuthRequestBuilder.makeFormRequest(url:configuration.baseURL.appendingPathComponent("api/im/message/\(messageID)/attachment"),fields:[:],token:credential,includesBody:false)
        request.httpMethod="GET";request.httpShouldHandleCookies=false
        let (data,status)=try await api.send(request)
        guard isCurrent,token()==credential,!Task.isCancelled else{throw CancellationError()}
        guard data.count<=16384 else{throw APIError.malformedResponse}
        struct Envelope:Decodable {let code:Int;let data:Descriptor?}
        if status==401{unauthorized();throw APIError.unauthorized}
        if status==403 || status==404 { throw Failure.denied }
        guard (200..<300).contains(status),let envelope=try? JSONDecoder().decode(Envelope.self,from:data) else{throw APIError.malformedResponse}
        if envelope.code==401{unauthorized();throw APIError.unauthorized}
        if envelope.code==403 || envelope.code==404 { throw Failure.denied }
        guard envelope.code==200,let value=envelope.data,value.messageID==String(messageID),value.conversationID==String(scope.conversationID),
              value.source=="LEGACY_SINGLE_IMAGE",value.kind=="IMAGE",
              ["READY","PENDING","REJECTED","UNAVAILABLE","UNSUPPORTED","SOURCE_UNCONFIRMED","UNKNOWN"].contains(value.state) else{throw APIError.malformedResponse}
        return value
    }
    private func apply(_ value:Descriptor) {
        let next: State
        switch value.state {
        case "PENDING":next = .pending
        case "REJECTED":next = .rejected
        case "UNSUPPORTED":next = .unsupported
        case "SOURCE_UNCONFIRMED":next = .sourceUnconfirmed
        case "UNAVAILABLE":next = .unavailable
        default:next = .unknown
        }
        // A newer authoritative result retires the whole displayed lease, not only
        // its bytes. An old deadline must not replace REJECTED/PENDING with expired.
        retire(to: next)
    }
    private func monitor(stamp:UUID) {
        monitoring=Task { @MainActor in
            while !Task.isCancelled,generation==stamp {
                do {
                    try await timing.sleepUntil(timing.now().advanced(by: .seconds(5)))
                    guard generation==stamp else{return}
                    guard isCurrent else{retire(to: .unavailable);return}
                    guard let deadline,timing.now()<deadline else{retire(to: .expired);return}
                    let latest=try await readDescriptor()
                    guard generation==stamp else{return}
                    guard isCurrent else { retire(to: .unavailable);return }
                    guard let descriptor,latest.state=="READY",latest.sameOriginal(as:descriptor) else{apply(latest);return}
                    // A newer response's URL is deliberately discarded: no silent renewal of the displayed link.
                } catch {
                    guard generation==stamp else{return}
                    retire(to: error is Failure ? .unavailable : (isCurrent ? .unknown : .unavailable));return
                }
            }
        }
    }
    public func unsupportedBytes() { retire(to: .unsupported) }
    public func clear() { retire(to: .idle) }
    /// Generation retirement is required even if a transport/sleeper ignores cancel.
    /// Both independent tasks end together; a still-displayed lease keeps both alive.
    private func retire(to next: State) {
        generation=UUID();monitoring?.cancel();monitoring=nil;expiryTask?.cancel();expiryTask=nil
        bytes=nil;descriptor=nil;deadline=nil;state=next;onChange?()
    }
}
