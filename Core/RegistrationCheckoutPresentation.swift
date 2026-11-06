import Foundation

/// Source checkout order (pages/activity/baoming): already-registered banner, 参与人信息,
/// 活动信息, 费用明细 (票种 → 订单金额 → 俱乐部会员权益 → 积分抵扣 → 总计), then the
/// waitlist card and the consent/submit bar. `RegistrationSheetView` follows this order for
/// a fresh form; retained/pending outcomes show only the activity and status sections.
public enum RegistrationCheckoutSection: String, CaseIterable {
    case alreadyRegistered, participants, activity, ticket, fees, waitlist, confirmation
}

/// Source 俱乐部会员权益 row: a server deduction, otherwise a priority-signup note.
/// Only explicit quote fields produce it; nothing is shown when neither is present.
public enum RegistrationCheckoutClubBenefit: Equatable {
    case discount(Decimal)
    case priorityActive
    case priorityReserved

    public static func from(_ quote: RegistrationQuote) -> RegistrationCheckoutClubBenefit? {
        if let amount = quote.memberDiscountYuan, amount > .zero { return .discount(amount) }
        guard quote.prioritySignupEnabled else { return nil }
        return quote.clubMember ? .priorityActive : .priorityReserved
    }

    /// Localized note for priority-only benefits; a discount is shown as an amount row.
    public var noteKey: String? {
        switch self {
        case .discount: return nil
        case .priorityActive: return "registrationParity.clubPriorityActive"
        case .priorityReserved: return "registrationParity.clubPriorityReserved"
        }
    }
}

/// Presentation-only checkout facts. Amounts stay nil when the source did not supply them;
/// the view must then show its explicit unavailable state, never zero or a converted value.
public struct RegistrationCheckoutFacts: Equatable {
    /// Source navigation title "结算". The sheet still uses `registration.form.title`
    /// because existing UI tests assert that navigation bar title.
    public static let sourceTitleKey = "registrationParity.title"

    /// Source banner condition `activityInfo.isSignUp === 1`; unknown is not signed up.
    public let viewerAlreadyRegistered: Bool
    /// Source `selectedTicket.meetingPoint`; the row is omitted when absent.
    public let meetingPoint: String?
    /// Source `activityInfo.address || activityInfo.addressName`; nil → 待确认集合地点.
    public let venue: String?
    /// Source 订单金额 is the selected ticket's listed price; nil means unknown.
    public let orderAmount: Decimal?

    public init(activity: ActivityDetail, ticket: ActivityTicket?) {
        viewerAlreadyRegistered = activity.signUpFlag == 1
        meetingPoint = ActivityDetailHeaderFacts.nonempty(ticket?.meetingPoint)
        venue = ActivityDetailHeaderFacts.nonempty(activity.summary.address)
            ?? ActivityDetailHeaderFacts.nonempty(activity.summary.addressName)
        orderAmount = ticket?.price
    }
}
