import Foundation
import CoreFoundation

/// Display-only fields from the original actor/action-bound appeal current read.
/// Deliberately does not expose raw task snapshots, media URLs or new permissions.
public struct NativeChannelAppealDetails:Equatable {
    public struct Evidence:Equatable,Identifiable {
        public let id:Int
        public let text:String?
        public let supplement:Bool
        public let messageIDs:[String]
        public let attachmentCount:Int?
    }
    public struct Event:Equatable,Identifiable {
        public let id:Int
        public let event:String?,at:String?,reason:String?
    }
    public let reason:String?,submittedAt:String?,decidedAt:String?,withdrawnAt:String?,dueAt:String?,slaDueAt:String?
    public let evidenceCount:Int?
    public let evidence:[Evidence]
    public let timeline:[Event]
    public let evidenceUnavailable:Bool,timelineUnavailable:Bool
    public init(source:[String:Any]) {
        reason=Self.text(source["reason_text"]);submittedAt=Self.text(source["submitted_at"])
        decidedAt=Self.text(source["decided_at"]);withdrawnAt=Self.text(source["withdrawn_at"])
        dueAt=Self.text(source["due_at"]);slaDueAt=Self.text(source["sla_due_at"])
        if let value=source["evidence_count"] as? NSNumber,CFGetTypeID(value) != CFBooleanGetTypeID(),value.doubleValue.isFinite,
           value.doubleValue==Double(value.intValue),value.intValue>=0 {evidenceCount=value.intValue} else{evidenceCount=nil}
        var items:[Evidence]=[]
        if let original=source["evidence_json"],!(original is NSNull) {items.append(Self.evidenceItem(original,id:0,supplement:false))}
        var unavailable=source["evidence_json"] == nil
        if let values=source["supplements"] as? [Any],values.count<=100 {
            for (index,value) in values.enumerated(){items.append(Self.evidenceItem(value,id:index+1,supplement:true))}
        } else {unavailable=true}
        evidence=items;evidenceUnavailable=unavailable
        if let rows=source["timeline"] as? [[String:Any]],rows.count<=500 {
            timeline=rows.enumerated().map { index,row in .init(id:index,event:Self.text(row["event"]),at:Self.text(row["at"]),reason:Self.text(row["reason"])) }
            timelineUnavailable=false
        } else {timeline=[];timelineUnavailable=true}
    }
    private static func text(_ value:Any?)->String? {
        guard let s=value as? String,!s.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else{return nil};return s
    }
    private static func evidenceItem(_ value:Any,id:Int,supplement:Bool)->Evidence {
        // Original supplements are JSON strings; original evidence_json is already decoded.
        let fields:[String:Any]?
        if let object=value as? [String:Any]{fields=object}
        else if let raw=value as? String,let data=raw.data(using:.utf8),data.count<=64*1024 {
            fields=(try? JSONSerialization.jsonObject(with:data)) as? [String:Any]
        } else{fields=nil}
        let ids=(fields?["message_ids"] as? [Any]).flatMap { values -> [String]? in
            guard values.count<=100 else{return nil}
            let checked=values.compactMap { NativeChannelGovernanceNotice.positive($0) }
            return checked.count==values.count ? checked:nil
        } ?? []
        let attachments=(fields?["screenshot_urls"] as? [String]).flatMap { values -> Int? in
            values.count<=100 && values.allSatisfy{!$0.isEmpty} ? values.count:nil
        }
        return Evidence(id:id,text:text(fields?["text"]),supplement:supplement,messageIDs:ids,attachmentCount:attachments)
    }
}
