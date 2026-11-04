import SwiftUI

@MainActor struct NativeRpgResourceAuthorEntry:View {
    @ObservedObject var model:ProjectEditModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var editToken = UUID()
    @State private var editor:NativeRpgResourceAuthorDraft?
    @State private var capture:Capture?
    @State private var reviewed:ProjectEditJSON?
    @State private var message:String?
    private struct Capture {
        let incarnation:UUID;let revision:Int;let session:ProjectEditSession;let snapshot:ProjectEditSnapshot
        let draft:ProjectEditDraft;let draftBytes:Data;let lease:ProjectEditStarterController.Lease
    }
    private var current:Bool {
        guard scenePhase == .active,let capture,model.fullEdit,model.confirmation == nil else{return false}
        return model.editorIncarnation == capture.incarnation && model.draftMutationRevision == capture.revision
            && model.coordinator.session == capture.session
            && model.coordinator.session?.storageNamespace.utf8.elementsEqual(capture.session.storageNamespace.utf8) == true
            && model.coordinator.snapshot == capture.snapshot && model.draft == capture.draft
            && ProjectEditPendingMaterials.exactData(model.draft) == capture.draftBytes
            && model.isCurrentStarterLease(capture.lease)
    }
    private func close(){editToken = UUID();editor = nil;capture = nil;reviewed = nil}
    private func mutate(_ token: UUID, _ action:(inout NativeRpgResourceAuthorDraft)->Void){guard current,editToken == token,var next = editor else{return};action(&next);editor = next;editToken = UUID();reviewed = nil;message = nil}
    private func field(_ name:String,_ field:String)->Binding<String>{let token = editToken; return Binding(get:{editor?.text(name,field) ?? ""},set:{value in mutate(token){$0.edit(name,field,value)}})}
    var body:some View {
        let token = editToken
        Section("原v2四资源配置") {
            if editor == nil {
                Button("编辑原HP／士气／幸运／灵感声明") {
                    guard editToken == token,capture == nil,scenePhase == .active,model.fullEdit,model.confirmation == nil,let session = model.coordinator.session,let snapshot = model.coordinator.snapshot,
                          let lease = model.captureStarterLease(),let bytes = ProjectEditPendingMaterials.exactData(model.draft) else{return}
                    do {editor = try .init(draft:model.draft);capture = .init(incarnation:model.editorIncarnation,revision:model.draftMutationRevision,session:session,snapshot:snapshot,draft:model.draft,draftBytes:bytes,lease:lease);message = nil}
                    catch {message = "须已有原schema2 journeyRules；不转换schema1、不新建角色或资源模板。"}
                }.disabled(scenePhase != .active || !model.fullEdit || model.confirmation != nil)
            } else if current,let draft = editor {
                Group {
                    Text("只声明发布后的原资源开关、初始值和上限；不改变当前局余额。空白表示原源未显式声明，改动该资源时必须明确三项，不自动填入默认值。").nativeAuthorSupportingCopy()
                    ForEach(NativeRpgResourceAuthorDraft.names,id:\.self){name in
                        VStack(alignment:.leading){
                            Text(name).font(.headline)
                            Picker("显式启用状态",selection:field(name,"enabled")) {Text("未显式声明").tag("");Text("启用").tag("true");Text("关闭").tag("false")}
                            TextField("明确初始值 init",text:field(name,"init")).keyboardType(.numberPad)
                            TextField("明确上限 max",text:field(name,"max")).keyboardType(.numberPad)
                            Text(name == "hp" ? "原上限范围1–20；初始值0至上限。" : name == "luck" ? "原上限范围0–5；初始值0至上限。" : "原上限范围0–1000；初始值0至上限。")
                            Button("恢复此资源的原声明"){mutate(token){$0.restore(name)}}
                        }
                    }
                    VStack(alignment:.leading){
                        Text("原阶段休整士气保底").font(.headline)
                        TextField("可选 stageRestMoraleFloor",text:Binding(get:{editor?.stageMoraleFloorText ?? ""},set:{value in mutate(token){$0.editStageMoraleFloor(value)}})).keyboardType(.numberPad)
                        Text("留空即不声明士气保底，不会采用默认恢复量。仅明确启用士气的发布版本在原章节阶段休整时执行；不新增休息按钮，不改变旧局冻结规则。").nativeAuthorSupportingCopy()
                        Button("恢复原阶段士气保底声明"){mutate(token){$0.restoreStageMoraleFloor()}}
                    }
                    ForEach(Array(draft.issues.enumerated()),id:\.offset){_,issue in NativeAuthorNotice(text: Text(issue), tone: .attention)}
                    Button("预览原四资源配置") {
                        guard current, editToken == token else{return}
                        do {reviewed = try draft.applying(to:model.draft).preserved["journeyRules"];message = nil}
                        catch {reviewed = nil;message = "字段或原草稿不可用，未生成可确认预览。"}
                    }.disabled(!draft.issues.isEmpty)
                    if let reviewed {
                        Text(reviewed.text ?? "").font(.caption.monospaced()).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        Button("确认写回并保存原项目草稿") {
                            guard current,editToken == token,let reviewedText = reviewed.text,let currentReview = self.reviewed?.text,
                                  currentReview.utf8.elementsEqual(reviewedText.utf8),let capture,let editor,
                                  let proposed = try? editor.applying(to:model.draft),let proposedText = proposed.preserved["journeyRules"]?.text,
                                  proposedText.utf8.elementsEqual(reviewedText.utf8) else{return}
                            guard model.persistLocalChange(proposed,lease:capture.lease) else {
                                message = "原本地保存未确认；保留资源编辑副本，可再次确认本地保存，尚未保存服务器或发布。";return
                            }
                            close();message = "已沿原保存器保存本地草稿，尚未保存服务器或发布。"
                        }.nativeAuthorPrimaryAction()
                    }
                    Text("沿原项目保存／同请求恢复／发布及真实新局初始化。旧局不补资源、不迁移余额；原消费、技能点、专长及TEAM写端均不改；阶段士气保底只由原STAGE_REST写端使用明确冻结值。角色页另读本人原局当前资源，检定结果展示该原请求已保存余额。").nativeAuthorSupportingCopy()
                }.disabled(!current)
                Button("关闭资源编辑副本"){guard editToken == token else{return};close()}
            } else {
                Text("项目、草稿或权限已变化；旧资源副本已停用，请重新读取。")
                Button("关闭资源编辑副本"){guard editToken == token else{return};close()}
            }
            if let message{NativeAuthorNotice(text: Text(message))}
        }.onDisappear{close()}.onChange(of:current){_,valid in if !valid{close()}}
    }
}
