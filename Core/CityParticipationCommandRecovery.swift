import Foundation
import Observation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A single unresolved original command per deployment/account. UNKNOWN is written BEFORE POST.
/// Original bytes include the JOIN invite code, but never credentials, epoch or location. No logging.
/// Verified completed records are archived before a separately granted new command; UNKNOWN is never overwritten.
@MainActor public final class CityParticipationCommandJournal {
    struct Record: Codable, Equatable {
        let scope: [String]
        let bytes: Data
        var terminalStatus: Int?
        var command: CityParticipationCommand { get throws { try JSONDecoder().decode(CityParticipationCommand.self, from: bytes) } }
    }
    private let root: URL
    public init(directory: URL) throws {
        guard directory.isFileURL else { throw CityParticipationCommandFailure.storage }; root = directory
    }
    private func file(_ scope: CityParticipationCommandScope) throws -> URL {
        try scope.durableKey.reduce(root.appendingPathComponent("city-participation-original-v1", isDirectory: true)) { url, value in
            let component = Data(value.utf8).base64EncodedString().replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "+", with: "-")
            guard !component.isEmpty, component.utf8.count <= 240 else { throw CityParticipationCommandFailure.storage }
            return url.appendingPathComponent(component, isDirectory: true)
        }.appendingPathComponent("original.json")
    }
    func load(_ scope: CityParticipationCommandScope) throws -> Record? {
        let url = try file(scope)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let bytes = try Data(contentsOf: url)
        guard bytes.count <= 16384 else { throw CityParticipationCommandFailure.storage }
        let record = try JSONDecoder().decode(Record.self, from: bytes)
        guard record.scope == scope.durableKey, try record.command.wireBytes() == record.bytes,
              record.terminalStatus == nil || [200, 400, 409].contains(record.terminalStatus!) else { throw CityParticipationCommandFailure.storage }
        return record
    }
    func begin(_ bytes: Data, scope: CityParticipationCommandScope) throws -> Record {
        let record = Record(scope: scope.durableKey, bytes: bytes, terminalStatus: nil)
        guard try record.command.wireBytes() == bytes else { throw CityParticipationCommandFailure.invalid }
        let originalID = try record.command.requestId
        let directory = try file(scope).deletingLastPathComponent()
        let archive = directory.appendingPathComponent("completed", isDirectory: true)
        guard !FileManager.default.fileExists(atPath: archive.appendingPathComponent(originalID + ".json").path) else {
            throw CityParticipationCommandFailure.busy
        }
        if let previous = try load(scope) {
            guard previous.terminalStatus != nil, try previous.command.requestId != originalID else { throw CityParticipationCommandFailure.busy }
            // Preserve verified original evidence BEFORE replacing the current pointer. No deletion.
            let archived = archive.appendingPathComponent(try previous.command.requestId + ".json")
            let oldBytes = try JSONEncoder().encode(previous)
            if FileManager.default.fileExists(atPath: archived.path) {
                guard try JSONDecoder().decode(Record.self, from: Data(contentsOf: archived)) == previous else { throw CityParticipationCommandFailure.storage }
            } else { try write(oldBytes, to: archived) }
        }
        try persist(record, scope: scope); return record
    }
    func complete(_ record: Record, status: Int, scope: CityParticipationCommandScope) throws {
        guard [200, 400, 409].contains(status), try load(scope) == record else { throw CityParticipationCommandFailure.storage }
        var completed = record; completed.terminalStatus = status
        try persist(completed, scope: scope)
    }
    private func persist(_ record: Record, scope: CityParticipationCommandScope) throws {
        try write(JSONEncoder().encode(record), to: file(scope))
    }
    private func write(_ bytes: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try bytes.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        guard try Data(contentsOf: url) == bytes else { throw CityParticipationCommandFailure.storage }
    }
}

