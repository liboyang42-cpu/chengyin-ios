import SwiftUI

private func storyWalkingAuthorText(_ key: String, locale: Locale) -> String {
    String(localized: LocalizedStringResource(String.LocalizationValue(stringLiteral: "walkingAuthor." + key), table: "NativeStoryWalkingAuthor", locale: locale))
}

@MainActor struct NativeStoryWalkingAuthorEntry: View {
    @ObservedObject var model: ProjectEditModel
    @Environment(\.locale) private var locale
    private func text(_ key: String) -> String { storyWalkingAuthorText(key, locale: locale) }
    var body: some View {
        if model.fullEdit { NavigationLink(text("entry")) { NativeStoryWalkingAuthorView(model:model) } }
    }
}

@MainActor private struct NativeStoryWalkingAuthorView: View {
    @ObservedObject var model: ProjectEditModel
    @Environment(\.locale) private var locale
    private func text(_ key: String) -> String { storyWalkingAuthorText(key, locale: locale) }
    @State private var editor: NativeStoryWalkingAuthorDraft?
    @State private var capture: Capture?
    @State private var acknowledged = false
    @State private var notice: String? // Catalog key; never cache a previous UI language.
    @State private var editToken = UUID()
    @State private var opened = false
    @State private var retired = false
    @State private var edited = false
    @State private var confirmingExit = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    private struct Capture { let lease: ProjectEditStarterController.Lease; let bytes: Data; let incarnation: UUID; let revision: Int; let session: ProjectEditSession; let snapshot: ProjectEditSnapshot; let draft: ProjectEditDraft }
    private var current: Bool {
        guard phase == .active, let capture, model.fullEdit, model.confirmation == nil, model.isCurrentStarterLease(capture.lease), model.coordinator.session?.storageNamespace.utf8.elementsEqual(capture.session.storageNamespace.utf8) == true else { return false }
        return capture.incarnation == model.editorIncarnation && capture.revision == model.draftMutationRevision
            && capture.session == model.coordinator.session && capture.snapshot == model.coordinator.snapshot && ProjectEditPendingMaterials.exactData(model.draft) == capture.bytes
    }
    private var sourceNodes: [(Int,String)] {
        guard current, let capture else { return [] }
        return capture.draft.chapters.flatMap(\.nodes).compactMap { node in guard let id = node.localMetadata["id"]?.integer, id > 0 else { return nil }; return (id,node.name) }
    }
    var body: some View {
        let token = editToken
        let validation = current ? editor.map { NativeStoryWalkingAuthorValidation($0, original: model.draft) } : nil
        Form {
            if retired {
                Section(text("retired.title")) {
                    NativeAuthorNotice(text: Text(text("retired.message")), tone: .attention)
                    Button(text("return")) { dismiss() }.disabled(phase != .active)
                }
            } else {
                Section(text("scope.title")) {
                    Text(text("scope")).nativeAuthorSupportingCopy()
                    Text(text("reviewScope")).nativeAuthorSupportingCopy()
                }
                if let notice {
                    Section(text("notice.title")) { NativeAuthorNotice(text: Text(text(notice))) }
                }
                if opened && editor == nil {
                    Button(text("return")) { dismiss() }.disabled(phase != .active)
                }
                if let editor {
                    if editor.schema == 1 {
                        Section(text("legacy.title")) {
                            Text(text("legacy.scope"))
                            LabeledContent(text("authorization.title"), value: String(format: text("duration.value"), locale: locale, editor.ttl))
                            ForEach(editor.nodes) { node in Text(verbatim: nodeDescription(node.id) + " · " + node.region) }
                            Button(text("legacy.upgrade")) { guard current, editToken == token else { return }; self.editor?.schema = 2; edited = true; acknowledged = false; notice = nil; editToken = UUID() }
                        }.disabled(!current)
                    } else {
                        Section(text("authorization.title")) {
                            if let validation {
                                ForEach(validation.global, id: \.self) { issue in
                                    NativeAuthorNotice(text: Text(verbatim: NativeStoryWalkingAuthorValidation.text(issue, locale: locale)), tone: .attention)
                                        .accessibilityIdentifier("walkingAuthor.validation.\(issue.rawValue)")
                                }
                            }
                            TextField(text("ttl"),text:ttl).keyboardType(.numberPad).disabled(!current)
                        }
                        if editor.nodes.isEmpty { NativeAuthorNotice(text: Text(text("nodes.empty"))) }
                        ForEach(editor.nodes) { node in nodeSection(node, issues: validation?.nodes[node.id] ?? []) }
                        let available = sourceNodes.filter { pair in !editor.nodes.contains { $0.id == pair.0 } }
                        Menu(text("node.add")) {
                            ForEach(available,id:\.0) { id,name in
                                Button(name) { guard current, editToken == token else { return }; self.editor?.nodes.append(.init(id:id)); edited = true; acknowledged = false; notice = nil; editToken = UUID() }
                            }
                        }.disabled(!current || editor.nodes.count >= 2000 || available.isEmpty)
                        if editor.nodes.count >= 2000 { Text(text("nodes.limit")) }
                        if sourceNodes.isEmpty { NativeAuthorNotice(text: Text(text("nodes.noneSaved"))) }
                        else if available.isEmpty { Text(text("nodes.allAdded")) }
                        Section(text("confirmation.title")) {
                            Toggle(text("acknowledge"),isOn:Binding(get: { acknowledged }, set: { value in guard current, editToken == token else { return }; acknowledged = value; editToken = UUID() })).disabled(!current)
                            Button(text("apply")) { apply(token) }.nativeAuthorPrimaryAction().disabled(!current || !acknowledged || validation?.canApply != true).accessibilityIdentifier("walkingAuthor.apply")
                            Text(text("saveScope")).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .nativeAuthorSurface()
        .navigationTitle(text("title"))
        .navigationBarBackButtonHidden(true)
        .interactiveDismissDisabled(current && edited)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { requestReturn() } label: {
                    Label(text("back"), systemImage: "chevron.backward").labelStyle(.iconOnly)
                }.disabled(phase != .active).accessibilityIdentifier("walkingAuthor.back")
            }
        }
        .confirmationDialog(text("discard.title"), isPresented: $confirmingExit, titleVisibility: .visible) {
            Button(text("discard.confirm"), role: .destructive) {
                guard current, editToken == token else { return }; retire(); dismiss()
            }
            Button(text("discard.cancel"), role: .cancel) { }
        } message: { Text(text("discard.message")) }
        .onAppear { open() }
        .onChange(of:current) { _,value in if !value { retire() } }
        .onDisappear { retire() }
    }
    @ViewBuilder private func nodeSection(_ node: NativeStoryWalkingAuthorDraft.Node, issues: [NativeStoryWalkingAuthorValidation.Issue]) -> some View {
        let token = editToken
        Section(sourceNodes.first(where: { $0.0 == node.id })?.1 ?? nodeDescription(node.id)) {
            ForEach(issues, id: \.self) { issue in
                NativeAuthorNotice(text: Text(verbatim: NativeStoryWalkingAuthorValidation.text(issue, locale: locale)), tone: .attention)
                    .accessibilityIdentifier("walkingAuthor.node.\(node.id).issue.\(issue.rawValue)")
            }
            TextField(text("region"),text:region(node.id)).textInputAutocapitalization(.characters)
            if let entrance = node.entrance {
                TextField(text("label"),text:entranceText(node.id,\.label))
                TextField(text("source"),text:entranceText(node.id,\.source),axis:.vertical)
                TextField(text("floor"),text:entranceText(node.id,\.floor))
                TextField(text("approach"),text:entranceText(node.id,\.approach),axis:.vertical)
                TextField(text("longitude"),text:entranceText(node.id,\.longitude)).keyboardType(.numbersAndPunctuation)
                TextField(text("latitude"),text:entranceText(node.id,\.latitude)).keyboardType(.numbersAndPunctuation)
                LabeledContent(text("datum")) {
                    Menu(entrance.datum.isEmpty ? text("choose") : entrance.datum) {
                        ForEach(["WGS84","GCJ02","BD09"],id:\.self) { datum in Button(datum) { mutate(node.id, token: token) { $0.entrance?.datum = datum } } }
                    }.accessibilityLabel(text("datum"))
                }
                Menu(entrance.closed.map { $0 ? text("closed.yes") : text("closed.no") } ?? text("closed.required")) {
                    Button(text("closed.chooseYes")) { mutate(node.id, token: token) { $0.entrance?.closed = true } }
                    Button(text("closed.chooseNo")) { mutate(node.id, token: token) { $0.entrance?.closed = false } }
                }
                TextField(text("businessTime"),text:entranceText(node.id,\.businessTime),axis:.vertical)
                TextField(text("alternative"),text:entranceText(node.id,\.alternative),axis:.vertical)
                Text(text("entranceScope"))
                    .font(.footnote)
                Button(text("entrance.remove"),role:.destructive) { mutate(node.id, token: token) { $0.entrance = nil } }
            } else {
                Text(text("entrance.undeclared"))
                Button(text("entrance.add")) { mutate(node.id, token: token) { $0.entrance = .init() } }
            }
            Button(text("node.remove"),role:.destructive) { guard current, editToken == token else { return }; editor?.nodes.removeAll { $0.id == node.id }; edited = true; acknowledged = false; notice = nil; editToken = UUID() }
        }.disabled(!current)
    }
    private var ttl: Binding<String> { let token = editToken; return Binding(get:{editor?.ttl ?? ""},set:{value in guard current,editToken == token else{return};editor?.ttl=value;edited=true;acknowledged=false;notice=nil;editToken = UUID()}) }
    private func region(_ id:Int) -> Binding<String> { let token = editToken; return Binding(get:{editor?.nodes.first(where:{$0.id==id})?.region ?? ""},set:{value in mutate(id, token: token){$0.region=value}}) }
    private func entranceText(_ id:Int,_ key:WritableKeyPath<NativeStoryWalkingAuthorDraft.Entrance,String>) -> Binding<String> {
        let token = editToken
        return Binding(get:{editor?.nodes.first(where:{$0.id==id})?.entrance?[keyPath:key] ?? ""},set:{value in mutate(id, token: token){$0.entrance?[keyPath:key]=value}})
    }
    private func mutate(_ id:Int,token:UUID,_ update:(inout NativeStoryWalkingAuthorDraft.Node)->Void) {
        guard current,editToken == token,var draft=editor,let index=draft.nodes.firstIndex(where:{$0.id==id}) else{return};update(&draft.nodes[index]);editor=draft;edited=true;acknowledged=false;editToken = UUID();notice=nil
    }
    private func nodeDescription(_ id: Int) -> String {
        String(format: text("node.number"), locale: locale, Int64(id))
    }
    private func requestReturn() {
        guard phase == .active else { return }
        if current && edited { confirmingExit = true }
        else { retire(); dismiss() }
    }
    private func open() {
        guard !opened, !retired else { return }
        opened = true
        guard phase == .active,capture==nil,model.fullEdit,model.confirmation == nil,let lease = model.captureStarterLease(),let bytes = ProjectEditPendingMaterials.exactData(model.draft),let session=model.coordinator.session,let snapshot=model.coordinator.snapshot else{notice="unavailable";return}
        do { editor=try .init(draft:model.draft);capture = .init(lease: lease, bytes: bytes, incarnation:model.editorIncarnation,revision:model.draftMutationRevision,session:session,snapshot:snapshot,draft:model.draft) }
        catch { notice="unsupported" }
    }
    private func retire(){editToken = UUID();capture=nil;editor=nil;acknowledged=false;confirmingExit=false;edited=false;retired=true;notice=nil}
    private func apply(_ token: UUID) {
        guard current, editToken == token, acknowledged, let capture, let editor else { return }
        do {
            let next = try editor.applying(to: model.draft)
            guard current, editToken == token else { return }
            if ProjectEditPendingMaterials.exactData(next) == capture.bytes { retire(); dismiss(); return }
            guard model.persistLocalChange(next, lease: capture.lease) else {
                notice = "saveUnconfirmed"; return
            }
            retire(); dismiss()
        } catch { notice = "invalid" }
    }
}
