import Foundation

/// Local recovery metadata for the existing W20 intent, containing identifiers and
/// consent identifiers only. No token, signed evidence, coordinates or balance is
/// stored. Composition must supply a namespace bound to backend, market and role;
/// this does not grant a capability or enable any endpoint.
@MainActor public final class CityActionRecoveryJournal {
    private struct Record: Codable {
        let scope: [String]
        let intent: CityActionIntent
    }
    private let directory: URL
    private let namespace: String

    public init(directory: URL, namespace: String) throws {
        guard directory.isFileURL, ReformWire.id(namespace) else { throw CityActionIssue.invalid }
        self.directory = directory; self.namespace = namespace
    }

    private func scope(memberId: String, read: CityReadSnapshot) throws -> [String] {
        guard ReformWire.id(memberId), let participation = read.participation else { throw CityActionIssue.notJoined }
        let context = [namespace, memberId, read.board.gameId, read.board.boardId, read.board.regionId,
                       read.board.seasonId, participation.participationId]
        guard context.allSatisfy(ReformWire.id) else { throw CityActionIssue.invalid }
        return context
    }
    private func file(_ scope: [String]) -> URL {
        // Each tuple component gets its own reversible, filesystem-safe segment.
        // No hash collision or delimiter ambiguity can cross an account boundary.
        scope.reduce(directory.appendingPathComponent("city-action-recovery-v1", isDirectory: true)) { url, value in
            let segment = Data(value.utf8).base64EncodedString().replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "+", with: "-")
            return url.appendingPathComponent(segment, isDirectory: true)
        }.appendingPathComponent("pending.json")
    }
    private func validate(_ intent: CityActionIntent, memberId: String, read: CityReadSnapshot) throws {
        guard intent.boardId == read.board.boardId, intent.participationId == read.participation?.participationId,
              ReformWire.id(intent.boardId), ReformWire.id(intent.participationId), ReformWire.id(intent.targetId),
              ReformWire.requestID(intent.requestId), ReformWire.version(intent.roundSeq), ReformWire.version(intent.expectedVersion),
              intent.kind.requiresQuote == (intent.consent != nil) else { throw CityActionIssue.invalid }
        if let consent = intent.consent {
            guard consent.payerMemberId == memberId, ReformWire.id(consent.quoteId), ReformWire.version(consent.quoteVersion) else {
                throw CityActionIssue.payerMismatch
            }
        }
    }
    public func restore(memberId: String, read: CityReadSnapshot) throws -> CityActionIntent? {
        let context = try scope(memberId: memberId, read: read), url = file(context)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        guard data.count <= 16_384 else { throw CityActionIssue.invalid }
        let record = try JSONDecoder().decode(Record.self, from: data)
        guard record.scope == context else { throw CityActionIssue.invalid }
        try validate(record.intent, memberId: memberId, read: read)
        return record.intent
    }
    public func save(_ intent: CityActionIntent, memberId: String, read: CityReadSnapshot) throws {
        try validate(intent, memberId: memberId, read: read)
        if let existing = try restore(memberId: memberId, read: read), existing != intent { throw CityActionIssue.busy }
        let context = try scope(memberId: memberId, read: read), url = file(context)
        let bytes = try JSONEncoder().encode(Record(scope: context, intent: intent))
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try bytes.write(to: url, options: .atomic)
        guard try Data(contentsOf: url) == bytes else { throw CityActionIssue.invalid }
    }
    public func clear(_ intent: CityActionIntent, memberId: String, read: CityReadSnapshot) throws {
        guard try restore(memberId: memberId, read: read) == intent else { throw CityActionIssue.receiptMismatch }
        let url = file(try scope(memberId: memberId, read: read))
        try FileManager.default.removeItem(at: url)
        guard !FileManager.default.fileExists(atPath: url.path) else { throw CityActionIssue.invalid }
    }
}
