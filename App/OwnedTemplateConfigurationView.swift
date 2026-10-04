import SwiftUI

@MainActor struct SessionOwnedTemplateConfigurationView: View {
    @EnvironmentObject private var session: AppSession
    let id: MemberPlayTemplateID
    var body: some View {
        OwnedTemplateConfigurationView(host: session.makeOwnedTemplateConfigurationHost(), id: id)
            .id(session.templateShelfViewIdentity)
    }
}
@MainActor struct OwnedTemplateConfigurationView: View {
    @EnvironmentObject private var session: AppSession
    @State private var host: OwnedTemplateConfigurationHost
    @State private var showingStory = false
    let id: MemberPlayTemplateID
    init(host: OwnedTemplateConfigurationHost, id: MemberPlayTemplateID) { _host = State(initialValue: host); self.id = id }
    var body: some View {
        Form {
            Section { Text("templateOwnerConfig.readOnly"); Text("templateOwnerConfig.scope").font(.caption).foregroundStyle(.secondary) }
            if host.loading { ProgressView("memberTemplate.loading") }
            if let snapshot = host.snapshot, snapshot.id == id {
                Section {
                    Text(verbatim: snapshot.title.value ?? "").font(.headline).accessibilityIdentifier("templateOwnerConfig.title")
                    if snapshot.title == .unsupported { Text("templateOwnerConfig.unsupported") }
                    else if snapshot.title.value == nil { Text("templateOwnerConfig.missing") }
                    LabeledContent("templateAuthor.shelf.identity", value: String(snapshot.id.rawValue))
                    switch snapshot.provenance {
                    case .value(let value):
                        LabeledContent("templateAuthor.original", value: String(value))
                        if value == 0 { Text("templateOwnerConfig.noProvenance") }
                    case .missing, .null: Text("templateOwnerConfig.noProvenance")
                    case .unsupported: Text("templateOwnerConfig.unsupported")
                    }
                }
                if let label = snapshot.specializedMethodLabel {
                    Section("templateAuthor.finish") {
                        Text(LocalizedStringKey(label)).accessibilityIdentifier("templateOwnerSensor.method")
                        if snapshot.validationMethod == 6 { Text("templateOwnerSensor.preferenceScope") }
                    }
                }
                if let sensor = snapshot.sensor { OwnedTemplateSensorConfigurationFields(configuration: sensor) }
                if let method = snapshot.supportedQAMethod {
                    Section("templateAuthor.finish") {
                        TemplateAuthoringQAFields(method: method,
                            field: { .constant(snapshot.field($0).value ?? "") }, readOnly: true,
                            annotation: { key in
                                switch snapshot.field(key) {
                                case .missing, .null: return "templateOwnerConfig.missing"
                                case .unsupported: return "templateOwnerConfig.unsupported"
                                case .value: return nil
                                }
                            })
                    }
                } else if snapshot.specializedMethodLabel == nil { Section { Text("templateOwnerConfig.unsupportedMethod") } }
                Section("templateAuthor.preference.title") {
                    if let raw = snapshot.preferenceJson.value { TemplatePreferencePreviewView(raw: raw) }
                    else { Text(LocalizedStringKey(snapshot.preferenceJson == .unsupported ? "templateOwnerConfig.unsupported" : "templateOwnerConfig.missing")) }
                }
                Section("templateAuthor.field.medalStyle") {
                    if let value = snapshot.medalStyle.value { Text(verbatim: value) }
                    else { Text(LocalizedStringKey(snapshot.medalStyle == .unsupported ? "templateOwnerConfig.unsupported" : "templateOwnerConfig.missing")) }
                }
                Section("templateAuthor.story") {
                    if let text = snapshot.storyText.value { Text(verbatim: text) }
                    Button("templateAuthor.storyTimeline") { showingStory = true }
                        .accessibilityIdentifier("templateOwnerConfig.story")
                }
                if !snapshot.unsupportedFields.isEmpty {
                    Section { Text("templateOwnerConfig.partial").accessibilityIdentifier("templateOwnerConfig.partial") }
                }
            } else if !host.loading {
                Section { Text(LocalizedStringKey(host.available ? "templateOwnerConfig.failed" : "templateAuthor.unavailable")) }
            }
            Section { Button("action.retry") { Task { await host.load(id: id) } }.disabled(host.loading).accessibilityIdentifier("templateOwnerConfig.reload") }
        }.navigationTitle("templateOwnerConfig.title")
            .privacySensitive().accessibilityIdentifier("templateOwnerConfig.form")
            .task(id: id) { showingStory = false; if host.snapshot?.id != id { await host.load(id: id) } }
            .navigationDestination(isPresented: $showingStory) { OwnedTemplateStoryConfigurationView(host: host, expectedID: id) }
            .onChange(of: session.templateShelfViewIdentity) { _, _ in host.clear(); showingStory = false }
            .onDisappear { if !showingStory || !host.available { host.clear() } }
    }
}
@MainActor struct OwnedTemplateStoryConfigurationView: View {
    @EnvironmentObject private var session: AppSession
    let host: OwnedTemplateConfigurationHost
    let expectedID: MemberPlayTemplateID
    var body: some View {
        Form {
            Section { Text("templateOwnerConfig.readOnly") }
            if let snapshot = host.snapshot, snapshot.id == expectedID {
                ForEach(snapshot.story) { beat in
                    Section {
                        TemplateStoryBeatFields(tag: .constant(beat.tag.value ?? ""), text: .constant(beat.text.value ?? ""), images: .constant(beat.images.joined(separator: "\n")))
                            .disabled(true)
                        if beat.text == .missing || beat.text == .null || beat.tag == .missing || beat.tag == .null { Text("templateOwnerConfig.missing") }
                        if beat.text == .unsupported || beat.tag == .unsupported { Text("templateOwnerConfig.unsupported") }
                        if !beat.unsupportedFields.isEmpty { Text("templateOwnerConfig.partial") }
                    }
                }
                if snapshot.story.isEmpty { Text("templateOwnerConfig.noStory") }
            } else { Text("templateAuthor.unavailable") }
        }.navigationTitle("templateAuthor.storyTimeline")
            .privacySensitive().accessibilityIdentifier("templateOwnerConfig.storyForm")
            .onChange(of: session.templateShelfViewIdentity) { _, _ in host.clear() }
            .onDisappear { if !host.available { host.clear() } }
    }
}
