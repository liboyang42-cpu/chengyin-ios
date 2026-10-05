import Foundation

/// Account-owned normal review composition. No fixture writer or synthetic identity is used.
/// Read, write, image upload, remote pixels and native selection stay independently disabled.
@MainActor final class RetainedPublicMerchantReviewHost {
    private let cache: RetainedImageContextCache
    private let evidence: PublicMerchantReviewImageEvidence
    private let currentSession: () -> PublicMerchantReviewSession?
    private let ownerID = UUID()
    private var activeTarget: PublicMerchantReviewTarget?
    let reader: any PublicMerchantReviewReading
    let writer: any PublicMerchantReviewWriting
    let imageReader: any RetainedPublicImageReading = RetainedPublicImageReader(enabled: false, origins: [])
    init(configuration: APIConfiguration, transport: any HTTPTransport, cache: RetainedImageContextCache,
         currentSession: @escaping () -> PublicMerchantReviewSession?) {
        self.cache = cache; self.currentSession = currentSession
        let evidence = PublicMerchantReviewImageEvidence(); self.evidence = evidence
        let concrete = PublicMerchantReviewHTTPWriter(configuration: configuration, transport: transport, currentSession: currentSession)
        writer = PublicMerchantReviewGatedWriter(base: concrete, enabled: false,
            record: { page, target, session in try? evidence.record(page, target: target, session: session) },
            discard: { evidence.suspend($0) })
        reader = RetainedScopedPublicReviewReader(configuration: configuration, transport: transport,
            enabled: false, currentSession: currentSession, evidence: evidence)
    }
    func writeContext(journal: any MerchantBusinessIntentStore) -> PublicMerchantReviewWriteContext {
        .init(writer: writer, journal: journal,
            imageContext: { [weak self] target, registrationID in self?.imageContext(target: target, registrationID: registrationID) },
            invalidateImages: { [weak self] target in self?.invalidate(target: target) })
    }
    private func imageContext(target: PublicMerchantReviewTarget, registrationID: Int) -> RetainedImageSelectionContext? {
        guard let session = currentSession(), writer.session == session, reader.scope == session.scope,
              let credentials = cache.credentials, credentials.accountID == session.accountID,
              credentials.realm == session.realm,
              let revision = evidence.revision(target: target, registrationID: registrationID, session: session) else { return nil }
        if activeTarget != target {
            cache.invalidate(ownerID: ownerID)
            if let old = activeTarget { evidence.invalidate(old) }
            activeTarget = target
        }
        guard let scope = try? RetainedImageScope(accountID: session.accountID, epoch: session.scope,
            realm: session.realm, destination: .publicReview(merchantRowID: target.merchantRowID.rawValue, registrationID: registrationID),
            accessRevision: revision, namespace: credentials.namespace) else { return nil }
        return cache.context(scope: scope, destination: .review(target.merchantRowID, registrationID: registrationID),
            ownerID: ownerID, isCurrent: { [weak self] in
                guard let self else { return false }
                return self.activeTarget == target && self.currentSession() == session && self.writer.session == session
                    && self.evidence.revision(target: target, registrationID: registrationID, session: session) == revision
            })
    }
    func invalidate(target: PublicMerchantReviewTarget) {
        evidence.invalidate(target)
        if activeTarget == target { activeTarget = nil; cache.invalidate(ownerID: ownerID) }
    }
    func invalidate() { activeTarget = nil; evidence.invalidate(); cache.invalidate(ownerID: ownerID) }
}

/// Captures the authenticated session per read and rejects callbacks from old accounts/tokens.
/// Construction and scope lookup are inert. This is not an anonymous image download adapter.
@MainActor private final class RetainedScopedPublicReviewReader: PublicMerchantReviewReading {
    private let configuration: APIConfiguration
    private let transport: any HTTPTransport
    private let enabled: Bool
    private let currentSession: () -> PublicMerchantReviewSession?
    private let evidence: PublicMerchantReviewImageEvidence
    private let unconfiguredScope = UUID()
    private var activeTarget: PublicMerchantReviewTarget?
    private var generation = 0
    var scope: UUID { currentSession()?.scope ?? unconfiguredScope }
    var isConfigured: Bool { enabled && currentSession()?.realm == configuration.baseURL.absoluteString }
    let isOfflineExample = false
    init(configuration: APIConfiguration, transport: any HTTPTransport, enabled: Bool = false,
         currentSession: @escaping () -> PublicMerchantReviewSession?, evidence: PublicMerchantReviewImageEvidence) {
        self.configuration = configuration; self.transport = transport; self.enabled = enabled
        self.currentSession = currentSession; self.evidence = evidence
    }
    func page(_ target: PublicMerchantReviewTarget, page: Int) async throws -> PublicMerchantReviewPage {
        guard isConfigured, let session = currentSession() else { throw PublicMerchantHomeFailure.notConfigured }
        generation += 1; let ticket = generation
        if activeTarget != target { evidence.invalidate(); activeTarget = target }
        evidence.suspend(target)
        let base = PublicMerchantReviewHTTPReader(configuration: configuration, transport: transport,
            scope: session.scope, isOfflineExample: false, session: session)
        do {
            let result = try await base.page(target, page: page)
            guard ticket == generation, activeTarget == target, currentSession() == session, !Task.isCancelled else { throw CancellationError() }
            try evidence.record(result, target: target, session: session)
            return result
        } catch {
            if ticket == generation { evidence.invalidate(target) }
            throw error
        }
    }
}
