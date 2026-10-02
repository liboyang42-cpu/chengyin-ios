import Foundation

/// Composition-only injection, never an Info.plist switch or remote feature toggle.
/// The regional registry, login/legal acceptance and exact endpoint approvals stay independent.
@MainActor struct NativeRuntimeDependencies {
    let officialActionApproval: OfficialActionProductionApproval?
    let socialMemberActionApprovals: [SocialMemberActionApproval]
    let nativePlatform: NativePlatformAcceptance?
    let orderLifecycleConfiguration: OrderLifecycleProductionConfiguration?
    let businessConfiguration: BusinessRuntimeConfiguration?
    let weChatPaymentConfiguration: WeChatSDKPaymentConfiguration?
    let signupDocument: (any TopicSelfPlayDocumentProviding)?
    let selfPlayPayment: (any TopicSelfPlayPaymentProviding)?
    let bankDocument: (any BankWithdrawalCurrentDocumentProviding)?
    let verificationCodeApproval: VerificationCodeApproval?
    let couponCodeApproval: CouponCodeApproval?
    let merchantPublicApproval: MerchantPublicProductionApproval?
    let merchantNPCGrants: MerchantNPCGrants
    let socialReaderApproval: SocialReaderProductionApproval?
    let merchantEngagementApproval: MerchantEngagementProductionApproval?
    let merchantBusinessApproval: MerchantBusinessProductionApproval?
    let clubOpsTimeApproval: ClubOpsTimeApproval?
    let contextualReviewApproval: ContextualReviewApproval?
    let clubGovernanceApproval: ClubGovernanceProductionApproval?
    let ownerRefundApproval: ClubOwnerRefundApproval?
    let configuration: RuntimeDependencyConfiguration?
    let transport: (any HTTPTransport)?
    let location: (any RoamDeviceLocationProviding)?
    let shopNPCGrants: ShopNPCGrants
    let journeyNarrativeImageReader: (any RetainedPublicImageReading)?
    let motion: (any PlayMotionSampleProviding)?
    init(officialActionApproval: OfficialActionProductionApproval? = nil, socialMemberActionApprovals: [SocialMemberActionApproval] = [], configuration: RuntimeDependencyConfiguration? = nil, businessConfiguration: BusinessRuntimeConfiguration? = nil, bankDocument: (any BankWithdrawalCurrentDocumentProviding)? = nil, signupDocument: (any TopicSelfPlayDocumentProviding)? = nil, selfPlayPayment: (any TopicSelfPlayPaymentProviding)? = nil, weChatPaymentConfiguration: WeChatSDKPaymentConfiguration? = nil, transport: (any HTTPTransport)? = nil,
         location: (any RoamDeviceLocationProviding)? = nil, shopNPCGrants: ShopNPCGrants = .init(), motion: (any PlayMotionSampleProviding)? = nil,
         verificationCodeApproval: VerificationCodeApproval? = nil, couponCodeApproval: CouponCodeApproval? = nil, socialReaderApproval: SocialReaderProductionApproval? = nil,
         clubOpsTimeApproval: ClubOpsTimeApproval? = nil, contextualReviewApproval: ContextualReviewApproval? = nil,
         ownerRefundApproval: ClubOwnerRefundApproval? = nil, nativePlatform: NativePlatformAcceptance? = nil, clubGovernanceApproval: ClubGovernanceProductionApproval? = nil, merchantBusinessApproval: MerchantBusinessProductionApproval? = nil, merchantEngagementApproval: MerchantEngagementProductionApproval? = nil, orderLifecycleConfiguration: OrderLifecycleProductionConfiguration? = nil, journeyNarrativeImageReader: (any RetainedPublicImageReading)? = nil, merchantPublicApproval: MerchantPublicProductionApproval? = nil, merchantNPCGrants: MerchantNPCGrants = .init()) {
        self.clubOpsTimeApproval = clubOpsTimeApproval; self.contextualReviewApproval = contextualReviewApproval
        self.officialActionApproval = officialActionApproval
        self.socialMemberActionApprovals = socialMemberActionApprovals
        self.merchantPublicApproval = merchantPublicApproval; self.merchantNPCGrants = merchantNPCGrants
        self.journeyNarrativeImageReader = journeyNarrativeImageReader
        self.socialReaderApproval = socialReaderApproval
        self.nativePlatform = nativePlatform
        self.weChatPaymentConfiguration = weChatPaymentConfiguration
        self.signupDocument = signupDocument; self.selfPlayPayment = selfPlayPayment
        self.merchantEngagementApproval = merchantEngagementApproval
        self.merchantBusinessApproval = merchantBusinessApproval
        self.clubGovernanceApproval = clubGovernanceApproval
        self.orderLifecycleConfiguration = orderLifecycleConfiguration
        self.businessConfiguration = businessConfiguration; self.bankDocument = bankDocument
        self.verificationCodeApproval = verificationCodeApproval; self.couponCodeApproval = couponCodeApproval; self.ownerRefundApproval = ownerRefundApproval
        self.configuration = configuration; self.transport = transport; self.location = location; self.shopNPCGrants = shopNPCGrants; self.motion = motion
    }
    func makeMerchantPublicFactory(api: APIConfiguration, journal: any OperationPendingJournal,
                                   current: @escaping () -> MerchantPublicHostContext?) -> MerchantPublicProductionFactory? {
        guard let context = current(), merchantPublicApproval?.matches(context) == true else { return nil }
        let acceptedGrants = merchantNPCGrants
        return MerchantPublicProductionFactory(api: api, approval: merchantPublicApproval,
            transport: transport ?? ResponseLimitedHTTPTransport(enabled: true), journal: journal,
            current: current, grants: { acceptedGrants })
    }
    static var dormant: Self { .init() }
}
