import SwiftUI

@MainActor struct MerchantContentEditView: View {
    enum Kind {
        case apply(Int), registrationCreate(topicID: Int, nodeID: Int), registrationEdit(Int), chapterNode(Int), placement, npc(Int), voice(Int)
        case auditApplication(Int), auditNode(Int), station(nodeID: Int, action: MerchantStationAction)
    }
    let service: any MerchantContentServing
    let query: MerchantContentQuery
    let kind: Kind
    @StateObject private var model: MerchantContentViewModel
    @State private var text: [String: String] = [:]
    @State private var checked: [String: Bool] = [:]
    @State private var templateID = 0
    @State private var fallbackIndex = 0
    @State private var approve = true
    @State private var confirmedAddress = false
    @State private var dirty = false
    @State private var discard = false
    @Environment(\.dismiss) private var dismiss
    init(service: any MerchantContentServing, query: MerchantContentQuery, kind: Kind) {
        self.service = service; self.query = query; self.kind = kind
        _model = StateObject(wrappedValue: .init(service: service, query: query))
    }
    private var c: MerchantContentCoordinator { model.coordinator }
    var body: some View {
        Form {
            Section { MerchantContentBoundary(); MerchantContentStatus(model: model, allowsReload: !dirty) }
            if c.isCurrent, let source = c.snapshot {
                fields(source)
                Section {
                    if let command = try? command(source) {
                        Button("merchant.content.review") { model.prepare(command) }
                            .disabled(c.busy || c.locked || c.receipt != nil)
                            .accessibilityIdentifier("merchant.content.review")
                    } else { Text("merchant.content.completeFields").foregroundStyle(.secondary) }
                    Text("merchant.content.mediaBoundary").font(.footnote)
                }
            } else if c.busy { ProgressView("merchant.loading") }
        }
        .accessibilityIdentifier("merchant.content.editor")
        .appNavigationTitle(key: "merchant.content." + query.key)
        .task(id: service.scope) { text = [:]; dirty = false; await model.load(); if c.isCurrent, let s = c.snapshot { seed(s) } }
        .navigationBarBackButtonHidden(dirty)
        .toolbar { if dirty { ToolbarItem(placement: .topBarLeading) { Button("action.cancel") { discard = true }.accessibilityIdentifier("merchant.content.close") } } }
        .interactiveDismissDisabled(dirty || c.busy)
        .confirmationDialog("merchant.content.discardTitle", isPresented: $discard, titleVisibility: .visible) {
            Button("merchant.content.discard", role: .destructive) { model.invalidate(); dismiss() }
            Button("merchant.content.keepEditing", role: .cancel) { }
        }
        .sheet(item: Binding(get: { c.isCurrent ? c.review : nil }, set: { if $0 == nil { model.cancel() } })) { MerchantContentReviewView(model: model, review: $0) }
        .onChange(of: c.snapshot?.observedAt) { _, _ in if !dirty, let s = c.snapshot { seed(s) } }
        .onChange(of: service.scope) { _, _ in model.invalidate(); text = [:]; checked = [:]; dirty = false }
    }
    private func binding(_ name: String) -> Binding<String> { Binding(get: { text[name] ?? "" }, set: { text[name] = $0; dirty = true; model.cancel() }) }
    private func field(_ name: String) -> some View {
        TextField(LocalizedStringKey("merchant.content.field." + name), text: binding(name), axis: .vertical)
            .textInputAutocapitalization(.sentences).autocorrectionDisabled()
            .accessibilityIdentifier("merchant.content.field." + name)
    }
    @ViewBuilder private func fields(_ s: MerchantContentSnapshot) -> some View {
        switch kind {
        case .apply:
            Section { field("message"); Text("merchant.content.applyTwoSteps").font(.footnote) }
        case .registrationCreate, .registrationEdit:
            Section("merchant.content.registrationContent") {
                ForEach(["addressName", "address", "longitude", "latitude", "activityDesc", "picUrl", "limitNum"], id: \.self) { field($0) }
                if case .registrationCreate = kind { field("cooperateDate") }
                Text("merchant.content.registrationPreservation").font(.footnote)
            }
        case .chapterNode:
            Section { templates(s); ForEach(["name", "description", "address", "longitude", "latitude", "imgUrl", "businessTime"], id: \.self) { field($0) }; Text("merchant.content.nodeReviewWarning").font(.footnote); Text("merchant.content.xpUnavailable").font(.footnote) }
        case .placement:
            Section { templates(s); ForEach(["name", "address", "latitude", "longitude", "tags", "coverImg", "cityCode"], id: \.self) { field($0) }
                Toggle("merchant.content.confirmAddress", isOn: Binding(get: { confirmedAddress }, set: { confirmedAddress = $0; dirty = true; model.cancel() }))
                    .accessibilityIdentifier("merchant.content.confirmAddress")
                Text("merchant.content.placementWarning").font(.footnote)
            }
        case .npc:
            Section { field("name"); field("avatar"); field("greeting"); Text("merchant.content.npcBoundary").font(.footnote) }
        case .voice(let node):
            Section { field("voiceSample"); Text("merchant.content.voiceBoundary").font(.footnote)
                Button("merchant.content.resetVoice", role: .destructive) { model.prepare(.resetVoice(nodeID: node)) }.disabled(c.busy || c.locked)
            }
        case .auditApplication(let id), .auditNode(let id):
            Section { MerchantContentFields(value: s.rows.first { $0["id"].integer == id } ?? .null, names: ["merchantName", "chapterName", "name", "message", "description", "address", "status"]); Toggle("merchant.content.approve", isOn: Binding(get: { approve }, set: { approve = $0; dirty = true; model.cancel() })); field("reason"); Text("merchant.content.auditWarning").font(.footnote) }
        case .station(let node, let action):
            if let p = try? MerchantStationProjection(s.value), let station = p.station(nodeID: node) { stationFields(p, station: station, action: action) }
        }
    }
    private func templates(_ s: MerchantContentSnapshot) -> some View {
        Picker("merchant.content.template", selection: Binding(get: { templateID }, set: { templateID = $0; dirty = true; model.cancel() })) {
            Text("merchant.content.chooseTemplate").tag(0)
            ForEach(Array((s.value["templates"].array ?? []).enumerated()), id: \.offset) { _, row in
                if let id = row["id"].integer, id > 0 { Text(verbatim: row["title"].text ?? "—").tag(id) }
            }
        }.accessibilityIdentifier("merchant.content.template")
    }
    @ViewBuilder private func stationFields(_ p: MerchantStationProjection, station: MerchantContentValue, action: MerchantStationAction) -> some View {
        Section { Text(LocalizedStringKey("merchant.content." + action.rawValue)); Text(verbatim: station["nodeName"].text ?? "—") }
        switch action {
        case .accept, .resume: Section { Text("merchant.content.stationReviewWarning") }
        case .decline:
            Section { reasonPicker(["SCHEDULE_CONFLICT", "RESOURCE_UNAVAILABLE", "LOCATION_UNSUITABLE"]); field("reason") }
        case .ready:
            Section {
                field("capacity"); field("serviceStartAt"); field("serviceEndAt"); field("note")
                Text("merchant.content.civilTime").font(.footnote)
                ForEach(Array((station["preparationChecklist"].array ?? []).enumerated()), id: \.offset) { _, item in
                    if let code = item["code"].text, let label = item["label"].text {
                        Toggle(isOn: Binding(get: { checked[code] ?? false }, set: { checked[code] = $0; dirty = true; model.cancel() })) { Text(verbatim: label) }
                            .accessibilityIdentifier("merchant.content.check." + code)
                    }
                }
            }
        case .pause:
            Section {
                reasonPicker(["CAPACITY", "STAFF", "EQUIPMENT", "EMERGENCY"]); field("reason"); field("resumeEta")
                let options = p.fallbackOptions.filter { $0["sourceNodeId"].integer == station["nodeId"].integer }
                Picker("merchant.content.fallback", selection: Binding(get: { fallbackIndex }, set: { fallbackIndex = $0; dirty = true; model.cancel() })) {
                    ForEach(Array(options.enumerated()), id: \.offset) { index, option in Text(verbatim: option["nodeName"].text ?? "—").tag(index) }
                }
                if options.indices.contains(fallbackIndex), let message = options[fallbackIndex]["playerMessage"].text { Text(verbatim: message) }
                Text("merchant.content.civilTime").font(.footnote)
            }
        case .verify:
            Section { field("submissionId"); Toggle("merchant.content.approve", isOn: Binding(get: { approve }, set: { approve = $0; dirty = true; model.cancel() }))
                if !approve { reasonPicker(["ANSWER_MISMATCH", "EVIDENCE_UNCLEAR", "DUPLICATE_SUBMISSION"]) }
            }
        }
    }
    private func reasonPicker(_ values: [String]) -> some View {
        Picker("merchant.content.field.reasonCode", selection: binding("reasonCode")) {
            Text("merchant.content.chooseReason").tag("")
            ForEach(values, id: \.self) { code in Text(LocalizedStringKey("merchant.content.reason." + code)).tag(code) }
        }
    }
    private func seed(_ s: MerchantContentSnapshot) {
        var value = s.value
        switch kind {
        case .placement:
            value = s.value["profile"]
            text["latitude"] = value["locationLat"].display ?? value["latitude"].display
            text["longitude"] = value["locationLng"].display ?? value["longitude"].display
        case .chapterNode: value = s.value["nodes"].array?.first ?? .null
        case .station(let node, _):
            value = (try? MerchantStationProjection(s.value))?.station(nodeID: node) ?? .null
            for item in value["preparationChecklist"].array ?? [] { if let code = item["code"].text { checked[code] = item["checked"].flag == true } }
        default: break
        }
        for name in ["name", "avatar", "greeting", "description", "addressName", "address", "longitude", "latitude", "activityDesc", "picUrl", "limitNum", "imgUrl", "businessTime", "voiceSample", "capacity", "serviceStartAt", "serviceEndAt"] {
            if text[name] == nil { text[name] = value[name].display ?? "" }
        }
        templateID = value["templateId"].integer ?? 0; dirty = false
    }
    private func registrationDraft() -> MerchantRegistrationContentDraft {
        .init(detail: .object(text.mapValues { .string($0) }))
    }
    private func command(_ s: MerchantContentSnapshot) throws -> MerchantContentCommand {
        func value(_ key: String) -> String { text[key] ?? "" }
        let result: MerchantContentCommand
        switch kind {
        case .apply(let chapter): result = .apply(chapterID: chapter, message: value("message"))
        case .registrationCreate(let topic, let node): result = .register(topicID: topic, nodeID: node, draft: registrationDraft(), cooperateDate: value("cooperateDate"))
        case .registrationEdit(let id):
            guard let topic = s.value["topicId"].integer else { throw MerchantContentFailure.invalid }
            result = .updateRegistration(id: id, topicID: topic, draft: registrationDraft())
        case .chapterNode(let chapter):
            var d = MerchantChapterContentDraft(); d.templateID = templateID; d.name = value("name"); d.description = value("description")
            d.address = value("address"); d.longitude = value("longitude"); d.latitude = value("latitude"); d.imgUrl = value("imgUrl"); d.businessTime = value("businessTime")
            result = .submitNode(chapterID: chapter, draft: d)
        case .placement:
            var d = MerchantCityPlacementDraft(); d.templateID = templateID; d.latitude = value("latitude"); d.longitude = value("longitude")
            d.name = value("name"); d.address = value("address"); d.tags = value("tags"); d.coverImg = value("coverImg"); d.cityCode = value("cityCode"); d.addressConfirmed = confirmedAddress
            result = .place(d)
        case .npc(let node): result = .saveNPC(nodeID: node, name: value("name"), avatar: value("avatar"), greeting: value("greeting"))
        case .voice(let node): result = .enrollVoice(nodeID: node, voiceSample: value("voiceSample"))
        case .auditApplication(let id): result = .auditApplication(id: id, approve: approve, reason: value("reason"))
        case .auditNode(let node): result = .auditNode(nodeID: node, approve: approve, reason: value("reason"))
        case .station(let node, let action):
            let p = try MerchantStationProjection(s.value); guard let station = p.station(nodeID: node) else { throw MerchantContentFailure.invalid }
            var f: [String: MerchantContentValue] = [:]
            switch action {
            case .accept, .resume: break
            case .decline: f = ["reasonCode": .string(value("reasonCode")), "reason": .string(value("reason"))]
            case .ready:
                f = ["capacity": .integer(Int(value("capacity")) ?? 0), "serviceStartAt": .string(value("serviceStartAt")), "serviceEndAt": .string(value("serviceEndAt")), "note": .string(value("note")),
                     "checklist": .array((station["preparationChecklist"].array ?? []).map { .object(["code": $0["code"], "checked": .bool(checked[$0["code"].text ?? ""] == true)]) })]
            case .pause:
                let options = p.fallbackOptions.filter { $0["sourceNodeId"].integer == node }
                guard options.indices.contains(fallbackIndex) else { throw MerchantContentFailure.invalid }
                let fallback = options[fallbackIndex]
                f = ["reasonCode": .string(value("reasonCode")), "reason": .string(value("reason")), "resumeEta": .string(value("resumeEta")), "fallbackPlanCode": fallback["planCode"], "fallbackPlanVersion": fallback["planVersion"]]
            case .verify:
                f = ["submissionId": .string(value("submissionId")), "decision": .string(approve ? "APPROVE" : "REJECT")]
                if !approve { f["reasonCode"] = .string(value("reasonCode")) }
            }
            result = .station(.init(activityID: p.activityID, nodeID: node, expectedRevision: p.revision, action: action, payload: f))
        }
        try result.validate(against: s); return result
    }
}