/// Explicit consumer only; no AppSession factory, grant issuer or automatic retry is installed.
@MainActor @Observable public final class CityParticipationCommandRecovery {
    public enum Display: Equatable { case hidden, unavailable, empty, unknown, complete(Int), storageBlocked }
    public private(set) var display: Display = .hidden
    public private(set) var busy = false
    private let configuration: APIConfiguration
    private let transport: any HTTPTransport
    private let journal: CityParticipationCommandJournal
    private let currentScope: () -> CityParticipationCommandScope?
    private let grant: () -> CityParticipationCommandGrant?
    private let receiptReader: CityOriginalReceiptReader?
    private var visit: UInt64 = 0
    private var scope: CityParticipationCommandScope?
    public init(configuration: APIConfiguration, transport: any HTTPTransport, journal: CityParticipationCommandJournal,
                currentScope: @escaping () -> CityParticipationCommandScope?,
                grant: @escaping () -> CityParticipationCommandGrant? = { nil }, receiptReader: CityOriginalReceiptReader? = nil) {
        self.configuration = configuration; self.transport = transport; self.journal = journal
        self.currentScope = currentScope; self.grant = grant; self.receiptReader = receiptReader
    }
    public func open() {
        close()
        guard let current = currentScope(), current.session.baseURL == configuration.baseURL else { display = .unavailable; return }
        scope = current
        do {
            if let record = try journal.load(current) { display = record.terminalStatus.map(Display.complete) ?? .unknown }
            else { display = .empty }
        } catch { display = .storageBlocked }
    }
    public func close() { visit &+= 1; scope = nil; display = .hidden; busy = false }
    public func identityChanged() { close() }
    private func valid(_ original: CityParticipationCommandScope, _ originalVisit: UInt64) -> Bool {
        scope == original && currentScope() == original && visit == originalVisit && configuration.baseURL == original.session.baseURL
    }
    public func submit(_ command: CityParticipationCommand) async {
        guard !busy, let original = scope else { return }
        let originalVisit = visit
        // Existing US implementation gate remains closed; a locally constructed grant cannot bypass it.
        guard original.session.market == .china, valid(original, originalVisit), let issued = grant(), !issued.isRevoked, issued.scope == original,
              let bytes = try? command.wireBytes(), issued.bytes == bytes else { display = .unavailable; return }
        busy = true
        defer { if visit == originalVisit { busy = false } }
        let record: CityParticipationCommandJournal.Record
        do { record = try journal.begin(bytes, scope: original) }
        catch {
            if valid(original, originalVisit) {
                if let saved = try? journal.load(original) { display = saved.terminalStatus.map(Display.complete) ?? .unknown }
                else { display = .storageBlocked }
            }
            return
        }
        display = .unknown // Durable claim exists. No branch below may call POST again.
        guard valid(original, originalVisit), grant() === issued, !issued.isRevoked, !Task.isCancelled else { close(); return }
        var request = URLRequest(url: configuration.baseURL.appendingPathComponent("api/city-game/team-participation/command"))
        request.httpMethod = "POST"; request.httpBody = record.bytes; request.httpShouldHandleCookies = false
        request.cachePolicy = .reloadIgnoringLocalCacheData; request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(original.token, forHTTPHeaderField: "Authorization")
        do {
            let (body, status) = try await transport.send(request)
            guard valid(original, originalVisit), grant() === issued, !issued.isRevoked, !Task.isCancelled else { if visit == originalVisit { close() }; return }
            guard body.count <= 1_048_576, let response = try? JSONDecoder().decode(Response.self, from: body),
                  response.code == status, response.data.requestId == command.requestId,
                  response.data.requestStatus == "COMPLETE", [200, 400, 409].contains(status),
                  response.data.kind == nil || response.data.kind == command.kind.rawValue,
                  status != 200 || (response.data.kind == command.kind.rawValue && (response.errorCode == nil || response.errorCode == "")) else { return }
            try journal.complete(record, status: status, scope: original)
            display = .complete(status)
        } catch {
            if !valid(original, originalVisit) { if visit == originalVisit { close() } }
            // Transport, decoding or uncertain storage never authorizes replay or removes the claim.
        }
    }
    public func recheck() async {
        guard !busy, let original = scope else { return }
        let originalVisit = visit
        guard valid(original, originalVisit), let receiptReader else { display = .unavailable; return }
        busy = true; defer { if visit == originalVisit { busy = false } }
        do {
            guard let record = try journal.load(original), record.terminalStatus == nil else { return }
            let command = try record.command
            let reference = try CityOriginalReceiptReference(session: original.session, domain: .participation, requestID: command.requestId)
            let observation = try await receiptReader.read(reference)
            guard valid(original, originalVisit) else { if visit == originalVisit { close() }; return }
            switch observation.state {
            case .unknown: display = .unknown
            case .complete(let status, _):
                try journal.complete(record, status: status, scope: original); display = .complete(status)
            }
        } catch {
            guard valid(original, originalVisit) else { if visit == originalVisit { close() }; return }
            display = .unknown // Includes private/missing 404 and revoked read grant; lock remains.
        }
    }
    private struct Response: Decodable {
        let code: Int; let errorCode: String?; let data: Receipt
        struct Receipt: Decodable { let requestId: String; let requestStatus: String; let kind: String? }
    }
}
