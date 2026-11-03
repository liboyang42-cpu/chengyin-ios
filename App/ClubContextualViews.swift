import SwiftUI

private struct ClubOpsTimeFactoryKey: EnvironmentKey {
    static let defaultValue: ((Int) -> ClubOpsTimeCoordinator?)? = nil
}
extension EnvironmentValues {
    var clubOpsTimeFactory: ((Int) -> ClubOpsTimeCoordinator?)? {
        get { self[ClubOpsTimeFactoryKey.self] }
        set { self[ClubOpsTimeFactoryKey.self] = newValue }
    }
}
struct ClubOperatingRulesView: View {
    private let sections: [(String, [String])] = [
        ("leaveClub", ["owner", "membership", "chat"]),
        ("leaveTeam", ["last", "captain", "member"]),
        ("refund", ["redeemed", "deadline", "window", "missing"]),
        ("pause", ["reason", "backup", "blocked", "scope", "fallback", "resume"]),
        ("cancel", ["whole"])]
    var body: some View {
        List {
            Text("context.rules.notice").clubStatus("info.circle")
            ForEach(sections, id: \.0) { section in
                Section(LocalizedStringKey("context.rules." + section.0)) {
                    ForEach(section.1, id: \.self) { row in
                        VStack(alignment: .leading, spacing: Theme.Space.s2) {
                            Text(LocalizedStringKey("context.rules." + section.0 + "." + row + ".title")).font(.headline)
                            Text(LocalizedStringKey("context.rules." + section.0 + "." + row + ".body"))
                        }.fixedSize(horizontal: false, vertical: true).padding(.vertical, Theme.Space.s2)
                    }
                }
            }
        }.clubPageSurface().navigationTitle("context.rules.title").accessibilityIdentifier("club.context.rules")
    }
}

@MainActor struct ClubOpsTimeView: View {
    @Environment(\.dismiss) private var dismiss
    let activityID: Int
    let original: String
    let owner: ClubOpsTimeCoordinator?
    let onReadback: () -> Void
    @State private var date: Date
    @State private var review: ClubOpsTimeRequest?
    @State private var captured: ClubOpsTimeSession?
    @State private var busy = false
    @State private var revision = 0
    @State private var serverDate: String?
    @State private var readFailed = false
    init(activityID: Int, original: String, owner: ClubOpsTimeCoordinator?, onReadback: @escaping () -> Void) {
        self.activityID = activityID; self.original = original; self.owner = owner; self.onReadback = onReadback
        _date = State(initialValue: ClubOpsTimeRequest.date(original) ?? Date())
    }
    private var state: ClubOpsTimeState { let _ = revision; return owner?.state ?? .idle }
    var body: some View {
        Form {
            Section {
                Text("context.ops.policy")
                Text("context.ops.timezone").font(.caption)
                DatePicker("context.ops.time", selection: $date, displayedComponents: [.date, .hourAndMinute])
                    .environment(\.timeZone, TimeZone(identifier: "Asia/Shanghai")!)
                    .disabled(busy || state == .unknown)
                if let serverDate { LabeledContent("context.ops.serverTime", value: serverDate) }
            }
            if owner?.service.isConfigured != true { Text("context.ops.disabled") }
            if state == .unknown { Text("context.ops.unknown").clubStatus("clock", emphasized: true) }
            if state == .acknowledged { Text("context.ops.acknowledged") }
            if state == .rejected { Text("context.ops.rejected").clubStatus("exclamationmark.circle") }
            if readFailed { Text("context.ops.readFailed").clubStatus("arrow.clockwise") }
            if busy { ProgressView() }
            Button {
                review = try? ClubOpsTimeRequest(activityID: activityID, startDate: ClubOpsTimeRequest.submissionTime(date))
                captured = owner?.service.session
            } label: { ClubControlLabel("context.review.preview") }.disabled(busy || state == .unknown || ClubOpsTimeRequest.date(original) == nil)
            if owner?.service.isConfigured == true {
                Button { Task { await readback() } } label: { ClubControlLabel("context.ops.readback") }.disabled(busy)
            }
        }.clubPageSurface().navigationTitle("context.ops.title")
            .confirmationDialog("context.ops.confirm", isPresented: Binding(get: { review != nil }, set: { if !$0 { review = nil; captured = nil } })) {
                Button("context.ops.save") { Task { await save() } }.disabled(owner?.canSave != true)
                Button("action.cancel", role: .cancel) { review = nil; captured = nil }
            } message: { if let review { Text(verbatim: review.startDate) } }
            .onChange(of: owner?.service.session) { _, _ in review = nil; captured = nil; serverDate = nil; revision += 1 }
    }
    private func save() async {
        guard let owner, let review, let captured, owner.service.session == captured else { return }
        busy = true; await owner.save(review, expected: captured); busy = false; self.review = nil; revision += 1
        guard owner.service.session == captured else { return }
        if state == .acknowledged || state == .unknown { await readback(); onReadback() }
    }
    private func readback() async {
        guard let owner, let session = owner.service.session else { return }
        busy = true; readFailed = false
        defer { busy = false }
        do {
            let value = try await owner.service.read(activityID: activityID, session: session)
            guard owner.service.session == session, !Task.isCancelled else { return }; serverDate = value
        } catch { if owner.service.session == session { readFailed = true } }
    }
}
