import Foundation

/// Account/topic-local intentions and returned producer facts. Never stores picked image bytes or credentials.
/// An upload has no server status API; its missing asset receipt remains explicitly unresolved.
@MainActor public final class OwnedTopicCoverJournal {
    public struct Upload: Equatable {
        public let id: UUID, localDigest: String
        public fileprivate(set) var asset: OwnedTopicCoverAsset?
        var fields: ProjectEditJSON { .object(["id":.string(id.uuidString),"localDigest":.string(localDigest),"asset":asset?.fields ?? .null]) }
    }
    public struct Selection: Equatable {
        public let command: OwnedTopicCoverSelectionCommand
        public fileprivate(set) var receipt: OwnedTopicCoverSelectionReceipt?
        var fields: ProjectEditJSON { .object(["command":.object(command.fields),"receipt":receipt?.fields ?? .null]) }
    }
    public struct Snapshot: Equatable {
        public let ownerKey: String, topicID: Int
        public let uploads: [Upload], selections: [Selection]
        fileprivate let raw: Data?
        public var currentSelection: Selection? { selections.last }
        public var unresolvedUploadCount: Int { uploads.filter { $0.asset == nil }.count }
    }
    private let storage: any ProjectEditDataStorage
    // A live acknowledged receipt must not disappear merely because its sheet closes after a local write error.
    // These are process-local facts, not durable storage or server recovery for an unknown upload.
    private var receivedUploads: [String:[UUID:OwnedTopicCoverAsset]] = [:]
    private var receivedSelections: [String:OwnedTopicCoverSelectionReceipt] = [:]
    public init(storage: any ProjectEditDataStorage) { self.storage = storage }
    private func key(_ session: ProjectEditSession, _ topic: Int) -> String {
        "owned-topic-cover.v1." + Data((session.ownerKey + ":" + String(topic)).utf8).base64EncodedString()
    }
    public func receivedUpload(session:ProjectEditSession,topicID:Int) -> (id:UUID,asset:OwnedTopicCoverAsset)? {
        guard let receipts = receivedUploads[key(session,topicID)], let id = receipts.keys.sorted(by: { $0.uuidString < $1.uuidString }).first, let asset = receipts[id] else { return nil }
        return (id,asset)
    }
    public func receivedSelection(session:ProjectEditSession,topicID:Int) -> OwnedTopicCoverSelectionReceipt? { receivedSelections[key(session,topicID)] }
    public func rememberUpload(_ asset:OwnedTopicCoverAsset,id:UUID,session:ProjectEditSession,topicID:Int) {
        guard asset.ownerMemberID == session.accountID else { return }; receivedUploads[key(session,topicID),default:[:]][id] = asset
    }
    public func rememberSelection(_ receipt:OwnedTopicCoverSelectionReceipt,session:ProjectEditSession) {
        guard receipt.asset.ownerMemberID == session.accountID else { return };receivedSelections[key(session,receipt.topicID)] = receipt
    }
    public func read(session: ProjectEditSession, topicID: Int) throws -> Snapshot {
        guard topicID > 0 else { throw OwnedTopicCoverFailure.invalidResponse }
        let raw = try storage.read(key(session,topicID))
        guard let raw else { return .init(ownerKey: session.ownerKey, topicID: topicID, uploads: [], selections: [], raw: nil) }
        return try decode(raw, session: session, topicID: topicID)
    }
    private func decode(_ raw: Data, session: ProjectEditSession, topicID: Int) throws -> Snapshot {
        let value = try ApprovedTopicReleaseWire.envelope(raw)
        guard Set(value.keys) == ["version","ownerKey","topicId","uploads","selections"], value["version"]?.integer == 1,
              value["ownerKey"]?.text == session.ownerKey, value["topicId"]?.integer == topicID,
              let uploads = value["uploads"]?.array, let selections = value["selections"]?.array,
              uploads.count <= 32, selections.count <= 32 else { throw OwnedTopicCoverFailure.invalidResponse }
        var ids = Set<UUID>()
        let loadedUploads = try uploads.map { item -> Upload in
            guard let row = item.object, Set(row.keys) == ["id","localDigest","asset"], let text = row["id"]?.text,
                  let id = UUID(uuidString:text), id.uuidString == text, ids.insert(id).inserted,
                  let digest = row["localDigest"]?.text, ApprovedTopicReleasePreparation.validHash(digest) else { throw OwnedTopicCoverFailure.invalidResponse }
            let asset: OwnedTopicCoverAsset?
            if row["asset"] == .null { asset = nil }
            else { guard let a = row["asset"] else { throw OwnedTopicCoverFailure.invalidResponse }; asset = try .decode(a,owner:session.accountID) }
            return .init(id:id,localDigest:digest,asset:asset)
        }
        var requests = Set<String>()
        let loadedSelections = try selections.enumerated().map { index, item -> Selection in
            guard let row = item.object, Set(row.keys) == ["command","receipt"], let c = row["command"] else { throw OwnedTopicCoverFailure.invalidResponse }
            let command = try OwnedTopicCoverSelectionCommand.decode(c,owner:session.accountID)
            guard command.topicID == topicID, requests.insert(command.requestID).inserted else { throw OwnedTopicCoverFailure.invalidResponse }
            let receipt: OwnedTopicCoverSelectionReceipt?
            if row["receipt"] == .null { receipt = nil }
            else { guard let r = row["receipt"] else { throw OwnedTopicCoverFailure.invalidResponse }; receipt = try .decode(r,command:command) }
            guard index == selections.count-1 || receipt != nil else { throw OwnedTopicCoverFailure.invalidResponse }
            return .init(command:command,receipt:receipt)
        }
        return .init(ownerKey:session.ownerKey,topicID:topicID,uploads:loadedUploads,selections:loadedSelections,raw:raw)
    }
    private func replace(_ expected: Snapshot, uploads: [Upload], selections: [Selection], session: ProjectEditSession) throws -> Snapshot {
        guard expected.ownerKey == session.ownerKey, try read(session:session,topicID:expected.topicID) == expected else { throw OwnedTopicCoverFailure.changedContext }
        let value: [String:ProjectEditJSON] = ["version":.number(1),"ownerKey":.string(expected.ownerKey),"topicId":.number(Decimal(expected.topicID)),"uploads":.array(uploads.map(\.fields)),"selections":.array(selections.map(\.fields))]
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]; let data = try encoder.encode(value)
        let decoded = try decode(data,session:session,topicID:expected.topicID)
        guard decoded.uploads == uploads, decoded.selections == selections else { throw OwnedTopicCoverFailure.invalidResponse }
        try storage.write(data,key:key(session,expected.topicID))
        let saved = try read(session:session,topicID:expected.topicID)
        guard saved.raw == data else { throw OwnedTopicCoverFailure.persistenceUnavailable }; return saved
    }
    /// A new explicit upload may follow an unresolved upload. Its predecessor is retained; it is never retried automatically.
    public func beginUpload(localDigest: String, expected: Snapshot, session: ProjectEditSession, id: UUID = UUID()) throws -> Snapshot {
        guard expected.uploads.count < 32, ApprovedTopicReleasePreparation.validHash(localDigest), !expected.uploads.contains(where: { $0.id == id }) else { throw OwnedTopicCoverFailure.persistenceUnavailable }
        return try replace(expected,uploads:expected.uploads + [.init(id:id,localDigest:localDigest,asset:nil)],selections:expected.selections,session:session)
    }
    public func recordUpload(_ asset: OwnedTopicCoverAsset, uploadID: UUID, expected: Snapshot, session: ProjectEditSession) throws -> Snapshot {
        guard asset.ownerMemberID == session.accountID, let index = expected.uploads.firstIndex(where: { $0.id == uploadID }),
              expected.uploads[index].asset == nil || expected.uploads[index].asset == asset else { throw OwnedTopicCoverFailure.changedContext }
        var uploads = expected.uploads; uploads[index].asset = asset
        let saved = try replace(expected,uploads:uploads,selections:expected.selections,session:session)
        receivedUploads[key(session,expected.topicID)]?.removeValue(forKey:uploadID)
        return saved
    }
    public func beginSelection(_ command: OwnedTopicCoverSelectionCommand, expected: Snapshot, session: ProjectEditSession) throws -> Snapshot {
        guard command.topicID == expected.topicID, command.asset.ownerMemberID == session.accountID, expected.selections.count < 32,
              expected.currentSelection == nil || expected.currentSelection?.receipt != nil,
              !expected.selections.contains(where: { $0.command.requestID == command.requestID }) else { throw OwnedTopicCoverFailure.outcomeUnknown }
        return try replace(expected,uploads:expected.uploads,selections:expected.selections + [.init(command:command,receipt:nil)],session:session)
    }
    public func recordSelection(_ receipt: OwnedTopicCoverSelectionReceipt, expected: Snapshot, session: ProjectEditSession) throws -> Snapshot {
        guard let current = expected.currentSelection else { throw OwnedTopicCoverFailure.changedContext }
        _ = try OwnedTopicCoverSelectionReceipt.decode(receipt.fields,command:current.command)
        guard current.receipt == nil || current.receipt == receipt else { throw OwnedTopicCoverFailure.changedContext }
        var selected = expected.selections; selected[selected.count-1].receipt = receipt
        let saved = try replace(expected,uploads:expected.uploads,selections:selected,session:session)
        if receivedSelections[key(session,expected.topicID)] == receipt { receivedSelections.removeValue(forKey:key(session,expected.topicID)) }
        return saved
    }
}
