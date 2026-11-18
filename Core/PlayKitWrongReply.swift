import Foundation

/// F02: the server's reply to a wrong typed answer (a matching near-miss row or the
/// generic wrong reply), shown right under the input. The wrong-answer table itself
/// never reaches the client; the typed input is kept so the player can edit it.
public enum PlayKitWrongReply {
    public static func text(segment: PlayWireValue) -> String? {
        guard segment["passed"].bool != true, segment["finished"].bool != true,
              (segment["attempts"].integer ?? 0) > 0,
              let reply = segment["lastFeedback"].text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !reply.isEmpty else { return nil }
        return reply
    }
}

/// A qa choice with no right answer (`judge:false`): every option completes the
/// stop, so the result reads as "recorded", never as passed or failed.
public enum PlayKitNoRightAnswer {
    public static func applies(kind: PlayKitScreenKind, segment: PlayWireValue) -> Bool {
        kind == .qa && (segment["mode"].text ?? "").uppercased() == "PICK" && segment["judge"].bool == false
    }
}
