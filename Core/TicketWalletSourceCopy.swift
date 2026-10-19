import Foundation

/// Mini-program signup copy that depends only on the already-read ticket row.
/// Presentation only: it never changes `action`, opens play, or authorizes payment.
public extension TicketWalletTicket {
    /// The list lane comes from the source row's ownerType (1 route list, 2 activity list).
    var lane: TicketWalletLane? { ownerType.flatMap(TicketWalletLane.init(rawValue:)) }

    /// Source title fallback is lane-specific; an unknown lane keeps the generic copy.
    var untitledKey: String {
        switch lane {
        case .route?: return "ticketWallet.parity.untitled.route"
        case .activity?: return "ticketWallet.parity.untitled.activity"
        case nil: return "ticketWallet.untitled"
        }
    }

    /// Source label "待使用 · 进入游玩" applies to unverified paid rows only. The pending
    /// "去支付" suffix is omitted because payment stays unavailable in the native app.
    var statusHintKey: String? {
        status == .ready ? "ticketWallet.parity.hint.ready" : nil
    }
}
