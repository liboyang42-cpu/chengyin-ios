import SwiftUI

@MainActor final class ProfileNicknameAvailabilityModel: ObservableObject {
    let flow: ProfileNicknameAvailabilityFlow
    @Published private(set) var revision: UInt64=0
    @Published private(set) var visible=false
    init(flow: ProfileNicknameAvailabilityFlow) { self.flow=flow }
    func appear() { visible=true }
    func leave() { visible=false;flow.leave();revision &+= 1 }
    func refresh() { revision &+= 1 }
    func load(_ input:String,original:String) async {
        guard visible else { return };flow.activate();flow.setInput(input,original:original);refresh();await flow.check();refresh()
    }
}

/// Nil authorization adds no status or restrictions to the original editor.
/// A chosen candidate changes only this sheet's temporary text; existing apply/save is untouched.
@MainActor struct ProfileNicknameSheetSection: View {
    let edit:ProfileTextFieldEdit
    @Binding var text:String
    let reader:(any ProfileNicknameAvailabilityReading)?
    @StateObject private var model:ProfileNicknameAvailabilityModel
    @Environment(\.scenePhase) private var scenePhase
    private struct Key:Hashable { let input:[UInt8];let source:UUID?;let active:Bool }
    init(edit:ProfileTextFieldEdit,text:Binding<String>,reader:(any ProfileNicknameAvailabilityReading)?) {
        self.edit=edit;_text=text;self.reader=reader
        _model=StateObject(wrappedValue:.init(flow:.init(reader:reader,expectedIdentity:edit.identity,expectedViewerRevision:edit.viewerRevision)))
    }
    private var active:Bool { model.visible && scenePhase == .active }
    private var key:Key { .init(input:Array(text.utf8),source:reader?.sourceRevision,active:active) }
    var body:some View {
        let _=model.revision
        let action=model.flow.actionID
        VStack(alignment:.leading,spacing:10) {
            if active,reader?.isConfigured == true,model.flow.matchesInput(text) {
                if let message=model.flow.state.message { Text(LocalizedStringKey(message),tableName:"ProfileNicknameRead").font(.footnote).foregroundStyle(.secondary).accessibilityIdentifier("profile.nickname.availability") }
                if model.flow.state == .unavailable,let action {
                    Button { Task { guard active,model.flow.matchesInput(text) else { return };await model.flow.retryCheck(action:action);model.refresh() } } label: { Text("nickname.read.retry",tableName:"ProfileNicknameRead") }.accessibilityIdentifier("profile.nickname.retryCheck")
                }
                ForEach(Array(model.flow.candidates.enumerated()),id:\.offset) { _,nickname in
                    Button { guard active,model.flow.matchesInput(text),let action,let value=model.flow.select(nickname,action:action) else { return };text=value;model.refresh() } label:{ Text(verbatim:nickname) }
                        .disabled(model.flow.isSuggesting).accessibilityIdentifier("profile.nickname.suggestion")
                }
                if let message=model.flow.suggestionsMessage { Text(LocalizedStringKey(message),tableName:"ProfileNicknameRead").font(.footnote) }
                if model.flow.state == .taken,let action {
                    Button { Task { guard active,model.flow.matchesInput(text) else { return };await model.flow.loadSuggestions(action:action);model.refresh() } } label: { Text("nickname.read.more",tableName:"ProfileNicknameRead") }.disabled(!model.flow.canSuggest).accessibilityIdentifier("profile.nickname.more")
                }
                if model.flow.isSuggesting { ProgressView { Text("nickname.read.suggesting",tableName:"ProfileNicknameRead") } }
                Text("nickname.read.notReserved",tableName:"ProfileNicknameRead").font(.caption).foregroundStyle(.secondary)
            }
        }
        .privacySensitive()
        .onAppear { model.appear() }
        .onDisappear { model.leave() }
        .onChange(of:scenePhase) { _,phase in if phase != .active { model.flow.leave();model.refresh() } }
        .task(id:key) {
            model.flow.leave();model.refresh()
            guard active,reader?.isConfigured == true else { return }
            await model.load(text,original:edit.snapshot.nickname)
        }
    }
}
