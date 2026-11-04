import Foundation
import SwiftUI
import Observation

/// Presentation state retained by SwiftUI while the requested channel input can change.
/// Each load owns an exact target and request identity; stale success/error cannot mutate a later load.
@MainActor @Observable final class NativeChannelManagementWebhookEntryState {
    private struct Request: Equatable { let id: UUID; let channelID: NativeChannelManagementID }
    private var request: Request?
    private(set) var requestedChannelID: NativeChannelManagementID?
    private(set) var channel: NativeChannelManagementIntegrationContext?
    private(set) var scope: NativeWebhookScope?
    private(set) var failed = false

    func load(channels: any NativeChannelManagementIntegrationContextProviding, channelID: NativeChannelManagementID) async {
        guard !Task.isCancelled else { return }
        let captured = Request(id: UUID(), channelID: channelID)
        request = captured; requestedChannelID = channelID; channel = nil; scope = nil; failed = false
        do {
            let current = try await channels.currentChannelContext(channelID: captured.channelID)
            guard request == captured, !Task.isCancelled else { return }
            guard current.channelID == captured.channelID, channels.contextIsCurrent(current) else {
                failed = true; return
            }
            let resolved = try NativeChannelManagementWebhookScopeAdapter.scope(from: current)
            guard request == captured, !Task.isCancelled else { return }
            channel = current; scope = resolved
        } catch {
            guard request == captured, !Task.isCancelled else { return }
            channel = nil; scope = nil; failed = true
        }
    }
    func readyScope(for channelID: NativeChannelManagementID,
                    channels: any NativeChannelManagementIntegrationContextProviding) -> NativeWebhookScope? {
        guard request?.channelID == channelID, requestedChannelID == channelID,
              let channel, channel.channelID == channelID, channels.contextIsCurrent(channel),
              let scope, scope.channelID.rawValue == channelID.rawValue else { return nil }
        return scope
    }
    func invalidate(for channelID: NativeChannelManagementID) {
        guard requestedChannelID == channelID else { return }
        request = nil; requestedChannelID = nil; channel = nil; scope = nil; failed = false
    }
}

/// P03 -> original 8's P45 entry. The original factory, coordinator, recovery and return action are reused.
/// A fresh real channel is resolved before factory construction. No authorizationVersion is synthesized.
@MainActor struct NativeChannelManagementWebhookEntry: View {
    let channels: any NativeChannelManagementIntegrationContextProviding
    let channelID: NativeChannelManagementID
    let parentRouteIsActive: (() -> Bool)?
    var makeCoordinator: (@MainActor (NativeWebhookScope) throws -> NativeWebhookCoordinator)? = nil
    @State private var state = NativeChannelManagementWebhookEntryState()
    init(channels: any NativeChannelManagementIntegrationContextProviding, channelID: NativeChannelManagementID,
         makeCoordinator: (@MainActor (NativeWebhookScope) throws -> NativeWebhookCoordinator)? = nil,
         state: NativeChannelManagementWebhookEntryState? = nil,
         parentRouteIsActive: (() -> Bool)? = nil) {
        self.channels = channels; self.channelID = channelID; self.makeCoordinator = makeCoordinator
        self.parentRouteIsActive = parentRouteIsActive
        _state = State(initialValue: state ?? NativeChannelManagementWebhookEntryState())
    }
    private var routeSourceIsCurrent: Bool {
        guard state.readyScope(for: channelID, channels: channels) != nil else { return false }
        return parentRouteIsActive?() ?? (state.requestedChannelID == channelID)
    }
    var body: some View {
        Group {
            if let scope = state.readyScope(for: channelID, channels: channels) {
                Group {
                    if let makeCoordinator { NativeWebhookManagementEntry(makeCoordinator: {
                        guard routeSourceIsCurrent, state.readyScope(for: channelID, channels: channels) == scope else {
                            throw NativeWebhookClientError.scopeChanged
                        }
                        let owner = try makeCoordinator(scope)
                        owner.restrictPresentation { [weak state] in
                            guard let state, state.readyScope(for: channelID, channels: channels) == scope else { return false }
                            // Normal composition supplies the complete parent path. Legacy injected
                            // standalone entries retain their own freshly verified state lifetime.
                            return parentRouteIsActive?() ?? (state.requestedChannelID == channelID)
                        }
                        return owner
                    }) }
                    else { NativeWebhookManagementEntry() }
                }.id(scope) // Original 8's retained StateObject must also change from channel A to B.
            } else if state.requestedChannelID == channelID && (state.failed || state.channel != nil) { NativeChannelManagementUnavailableView() }
            else { ProgressView("正在核对频道权限…") }
        }
        .nativeChannelFlowPage()
        .task(id: channelID) {
            await state.load(channels: channels, channelID: channelID)
        }
        .onDisappear { state.invalidate(for: channelID) }
    }
}
