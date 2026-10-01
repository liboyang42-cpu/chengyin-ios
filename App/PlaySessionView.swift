import SwiftUI

/// Mount inside the existing NavigationStack with a stable, scope-specific reader.
/// This screen never starts a purchase, requests location or silently opens a scanner.
@MainActor
struct PlaySessionView: View {
    let reader: any PlayReading
    @State private var model: PlayViewModel
    @State private var selectedNodeID: Int?
    init(reader: any PlayReading) {
        self.reader = reader; _model = State(initialValue: PlayViewModel(reader: reader))
    }
    var body: some View {
        Group {
            if !reader.scope.isValid {
                PlayIssueView(issue: .init(APIError.invalidRequest))
            } else if !reader.isConfigured {
                PlayIssueView(issue: .init(APIError.notConfigured))
            } else if reader.identity == nil {
                PlayIssueView(issue: .init(APIError.unauthorized))
            } else if model.isLoading {
                ProgressView("play.loading").accessibilityIdentifier("play.loading")
            } else if let issue = model.visibleIssue {
                PlayIssueView(issue: issue) { Task { await model.load(keepingReceipt: true) } }
            } else if let snapshot = model.visibleSnapshot {
                overview(snapshot)
            } else {
                PlayIssueView(issue: .init(APIError.malformedResponse)) { Task { await model.load() } }
            }
        }
        .privacySensitive()
        .appNavigationTitle("play.title")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("play.refresh", systemImage: "arrow.clockwise") { Task { await model.load(keepingReceipt: true) } }
                    .disabled(model.isLoading || model.isSubmitting || reader.identity == nil || !reader.isConfigured)
                    .accessibilityIdentifier("play.refresh")
            }
        }
        .navigationDestination(item: $selectedNodeID) { nodeID in
            PlayNodeDetailView(nodeID: nodeID, model: model)
        }
        .task(id: reader.identity) { await model.load() }
        .onChange(of: reader.identity) { _, _ in selectedNodeID = nil }
    }
    private func overview(_ snapshot: PlaySnapshot) -> some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    if let name = snapshot.result.topicName, !name.isEmpty {
                        Text(verbatim: name).font(.title2.bold()).accessibilityIdentifier("play.topicName")
                    }
                    Label(LocalizedStringKey(snapshot.availability.titleKey), systemImage: statusSymbol(snapshot.availability))
                        .font(.headline).accessibilityIdentifier("play.status")
                    if let total = snapshot.result.total, let done = snapshot.displayedDoneCount, total > 0 {
                        ProgressView(value: Double(min(done, total)), total: Double(total))
                        LabeledContent("play.progress") { Text(verbatim: "\(done) / \(total)") }
                    } else { Text("play.progress.unknown").font(.subheadline).foregroundStyle(.secondary) }
                    if let description = snapshot.result.topicDescription, !description.isEmpty { Text(verbatim: description) }
                    if let note = snapshot.result.timeNote, !note.isEmpty { Text(verbatim: note).foregroundStyle(.secondary) }
                    if let expires = snapshot.result.expiresAt, !expires.isEmpty {
                        LabeledContent("play.expiresAt") { Text(verbatim: expires) }
                    }
                    if let status = snapshot.route?.status, !status.isEmpty {
                        LabeledContent("play.routeStatus") { Text(verbatim: status) }
                    }
                }.padding(.vertical, 4)
            }
            if snapshot.availability != .active && snapshot.availability != .completed {
                Section { Text(LocalizedStringKey(snapshot.availability.detailKey)).foregroundStyle(.secondary) }
            }
            if let receipt = model.visibleReceipt { Section { PlayReceiptView(receipt: receipt) } }
            if snapshot.availability != .registrationRequired {
                Section("play.nodes") {
                    if snapshot.visibleNodes.isEmpty {
                        Text(LocalizedStringKey(snapshot.result.nodes.isEmpty ? "play.empty.detail" : "play.nodes.hidden")).foregroundStyle(.secondary)
                    }
                    ForEach(snapshot.visibleNodes) { node in
                        Button { selectedNodeID = node.id } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: snapshot.isDone(node) ? "checkmark.circle.fill" : snapshot.isLocked(node) ? "lock.circle" : "circle")
                                    .font(.title3).foregroundStyle(snapshot.isDone(node) ? Color.green : Color.secondary)
                                VStack(alignment: .leading, spacing: 5) {
                                    if let name = node.name, !name.isEmpty { Text(verbatim: name).font(.headline) }
                                    else { Text("play.node.untitled").font(.headline) }
                                    if let chapterID = node.chapterID, let chapter = snapshot.result.chapters.first(where: { $0.id == chapterID }),
                                       let name = chapter.name, !name.isEmpty {
                                        Text(verbatim: name).font(.caption).foregroundStyle(.secondary)
                                    }
                                    if let hook = node.hookText, !hook.isEmpty { Text(verbatim: hook).font(.subheadline).foregroundStyle(.secondary) }
                                    Text(LocalizedStringKey(snapshot.isDone(node) ? "play.node.completed" : snapshot.isLocked(node) ? "play.node.locked" : "play.node.open"))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 4)
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                            }.padding(.vertical, 6).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityIdentifier("play.node.\(node.id)")
                    }
                }
            }
        }
        .refreshable { await model.load(keepingReceipt: true) }
        .accessibilityIdentifier("play.overview")
    }
    private func statusSymbol(_ availability: PlaySessionAvailability) -> String {
        switch availability { case .completed: return "checkmark.seal.fill"
        case .active: return "figure.walk"
        case .empty: return "map"
        default: return "lock.circle" }
    }
}

struct PlayReceiptView: View {
    let receipt: PlayAnswerReceipt
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("play.answer.accepted", systemImage: "checkmark.circle").font(.headline)
            Text("play.answer.readback").font(.footnote).foregroundStyle(.secondary)
            if let xp = receipt.xp { LabeledContent("play.xp") { Text(verbatim: String(xp)) } }
            if let score = receipt.puzzleScore { LabeledContent("play.puzzleScore") { Text(verbatim: String(score)) } }
            if receipt.completed == true { Text("play.answer.routeCompleted") }
        }.accessibilityIdentifier("play.answer.receipt")
    }
}
