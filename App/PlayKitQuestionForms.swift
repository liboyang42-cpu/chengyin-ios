import SwiftUI

extension PlayKitScreen {
    @ViewBuilder var qaForm: some View {
        artwork(raw["imageUrl"].text)
        PlatformAudioHost(rawURL: raw["audioUrl"].text, scope: mediaScope, makeModel: makeAudio)
        let mode = (raw["mode"].text ?? "TYPE").uppercased()
        if mode == "SHOT" {
            if let note = raw["shotNote"].text { Text(verbatim: note) }
            photoInput { url in prepare("SUBMIT_QA", ["imageUrl": .string(url)]) }
        } else if mode == "PICK" {
            let multi = raw["multi"].bool == true
            if multi { Text("playkit.qa.multiHint").font(.footnote) }
            ForEach(projection.options) { option in
                Button { toggle(option.id, multi: multi) } label: {
                    HStack { Image(systemName: selected.contains(option.id) ? "checkmark.circle.fill" : "circle"); Text(verbatim: option.label); Spacer() }
                }.buttonStyle(.bordered).disabled(!enabled)
                    .accessibilityAddTraits(selected.contains(option.id) ? .isSelected : [])
            }
            submitButton("SUBMIT_QA", payload: multi ? ["optionIds": .array(selected.sorted().map(PlayWireValue.string))] : ["optionId": .string(selected.first ?? "")], valid: !selected.isEmpty)
        } else {
            TextField("playkit.qa.answer", text: textBinding(), axis: .vertical).textFieldStyle(.roundedBorder).disabled(!enabled)
            submitButton("SUBMIT_QA", payload: ["input": .string(text)], valid: !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        if let answer = raw["answerId"].text, !answer.isEmpty, projection.complete {
            LabeledContent("playkit.qa.revealedAnswer") { Text(verbatim: projection.options.first { $0.id == answer }?.label ?? answer) }
        }
        attempts
    }
    @ViewBuilder var branchForm: some View {
        if let title = raw["currentStep"]["title"].text { Text(verbatim: title).font(.title2.bold()) }
        if let body = raw["currentStep"]["body"].text { Text(verbatim: body) }
        ForEach(projection.options) { option in
            Button { prepare("CHOOSE", ["optionId": .string(option.id)]) } label: { Text(verbatim: option.label).frame(maxWidth: .infinity, alignment: .leading) }
                .buttonStyle(.bordered).disabled(!enabled)
        }
        if projection.complete { Text("playkit.branch.ended") }
    }
    @ViewBuilder var estimateForm: some View {
        if let lo = raw["min"].double, let hi = raw["max"].double, lo.isFinite, hi.isFinite, hi >= lo {
            LabeledContent("playkit.estimate.range") { Text(verbatim: "\(lo.formatted()) – \(hi.formatted()) \(raw["unit"].text ?? "")") }
            TextField("playkit.estimate.value", text: textBinding(limit: 32)).keyboardType(.decimalPad).textFieldStyle(.roundedBorder).disabled(!enabled)
            let value = Double(text.replacingOccurrences(of: ",", with: "."))
            submitButton("SUBMIT_ESTIMATE", payload: ["value": .number(value ?? 0)], valid: value.map { $0.isFinite && (lo...hi).contains($0) } ?? false)
        } else { Text("playkit.configurationInvalid") }
        attempts
    }
    @ViewBuilder var pricePairForm: some View {
        ForEach(projection.options) { option in
            VStack(alignment: .leading, spacing: 12) {
                artwork(option.raw["imageUrl"].text)
                Text(verbatim: option.label).font(.headline)
                if let note = option.raw["note"].text { Text(verbatim: note) }
                Button { toggle(option.id, multi: false) } label: {
                    Label("playkit.select", systemImage: selected.contains(option.id) ? "checkmark.circle.fill" : "circle")
                }.disabled(!enabled)
            }.padding().background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
        submitButton("SUBMIT_PRICE_PAIR", payload: ["pickId": .string(selected.first ?? "")], valid: !selected.isEmpty)
        attempts
    }
    @ViewBuilder var hiddenObjectForm: some View {
        let found = Set((raw["foundIds"].array ?? []).compactMap(\.text))
        ForEach(PlayKitOption.read(raw["targets"])) { target in
            Label { Text(verbatim: target.label) } icon: { Image(systemName: found.contains(target.id) || target.raw["found"].bool == true ? "checkmark.circle.fill" : "circle") }
        }
        if let url = QuestifyCardArtwork.safeURL(raw["imageUrl"].text), let host = url.host, approvedArtworkHosts.contains(host) {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFit().overlay {
                        // The overlay follows the fitted image's actual rectangle, not its outer container.
                        GeometryReader { geometry in
                            Color.clear.contentShape(Rectangle())
                                .gesture(SpatialTapGesture().onEnded { event in
                                    guard enabled, let point = PlayKitInputContract.imagePoint(x: Double(event.location.x), y: Double(event.location.y), viewWidth: Double(geometry.size.width), viewHeight: Double(geometry.size.height), imageWidth: Double(geometry.size.width), imageHeight: Double(geometry.size.height)) else { return }
                                    prepare("SUBMIT_HIDDEN_OBJECT", ["x": .number(point.0), "y": .number(point.1)])
                                })
                        }
                    }.accessibilityLabel(Text("playkit.hidden.scene"))
                        .accessibilityHint(Text("playkit.hidden.hint"))
                        .accessibilityAction(named: Text("playkit.hidden.center")) {
                            if enabled { prepare("SUBMIT_HIDDEN_OBJECT", ["x": .number(0.5), "y": .number(0.5)]) }
                        }
                } else if phase.error != nil { Label("playkit.imageUnavailable", systemImage: "photo.badge.exclamationmark") }
                else { ProgressView("playkit.imageLoading") }
            }
        } else { Label("playkit.imageGated", systemImage: "photo") }
        Text("playkit.hidden.boundary").font(.footnote)
        attempts
    }
    @ViewBuilder var predictForm: some View {
        if let mine = raw["myOptionKey"].text, !mine.isEmpty {
            LabeledContent("playkit.predict.mine") { Text(verbatim: projection.options.first { $0.id == mine }?.label ?? mine) }
        } else {
            ForEach(projection.options) { option in
                Button { toggle(option.id, multi: false) } label: {
                    HStack { Image(systemName: selected.contains(option.id) ? "checkmark.circle.fill" : "circle"); Text(verbatim: option.label) }
                }.buttonStyle(.bordered).disabled(!enabled)
            }
            submitButton("SUBMIT_PREDICT", payload: ["optionKey": .string(selected.first ?? "")], valid: !selected.isEmpty)
        }
        if let status = raw["settleStatus"].integer {
            if status == 2 { Text("playkit.predict.voided") }
            else if status == 1 {
                Text(raw["won"].bool == true ? "playkit.predict.won" : "playkit.predict.lost")
                let answer = raw["settledOption"].text ?? ""
                LabeledContent("playkit.predict.answer") { Text(verbatim: projection.options.first { $0.id == answer }?.label ?? answer) }
            } else { Text("playkit.predict.wait") }
        }
        if let days = raw["revealDays"].integer, days >= 0 { LabeledContent("playkit.predict.revealDays") { Text(verbatim: String(days)) } }
        if let hour = raw["revealHour"].integer, (0...23).contains(hour) { LabeledContent("playkit.predict.revealHour") { Text(verbatim: String(hour)) } }
    }
    @ViewBuilder var attempts: some View {
        if let count = raw["attempts"].integer ?? raw["tries"].integer { LabeledContent("playkit.attempts") { Text(verbatim: String(count)) } }
        if let cap = raw["maxTries"].integer ?? raw["maxAttempts"].integer, cap > 0 { LabeledContent("playkit.attemptLimit") { Text(verbatim: String(cap)) } }
    }
    private func toggle(_ id: String, multi: Bool) {
        if multi { if selected.contains(id) { selected.remove(id) } else { selected.insert(id) } }
        else { selected = [id] }
        dirty = true
    }
}
