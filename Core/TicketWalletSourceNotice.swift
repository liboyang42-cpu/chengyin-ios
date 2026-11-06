import Foundation

/// Inline equivalents of the mini-program signup tap toasts. Presentation only:
/// nothing here changes `action`, opens play, or authorizes payment.
public extension TicketWalletTicket {
    /// Source toasts 票已取消 / 票已过期 / 票状态待确认 for rows that do not open.
    /// The payment-unavailable notice stays native because payment is not offered.
    var sourceNoticeKey: String {
        switch action {
        case .cancelled: return "ticketWallet.p2.notice.cancelled"
        case .expired: return "ticketWallet.p2.notice.expired"
        case .unknown: return "ticketWallet.p2.notice.unknown"
        case .paymentUnavailable, .detail: return "ticketWallet.action." + action.rawValue
        }
    }

    /// Source: a paid row without a session owner shows 场次信息待同步 instead of opening play.
    /// The native detail entry is unchanged; this only adds the source notice.
    var needsScheduleSync: Bool { action == .detail && (ownerID ?? 0) <= 0 }
}
