import SwiftUI

/// Local input only. Neither preview nor acceptance validates a submission or sends a command.
@MainActor final class MerchantGameNodeImportSession: ObservableObject, Identifiable {
    let id = UUID()
    @Published private(set) var raw = ""
    @Published private(set) var code: MerchantStationSubmissionCode?
    @Published private(set) var issue: String?
    private let current: () -> Bool
    private var retired = false
    init(current: @escaping () -> Bool) { self.current = current }
    var isCurrent: Bool { !retired && current() }
    func update(_ text: String) {
        code = nil; issue = nil
        guard isCurrent else { retire(); return }
        guard text.utf8.count <= MerchantStationSubmissionCode.maximumInputBytes else {
            raw = ""; issue = "merchant.submissionImport.oversized"; return
        }
        raw = text
    }
    func preview() {
        guard isCurrent else { retire(); return }
        defer { raw = "" }
        do { code = try MerchantStationSubmissionCode(raw); issue = nil }
        catch MerchantStationSubmissionCode.Failure.oversized { code = nil; issue = "merchant.submissionImport.oversized" }
        catch MerchantStationSubmissionCode.Failure.unsupportedLink { code = nil; issue = "merchant.submissionImport.unsupportedLink" }
        catch { code = nil; issue = "merchant.submissionImport.invalid" }
    }
    func retire() { retired = true; raw = ""; code = nil; issue = nil }
}

/// Retain the dismissed presentation until its callback finishes. A second import cannot
/// race that callback, and no identifier escapes without a second original-owner check.
@MainActor final class MerchantGameNodeImportController: ObservableObject {
    @Published private(set) var session: MerchantGameNodeImportSession?
    @Published private var presented = false
    private var pendingID: String?
    func open(current: @escaping () -> Bool) {
        guard session == nil, current() else { return }
        session = .init(current: current); pendingID = nil; presented = true
    }
    func presentationBinding() -> Binding<Bool> {
        let id = session?.id
        return Binding(get: { [weak self] in self?.session?.id == id && self?.presented == true },
                       set: { [weak self] value in
            guard !value, let id, self?.session?.id == id else { return }
            self?.presented = false
        })
    }
    func accept(_ original: MerchantGameNodeImportSession) {
        guard session === original, presented, original.isCurrent, let code = original.code else { return }
        pendingID = code.submissionID; presented = false
    }
    func cancel(_ original: MerchantGameNodeImportSession) {
        guard session === original else { return }
        invalidate()
    }
    func invalidate() {
        pendingID = nil; session?.retire(); presented = false
        // Keep session until onDismiss, so its callback cannot consume a newer import.
    }
    func finishDismissal(id: UUID?) -> String? {
        guard let id, session?.id == id else { return nil }
        let result = session?.isCurrent == true ? pendingID : nil
        session?.retire(); session = nil; pendingID = nil; presented = false
        return result
    }
}
