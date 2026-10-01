import SwiftUI

/// Reader must publish account/epoch changes. Stored content is also identity checked in
/// body, so a previous account's rows are hidden before the replacement task starts.
@MainActor
struct ClubReadScreen<Reader: ClubReading & ObservableObject, Value, Content: View>: View {
    @ObservedObject var reader: Reader
    let accessibilityPrefix: String
    let requiresSignIn: Bool
    let onSignIn: (() -> Void)?
    let load: () async throws -> Value
    let content: (Value) -> Content
    @State private var value: Value?
    @State private var loadedIdentity: ClubReadIdentity?
    @State private var issue: ClubLoadIssue?
    @State private var issueIdentity: ClubReadIdentity?
    @State private var isLoading = false
    @State private var generation: UInt64 = 0

    init(reader: Reader, accessibilityPrefix: String, requiresSignIn: Bool = false,
         onSignIn: (() -> Void)? = nil, load: @escaping () async throws -> Value,
         @ViewBuilder content: @escaping (Value) -> Content) {
        self.reader = reader; self.accessibilityPrefix = accessibilityPrefix
        self.requiresSignIn = requiresSignIn; self.onSignIn = onSignIn
        self.load = load; self.content = content
    }
    var body: some View {
        Group {
            if !reader.isClubConfigured {
                ContentUnavailableView("club.unavailable", systemImage: "network.slash", description: Text("auth.notConfigured"))
            } else if requiresSignIn && !reader.clubIdentity.isSignedIn {
                issueView(ClubLoadIssue(ClubReadFailure.unauthorized(message: nil)))
            } else if issueIdentity == reader.clubIdentity, let issue {
                issueView(issue)
            } else if loadedIdentity == reader.clubIdentity, let value {
                content(value)
                    .overlay(alignment: .top) {
                        if isLoading { ProgressView().padding(8).background(.regularMaterial, in: Capsule()) }
                    }
            } else {
                ProgressView("club.loading").accessibilityIdentifier(accessibilityPrefix + ".loading")
            }
        }
        .refreshable { await reload() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("club.refresh", systemImage: "arrow.clockwise") { Task { await reload() } }
                    .disabled(isLoading || !reader.isClubConfigured || (requiresSignIn && !reader.clubIdentity.isSignedIn))
                    .accessibilityIdentifier(accessibilityPrefix + ".refresh")
            }
        }
        .task(id: reader.clubIdentity) { await reload() }
        .onDisappear {
            // Invalidate outstanding work without removing NavigationLink source rows on push.
            generation &+= 1
            isLoading = false
        }
    }
    private func issueView(_ issue: ClubLoadIssue) -> some View {
        ContentUnavailableView {
            Label {
                Text(LocalizedStringKey(issue.titleKey)).accessibilityIdentifier(accessibilityPrefix + ".error")
            } icon: { Image(systemName: issue.needsSignIn ? "person.crop.circle.badge.exclamationmark" : "exclamationmark.circle") }
        } description: {
            if let message = issue.message { Text(verbatim: message) }
            else { Text(LocalizedStringKey(issue.hintKey)) }
        } actions: {
            if issue.needsSignIn, let onSignIn {
                Button("club.signIn", action: onSignIn).accessibilityIdentifier(accessibilityPrefix + ".signIn")
            } else if issue.canRetry {
                Button("action.retry") { Task { await reload() } }.accessibilityIdentifier(accessibilityPrefix + ".retry")
            }
        }
    }
    private func reload() async {
        generation &+= 1
        let request = generation, identity = reader.clubIdentity
        if loadedIdentity != identity { value = nil; loadedIdentity = nil }
        issue = nil; issueIdentity = nil
        guard reader.isClubConfigured, !requiresSignIn || identity.isSignedIn else { isLoading = false; return }
        isLoading = true
        defer { if request == generation { isLoading = false } }
        do {
            let result = try await load()
            guard !Task.isCancelled, request == generation, reader.clubIdentity == identity else { return }
            value = result; loadedIdentity = identity
        } catch is CancellationError { }
        catch {
            guard !Task.isCancelled, request == generation, reader.clubIdentity == identity else { return }
            value = nil; loadedIdentity = nil
            issue = ClubLoadIssue(error); issueIdentity = identity
        }
    }
}

private struct ClubLoadIssue {
    let titleKey: String
    let hintKey: String
    let message: String?
    let needsSignIn: Bool
    let canRetry: Bool
    init(_ error: Error) {
        let failure = error as? ClubReadFailure
        message = failure?.message.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        needsSignIn = failure?.isUnauthorized == true || error as? APIError == .unauthorized
        canRetry = !needsSignIn && error as? APIError != .notConfigured
        if needsSignIn { titleKey = "club.signInRequired"; hintKey = "club.signInHint" }
        else if failure?.isForbidden == true { titleKey = "club.accessDenied"; hintKey = "club.accessDeniedHint" }
        else if failure == .membershipRequired { titleKey = "club.membersUnavailable"; hintKey = "club.joinToSeeMembers" }
        else if error as? APIError == .malformedResponse { titleKey = "club.loadFailed"; hintKey = "club.invalidResponse" }
        else { titleKey = "club.loadFailed"; hintKey = "club.retryHint" }
    }
}
