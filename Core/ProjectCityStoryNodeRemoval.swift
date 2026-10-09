import Foundation

/// Explicit city story-node removal. Opaque dependency data is never rewritten.
public enum ProjectCityStoryNodeRemoval {
    public enum Failure: Error { case identity, unsupported, referenced, stale }
    public struct Receipt {
        public let before: ProjectEditDraft, after: ProjectEditDraft
        public let nodeIDs: [String]
    }
    public static func removing(nodeID: String, chapterID: String, in draft: ProjectEditDraft) throws -> Receipt {
        guard draft.product == .city, draft.owner == .personal else { throw Failure.unsupported }
        try ProjectEditPendingMaterials.validateIDs(draft)
        guard !chapterID.isEmpty, !nodeID.isEmpty,
              let ci=draft.chapters.firstIndex(where: { Data($0.id.utf8)==Data(chapterID.utf8) }),
              draft.chapters.filter({ $0.id==chapterID }).count==1,
              draft.chapters.flatMap(\.nodes).filter({ $0.id==nodeID }).count==1,
              !(draft.pendingMaterials ?? []).contains(where: { $0.id==nodeID }),
              let ni=draft.chapters[ci].nodes.firstIndex(where: { Data($0.id.utf8)==Data(nodeID.utf8) }) else { throw Failure.identity }
        let chapter=draft.chapters[ci],node=chapter.nodes[ni]
        guard chapter.schemaVersion==1,chapter.required==1,
              chapter.preserved["opening"]==nil || chapter.preserved["opening"] == .null || chapter.preserved["opening"] == .bool(false),
              chapter.preserved["ending"]==nil || chapter.preserved["ending"] == .null,
              let blocks=chapter.blocks else { throw Failure.unsupported }
        switch draft.preserved["routeMode"] { case nil,.null?,.string("LINEAR")?: break; default: throw Failure.referenced }
        switch draft.preserved["routeGraphJson"] { case nil,.null?,.string("")?: break; default: throw Failure.referenced }
        let allBlocks=draft.chapters.flatMap { $0.blocks ?? [] }
        guard allBlocks.allSatisfy({ !$0.id.isEmpty }),Set(allBlocks.map(\.id)).count==allBlocks.count,
              let bi=blocks.firstIndex(where: { $0.kind == .node && Data($0.nodeID.utf8)==Data(nodeID.utf8) }),
              allBlocks.filter({ $0.nodeID==nodeID }).count==1,
              node.localMetadata["_storyGame"]==nil || node.localMetadata["_storyGame"] == .null || node.localMetadata["_storyGame"] == .bool(false),
              blocks[bi].sourceFields?["locationRequired"]==nil || blocks[bi].sourceFields?["locationRequired"] == .bool(true) else { throw Failure.referenced }
        let serverID: Int?
        switch node.localMetadata["id"] {
        case nil,.null?: serverID=nil
        case let value?: guard let id=value.integer,id>0 else { throw Failure.identity };serverID=id
        }
        if let serverID {
            guard draft.chapters.flatMap(\.nodes).filter({ $0.localMetadata["id"]?.integer==serverID }).count==1 else { throw Failure.identity }
        }
        let clientKey: String?
        switch node.localMetadata["clientNodeKey"] {
        case nil,.null?: clientKey=nil
        case .string(let key)?: guard !key.isEmpty else { throw Failure.identity };clientKey=key
        default: throw Failure.identity
        }
        if let clientKey {
            guard draft.chapters.flatMap(\.nodes).filter({ $0.localMetadata["clientNodeKey"]?.text==clientKey }).count==1 else { throw Failure.identity }
        }
        let guarder=ReferenceGuard(localID:nodeID,clientKey:clientKey,serverID:serverID)
        // The old stored raw story is a separate representation we cannot update here.
        try guarder.inspect(.object(draft.preserved))
        for c in draft.chapters {
            try guarder.inspect(.object(c.preserved))
            for n in c.nodes {
                var metadata=n.localMetadata
                // Only known, non-reference node value fields are excluded. Unknown
                // nested configuration still passes through the conservative guard.
                for key in ["id","clientNodeKey","name","subtitle","description","address","longitude","latitude","imgUrl","nodeTime","sortID","sortId","businessTime","templateId","templateName","hookText","cardHookLong","fragmentText","_storyGame"] { metadata.removeValue(forKey:key) }
                try guarder.inspect(.object(metadata))
            }
            for block in c.blocks ?? [] { try guarder.inspect(.object(block.sourceFields ?? [:])) }
        }
        for pending in draft.pendingMaterials ?? [] { try guarder.inspect(.object(pending.node.localMetadata)) }
        for ticket in draft.tickets { try guarder.inspect(.object(ticket.localMetadata)) }
        var next=draft
        next.chapters[ci].blocks?.remove(at:bi)
        next.chapters[ci].nodes.remove(at:ni)
        // No adjacent text merge, pending copy, graph pruning or metadata normalization.
        return .init(before:draft,after:next,nodeIDs:[nodeID])
    }
    public static func restoring(_ receipt: Receipt, in current: ProjectEditDraft) throws -> ProjectEditDraft {
        guard let expected=ProjectEditPendingMaterials.exactData(receipt.after),
              ProjectEditPendingMaterials.exactData(current)==expected else { throw Failure.stale }
        return receipt.before
    }
    public static func combining(_ earlier: Receipt, with later: Receipt) throws -> Receipt {
        guard let expected=ProjectEditPendingMaterials.exactData(earlier.after),
              ProjectEditPendingMaterials.exactData(later.before)==expected,
              Set(earlier.nodeIDs).isDisjoint(with:later.nodeIDs) else { throw Failure.stale }
        return .init(before:earlier.before,after:later.after,nodeIDs:earlier.nodeIDs+later.nodeIDs)
    }
    private struct ReferenceGuard {
        let localID:String,clientKey:String?,serverID:Int?
        func inspect(_ value:ProjectEditJSON,depth:Int=0)throws {
            guard depth<32 else { throw Failure.referenced }
            switch value {
            case .null,.bool(_): break
            case .number(let value): if let serverID,value==Decimal(serverID) { throw Failure.referenced }
            case .string(let raw):
                if raw==localID || (clientKey.map { raw==$0 } ?? false) || (serverID.map { raw==String($0) } ?? false) { throw Failure.referenced }
                let trimmed=raw.trimmingCharacters(in:.whitespacesAndNewlines)
                if trimmed==localID || (clientKey.map { trimmed==$0 } ?? false) || (serverID.map { trimmed==String($0) } ?? false) { throw Failure.referenced }
                if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
                    // Do not interpret serialized future dependency documents. In
                    // particular no lossy Foundation dictionary collapse is allowed.
                    guard trimmed=="{}" || trimmed=="[]" else { throw Failure.referenced }
                }
            case .array(let values): for child in values { try inspect(child,depth:depth+1) }
            case .object(let object):
                for (key,child) in object {
                    let lower=key.lowercased()
                    if ["node","grant","quest","graph"].contains(where:{lower.contains($0)}),!empty(child) { throw Failure.referenced }
                    try inspect(child,depth:depth+1)
                }
            }
        }
        private func empty(_ value:ProjectEditJSON)->Bool {
            switch value { case .null: return true;case .string(let raw):return raw.isEmpty;case .array(let rows):return rows.isEmpty;case .object(let row):return row.isEmpty;default:return false }
        }
    }
}
