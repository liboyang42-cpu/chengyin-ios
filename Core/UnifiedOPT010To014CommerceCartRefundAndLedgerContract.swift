import Foundation

public struct OPTCommercePackageContract: Equatable, Codable, Sendable, Identifiable {
    public let optID: String
    public let title: String
    public let decisionDependencies: [String]
    public let reusedSliceIDs: [String]
    public let iosCoreImplementation: String
    public let iosViewImplementation: String
    public let invariants: [String]
    public let isVerified: Bool

    public var id: String { optID }

    public init(
        optID: String,
        title: String,
        decisionDependencies: [String],
        reusedSliceIDs: [String],
        iosCoreImplementation: String,
        iosViewImplementation: String,
        invariants: [String],
        isVerified: Bool
    ) {
        self.optID = optID
        self.title = title
        self.decisionDependencies = decisionDependencies
        self.reusedSliceIDs = reusedSliceIDs
        self.iosCoreImplementation = iosCoreImplementation
        self.iosViewImplementation = iosViewImplementation
        self.invariants = invariants
        self.isVerified = isVerified
    }
}

public enum UnifiedOPT010To014CommerceCartRefundAndLedgerContract {
    public static let packages: [OPTCommercePackageContract] = [
        OPTCommercePackageContract(
            optID: "OPT-010",
            title: "统一积分报价与规则展示",
            decisionDependencies: ["D-01"],
            reusedSliceIDs: ["MP-18"],
            iosCoreImplementation: "Core/RegistrationCheckoutPresentation.swift",
            iosViewImplementation: "App/WalletPointsTasksView.swift",
            invariants: [
                "同规则版本下三处金额可复算",
                "旧单与退款不被新费率重算，不擅自乘50",
                "负值、上限、精度和报价过期均有反例保护"
            ],
            isVerified: true
        ),
        OPTCommercePackageContract(
            optID: "OPT-011",
            title: "保留购物车原子性并补成功结果读回",
            decisionDependencies: [],
            reusedSliceIDs: [],
            iosCoreImplementation: "Core/AssetPointsAndOrderCancellationAudit.swift",
            iosViewImplementation: "App/OrderLifecycleView.swift",
            invariants: [
                "同购物车并发只一笔提交且扣分/库存/订单守恒",
                "服务端已提交但客户端丢响应后能先查订单事实恢复",
                "请求身份冲突明确拒绝，不生成第二单"
            ],
            isVerified: true
        ),
        OPTCommercePackageContract(
            optID: "OPT-012",
            title: "退款审核到资金执行与权益补偿",
            decisionDependencies: ["D-02", "D-05"],
            reusedSliceIDs: [],
            iosCoreImplementation: "Core/ClubAccessAndSettlementParityAudit.swift",
            iosViewImplementation: "App/ClubSettlementDetail.swift",
            invariants: [
                "申请后能推进到成功或明确拒绝/失败，不永久停在审核中",
                "重复回调或审核不重复出账，未知结果先查渠道事实",
                "退款金额、账单、权益和商家应付各有独立读回"
            ],
            isVerified: true
        ),
        OPTCommercePackageContract(
            optID: "OPT-013",
            title: "商家应付结算核销撤销与资金读回",
            decisionDependencies: ["D-05"],
            reusedSliceIDs: [],
            iosCoreImplementation: "Core/MerchantLedgerParity.swift",
            iosViewImplementation: "App/MerchantLedgerParityViews.swift",
            invariants: [
                "每个资金动作有业务键、操作者、冻结金额与可追溯凭证",
                "重复执行净额不变，已打款批次不能任意再冲抵",
                "应收/冻结/欠款/已付显示同一账本且可解释"
            ],
            isVerified: true
        ),
        OPTCommercePackageContract(
            optID: "OPT-014",
            title: "积分发放券限领库存与退款守恒",
            decisionDependencies: [],
            reusedSliceIDs: [],
            iosCoreImplementation: "Core/CouponManagementPresentation.swift",
            iosViewImplementation: "App/AccountCollectionCouponsView.swift",
            invariants: [
                "非空和NULL事件键分别验证且并发不超发",
                "单人领券和全局库存上限都不被并发事务穿透",
                "重复撤销/退款不重复回补，失败事务无净资产变化"
            ],
            isVerified: true
        )
    ]

    public static var isFullyVerified: Bool {
        packages.count == 5 && packages.allSatisfy(\.isVerified)
    }
}
