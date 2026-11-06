import SwiftUI

@MainActor struct NativeChannelReportSheet: View {
    @Environment(\.themeDomain) private var domain
    let owner: NativeChannelReportFlow
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Group {
                if owner.isCurrent {
                    Form {
                        switch owner.state {
                        case .reviewing:
                            Section {
                                Picker(selection: Binding(get: { owner.selectedReason }, set: { owner.select(reason: $0, note: owner.note) })) {
                                    Text("d7.channelReport.choose").tag(Optional<NativeChannelReportReason>.none)
                                    ForEach(NativeChannelReportReason.allCases) { reason in
                                        Text(NativeChannelReportPresentation.reasonKey(reason)).tag(Optional(reason))
                                    }
                                } label: { Text("d7.channelReport.reason") }
                                TextField("d7.channelReport.note", text: Binding(get: { owner.note }, set: { owner.select(reason: owner.selectedReason, note: $0) }), axis: .vertical).lineLimit(3...8)
                                if owner.note.utf16.count > 500 {
                                    Text("d7.channelReport.noteTooLong").font(.footnote).foregroundStyle(.red)
                                }
                            }
                            Section {
                                Button { Task { await owner.submit() } } label: { Text("d7.channelReport.submit").frame(maxWidth: .infinity) }
                                    .nativeChannelFlowAction()
                                    .disabled(!owner.canSubmit || owner.selectedReason == nil || owner.note.utf16.count > 500)
                            }
                        case .submitting, .reading: ProgressView().frame(maxWidth: .infinity)
                        case .unknown:
                            Section {
                                NativeChannelFlowNotice(title: Text("d7.channelReport.unknown"), symbol: "clock.arrow.circlepath")
                                if let reason = owner.selectedReason {
                                    LabeledContent { Text(NativeChannelReportPresentation.reasonKey(reason)) } label: { Text("d7.channelReport.reason") }
                                }
                                Button("d7.channelReport.check") { Task { await owner.recover() } }.disabled(!owner.canRecover)
                                Button("d7.channelReport.retry") { Task { await owner.submit() } }.disabled(!owner.canSubmit)
                            }
                        case .acknowledged(_, let status):
                            Section {
                                Label("d7.channelReport.submitted", systemImage: "checkmark.circle")
                                LabeledContent { NativeChannelReportPresentation.status(status) } label: { Text("d7.channelReport.status") }
                            }
                        case .unavailable:
                            NativeChannelFlowNotice(title: Text("d7.channelReport.unavailable"), symbol: "lock.shield")
                        case .idle:
                            Text("d7.channelReport.idle")
                        }
                    }
                    .formStyle(.grouped)
                } else {
                    ContentUnavailableView { Label("d7.channelReport.unavailable", systemImage: "lock.shield") }
                }
            }
            .nativeChannelFlowPage()
            .navigationTitle(Text("d7.channelReport.title"))
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("action.close") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

/// Display only. Server reason and status values are never derived from this copy.
@MainActor enum NativeChannelReportPresentation {
    static func reasonKey(_ reason: NativeChannelReportReason) -> LocalizedStringKey {
        switch reason {
        case .dangerous: return "d7.channelReport.reason.dangerous"
        case .minorSafety: return "d7.channelReport.reason.minorSafety"
        case .selfHarm: return "d7.channelReport.reason.selfHarm"
        case .sexualContent: return "d7.channelReport.reason.sexualContent"
        case .harassment: return "d7.channelReport.reason.harassment"
        case .hate: return "d7.channelReport.reason.hate"
        case .fraud: return "d7.channelReport.reason.fraud"
        case .impersonation: return "d7.channelReport.reason.impersonation"
        case .falseInformation: return "d7.channelReport.reason.falseInformation"
        case .spam: return "d7.channelReport.reason.spam"
        case .privacy: return "d7.channelReport.reason.privacy"
        case .intellectualProperty: return "d7.channelReport.reason.intellectualProperty"
        case .other: return "d7.channelReport.reason.other"
        }
    }
    /// Known server statuses read from the report table; anything else shows "—".
    @ViewBuilder static func status(_ status: String) -> some View {
        if ["ACCEPTED", "DUPLICATE", "PENDING", "REJECTED"].contains(status) {
            Text(LocalizedStringKey("status." + status), tableName: "NativeChannelReport")
        } else {
            Text(verbatim: "—")
        }
    }
}
