import SwiftUI

extension PlayKitScreen {
    var reasoningForm: some View {
        PlayKitReasoningForm(kind: kind, segment: raw, enabled: enabled,
            showResult: reasoningFeedback.showsResult(for: projection),
            onDirty: { reasoningFeedback.markEdited(projection); dirty = true }, requestReview: prepare)
            // Scope changes discard the draft; ordinary backgrounding preserves it.
            .id(lifetime)
    }
}

@MainActor struct PlayKitReasoningForm: View {
    let kind: PlayKitScreenKind; let segment: PlayWireValue; let enabled: Bool
    var showResult = true
    let onDirty: () -> Void; let requestReview: PlayKitReviewRequest
    @State private var order: [String] = []
    @State private var placement: [String: String] = [:]
    private var items: [PlayKitOption] { PlayKitOption.read(segment["items"]) }
    private var left: [PlayKitOption] { PlayKitOption.read(segment["left"]) }
    private var right: [PlayKitOption] { PlayKitOption.read(segment["right"]) }
    private var bins: [PlayKitOption] { PlayKitOption.read(segment["bins"]) }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if kind == .sort { sortRows }
            else if kind == .match { matchRows }
            else { classifyRows }
            if let attempts = segment["attempts"].integer, attempts > 0 {
                LabeledContent("playkit.attempts") { Text(verbatim: String(attempts)) }
                if showResult, let resultKey = PlayKitScreenProjection(kind: kind, segment: segment).reasoningResultKey {
                    Text(LocalizedStringKey(resultKey)).accessibilityIdentifier("playkit.reasoning.result")
                }
            }
            if let cap = segment["maxAttempts"].integer, cap > 0 { LabeledContent("playkit.attemptLimit") { Text(verbatim: String(cap)) } }
            Text("playkit.reasoning.serverOnly").font(.footnote)
            Button("playkit.review") { requestReview(action, payload, {}) }.buttonStyle(.borderedProminent).disabled(!enabled || !valid)
        }.onAppear { if order.isEmpty { order = items.map(\.id) } }
            .onChange(of: items.map(\.id)) { _, ids in order = ids; placement = [:] }
            .onChange(of: left.map(\.id)) { _, _ in placement = [:] }
            .onChange(of: right.map(\.id)) { _, _ in placement = [:] }
            .onChange(of: bins.map(\.id)) { _, _ in placement = [:] }
    }
    private var action: String { kind == .sort ? "SUBMIT_SORT" : kind == .match ? "SUBMIT_MATCH" : "SUBMIT_CLASSIFY" }
    private var payload: [String: PlayWireValue] {
        if kind == .sort { return ["order": .array(order.map(PlayWireValue.string))] }
        if kind == .match { return ["pairs": .array(left.compactMap { item in placement[item.id].map { .array([.string(item.id), .string($0)]) } })] }
        return ["placement": .object(placement.mapValues(PlayWireValue.string))]
    }
    private var valid: Bool { (try? PlayKitInputContract.validate(kind: kind.rawValue, action: action, payload: payload, segment: segment)) != nil }
    @ViewBuilder private var sortRows: some View {
        Text("playkit.sort.instructions").font(.footnote)
        ForEach(Array(order.enumerated()), id: \.element) { index, id in
            HStack {
                Text(verbatim: String(index + 1)).monospacedDigit()
                Text(verbatim: items.first { $0.id == id }?.label ?? id).frame(maxWidth: .infinity, alignment: .leading)
                Button { move(index, -1) } label: { Image(systemName: "arrow.up") }.accessibilityLabel(Text("playkit.sort.up")).disabled(!enabled || index == 0)
                Button { move(index, 1) } label: { Image(systemName: "arrow.down") }.accessibilityLabel(Text("playkit.sort.down")).disabled(!enabled || index == order.count - 1)
            }.padding().background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                .accessibilityElement(children: .contain)
                .accessibilityAction(named: Text("playkit.sort.up")) { move(index, -1) }
                .accessibilityAction(named: Text("playkit.sort.down")) { move(index, 1) }
        }
    }
    @ViewBuilder private var matchRows: some View {
        Text("playkit.match.instructions").font(.footnote)
        ForEach(left) { item in
            Picker(selection: Binding(get: { placement[item.id] ?? "" }, set: { value in
                guard enabled, value != (placement[item.id] ?? "") else { return }
                if value.isEmpty { placement.removeValue(forKey: item.id) }
                else {
                    // One right item can be paired once; reassignment removes its old pair.
                    placement = placement.filter { $0.key == item.id || $0.value != value }; placement[item.id] = value
                }
                onDirty()
            })) {
                Text("playkit.choose").tag("")
                ForEach(right) { option in Text(verbatim: option.label).tag(option.id) }
            } label: { Text(verbatim: item.label) }.pickerStyle(.menu).disabled(!enabled)
        }
    }
    @ViewBuilder private var classifyRows: some View {
        Text("playkit.classify.instructions").font(.footnote)
        ForEach(items) { item in
            Picker(selection: Binding(get: { placement[item.id] ?? "" }, set: { value in
                guard enabled, value != (placement[item.id] ?? "") else { return }
                if value.isEmpty { placement.removeValue(forKey: item.id) } else { placement[item.id] = value }; onDirty()
            })) {
                Text("playkit.choose").tag("")
                ForEach(bins) { bin in Text(verbatim: bin.label).tag(bin.id) }
            } label: { Text(verbatim: item.label) }.pickerStyle(.menu).disabled(!enabled)
        }
        LabeledContent("playkit.classify.remaining") { Text(verbatim: String(max(0, items.count - placement.count))) }
    }
    private func move(_ index: Int, _ delta: Int) {
        let destination = index + delta
        guard enabled, index != destination, order.indices.contains(index), order.indices.contains(destination) else { return }
        let value = order.remove(at: index); order.insert(value, at: destination); onDirty()
    }
}
