import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Final-forward consumer of already-issued channel-host features. It never creates
/// routes, changes the generic composition gate, or treats a shared path as a grant.
@MainActor public final class NativeChannelHostRuntimeTransport: HTTPTransport {
    private let context: RuntimeDependencyContext
    private let issued: BusinessRuntimeConfiguration
    private let features: Set<BusinessRuntimeFeature>
    private let underlying: any HTTPTransport
    private let runtime: () -> RuntimeDependencyContext?
    private let configuration: () -> BusinessRuntimeConfiguration?
    private let presentation: () -> Bool
    private var retired = false
    public init?(context: RuntimeDependencyContext, issued: BusinessRuntimeConfiguration,
        features: Set<BusinessRuntimeFeature>, underlying: any HTTPTransport,
        runtime: @escaping () -> RuntimeDependencyContext?,
        configuration: @escaping () -> BusinessRuntimeConfiguration?, presentation: @escaping () -> Bool) {
        guard !features.isEmpty, features.isSubset(of: Self.supported), issued.matches(context),
              runtime() == context, presentation() else { return nil }
        self.context = context; self.issued = issued; self.features = features; self.underlying = underlying
        self.runtime = runtime; self.configuration = configuration; self.presentation = presentation
        guard isCurrent else { return nil }
    }
    public var isCurrent: Bool {
        guard !retired, presentation(), runtime() == context, let live = configuration(), live.matches(context),
              live.imMediaOrigins == issued.imMediaOrigins, live.imImageSelection == issued.imImageSelection,
              features.allSatisfy({ live.routes[$0] == issued.routes[$0] }) else {
            retired = true; return false
        }
        return true
    }
    public func send(_ request: URLRequest) async throws -> (Data, Int) {
        try Task.checkCancellation()
        guard isCurrent, request.httpShouldHandleCookies == false,
              request.value(forHTTPHeaderField: "Cookie") == nil,
              request.value(forHTTPHeaderField: "Authorization")?.utf8.elementsEqual(context.session.token.utf8) == true else { throw APIError.notConfigured }
        let exact = features.reduce(into: Set<BusinessRuntimeRoute>()) { $0.formUnion(issued.routes[$1] ?? []) }
        let guardTransport = BusinessRuntimeTransport(configuration: issued, captured: context,
            routes: { exact }, transport: underlying, current: { [weak self] in
                guard let self, self.isCurrent else { return nil }; return self.context
            })
        let result = try await guardTransport.send(request)
        try Task.checkCancellation()
        guard isCurrent else { throw CancellationError() }
        return result
    }
    private static let supported: Set<BusinessRuntimeFeature> = [
        .imStart, .imRead, .imMute, .imSend, .imUpload, .imReport, .imChannelReportReceipt,
        .imChannelMentionMemberRead, .imChannelMentionRoleRead,
        .imChannelPersonalStateRead, .imChannelPersonalStateWrite, .imChannelPersonalStateReceipt,
        .imChannelRoleRead, .imChannelRoleWrite, .imChannelRoleReceipt, .imChannelRoleMemberRead,
        .imChannelModerationRead, .imChannelModerationWrite, .imChannelModerationReceipt,
        .imChannelAuditRead, .imChannelLifecycleAuditRead,
        .imPollResult, .imPollCreate, .imPollVote, .imPollClose, .imPollCreateReceipt,
        .imOrdinaryReadReceipt, .imOrdinaryReadState, .imOrdinaryMuteReceipt, .imOrdinaryMuteState,
        .imOrdinarySendReceipt, .imImageUploadReceipt, .imStaticLocationSend, .imStaticLocationReceipt,
        .imRouteShareRead, .imRouteSend, .imRouteReceipt,
        .imVoiceUpload, .imVoiceUploadReceipt, .imVoicePlayback, .imVoicePlaybackStatus, .imVoiceSend, .imVoiceReceipt,
        .imFileUpload, .imFileUploadReceipt, .imFileScan, .imFilePreview, .imFilePreviewStatus, .imFileSend, .imFileReceipt,
        .imVideoUpload, .imVideoUploadReceipt, .imVideoPolicy, .imVideoPreview, .imVideoPreviewStatus, .imVideoSend, .imVideoReceipt,
        .imChainRead, .imChainCreate, .imChainJoin, .imChainWithdraw, .imChainClose, .imChainReceipt,
        .imCheckinStatus, .imCheckinWrite, .imCheckinRank, .imCheckinReceipt
    ]
}
