import Foundation

/// One captured node-photo presentation. Display failures do not replace receipt facts.
@MainActor public final class ProjectNodeImageFlow {
    public struct Review: Identifiable { public let id=UUID(); public let image:RetainedSelectedImage }
    public struct UploadClaim { public let id=UUID(); fileprivate let attemptID:UUID,image:RetainedSelectedImage }
    public enum State: Equatable { case idle,ready,uploading,uploaded,unknown,unauthorized,localSaveFailed,applied,failed,closed }
    public let id=UUID()
    public private(set) var context:ProjectNodeImageContext
    public var session:ProjectEditSession{context.session}
    public var identity:ProjectEditDraftIdentity{context.identity}
    public var target:ProjectNodeImageTarget{context.target}
    public private(set) var state:State = .idle
    public private(set) var review:Review?
    public private(set) var snapshot:ProjectNodeImageJournal.Snapshot?
    public private(set) var activeAttempt:UUID?
    public private(set) var unstoredReceipt:ProjectNodeUploadedImage?
    private let initialTarget:ProjectNodeImageTarget
    private let recoveryEntry:ProjectNodeImageJournal.Entry?
    private let source:any ProjectNodeImageUploading
    private let journal:ProjectNodeImageJournal
    private let currentDraft:()->ProjectEditDraft?
    private let parentCurrent:()->Bool
    private var task:Task<ProjectNodeUploadedImage,Error>?
    private var claimID:UUID?,pickerID:UUID?
    public init(context:ProjectNodeImageContext,
                source:any ProjectNodeImageUploading,journal:ProjectNodeImageJournal,
                recoveryOnly:ProjectNodeImageJournal.Entry? = nil,
                currentDraft:@escaping()->ProjectEditDraft?,parentCurrent:@escaping()->Bool){
        self.context=context;initialTarget=context.target
        self.source=source;self.journal=journal;recoveryEntry=recoveryOnly;self.currentDraft=currentDraft;self.parentCurrent=parentCurrent
    }
    public var isCurrent:Bool{state != .closed && parentCurrent() && source.isCurrent(context:context)}
    public var busy:Bool{task != nil || claimID != nil || pickerID != nil}
    public var receipt:ProjectNodeUploadedImage?{unstoredReceipt ?? snapshot?.entries.first(where:{$0.attemptID==activeAttempt})?.receipt}
    public var hasUnstoredReceipt:Bool{unstoredReceipt != nil}
    public var referenceFitsCSV:Bool{receipt.map { ProjectNodeImageTarget.representable($0.reference) } ?? false}
    public var matchesCapturedDraft:Bool{
        guard let draft=currentDraft()else{return false}
        return target.matches(draft,identity:identity,session:session)
    }
    public var alreadyApplied:Bool{
        guard let receipt,let draft=currentDraft()else{return false}
        return target.hasAppliedReference(receipt,in:draft,identity:identity,session:session)
    }
    public var canPick:Bool{recoveryEntry == nil && snapshot != nil && receipt == nil && unresolvedUploadCount == 0 && isCurrent && state != .unauthorized && state != .unknown && !busy && !hasUnstoredReceipt && matchesCapturedDraft && source.permitsPicker(context:context)}
    public var canPersistReceipt:Bool{isCurrent && !busy && hasUnstoredReceipt}
    public var canApply:Bool{
        guard isCurrent,!busy,review == nil,!hasUnstoredReceipt,referenceFitsCSV,let receipt,source.permitsReference(receipt,context:context)else{return false}
        if let recoveryEntry {
            return target==recoveryEntry.target && activeAttempt==recoveryEntry.attemptID &&
                self.receipt==recoveryEntry.receipt && snapshot?.entries.contains(recoveryEntry)==true && alreadyApplied
        }
        return matchesCapturedDraft || alreadyApplied
    }
    public var unresolvedUploadCount:Int{snapshot?.entries.filter{$0.receipt==nil && sameField($0.target)}.count ?? 0}
    private func sameField(_ saved:ProjectNodeImageTarget)->Bool{initialTarget.sameField(saved)}
    public func load(){
        guard isCurrent,!busy else{return}
        do{
            let saved=try journal.read(session:session,identity:identity);snapshot=saved
            if let recoveryEntry {
                activeAttempt=nil
                guard let draft=currentDraft(), recoveryEntry.target==initialTarget, !recoveryEntry.applied,
                      let entry=saved.entries.first(where:{$0.attemptID==recoveryEntry.attemptID}), entry==recoveryEntry,
                      let receipt=entry.receipt, entry.target.hasAppliedReference(receipt,in:draft,identity:identity,session:session)
                else{state = .failed;return}
                context=try context.replacingTarget(entry.target);activeAttempt=entry.attemptID;state = .uploaded;return
            }
            if let pending=journal.unstored(session:session,identity:identity).first(where:{ receipt in
                saved.entries.contains(where:{$0.attemptID==receipt.attemptID && sameField($0.target)})
            }),let entry=saved.entries.first(where:{$0.attemptID==pending.attemptID}){
                context=try context.replacingTarget(entry.target);activeAttempt=entry.attemptID;unstoredReceipt=pending;state = .uploaded;return
            }
            if let draft=currentDraft(),let entry=saved.entries.last(where:{ entry in
                guard sameField(entry.target),!entry.applied,let receipt=entry.receipt else{return false}
                return entry.target.matches(draft,identity:identity,session:session) || entry.target.hasAppliedReference(receipt,in:draft,identity:identity,session:session)
            }){context=try context.replacingTarget(entry.target);activeAttempt=entry.attemptID;state = .uploaded}
            else{state = .ready}
        }catch{state = .failed}
    }
    public func beginPicking()->UUID?{guard canPick else{return nil};let id=UUID();pickerID=id;return id}
    public func finishPicking(_ image:RetainedSelectedImage?,original:UUID){
        guard pickerID==original else{return};pickerID=nil
        guard let image,canPick,source.policy(context:context)?.permits(image)==true else{return};review = .init(image:image);state = .ready
    }
    /// The native crop controller supplies only its own freshly sanitized output.
    public func stageCropped(_ image:RetainedSelectedImage){guard canPick,source.policy(context:context)?.permits(image)==true else{return};review = .init(image:image);state = .ready}
    public func cancelReview(_ original:Review){guard review?.id==original.id,!busy else{return};review=nil}
    public func canUpload(_ original:Review)->Bool{recoveryEntry == nil && unresolvedUploadCount == 0 && isCurrent && !busy && !hasUnstoredReceipt && matchesCapturedDraft && review?.id==original.id && source.policy(context:context)?.permits(original.image)==true}
    public func claimUpload(_ original:Review)->UploadClaim?{
        guard canUpload(original),let snapshot else{return nil}
        do{
            let attempt=UUID(),digest=ProjectNodeImageTarget.hash(original.image.jpeg)
            self.snapshot=try journal.begin(target:target,digest:digest,expected:snapshot,session:session,identity:identity,id:attempt)
            let claim=UploadClaim(attemptID:attempt,image:original.image);claimID=claim.id;activeAttempt=attempt;review=nil;state = .uploading;return claim
        }catch{state = .failed;return nil}
    }
    public func upload(_ original:UploadClaim)async{
        guard claimID==original.id,activeAttempt==original.attemptID else{return}
        guard isCurrent,matchesCapturedDraft else{close();return};claimID=nil
        let captured=context
        let pending=Task{[weak self,source]in
            try await source.upload(original.image,attemptID:original.attemptID,context:captured){[weak self]in
                guard let self else{return false};return self.isCurrent && self.matchesCapturedDraft && self.activeAttempt==original.attemptID
            }
        };task=pending
        do{
            let received=try await withTaskCancellationHandler(operation:{try await pending.value},onCancel:{pending.cancel()})
            guard task != nil else{return}
            guard !pending.isCancelled,!Task.isCancelled,isCurrent,activeAttempt==received.attemptID,received.targetID==target.id,Data(received.ownerKey.utf8)==Data(target.ownerKey.utf8) else{close();return}
            task=nil;journal.remember(received,identity:identity);unstoredReceipt=received
            persistReceipt()
        }catch{
            guard task != nil else{return};task=nil
            guard isCurrent else{close();return};state = error as? APIError == .unauthorized ? .unauthorized : .unknown
        }
    }
    public func persistReceipt(){
        guard canPersistReceipt,let receipt=unstoredReceipt else{return}
        do{
            let latest=try journal.read(session:session,identity:identity)
            guard latest.entries.contains(where:{$0.attemptID==receipt.attemptID && $0.target==target})else{throw ProjectNodeImageFailure.changedContext}
            snapshot=try journal.record(receipt,expected:latest,session:session,identity:identity);unstoredReceipt=nil;state = .uploaded
        }catch{state = .failed}
    }
    public func draftForApply()->ProjectEditDraft?{
        guard canApply,let receipt,let draft=currentDraft()else{return nil}
        if alreadyApplied{return draft}
        return try? target.applying(receipt,to:draft,identity:identity,session:session)
    }
    /// Call only after the ordinary editor reports its existing local save succeeded.
    public func didSaveAppliedDraft(){
        guard isCurrent,!busy,!hasUnstoredReceipt,alreadyApplied,let attempt=activeAttempt else{return}
        do{
            let latest=try journal.read(session:session,identity:identity)
            guard let entry=latest.entries.first(where:{$0.attemptID==attempt}),entry.target==target,entry.receipt==receipt else{throw ProjectNodeImageFailure.changedContext}
            snapshot=try journal.markApplied(attemptID:attempt,expected:latest,session:session,identity:identity);state = .applied
        }catch{state = .localSaveFailed}
    }
    public func localSaveFailed(){guard isCurrent else{return};state = .localSaveFailed}
    public func close(){task?.cancel();task=nil;claimID=nil;pickerID=nil;review=nil;unstoredReceipt=nil;state = .closed}
}
