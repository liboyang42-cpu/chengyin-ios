import Foundation

/// Exact native backend v1 canonical bytes. The assertion provider hashes these
/// bytes with SHA-256. This is not JSON canonicalization and has no trailing LF.
public enum NativeStepCanonical {
    public static func clientData(challenge: NativeStepChallenge, reading: NativePedometerReading, idempotencyKey: String) throws -> Data {
        guard idempotencyKey.range(of: "^[A-Za-z0-9._:-]{1,64}$", options: .regularExpression) != nil, reading.steps <= 100_000,
              Int((reading.start.timeIntervalSince1970 * 1000).rounded()) == challenge.dayStartAt else { throw NativePlatformIssue.invalidContract }
        let lines = ["CHENGYIN_NATIVE_STEPS_V1", NativeStepChallenge.provider, String(challenge.accountID),
            String(challenge.sessionID), String(challenge.attemptStartedAt), challenge.deviceKeyID, challenge.challengeID,
            String(challenge.issuedAt), String(challenge.expiresAt), challenge.timeZone, challenge.dayKey,
            String(challenge.dayStartAt), String(challenge.dayEndAt), String(challenge.dayStartAt),
            String(Int((reading.end.timeIntervalSince1970 * 1000).rounded())), String(reading.steps),
            String(challenge.sessionVersion), idempotencyKey]
        guard lines.count == 18, lines.allSatisfy({ !$0.isEmpty && !$0.contains("\n") && !$0.contains("\r") }) else { throw NativePlatformIssue.invalidContract }
        return Data(lines.joined(separator: "\n").utf8)
    }
}
