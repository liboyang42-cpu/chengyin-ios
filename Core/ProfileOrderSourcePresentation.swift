import Foundation

/// Display-only projections of the Mini order history/detail components
/// (scene-member-order-history, scene-member-order-detail). Nothing here permits
/// payment, cancellation, refunds, verification or any other request.
public extension ProfileOrderHistoryFilter {
    /// Source chip labels: 全部 and 退款中 differ from the shared lifecycle state titles.
    var chipTitleKey: String {
        switch self {
        case .all: return "profile.orderParity.chip.all"
        case .refunding: return "profile.orderParity.chip.refunding"
        default: return titleKey
        }
    }
}

/// Source formatActivityTimeRange: both ends are required and each is shown as
/// `MM.dd HH:mm` of the server's wall-clock text. No time-zone conversion is applied.
public enum ProfileOrderTimeRangeText {
    public static func text(start: String?, end: String?) -> String? {
        guard let start = component(start), let end = component(end) else { return nil }
        return start + " - " + end
    }

    static func component(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let parts = text.split(omittingEmptySubsequences: false, whereSeparator: { $0 == " " || $0 == "T" }).map(String.init)
        guard parts.count == 1 || parts.count == 2 else { return nil }
        let date = parts[0].split(omittingEmptySubsequences: false, whereSeparator: { $0 == "-" || $0 == "/" }).map(String.init)
        guard date.count == 3, date[0].count == 4, date.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isASCIIDigitCharacter) }),
              let month = Int(date[1]), let day = Int(date[2]), (1...12).contains(month), (1...31).contains(day) else { return nil }
        var hour = 0, minute = 0
        if parts.count == 2 {
            let time = parts[1].split(separator: ":", omittingEmptySubsequences: false).map(String.init)
            guard time.count == 2 || time.count == 3,
                  time[0].allSatisfy(\.isASCIIDigitCharacter), time[1].count == 2, time[1].allSatisfy(\.isASCIIDigitCharacter),
                  let h = Int(time[0]), let m = Int(time[1]), (0...23).contains(h), (0...59).contains(m) else { return nil }
            if time.count == 3 {
                let seconds = time[2].split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
                guard let first = seconds.first, first.count == 2, first.allSatisfy(\.isASCIIDigitCharacter),
                      seconds.dropFirst().allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isASCIIDigitCharacter) }) else { return nil }
            }
            hour = h; minute = m
        }
        return pad(month) + "." + pad(day) + " " + pad(hour) + ":" + pad(minute)
    }

    private static func pad(_ value: Int) -> String { value < 10 ? "0" + String(value) : String(value) }
}

private extension Character {
    var isASCIIDigitCharacter: Bool { ("0"..."9").contains(self) }
}

/// Source STATE_TITLE notice. `unknown` deliberately has no card.
public struct ProfileOrderStateNotice: Equatable {
    public let titleKey: String
    public let tagKey: String
    public let hint: String?
}

public extension ProfileOrder {
    /// Source order-actual-pay.js isFreeOrder: total and payable are zero, and any
    /// present points/WeChat amounts are zero. Display only.
    var isSourceFreeOrder: Bool {
        historyFacts.totalAmountIsZero && payableAmount == .zero
            && (pointPaymentAmount == nil || pointPaymentAmount == .zero)
            && (wechatPaymentAmount == nil || wechatPaymentAmount == .zero)
    }

    func stateNotice(now: Date = Date()) -> ProfileOrderStateNotice? {
        let state = historyState(now: now)
        guard state != .unknown else { return nil }
        let free = isSourceFreeOrder && (state == .notStarted || state == .inProgress)
        let hint = orderHint.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        return ProfileOrderStateNotice(titleKey: "profile.orderParity.notice." + (free ? "free" : state.rawValue),
                                       tagKey: "orderLifecycle.state." + state.rawValue, hint: hint)
    }

    /// Source detail section title: 费用明细 for free orders, otherwise 支付明细.
    var paymentSectionTitleKey: String {
        isSourceFreeOrder ? "profile.orderParity.section.fees" : "profile.orderParity.section.payment"
    }

    /// Source overrides the payment method label for free orders; otherwise the
    /// server label is literal text. Nil when neither is available.
    var sourcePaymentTypeLabelKey: String? { isSourceFreeOrder ? "profile.orderParity.paymentType.free" : nil }
}

/// Labels only for codes whose meaning the source states; any other value keeps its
/// raw number under a 状态码 label so nothing is guessed.
public enum ProfileOrderCodeLabel: Equatable {
    case key(String)
    case raw(Int)

    /// refundApplication.status: 0 awaiting review; 2 rejected (order-status.js).
    public static func refundApplication(_ code: Int) -> ProfileOrderCodeLabel {
        switch code {
        case 0: return .key("profile.orderParity.refundApplication.review")
        case 2: return .key("profile.orderParity.refundApplication.rejected")
        default: return .raw(code)
        }
    }

    /// paymentStatus 2 is the only paid value the source relies on.
    public static func payment(_ code: Int) -> ProfileOrderCodeLabel {
        code == 2 ? .key("profile.orderParity.payment.paid") : .raw(code)
    }
}

/// Screen-specific copy for ProfileReadScreen. The default screen copy is used when nil.
public struct ProfileReadIssueCopy: Equatable {
    public enum Kind: Equatable { case signIn, forbidden, malformed, failure }
    public let signInTitleKey: String
    public let signInDetailKey: String
    public let forbiddenTitleKey: String
    public let failureTitleKey: String
    public let failureDetailKey: String
    public let malformedDetailKey: String

    /// Source scene-member-order-history: 登录后查看订单 / 当前账号无法查看订单 / 订单暂时没有加载出来.
    public static let orders = ProfileReadIssueCopy(
        signInTitleKey: "profile.orderParity.signIn.title", signInDetailKey: "profile.orderParity.signIn.detail",
        forbiddenTitleKey: "profile.orderParity.forbidden.title",
        failureTitleKey: "profile.orderParity.error.title", failureDetailKey: "profile.orderParity.error.detail",
        malformedDetailKey: "profile.orderParity.error.malformed")

    public static func kind(of error: Error) -> Kind {
        let failure = error as? ProfileReadFailure
        if error as? APIError == .unauthorized || failure?.isUnauthorized == true { return .signIn }
        if error as? APIError == .httpStatus(403) || failure?.httpStatus == 403 || failure?.code == 403 { return .forbidden }
        if error as? APIError == .malformedResponse { return .malformed }
        return .failure
    }
}
