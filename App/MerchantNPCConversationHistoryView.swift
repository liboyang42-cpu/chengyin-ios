import SwiftUI

@MainActor struct MerchantNPCConversationHistoryView: View {
    let history: MerchantNPCConversationHistory
    var body: some View {
        if !history.turns.isEmpty || history.hasOmittedTurns {
            VStack(alignment: .leading, spacing: 16) {
                Text("merchantNPCHistory.title").font(.headline).accessibilityAddTraits(.isHeader)
                Text("merchantNPCHistory.notice").font(.footnote).foregroundStyle(.secondary)
                if history.hasOmittedTurns {
                    Text("merchantNPCHistory.omitted").font(.footnote)
                        .accessibilityIdentifier("merchantNPCHistory.omitted")
                }
                ForEach(history.turns) { turn in
                    VStack(alignment: .leading, spacing: 12) {
                        ChatMessageBubble(isOwn: true) { Text("messaging.you") } content: {
                            Text(verbatim: turn.question).textSelection(.enabled)
                        }
                        ChatMessageBubble(isOwn: false) {
                            Text(turn.outcome == .succeeded ? "merchantNPCHistory.aiReply" : "merchantNPCHistory.serviceReply")
                        } content: {
                            Text(verbatim: turn.safeText).textSelection(.enabled)
                        }
                        Text(turn.outcome == .succeeded ? "merchantNPCHistory.received" :
                             (turn.outcome == .rejected ? "merchantNPCHistory.rejected" : "merchantNPCHistory.failed"))
                            .font(.caption).foregroundStyle(.secondary)
                    }.accessibilityElement(children: .contain).accessibilityIdentifier("merchantNPCHistory.turn")
                }
            }.privacySensitive().accessibilityIdentifier("merchantNPCHistory.section")
        }
    }
}
