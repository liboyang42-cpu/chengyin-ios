import Foundation

/// One captured story-audio presentation. Display failures do not replace receipt facts.
@MainActor public final class ProjectStoryAudioFlow {
    public struct Review: Identifiable { public let id=UUID(); public let audio:ProjectStorySelectedAudio }
    public struct UploadClaim { public let id=UUID(); fileprivate let attemptID:UUID,audio:ProjectStorySelectedAudio }
    public enum State: Equatable { case idle,ready,uploading,uploaded,unknown,unauthorized,localSaveFailed,applied,failed,closed }
    public let id=UUID(),session:ProjectEditSession,identity:ProjectEditDraftIdentity
    public private(set) var target:ProjectStoryAudioTarget
    public private(set) var state:State = .idle
    public private(set) var review:Review?
    public private(set) var snapshot:ProjectStoryAudioJournal.Snapshot?
    public private(set) var activeAttempt:UUID?
    public private(set) var unstoredReceipt:ProjectStoryUploadedAudio?
    private let initialTarget:ProjectStoryAudioTarget
    private let source:any ProjectStoryAudioUploading
    private let journal:ProjectStoryAudioJournal
    private let currentDraft:()->ProjectEditDraft?
    private let parentCurrent:()->Bool
    private var task:Task<ProjectStoryUploadedAudio,Error>?
    private var claimID:UUID?,pickerID:UUID?
    public init(target:ProjectStoryAudioTarget,session:ProjectEditSession,identity:ProjectEditDraftIdentity,
                source:any ProjectStoryAudioUploading,journal:ProjectStoryAudioJournal,
                currentDraft:@escaping()->ProjectEditDraft?,parentCurrent:@escaping()->Bool){
        self.target=target;initialTarget=target;self.session=session;self.identity=identity
        self.source=source;self.journal=journal;self.currentDraft=currentDraft;self.parentCurrent=parentCurrent
    }
    public var isCurrent:Bool{state != .closed && parentCurrent() && source.isCurrent(session:session)}
    public var busy:Bool{task != nil || claimID != nil || pickerID != nil}
    public var receipt:ProjectStoryUploadedAudio?{unstoredReceipt ?? snapshot?.entries.first(where:{$0.attemptID==activeAttempt})?.receipt}
    public var hasUnstoredReceipt:Bool{unstoredReceipt != nil}
    public var referenceFitsStory:Bool{receipt.map { $0.reference.utf16.count <= 500 } ?? false}
    public var matchesCapturedDraft:Bool{
        guard let draft=currentDraft()else{return false}
        return target.matches(draft,identity:identity,session:session)
    }
    public var alreadyApplied:Bool{
        guard let receipt,let draft=currentDraft()else{return false}
        return target.hasAppliedReference(receipt,in:draft,identity:identity,session:session)
    }
    public var canPick:Bool{snapshot != nil && isCurrent && state != .unauthorized && !busy && !hasUnstoredReceipt && matchesCapturedDraft && source.permitsPicker(session:session)}
    public var canPersistReceipt:Bool{isCurrent && !busy && hasUnstoredReceipt}
    public var canApply:Bool{
        guard isCurrent,!busy,review == nil,!hasUnstoredReceipt,referenceFitsStory,let receipt,source.permitsReference(receipt.reference,session:session)else{return false}
        return matchesCapturedDraft || alreadyApplied
    }
    public var unresolvedUploadCount:Int{snapshot?.entries.filter{$0.receipt==nil}.count ?? 0}
    private func sameField(_ saved:ProjectStoryAudioTarget)->Bool{
        saved.ownerKey==initialTarget.ownerKey && saved.draftBucket==initialTarget.draftBucket &&
            saved.chapterID==initialTarget.chapterID && saved.blockID==initialTarget.blockID
    }
    public func load(){
        guard isCurrent,!busy else{return}
        do{
            let saved=try journal.read(session:session,identity:identity);snapshot=saved
            if let pending=journal.unstored(session:session,identity:identity).first(where:{ receipt in
                saved.entries.contains(where:{$0.attemptID==receipt.attemptID && sameField($0.target)})
            }),let entry=saved.entries.first(where:{$0.attemptID==pending.attemptID}){
                target=entry.target;activeAttempt=entry.attemptID;unstoredReceipt=pending;state = .uploaded;return
            }
            if let draft=currentDraft(),let entry=saved.entries.last(where:{ entry in
                guard sameField(entry.target),!entry.applied,let receipt=entry.receipt else{return false}
                return entry.target.matches(draft,identity:identity,session:session) || entry.target.hasAppliedReference(receipt,in:draft,identity:identity,session:session)
            }){target=entry.target;activeAttempt=entry.attemptID;state = .uploaded}
            else{state = .ready}
        }catch{state = .failed}
    }
    public func beginPicking()->UUID?{guard canPick else{return nil};let id=UUID();pickerID=id;return id}
    public func finishPicking(_ audio:ProjectStorySelectedAudio?,original:UUID){
        guard pickerID==original else{return};pickerID=nil
        guard let audio,canPick else{return};review = .init(audio:audio);state = .ready
    }
    /// Test/dependency seam for an already bounded explicit document copy; no decoding claim.
    public func stageSelected(_ audio:ProjectStorySelectedAudio){guard canPick else{return};review = .init(audio:audio);state = .ready}
    public func cancelReview(_ original:Review){guard review?.id==original.id,!busy else{return};review=nil}
    public func canUpload(_ original:Review)->Bool{isCurrent && !busy && !hasUnstoredReceipt && matchesCapturedDraft && review?.id==original.id}
    public func claimUpload(_ original:Review)->UploadClaim?{
        guard canUpload(original),let snapshot else{return nil}
        do{
            let attempt=UUID(),digest=ProjectStoryImageTarget.hash(original.audio.bytes)
            self.snapshot=try journal.begin(target:target,digest:digest,expected:snapshot,session:session,identity:identity,id:attempt)
            let claim=UploadClaim(attemptID:attempt,audio:original.audio);claimID=claim.id;activeAttempt=attempt;review=nil;state = .uploading;return claim
        }catch{state = .failed;return nil}
    }
    public func upload(_ original:UploadClaim)async{
        guard claimID==original.id,activeAttempt==original.attemptID else{return}
        guard isCurrent,matchesCapturedDraft else{close();return};claimID=nil
        let pending=Task{[source,session]in try await source.upload(original.audio,attemptID:original.attemptID,session:session)};task=pending
        do{
            let received=try await withTaskCancellationHandler(operation:{try await pending.value},onCancel:{pending.cancel()})
            guard task != nil else{return}
            guard !pending.isCancelled,!Task.isCancelled,isCurrent,activeAttempt==received.attemptID else{close();return}
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
            guard latest.entries.contains(where:{$0.attemptID==receipt.attemptID && $0.target==target})else{throw ProjectStoryAudioFailure.changedContext}
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
            guard let entry=latest.entries.first(where:{$0.attemptID==attempt}),entry.target==target,entry.receipt==receipt else{throw ProjectStoryAudioFailure.changedContext}
            snapshot=try journal.markApplied(attemptID:attempt,expected:latest,session:session,identity:identity);state = .applied
        }catch{state = .localSaveFailed}
    }
    public func localSaveFailed(){guard isCurrent else{return};state = .localSaveFailed}
    public func close(){task?.cancel();task=nil;claimID=nil;pickerID=nil;review=nil;unstoredReceipt=nil;state = .closed}
}
