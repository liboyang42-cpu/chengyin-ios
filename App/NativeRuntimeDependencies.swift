import Foundation

/// Composition-only injection, never an Info.plist switch or remote feature toggle.
/// The regional registry, login/legal acceptance and exact endpoint approvals stay independent.
@MainActor struct NativeRuntimeDependencies {
    let nativePlatform: NativePlatformAcceptance?
    let businessConfiguration: BusinessRuntimeConfiguration?
    let weChatPaymentConfiguration: WeChatSDKPaymentConfiguration?
    let signupDocument: (any TopicSelfPlayDocumentProviding)?
    let selfPlayPayment: (any TopicSelfPlayPaymentProviding)?
    let bankDocument: (any BankWithdrawalCurrentDocumentProviding)?
    let verificationCodeApproval: VerificationCodeApproval?
    let couponCodeApproval: CouponCodeApproval?
    let ownerRefundApproval: ClubOwnerRefundApproval?
    let configuration: RuntimeDependencyConfiguration?
    let transport: (any HTTPTransport)?
    let location: (any RoamDeviceLocationProviding)?
    let shopNPCGrants: ShopNPCGrants
    let motion: (any PlayMotionSampleProviding)?
    init(configuration: RuntimeDependencyConfiguration? = nil, businessConfiguration: BusinessRuntimeConfiguration? = nil, bankDocument: (any BankWithdrawalCurrentDocumentProviding)? = nil, signupDocument: (any TopicSelfPlayDocumentProviding)? = nil, selfPlayPayment: (any TopicSelfPlayPaymentProviding)? = nil, weChatPaymentConfiguration: WeChatSDKPaymentConfiguration? = nil, transport: (any HTTPTransport)? = nil,
         location: (any RoamDeviceLocationProviding)? = nil, shopNPCGrants: ShopNPCGrants = .init(), motion: (any PlayMotionSampleProviding)? = nil,
         verificationCodeApproval: VerificationCodeApproval? = nil, couponCodeApproval: CouponCodeApproval? = nil,
         ownerRefundApproval: ClubOwnerRefundApproval? = nil, nativePlatform: NativePlatformAcceptance? = nil) {
        self.nativePlatform = nativePlatform
        self.weChatPaymentConfiguration = weChatPaymentConfiguration
        self.signupDocument = signupDocument; self.selfPlayPayment = selfPlayPayment
        self.businessConfiguration = businessConfiguration; self.bankDocument = bankDocument
        self.verificationCodeApproval = verificationCodeApproval; self.couponCodeApproval = couponCodeApproval; self.ownerRefundApproval = ownerRefundApproval
        self.configuration = configuration; self.transport = transport; self.location = location; self.shopNPCGrants = shopNPCGrants; self.motion = motion
    }
    static var dormant: Self { .init() }
}
