import Foundation
import Combine
import SwiftUI

@MainActor
final class AppSession: ObservableObject {
    private weak var retainedNativeWebhookManagement: NativeWebhookCoordinator?
    private var nativeWebhookConfigurationGeneration: UInt64 = 0
    func makeNativeChannelModerationFlow(channels: any NativeChannelManagementIntegrationContextProviding,
                                         captured: NativeChannelManagementIntegrationContext) -> NativeChannelModerationFlow? {
        guard let storageScope else { return nil }
        let features: Set<BusinessRuntimeFeature> = [.imChannelModerationRead, .imChannelModerationWrite, .imChannelModerationReceipt]
        guard let (factory, gate) = channelHostRuntimeFactory(features, current: { channels.contextIsCurrent(captured) }) else { return nil }
        let issued = factory.routes(features)
        guard !issued.isEmpty else { return nil }
        let context = factory.captured, viewer = compositionViewerRevision
        let current: () -> Bool = { [weak self] in
            guard gate.isCurrent, let self else { return false }
            return self.compositionViewerRevision == viewer && self.currentRuntimeDependencyContext == context
        }
        return try? NativeChannelModerationFlow(captured: captured, channels: channels, context: context,
            transport: factory.client(features), storage: ProjectEditSecureStorage(scope: storageScope), current: current,
            permits: { method, path in current() && issued.contains(where: { $0.method == method && $0.path == path }) },
            unauthorized: { [weak self] in
                guard let self, current() else { return }
                self.expireIfMatching(error: APIError.unauthorized, stamp: context.session.epoch, credential: context.session.token)
            })
    }

    func makeNativeChannelPersonalStateFlow(channels: any NativeChannelManagementIntegrationContextProviding,
                                         captured: NativeChannelManagementIntegrationContext) -> NativeChannelPersonalStateFlow? {
        guard let storageScope else { return nil }
        let features: Set<BusinessRuntimeFeature> = [.imChannelPersonalStateRead, .imChannelPersonalStateWrite, .imChannelPersonalStateReceipt]
        guard let (factory, gate) = channelHostRuntimeFactory(features, current: { channels.contextIsCurrent(captured) }) else { return nil }
        let issued = factory.routes(features)
        guard !issued.isEmpty else { return nil }
        let context = factory.captured, viewer = compositionViewerRevision
        let current: () -> Bool = { [weak self] in
            guard gate.isCurrent, let self else { return false }
            return self.compositionViewerRevision == viewer && self.currentRuntimeDependencyContext == context
        }
        return try? NativeChannelPersonalStateFlow(captured: captured, channels: channels, context: context,
            transport: factory.client(features), storage: ProjectEditSecureStorage(scope: storageScope), current: current,
            permits: { method, path in current() && issued.contains(where: { $0.method == method && $0.path == path }) },
            unauthorized: { [weak self] in
                guard let self, current() else { return }
                self.expireIfMatching(error: APIError.unauthorized, stamp: context.session.epoch, credential: context.session.token)
            })
    }

    func makeNativeChannelRoleFlow(channels: any NativeChannelManagementIntegrationContextProviding,
                                         captured: NativeChannelManagementIntegrationContext) -> NativeChannelRoleFlow? {
        guard let storageScope else { return nil }
        let features: Set<BusinessRuntimeFeature> = [.imChannelRoleRead, .imChannelRoleWrite, .imChannelRoleReceipt, .imChannelRoleMemberRead]
        guard let (factory, gate) = channelHostRuntimeFactory(features, current: { channels.contextIsCurrent(captured) }) else { return nil }
        let issued = factory.routes(features)
        guard !issued.isEmpty else { return nil }
        let context = factory.captured, viewer = compositionViewerRevision
        let current: () -> Bool = { [weak self] in
            guard gate.isCurrent, let self else { return false }
            return self.compositionViewerRevision == viewer && self.currentRuntimeDependencyContext == context
        }
        return try? NativeChannelRoleFlow(captured: captured, channels: channels, context: context,
            transport: factory.client(features), storage: ProjectEditSecureStorage(scope: storageScope), current: current,
            permits: { method, path in current() && issued.contains(where: { $0.method == method && $0.path == path }) },
            unauthorized: { [weak self] in
                guard let self, current() else { return }
                self.expireIfMatching(error: APIError.unauthorized, stamp: context.session.epoch, credential: context.session.token)
            })
    }

    func makeNativeChannelAuditFlow(channels: any NativeChannelManagementIntegrationContextProviding,
                                    captured: NativeChannelManagementIntegrationContext) -> NativeChannelAuditFlow? {
        let features: Set<BusinessRuntimeFeature> = [.imChannelAuditRead]
        guard let (factory, gate) = channelHostRuntimeFactory(features, current: { channels.contextIsCurrent(captured) }) else { return nil }
        guard factory.routes(features).contains(where: { $0.method == "GET" && $0.path == "api/im/audit-log" }) else { return nil }
        let context = factory.captured, viewer = compositionViewerRevision
        let current: () -> Bool = { [weak self] in
            guard gate.isCurrent, let self else { return false }
            return self.compositionViewerRevision == viewer && self.currentRuntimeDependencyContext == context
        }
        return try? NativeChannelAuditFlow(captured: captured, channels: channels, context: context,
            transport: factory.client(features), current: current, unauthorized: { [weak self] in
                guard let self, current() else { return }
                self.expireIfMatching(error: APIError.unauthorized, stamp: context.session.epoch, credential: context.session.token)
            })
    }

    func makeNativeChannelLifecycleAuditFlow(channels: any NativeChannelManagementIntegrationContextProviding,
                                    captured: NativeChannelManagementIntegrationContext) -> NativeChannelAuditFlow? {
        let features: Set<BusinessRuntimeFeature> = [.imChannelLifecycleAuditRead]
        guard let (factory, gate) = channelHostRuntimeFactory(features, current: { channels.contextIsCurrent(captured) }) else { return nil }
        guard factory.routes(features).contains(where: { $0.method == "GET" && $0.path == "api/channels/\(captured.channelID.rawValue)/op-log" }) else { return nil }
        let context = factory.captured, viewer = compositionViewerRevision
        let current: () -> Bool = { [weak self] in
            guard gate.isCurrent, let self else { return false }
            return self.compositionViewerRevision == viewer && self.currentRuntimeDependencyContext == context
        }
        return try? NativeChannelAuditFlow(captured: captured, channels: channels, context: context,
            transport: factory.client(features), current: current, unauthorized: { [weak self] in
                guard let self, current() else { return }
                self.expireIfMatching(error: APIError.unauthorized, stamp: context.session.epoch, credential: context.session.token)
            }, source: .lifecycle)
    }

    func makeNativeChannelManagementFlow(scope: NativeChannelManagementScope) -> NativeChannelManagementCoordinator? {
        guard let context = currentRuntimeDependencyContext,
              let configuration = regionalConfiguration?.apiConfiguration, storageScope != nil else { return nil }
        let viewer = compositionViewerRevision
        let current: () -> RuntimeDependencyContext? = { [weak self] in
            guard let self, self.compositionViewerRevision == viewer else { return nil }
            return self.currentRuntimeDependencyContext
        }
        let selected: () -> NativeChannelManagementApproval? = { [weak self] in
            guard let self, current() != nil else { return nil }
            return self.composition.nativeChannelManagementApproval(context, viewer, scope)
        }
        guard let dispatcher = compositionTransport.makeNativeChannelManagementDispatcher(context: context,
            scope: scope, viewerRevision: viewer, currentRuntime: current,
            currentViewer: { [weak self] in self?.compositionViewerRevision ?? UInt64.max },
            selectedApproval: selected) else { return nil }
        return NativeChannelManagementBinding.make(context: context, viewerRevision: viewer, scope: scope,
            configuration: configuration, transport: dispatcher, storage: ProjectEditSecureStorage(scope: storageScope),
            current: current, viewer: { [weak self] in self?.compositionViewerRevision ?? UInt64.max },
            selectedApproval: selected, onUnauthorized: { [weak self] expected in
                guard let self, current() == context, expected == context else { return }
                self.expireIfMatching(error: APIError.unauthorized, stamp: context.session.epoch, credential: context.session.token)
            })
    }

    func nativeWebhookManagementDestination(for scope: NativeChannelManagementScope)
        -> (@MainActor (NativeWebhookScope) throws -> NativeWebhookCoordinator)? {
        guard scope.guildKind == 1, let captured = currentRuntimeDependencyContext else { return nil }
        if let configuration = composition.sessionDependencies(captured).nativeWebhookConfiguration {
            guard configuration.allowsOwner(scope.guildID.rawValue, context: captured) else { return nil }
        } else if composition.nativeWebhookRuntimeFactory == nil { return nil }
        let viewer = compositionViewerRevision
        let configurationGeneration = nativeWebhookConfigurationGeneration
        return { [weak self] selected in
            guard let self, self.compositionViewerRevision == viewer, self.nativeWebhookConfigurationGeneration == configurationGeneration,
                  self.currentRuntimeDependencyContext == captured,
                  selected.ownerID.rawValue == scope.guildID.rawValue else {
                throw NativeWebhookClientError.sourceUnavailable("WEBHOOK_REAL_CHANNEL_MANAGEMENT_CONTEXT_UNAVAILABLE")
            }
            return try self.makeNativeWebhookManagement(scope: selected)
        }
    }

    func makeNativeWebhookManagement(scope: NativeWebhookScope) throws -> NativeWebhookCoordinator {
        retainedNativeWebhookManagement?.invalidate()
        guard let captured = currentRuntimeDependencyContext else {
            throw NativeWebhookClientError.sourceUnavailable("WEBHOOK_NATIVE_SCOPE_RBAC_FACTORY_UNAVAILABLE")
        }
        let viewer = compositionViewerRevision
        let configurationGeneration = nativeWebhookConfigurationGeneration
        let visit = NativeWebhookRuntimeVisit()
        let current: () -> RuntimeDependencyContext? = { [weak self] in
            guard let self, visit.isCurrent, self.compositionViewerRevision == viewer,
                  self.nativeWebhookConfigurationGeneration == configurationGeneration else { return nil }
            return self.currentRuntimeDependencyContext
        }
        let factory: any NativeWebhookRuntimeFactory
        if let configuration = composition.sessionDependencies(captured).nativeWebhookConfiguration {
            guard let approval = configuration.approval(for: captured, scope: scope) else {
                throw NativeWebhookClientError.sourceUnavailable("WEBHOOK_REVIEWED_ENDPOINT_APPROVAL_UNAVAILABLE")
            }
            guard let dispatcher = compositionTransport.makeNativeWebhookFinalForwardTransport(
                context: captured, scope: scope, issued: approval, currentRuntime: current,
                currentApproval: { [weak self] in
                    guard let live = self?.composition.sessionDependencies(captured).nativeWebhookConfiguration,
                          live == configuration else { return nil }
                    return live.approval(for: captured, scope: scope)
                }, stillCurrent: { visit.isCurrent }) else {
                throw NativeWebhookClientError.sourceUnavailable("WEBHOOK_REVIEWED_ENDPOINT_APPROVAL_UNAVAILABLE")
            }
            factory = NativeWebhookNormalRuntime.make(configuration: configuration,
                currentConfiguration: { [weak self] in self?.composition.sessionDependencies(captured).nativeWebhookConfiguration },
                current: current, transport: dispatcher,
                onUnauthorized: { [weak self] expected in
                    guard let self, visit.isCurrent, self.compositionViewerRevision == viewer, self.nativeWebhookConfigurationGeneration == configurationGeneration,
                          self.currentRuntimeDependencyContext == captured, expected == captured else { return }
                    self.expireIfMatching(error: APIError.unauthorized, stamp: captured.session.epoch,
                        credential: captured.session.token)
                })
        } else if let supplied = composition.nativeWebhookRuntimeFactory { factory = supplied }
        else { throw NativeWebhookClientError.sourceUnavailable("WEBHOOK_NATIVE_SCOPE_RBAC_FACTORY_UNAVAILABLE") }
        let coordinator = try factory.make(captured: captured, scope: scope,
            current: current, journal: composition.storage.operationJournal(),
            onUnauthorized: { [weak self] expected in
                guard let self, visit.isCurrent, self.compositionViewerRevision == viewer, self.nativeWebhookConfigurationGeneration == configurationGeneration,
                      self.currentRuntimeDependencyContext == captured, expected == captured else { return }
                self.expireIfMatching(error: APIError.unauthorized, stamp: captured.session.epoch,
                    credential: captured.session.token)
            })
        guard visit.bind(coordinator) else {
            coordinator.invalidate()
            throw NativeWebhookClientError.scopeChanged
        }
        retainedNativeWebhookManagement = coordinator
        return coordinator
    }

    func makeNativeFriendChannelInviteFlow(mode: NativeFriendChannelInviteMode,
                                          sourceCurrent: @escaping () -> Bool = { true }) -> NativeFriendChannelInviteFlow? {
        guard mode.valid, sourceCurrent(), let context = currentRuntimeDependencyContext,
              let approval = composition.nativeFriendChannelInviteApproval(context, mode), approval.mode == mode else { return nil }
        let viewerRevision = compositionViewerRevision
        let current: () -> Bool = { [weak self] in
            guard let self else { return false }
            return sourceCurrent() && self.compositionViewerRevision == viewerRevision && self.currentRuntimeDependencyContext == context &&
                self.composition.nativeFriendChannelInviteApproval(context, mode) == approval && Date() < approval.expiresAt
        }
        let ownerKey = (try? JSONSerialization.data(withJSONObject: [context.baseURL.absoluteString,
            context.session.namespace, String(context.session.accountID)]).base64EncodedString()) ?? ""
        guard !ownerKey.isEmpty else { return nil }
        let journal = storageScope.map { NativeFriendChannelInviteJournal(storage: ProjectEditSecureStorage(scope: $0), ownerKey: ownerKey) }
        guard let service = try? NativeFriendChannelInviteService(context: context, approval: approval,
            transport: NativeFriendDispatchTransport { [weak self] request in
                guard let self, current() else { throw NativeFriendFailure.notSent }
                return try await self.compositionTransport.sendNativeFriendChannelInvite(request, context: context, approval: approval, stillApproved: current)
            }, current: current, unauthorized: { [weak self] in
                guard let self, current() else { return }
                self.expireIfMatching(error: APIError.unauthorized, stamp: context.session.epoch, credential: context.session.token)
            }) else { return nil }
        return NativeFriendChannelInviteFlow(service: service, journal: journal)
    }

    func makeNativeFriendChannelInviteFlow(channels: any NativeChannelManagementIntegrationContextProviding,
                                          captured: NativeChannelManagementIntegrationContext) -> NativeFriendChannelInviteFlow? {
        guard let context = currentRuntimeDependencyContext, let channel = Int64(captured.channelID.rawValue),
              captured.identity.owner.accountID == context.session.accountID, ["CLUB", "TEAM"].contains(captured.ownerType),
              captured.serverPermissionNames.isSuperset(of: ["VIEW_CHANNEL", "MANAGE_CHANNEL"]), channels.contextIsCurrent(captured) else { return nil }
        return makeNativeFriendChannelInviteFlow(mode: .channel(channel), sourceCurrent: { channels.contextIsCurrent(captured) })
    }

    func makeNativeFriendChannelSourceFlow(channels: any NativeChannelManagementIntegrationContextProviding,
                                          captured: NativeChannelManagementIntegrationContext) -> NativeFriendChannelSourceFlow? {
        guard let context = currentRuntimeDependencyContext, let channelID = Int64(captured.channelID.rawValue),
              captured.identity.owner.accountID == context.session.accountID, captured.ownerType == "CLUB",
              captured.serverPermissionNames.contains("VIEW_CHANNEL"), channels.contextIsCurrent(captured),
              let approval = composition.nativeFriendChannelSourceApproval(context, channelID), approval.channelID == channelID else { return nil }
        let viewerRevision = compositionViewerRevision
        let current: () -> Bool = { [weak self] in
            guard let self else { return false }
            return self.compositionViewerRevision == viewerRevision && self.currentRuntimeDependencyContext == context &&
                channels.contextIsCurrent(captured) && self.composition.nativeFriendChannelSourceApproval(context, channelID) == approval && Date() < approval.expiresAt
        }
        return try? NativeFriendChannelSourceFlow(context: context, approval: approval,
            friend: makeNativeFriendFlow(sourceCurrent: current),
            transport: NativeFriendDispatchTransport { [weak self] request in
                guard let self, current() else { throw NativeFriendFailure.notSent }
                return try await self.compositionTransport.sendNativeFriendChannelSource(request, context: context, approval: approval, stillApproved: current)
            }, current: current, unauthorized: { [weak self] in
                guard let self, current() else { return }
                self.expireIfMatching(error: APIError.unauthorized, stamp: context.session.epoch, credential: context.session.token)
            })
    }

    func makeNativeFriendTeamInviteFlow(mode: NativeFriendTeamInviteMode,
                                          sourceCurrent: @escaping () -> Bool = { true }) -> NativeFriendTeamInviteFlow? {
        guard mode.valid, sourceCurrent(), let context = currentRuntimeDependencyContext,
              let approval = composition.nativeFriendTeamInviteApproval(context, mode), approval.mode == mode else { return nil }
        let viewerRevision = compositionViewerRevision
        let current: () -> Bool = { [weak self] in
            guard let self else { return false }
            return sourceCurrent() && self.compositionViewerRevision == viewerRevision && self.currentRuntimeDependencyContext == context &&
                self.composition.nativeFriendTeamInviteApproval(context, mode) == approval && Date() < approval.expiresAt
        }
        let ownerKey = (try? JSONSerialization.data(withJSONObject: [context.baseURL.absoluteString,
            context.session.namespace, String(context.session.accountID)]).base64EncodedString()) ?? ""
        guard !ownerKey.isEmpty else { return nil }
        let journal = storageScope.map { NativeFriendTeamInviteJournal(storage: ProjectEditSecureStorage(scope: $0), ownerKey: ownerKey) }
        guard let service = try? NativeFriendTeamInviteService(context: context, approval: approval,
            transport: NativeFriendDispatchTransport { [weak self] request in
                guard let self, current() else { throw NativeFriendFailure.notSent }
                return try await self.compositionTransport.sendNativeFriendTeamInvite(request, context: context, approval: approval, stillApproved: current)
            }, current: current, unauthorized: { [weak self] in
                guard let self, current() else { return }
                self.expireIfMatching(error: APIError.unauthorized, stamp: context.session.epoch, credential: context.session.token)
            }) else { return nil }
        return NativeFriendTeamInviteFlow(service: service, journal: journal)
    }

    func makeNativeFriendMetadataFlow(peerID: Int64) -> NativeFriendMetadataFlow {
        let context = currentRuntimeDependencyContext
        let viewerRevision = compositionViewerRevision
        let ownerKey = context.flatMap { value in
            try? JSONSerialization.data(withJSONObject: [value.baseURL.absoluteString,
                value.session.namespace, String(value.session.accountID)])
        }.map { "friend-meta:" + $0.base64EncodedString() } ?? "friend-meta:unconfigured"
        let journal = OperationDefaultsJournal(defaults: composition.storage.defaults)
        guard let context, let approval = composition.nativeFriendMetadataApproval(context) else {
            return NativeFriendMetadataFlow(peerID: peerID, service: nil, journal: journal, ownerKey: ownerKey)
        }
        let service = try? NativeFriendMetadataService(context: context, approval: approval,
            currentApproval: { [weak self] in
                guard let self, self.compositionViewerRevision == viewerRevision,
                      self.currentRuntimeDependencyContext == context else { return nil }
                return self.composition.nativeFriendMetadataApproval(context)
            }, transport: NativeFriendDispatchTransport { [weak self] request in
                guard let self, self.compositionViewerRevision == viewerRevision,
                      self.currentRuntimeDependencyContext == context else { throw NativeFriendFailure.notSent }
                return try await self.compositionTransport.sendNativeFriendMetadata(request, context: context, approval: approval,
                    stillApproved: { self.compositionViewerRevision == viewerRevision &&
                        self.currentRuntimeDependencyContext == context && self.composition.nativeFriendMetadataApproval(context) == approval })
            }, current: { [weak self] in
                guard let self, self.compositionViewerRevision == viewerRevision else { return nil }
                return self.currentRuntimeDependencyContext
            }, onUnauthorized: { [weak self] captured in
                guard let self, self.compositionViewerRevision == viewerRevision,
                      self.currentRuntimeDependencyContext == context, captured == context else { return }
                self.expireIfMatching(error: APIError.unauthorized, stamp: captured.session.epoch,
                    credential: captured.session.token)
            })
        return NativeFriendMetadataFlow(peerID: peerID, service: service, journal: journal, ownerKey: ownerKey)
    }

    func makeNativeFriendDirectoryFlow() -> NativeFriendDirectoryFlow {
        let context = currentRuntimeDependencyContext
        let viewerRevision = compositionViewerRevision
        guard let context, let approval = composition.nativeFriendDirectoryApproval(context) else {
            return NativeFriendDirectoryFlow(service: nil)
        }
        let service = try? NativeFriendDirectoryService(context: context, approval: approval,
            currentApproval: { [weak self] in
                guard let self, self.compositionViewerRevision == viewerRevision,
                      self.currentRuntimeDependencyContext == context else { return nil }
                return self.composition.nativeFriendDirectoryApproval(context)
            }, transport: NativeFriendDispatchTransport { [weak self] request in
                guard let self, self.compositionViewerRevision == viewerRevision,
                      self.currentRuntimeDependencyContext == context else { throw NativeFriendFailure.notSent }
                return try await self.compositionTransport.sendNativeFriendDirectory(request, context: context, approval: approval,
                    stillApproved: { self.compositionViewerRevision == viewerRevision &&
                        self.currentRuntimeDependencyContext == context && self.composition.nativeFriendDirectoryApproval(context) == approval })
            }, current: { [weak self] in
                guard let self, self.compositionViewerRevision == viewerRevision else { return nil }
                return self.currentRuntimeDependencyContext
            }, onUnauthorized: { [weak self] captured in
                guard let self, self.compositionViewerRevision == viewerRevision,
                      self.currentRuntimeDependencyContext == context, captured == context else { return }
                self.expireIfMatching(error: APIError.unauthorized, stamp: captured.session.epoch,
                    credential: captured.session.token)
            })
        return NativeFriendDirectoryFlow(service: service)
    }

    func makeNativeFriendProgressCard(item: NativeFriendItem, isCurrent: @escaping () -> Bool) -> NativeFriendProgressCard {
        let context = currentRuntimeDependencyContext
        let viewerRevision = compositionViewerRevision
        guard let context, let approval = composition.nativeFriendProgressApproval(context), isCurrent() else {
            return NativeFriendProgressCard(source: nil)
        }
        let policyOwner = NativeProgressPrivacyInvalidation.owner(origin: context.baseURL, namespace: context.session.namespace, actor: Int64(context.session.accountID))
        do {
            let records = try OperationDefaultsJournal(defaults: composition.storage.defaults).pendingRecords(ownerKey: policyOwner)
                .filter { $0.targetKey.hasPrefix("native-progress-privacy.v1.") }
            NativeProgressPrivacyInvalidation.restore(owner: policyOwner, requests: Set(records.map(\.operationID)))
        } catch { NativeProgressPrivacyInvalidation.restore(owner: policyOwner, requests: nil) }
        let service = try? NativeFriendProgressService(context: context, approval: approval, friend: item,
            currentApproval: { [weak self] in
                guard let self, self.compositionViewerRevision == viewerRevision,
                      self.currentRuntimeDependencyContext == context, isCurrent() else { return nil }
                return self.composition.nativeFriendProgressApproval(context)
            }, transport: NativeFriendDispatchTransport { [weak self] request in
                guard let self, self.compositionViewerRevision == viewerRevision,
                      self.currentRuntimeDependencyContext == context, isCurrent() else { throw NativeFriendFailure.notSent }
                return try await self.compositionTransport.sendNativeFriendProgress(request, context: context, approval: approval,
                    stillApproved: { self.compositionViewerRevision == viewerRevision && isCurrent() &&
                        self.currentRuntimeDependencyContext == context && self.composition.nativeFriendProgressApproval(context) == approval })
            }, current: { [weak self] in
                guard let self, self.compositionViewerRevision == viewerRevision else { return nil }
                return self.currentRuntimeDependencyContext
            }, relationshipCurrent: isCurrent, onUnauthorized: { [weak self] captured in
                guard let self, self.compositionViewerRevision == viewerRevision,
                      self.currentRuntimeDependencyContext == context, captured == context else { return }
                self.expireIfMatching(error: APIError.unauthorized, stamp: captured.session.epoch, credential: captured.session.token)
            })
        return NativeFriendProgressCard(source: service)
    }

    func makeNativeFriendRemovalFlow(item: NativeFriendItem? = nil) -> NativeFriendRemovalFlow {
        let context = currentRuntimeDependencyContext
        let viewerRevision = compositionViewerRevision
        let ownerKey = context.flatMap { value in
            try? JSONSerialization.data(withJSONObject: [value.baseURL.absoluteString,
                value.session.namespace, String(value.session.accountID)])
        }.map { "friend-remove:" + $0.base64EncodedString() } ?? "friend-remove:unconfigured"
        let journal = OperationDefaultsJournal(defaults: composition.storage.defaults)
        guard let context, let approval = composition.nativeFriendRemovalApproval(context) else {
            return NativeFriendRemovalFlow(item: item, service: nil, journal: journal, ownerKey: ownerKey)
        }
        let service = try? NativeFriendRemovalService(context: context, approval: approval,
            currentApproval: { [weak self] in
                guard let self, self.compositionViewerRevision == viewerRevision,
                      self.currentRuntimeDependencyContext == context else { return nil }
                return self.composition.nativeFriendRemovalApproval(context)
            }, transport: NativeFriendDispatchTransport { [weak self] request in
                guard let self, self.compositionViewerRevision == viewerRevision,
                      self.currentRuntimeDependencyContext == context else { throw NativeFriendFailure.notSent }
                return try await self.compositionTransport.sendNativeFriendRemoval(request, context: context, approval: approval,
                    stillApproved: { self.compositionViewerRevision == viewerRevision &&
                        self.currentRuntimeDependencyContext == context && self.composition.nativeFriendRemovalApproval(context) == approval })
            }, current: { [weak self] in
                guard let self, self.compositionViewerRevision == viewerRevision else { return nil }
                return self.currentRuntimeDependencyContext
            }, onUnauthorized: { [weak self] captured in
                guard let self, self.compositionViewerRevision == viewerRevision,
                      self.currentRuntimeDependencyContext == context, captured == context else { return }
                self.expireIfMatching(error: APIError.unauthorized, stamp: captured.session.epoch,
                    credential: captured.session.token)
            })
        return NativeFriendRemovalFlow(item: item, service: service, journal: journal, ownerKey: ownerKey)
    }

    func makeNativeBlacklistFlow() -> NativeBlacklistFlow {
        let context = currentRuntimeDependencyContext
        let viewerRevision = compositionViewerRevision
        let ownerKey = context.flatMap { value in
            try? JSONSerialization.data(withJSONObject: [value.baseURL.absoluteString,
                value.session.namespace, String(value.session.accountID)])
        }.map { "blacklist:" + $0.base64EncodedString() } ?? "blacklist:unconfigured"
        let journal = OperationDefaultsJournal(defaults: composition.storage.defaults)
        guard let context, let approval = composition.nativeBlacklistApproval(context) else {
            return NativeBlacklistFlow(service: nil, journal: journal, ownerKey: ownerKey)
        }
        let service = try? NativeBlacklistService(context: context, approval: approval,
            currentApproval: { [weak self] in
                guard let self, self.compositionViewerRevision == viewerRevision,
                      self.currentRuntimeDependencyContext == context else { return nil }
                return self.composition.nativeBlacklistApproval(context)
            }, transport: NativeBlacklistDispatchTransport { [weak self] request in
                guard let self, self.compositionViewerRevision == viewerRevision,
                      self.currentRuntimeDependencyContext == context else { throw NativeBlacklistFailure.notSent }
                return try await self.compositionTransport.sendNativeBlacklist(request, context: context, approval: approval,
                    stillApproved: { self.compositionViewerRevision == viewerRevision &&
                        self.currentRuntimeDependencyContext == context && self.composition.nativeBlacklistApproval(context) == approval })
            }, current: { [weak self] in
                guard let self, self.compositionViewerRevision == viewerRevision else { return nil }
                return self.currentRuntimeDependencyContext
            }, onUnauthorized: { [weak self] captured in
                guard let self, self.compositionViewerRevision == viewerRevision,
                      self.currentRuntimeDependencyContext == context, captured == context else { return }
                self.expireIfMatching(error: APIError.unauthorized, stamp: captured.session.epoch,
                    credential: captured.session.token)
            })
        return NativeBlacklistFlow(service: service, journal: journal, ownerKey: ownerKey)
    }

    func makeNativeFriendFlow(sourceCurrent: @escaping () -> Bool = { true }) -> NativeFriendFlow {
        let context = currentRuntimeDependencyContext
        let viewerRevision = compositionViewerRevision
        let ownerKey = context.flatMap { value in
            try? JSONSerialization.data(withJSONObject: [value.baseURL.absoluteString,
                value.session.namespace, String(value.session.accountID)])
        }.map { "friend:" + $0.base64EncodedString() } ?? "friend:unconfigured"
        let journal = OperationDefaultsJournal(defaults: composition.storage.defaults)
        let fullIntent = storageScope.map { NativeFriendIntentJournal(storage: ProjectEditSecureStorage(scope: $0), ownerKey: ownerKey) }
        guard sourceCurrent(), let context, let approval = composition.nativeFriendApproval(context) else {
            return NativeFriendFlow(service: nil, journal: journal, ownerKey: ownerKey, intentJournal: fullIntent)
        }
        let service = try? NativeFriendService(context: context, approval: approval,
            currentApproval: { [weak self] in
                guard let self, self.compositionViewerRevision == viewerRevision,
                      self.currentRuntimeDependencyContext == context, sourceCurrent() else { return nil }
                return self.composition.nativeFriendApproval(context)
            }, transport: NativeFriendDispatchTransport { [weak self] request in
                guard let self, self.compositionViewerRevision == viewerRevision,
                      self.currentRuntimeDependencyContext == context, sourceCurrent() else { throw NativeFriendFailure.notSent }
                return try await self.compositionTransport.sendNativeFriend(request, context: context, approval: approval,
                    stillApproved: { self.compositionViewerRevision == viewerRevision &&
                        self.currentRuntimeDependencyContext == context && sourceCurrent() && self.composition.nativeFriendApproval(context) == approval })
            }, current: { [weak self] in
                guard let self, self.compositionViewerRevision == viewerRevision, sourceCurrent() else { return nil }
                return self.currentRuntimeDependencyContext
            }, onUnauthorized: { [weak self] captured in
                guard let self, self.compositionViewerRevision == viewerRevision,
                      self.currentRuntimeDependencyContext == context, captured == context else { return }
                self.expireIfMatching(error: APIError.unauthorized, stamp: captured.session.epoch,
                    credential: captured.session.token)
            })
        return NativeFriendFlow(service: service, journal: journal, ownerKey: ownerKey, intentJournal: fullIntent)
    }

    func nativeChannelProgressTeams(channelID: NativeChannelManagementID, board: NativeChannelProgressBoard) -> [NativeChannelProgressTeamOption]? {
        guard let context = currentRuntimeDependencyContext else { return nil }
        return composition.nativeChannelProgressTeamOptions(context, channelID, board)
    }

    func makeNativeChannelProgressFlow(channels: any NativeChannelManagementIntegrationContextProviding,
        captured: NativeChannelManagementIntegrationContext, sourceCurrent: @escaping @MainActor () -> Bool) -> NativeChannelProgressCoordinator? {
        guard let context = currentRuntimeDependencyContext, let storageScope,
              sourceCurrent(), channels.contextIsCurrent(captured),
              let selection = composition.nativeChannelProgressSelection(context, captured) else { return nil }
        let viewer = compositionViewerRevision
        let current: () -> RuntimeDependencyContext? = { [weak self] in
            guard let self, self.compositionViewerRevision == viewer, sourceCurrent(),
                  channels.contextIsCurrent(captured) else { return nil }
            return self.currentRuntimeDependencyContext
        }
        let selected: () -> NativeChannelProgressRuntimeSelection? = { [weak self] in
            guard let self, let latest = current(), ContentDraftContextFence.matches(latest, context),
                  latest.session == context.session else { return nil }
            return self.composition.nativeChannelProgressSelection(latest, captured)
        }
        let storage = NativeChannelProgressSecureJournalStorage(storage: ProjectEditSecureStorage(scope: storageScope))
        guard let journal = try? NativeChannelProgressPrivacyJournal(identity: selection.authority.identity, storage: storage),
              let dispatcher = compositionTransport.makeNativeChannelProgressFinalForward(context: context,
                  selection: selection, journal: journal, currentRuntime: current, selected: selected,
                  stillCurrent: sourceCurrent, receiptApproval: { [weak self] command in
                      guard let self, selected() == selection else { return nil }
                      return self.composition.nativeChannelProgressReceiptApproval(context, captured, command)
                  }) else { return nil }
        return try? NativeChannelProgressBinding.make(context: captured, provider: channels,
            selectedAuthority: { dispatcher.isCurrent ? selected()?.authority : nil }, dispatcher: dispatcher,
            token: { dispatcher.isCurrent ? current()?.session.token : nil }, storage: storage,
            onUnauthorized: { [weak self] in
                guard let self, dispatcher.isCurrent, current()?.session == context.session else { return }
                self.expireIfMatching(error: APIError.unauthorized, stamp: context.session.epoch, credential: context.session.token)
            })
    }

    func makeNativeChannelProgressPrivacyFlow(channels: any NativeChannelManagementIntegrationContextProviding,
                                             captured: NativeChannelManagementIntegrationContext) -> NativeProgressPrivacyFlow? {
        guard let context = currentRuntimeDependencyContext, captured.ownerType == "CLUB", channels.contextIsCurrent(captured),
              captured.identity.owner.accountID == context.session.accountID, captured.identity.owner.baseURL == context.baseURL.absoluteString,
              captured.identity.owner.namespace == context.session.namespace, captured.identity.epoch == context.session.epoch,
              captured.identity.viewerRevision == compositionViewerRevision,
              captured.serverPermissionNames.isSuperset(of: ["VIEW_CHANNEL", "MANAGE_PROGRESS"]),
              let id = Int64(captured.channelID.rawValue), let target = try? NativeProgressPrivacyTarget(kind: .channel, id: id) else { return nil }
        return makeNativeProgressPrivacyFlow(target: target, channelCurrent: { channels.contextIsCurrent(captured) })
    }

    private func makeNativeProgressPrivacyFlow(target: NativeProgressPrivacyTarget?, channelCurrent: @escaping () -> Bool) -> NativeProgressPrivacyFlow {
        let context = currentRuntimeDependencyContext, viewerRevision = compositionViewerRevision
        let ownerKey = context.flatMap { value in
            try? JSONSerialization.data(withJSONObject: [value.baseURL.absoluteString, value.session.namespace, String(value.session.accountID)])
        }.map { "progress-privacy:" + $0.base64EncodedString() } ?? "progress-privacy:unconfigured"
        let journal = OperationDefaultsJournal(defaults: composition.storage.defaults)
        guard let context, let target, let approval = composition.nativeProgressPrivacyApproval(context, target), channelCurrent() else {
            return NativeProgressPrivacyFlow(service: nil, journal: journal, ownerKey: ownerKey)
        }
        let service = try? NativeProgressPrivacyService(context: context, approval: approval, target: target,
            transport: NativeFriendDispatchTransport { [weak self] request in
                guard let self, self.compositionViewerRevision == viewerRevision, self.currentRuntimeDependencyContext == context,
                      channelCurrent() else { throw NativeFriendFailure.notSent }
                return try await self.compositionTransport.sendNativeProgressPrivacy(request, context: context, approval: approval,
                    stillApproved: { self.compositionViewerRevision == viewerRevision && self.currentRuntimeDependencyContext == context &&
                        channelCurrent() && self.composition.nativeProgressPrivacyApproval(context, target) == approval })
            }, current: { [weak self] in
                guard let self, self.compositionViewerRevision == viewerRevision else { return nil }; return self.currentRuntimeDependencyContext
            }, currentApproval: { [weak self] in
                guard let self, self.compositionViewerRevision == viewerRevision, self.currentRuntimeDependencyContext == context else { return nil }
                return self.composition.nativeProgressPrivacyApproval(context, target)
            }, channelCurrent: channelCurrent, onUnauthorized: { [weak self] captured in
                guard let self, self.compositionViewerRevision == viewerRevision, self.currentRuntimeDependencyContext == context, captured == context else { return }
                self.expireIfMatching(error: APIError.unauthorized, stamp: captured.session.epoch, credential: captured.session.token)
            })
        return NativeProgressPrivacyFlow(service: service, journal: journal, ownerKey: ownerKey)
    }

    func makeNativeChannelWelcome(scope:NativeChannelManagementScope,sourceCurrent:@escaping()->Bool) -> NativeChannelWelcomeFlow? {
        guard let context=currentRuntimeDependencyContext,let approval=composition.nativeChannelWelcomeApproval(context) else { return nil }
        let viewer=compositionViewerRevision
        let available: () -> Bool = { [weak self] in
            guard let self,sourceCurrent(),self.currentRuntimeDependencyContext == context,self.compositionViewerRevision == viewer else { return false }
            return self.composition.nativeChannelWelcomeApproval(context) == approval
        }
        let dispatch=NativeFriendDispatchTransport { [weak self] request in
            guard let self,available() else { throw NativeSpaceAdmissionFailure.notSent }
            return try await self.compositionTransport.sendNativeChannelWelcome(request,context:context,approval:approval,stillApproved:available)
        }
        return try? NativeChannelWelcomeFlow(scope:scope,context:context,approval:approval,transport:dispatch,current:available,unauthorized:{ [weak self] in
            guard let self,available() else { return }
            self.expireIfMatching(error:APIError.unauthorized,stamp:context.session.epoch,credential:context.session.token)
        })
    }

    func makeNativeChannelOnboarding(scope:NativeChannelManagementScope,sourceCurrent:@escaping()->Bool) -> NativeChannelOnboardingFlow? {
        guard let context=currentRuntimeDependencyContext,let storageScope,let approval=composition.nativeChannelOnboardingApproval(context) else{return nil}
        let viewer=compositionViewerRevision
        let available: () -> Bool = { [weak self] in
            guard let self,sourceCurrent(),self.currentRuntimeDependencyContext==context,self.compositionViewerRevision==viewer else{return false}
            return self.composition.nativeChannelOnboardingApproval(context)==approval
        }
        let dispatch=NativeFriendDispatchTransport { [weak self] request in
            guard let self,available() else{throw NativeSpaceAdmissionFailure.notSent}
            return try await self.compositionTransport.sendNativeChannelOnboarding(request,context:context,approval:approval,stillApproved:available)
        }
        return try? NativeChannelOnboardingFlow(scope:scope,context:context,approval:approval,transport:dispatch,storage:ProjectEditSecureStorage(scope:storageScope),current:available,unauthorized:{[weak self] in
            guard let self,available() else{return}
            self.expireIfMatching(error:APIError.unauthorized,stamp:context.session.epoch,credential:context.session.token)
        })
    }

    func withNativeWebhookConfigurationChange(_ change: () -> Void) {
        nativeWebhookConfigurationGeneration &+= 1
        retainedNativeWebhookManagement?.invalidate(); retainedNativeWebhookManagement = nil
        change()
    }

    @Published private(set) var account: Account? { willSet { if account?.id != newValue?.id || account?.effectiveRole != newValue?.effectiveRole { invalidatePersonalLocationShare() }; if account?.id != newValue?.id || account?.effectiveRole.data(using: .utf8) != newValue?.effectiveRole.data(using: .utf8) { invalidateWorkshopReadBindings() }; invalidateOwnerDraftBrowser(); if account?.id != newValue?.id || account?.effectiveRole != newValue?.effectiveRole { invalidateShopNPCConversations(); merchantNPCSessionOwner.invalidate() }; if account?.id != newValue?.id { platformConsumers.invalidate() } } didSet { _ = runtimeDependencies; synchronizeAccountMarketingEntry(); _ = searchMapReader.scope } }
    @Published private(set) var isWorking = false { didSet { synchronizeAccountMarketingEntry() } }
    @Published private(set) var errorKey: String?
    let platformConsumers = PlatformConsumerSessionOwner()
    let retainedImagePickerHost = RetainedImagePickerHost()
    private var publicMerchantReviewEpoch = UUID()
    private var currentRetainedImageCredentials: RetainedImageHostCredentials? {
        guard let account, let token, let namespace = storageScope?.service,
              let configuration = regionalConfiguration?.apiConfiguration else { return nil }
        return RetainedImageHostCredentials(accountID: account.id, sessionVersion: gate.currentStamp,
            realm: configuration.baseURL.absoluteString, namespace: namespace, token: token, authorizationRevision: account.effectiveRole)
    }
    private lazy var imageUploadStorage = ImageUploadSecureStorage(scope: storageScope)
    private lazy var imageUploadJournal = StoredImageUploadJournal(
        read: { [unowned self] in try self.imageUploadStorage.read($0) },
        write: { [unowned self] in try self.imageUploadStorage.write($0, key: $1) })
    private lazy var retainedImageContextCache: RetainedImageContextCache? = {
        guard let configuration = regionalConfiguration?.apiConfiguration, storageScope != nil else { return nil }
        return RetainedImageContextCache(configuration: configuration, transport: runtimeHTTPTransport,
            pickerHost: retainedImagePickerHost, journal: imageUploadJournal, currentCredentials: { [weak self] in self?.currentRetainedImageCredentials })
    }()
    lazy var retainedMerchantImages: MerchantRetainedImageHost? = retainedImageContextCache.map { MerchantRetainedImageHost(cache: $0) }
    private var currentPublicMerchantReviewSession: PublicMerchantReviewSession? {
        guard let credentials = currentRetainedImageCredentials else { return nil }
        return try? PublicMerchantReviewSession(accountID: credentials.accountID, scope: publicMerchantReviewEpoch,
            realm: credentials.realm, token: credentials.token)
    }
    private lazy var retainedPublicMerchantReviews: RetainedPublicMerchantReviewHost? = {
        guard let configuration = regionalConfiguration?.apiConfiguration, let cache = retainedImageContextCache else { return nil }
        return RetainedPublicMerchantReviewHost(configuration: configuration, transport: runtimeHTTPTransport, cache: cache,
            currentSession: { [weak self] in self?.currentPublicMerchantReviewSession })
    }()

    private let merchantNPCSessionOwner = MerchantNPCSessionOwner()
    private var merchantNPCGrants: MerchantNPCGrants { merchantPublicFactory?.chatGrants ?? .init() }
    private var merchantNPCJournal: any OperationPendingJournal { composition.storage.operationJournal() }
    /// Original-result read authority is independent of game dispatch and merchant ownership.
    func makeMerchantGamePlayerCoordinator(merchantID: Int) -> MerchantGamePlayerCoordinator? {
        guard let context = currentRuntimeDependencyContext, let token,
              let configuration = regionalConfiguration?.apiConfiguration,
              let captured = try? MerchantGamePlayerSession(namespace: context.session.namespace,
                accountID: context.session.accountID, epoch: context.session.epoch, credential: token) else { return nil }
        let issued = composition.merchantGamePlayerReadGrant(context)
        let approved = issued?.matches(context) == true ? issued : nil
        let viewerRevision = compositionViewerRevision
        guard let service = try? MerchantGamePlayerService(configuration: configuration, merchantID: merchantID,
            session: captured, grant: approved, transport: runtimeHTTPTransport, journal: merchantNPCJournal,
            current: { [weak self] in
                guard let self, self.currentRuntimeDependencyContext == context, self.token == token,
                      self.compositionViewerRevision == viewerRevision,
                      self.composition.merchantGamePlayerReadGrant(context) == issued else { return nil }
                return captured
            }) else { return nil }
        return MerchantGamePlayerCoordinator(service: service)
    }

    private var merchantNPCAccess: (scope: UUID, value: MerchantOperationsAccess, revision: UUID)?
    private func merchantNPCScope(row: PublicMerchantRowID, resource: Bool = false) -> MerchantNPCScope? {
        guard let account, token != nil, let namespace = storageScope?.service else { return nil }
        let epoch = merchantOperationsReader.scope
        let revision: UUID
        if resource {
            guard let proof = merchantNPCAccess, proof.scope == epoch, proof.value.identity.merchantID == row.rawValue,
                  proof.value.allows(.assets) else { return nil }
            revision = proof.revision
        } else { revision = publicMerchantHomeReader.scope }
        return MerchantNPCScope(accountID: account.id, namespace: namespace, epoch: epoch, merchantRowID: row, accessRevision: revision)
    }
    private func merchantNPCClient(resource: Bool) -> MerchantNPCHTTPClient {
        guard let factory = merchantPublicFactory else { return .init() }
        if resource { return factory.resourceClient() }
        return factory.chatClient(currentScope: { [weak self] row in self?.merchantNPCScope(row: row) })
    }
    func merchantOperationsDestination(_ destination: MerchantOperationsDestination, access: MerchantOperationsAccess) -> AnyView {
        // w2-19: source pages/merchant/decor/ai-npc has its own page; saves stay dormant.
        if destination == .character { return merchantStoreCharacterDestination() }
        guard destination == .assets else { return AnyView(MerchantOperationsDocumentView(reader: merchantOperationsReader, destination: destination, imageHost: retainedMerchantImages, templateAssistFactory: { [weak self] coordinator in
            self?.merchantTemplateAssistFlow(coordinator: coordinator) ?? MerchantTemplateAssistFlow(coordinator: coordinator, client: nil)
        })) }
        // CURRENT backend has no legacy script/avatar resource contract. Do not query invented routes.
        guard MerchantPublicProductionFactory.supportsLegacyResources else { return AnyView(Text("merchantNPC.unavailable")) }
        let epoch = merchantOperationsReader.scope
        if merchantNPCAccess?.scope != epoch || merchantNPCAccess?.value != access {
            merchantNPCSessionOwner.invalidate(); merchantNPCAccess = (epoch, access, UUID())
        }
        guard let id = access.identity.merchantID, let row = PublicMerchantRowID(id), access.allows(.assets),
              let captured = merchantNPCScope(row: row, resource: true) else { return AnyView(Text("merchantNPC.unavailable")) }
        let coordinator = MerchantNPCResourcesCoordinator(scope: captured, client: merchantNPCClient(resource: true), reader: merchantOperationsReader,
            journal: merchantNPCJournal, currentScope: { [weak self] in self?.merchantNPCScope(row: row, resource: true) },
            grants: { .init() })
        merchantNPCSessionOwner.register(coordinator)
        return AnyView(MerchantNPCResourceEditor(coordinator: coordinator, imageContext: merchantNPCAvatarContext(captured),
            imageRealm: regionalConfiguration?.apiConfiguration?.baseURL.absoluteString, approvedImageHosts: []).id(captured.epoch))
    }
    private func merchantNPCAvatarContext(_ captured: MerchantNPCScope) -> RetainedImageSelectionContext? {
        guard let cache = retainedImageContextCache, let credentials = currentRetainedImageCredentials,
              merchantNPCScope(row: captured.merchantRowID, resource: true) == captured,
              let imageScope = try? RetainedImageScope(accountID: captured.accountID, epoch: captured.epoch,
                realm: credentials.realm, destination: .merchant(merchantRowID: captured.merchantRowID.rawValue, field: .avatar),
                accessRevision: captured.accessRevision, namespace: captured.namespace) else { return nil }
        return cache.context(scope: imageScope, destination: .merchant(captured.merchantRowID, .avatar, templateID: nil, newDraftID: nil),
            ownerID: captured.accessRevision, isCurrent: { [weak self] in
                self?.merchantNPCScope(row: captured.merchantRowID, resource: true) == captured
            })
    }
    private let disabledPublicMerchantHomeReader = DisabledPublicMerchantHomeReader()
    private var retainedMerchantPublicFactory: MerchantPublicProductionFactory?
    private var retainedMerchantPublicViewerRevision: UInt64?
    private var currentMerchantPublicContext: MerchantPublicHostContext? {
        guard let regionalConfiguration, let api = regionalConfiguration.apiConfiguration,
              let namespace = storageScope?.service else { return nil }
        return try? .init(market: regionalConfiguration.market, baseURL: api.baseURL, namespace: namespace,
            accountID: account?.id, epoch: gate.currentStamp, role: account?.effectiveRole, token: token)
    }
    private var merchantPublicFactory: MerchantPublicProductionFactory? {
        guard let api = regionalConfiguration?.apiConfiguration, let context = currentMerchantPublicContext else { return nil }
        if let retainedMerchantPublicFactory, retainedMerchantPublicFactory.captured == context,
           retainedMerchantPublicViewerRevision == compositionViewerRevision { return retainedMerchantPublicFactory }
        let dependencies = runtimeDependencies
        let transport: any HTTPTransport
        let chatTransport: (any HTTPTransport)?
        if let approval = dependencies.merchantPublicApproval {
            transport = compositionTransport.scopedForPublicMerchantHome(approval: approval, context: context)
            chatTransport = compositionTransport.scopedForMerchantGameNPC(approval: approval, context: context,
                grants: { dependencies.merchantNPCGrants })
        } else { transport = runtimeHTTPTransport; chatTransport = nil }
        let viewerRevision = compositionViewerRevision
        let factory = dependencies.makeMerchantPublicFactory(api: api, journal: merchantNPCJournal, transportOverride: transport,
            chatTransportOverride: chatTransport,
            current: { [weak self] in
                guard let self, self.compositionViewerRevision == viewerRevision else { return nil }
                return self.currentMerchantPublicContext
            })
        retainedMerchantPublicFactory = factory
        retainedMerchantPublicViewerRevision = viewerRevision
        return factory
    }
    private var publicMerchantHomeReader: any PublicMerchantHomeReading {
        merchantPublicFactory?.homeReader ?? disabledPublicMerchantHomeReader
    }
    private var publicMerchantReviewReader: any PublicMerchantReviewReading = DisabledPublicMerchantReviewReader()
    /// Read-only consumers receive no reviews, NPC, owner-profile or action contexts.
    var readOnlyPublicMerchantHomeContext: PublicMerchantHomeContext {
        PublicMerchantHomeContext(reader: publicMerchantHomeReader)
    }
    var publicMerchantHomeContext: PublicMerchantHomeContext {
        let retained = retainedPublicMerchantReviews
        let reviews: any PublicMerchantReviewReading = retained?.reader ?? publicMerchantReviewReader
        let images: any RetainedPublicImageReading = retained?.imageReader ?? RetainedPublicImageReader(enabled: false, origins: [])
        let writes = retained?.writeContext(journal: merchantBusinessJournal)
        var context = PublicMerchantHomeContext(reader: publicMerchantHomeReader,
            publicReviews: { AnyView(PublicMerchantReviewsView(target: $0, reader: reviews, imageReader: images, writes: writes)) })
        context.featured = makePublicMerchantFeaturedContext(homeReader: context.reader)
        context.ownerProfile = .init(makeReader: { [weak self] memberID in
            self?.makeProfilePublicInfoReader(memberID: memberID)
        }, squareReader: squareReader)
        if let destination = composition.merchantGamePlayerDestination {
            let makePage: (PublicMerchantRowID, AnyView?) -> AnyView = { [weak self] row, chat in
                guard let self, let captured = self.currentRuntimeDependencyContext else {
                    return AnyView(Text("merchantNPC.unavailable"))
                }
                let viewerRevision = self.compositionViewerRevision, token = self.token
                let grant = self.composition.merchantGamePlayerReadGrant(captured)
                return AnyView(MerchantGameFactsDestination(session: self, current: { [weak self] in
                    guard let self else { return false }
                    return self.currentRuntimeDependencyContext == captured && self.token == token &&
                        self.compositionViewerRevision == viewerRevision &&
                        self.composition.merchantGamePlayerReadGrant(captured) == grant
                }, make: { [weak self] in self?.makeMerchantGamePlayerCoordinator(merchantID: row.rawValue) },
                    render: destination, chat: chat))
            }
            context.gameFactsDestination = { makePage($0, nil) }
            // A local facts renderer must not silently enable NPC chat or make an
            // existing separately approved sender depend on an absent read grant.
            if merchantNPCGrants.chatAllowed, let captured = currentRuntimeDependencyContext,
               let grant = composition.merchantGamePlayerReadGrant(captured), grant.matches(captured),
               grant.endpoints.paths.isSuperset(of: MerchantGamePlayerReadGrant.playerPaths) {
                context.gamePlayerDestination = makePage
            }
        }
        context.installMerchantNPC(grants: { [weak self] in self?.merchantNPCGrants ?? .init() },
            scopeForRow: { [weak self] in self?.merchantNPCScope(row: $0) },
            currentScope: { [weak self] in self?.merchantNPCScope(row: $0) }, client: merchantNPCClient(resource: false),
            register: { [weak self] in self?.merchantNPCSessionOwner.register($0) })
        return context
    }
    private let dormantCommunityService = ClubCommunityService(dormantBaseURL: URL(string: "https://disabled.invalid")!, transport: CommunityDormantHTTPTransport())
    var clubCommunityReadApprovalSelector: (RuntimeDependencyContext) -> ClubCommunityReadApproval? = { _ in nil }
    var clubCommunityTransportOverride: (any HTTPTransport)?
    var clubCommunityPendingOutcomeQueryOverride: (any ClubCommunityPendingOutcomeQuerying)?
    var clubPostImageUploadApprovalSelector: (RuntimeDependencyContext, Int) -> ClubPostImageUploadApproval? = { _, _ in nil }
    func compositionClubCommunityReadApproval(_ context: RuntimeDependencyContext) -> ClubCommunityReadApproval? {
        composition.clubCommunityReadApproval(context)
    }
    private var communityService: ClubCommunityService {
        resolvedClubCommunityService(fallback: dormantCommunityService)
    }
    var clubCommunityRuntimeContext: RuntimeDependencyContext? { currentRuntimeDependencyContext }
    var clubCommunityRuntimeTransport: any HTTPTransport { scopedTransport(clubCommunityTransportOverride) }
    func currentClubCommunitySession() throws -> ClubCommunitySession { try currentCommunitySession() }
    private func currentCommunitySession() throws -> ClubCommunitySession {
        try ClubCommunitySession(identity: clubIdentity, token: token)
    }
    private struct ClubCommunityDynamicPendingOutcomeQuery: ClubCommunityPendingOutcomeQuerying {
        let resolve: () -> any ClubCommunityPendingOutcomeQuerying
        var allowsAuthoritativeQueries: Bool { resolve().allowsAuthoritativeQueries }
        func queryOutcome(
            for record: ClubCommunityPendingRecord,
            session: ClubCommunitySession,
            check: () throws -> Void
        ) async throws -> ClubCommunityPendingQueryResult {
            try await resolve().queryOutcome(for: record, session: session, check: check)
        }
    }
    private lazy var communityCoordinator = ClubCommunityCoordinator(
        service: dormantCommunityService,
        currentSession: { [weak self] in
            guard let self else { throw ClubCommunityFailure.unavailable }; return try self.currentCommunitySession()
        },
        refreshEvidence: { [weak self] old in
            guard let self else { throw ClubCommunityFailure.unavailable }
            return try await self.communityEvidence(clubID: old.clubID, post: old.post, comment: old.comment)
        },
        journal: ClubCommunityStoredPendingJournal(defaults: sessionDefaults),
        namespace: { [weak self] in self?.storageScope?.service ?? "default" },
        outcomeQuery: ClubCommunityDynamicPendingOutcomeQuery(resolve: { [weak self] in
            self?.clubCommunityPendingOutcomeQueryOverride ?? ClubCommunityDormantPendingOutcomeQuery()
        })
    )
    func currentClubPostImageUploadContext(clubID: Int, postID: Int?) -> ClubPostImageUploadContext? {
        guard let account, token != nil, let namespace = storageScope?.service else { return nil }
        return try? ClubPostImageUploadContext(
            accountID: account.id,
            epoch: gate.currentStamp,
            namespace: namespace,
            clubID: clubID,
            postID: postID
        )
    }
    func selectClubPostImageUploadApproval(clubID: Int) -> ClubPostImageUploadApproval? {
        guard let runtimeContext = currentRuntimeDependencyContext,
              let uploadContext = currentClubPostImageUploadContext(clubID: clubID, postID: nil),
              let configuration = regionalConfiguration?.apiConfiguration,
              let approval = clubPostImageUploadApprovalSelector(runtimeContext, clubID)
                  ?? composition.clubPostImageUploadApproval(runtimeContext, clubID),
              approval.matches(baseURL: configuration.baseURL, context: uploadContext) else {
            return nil
        }
        return approval
    }
    func makeClubPostImagePickerContext() -> ClubPostImagePickerContext {
        ClubPostImagePickerContext(
            makePickerForClub: { [weak self] clubID, postID in
                guard let self else { return ClubPostDisabledImagePicker() }
                return ClubPostNativeImagePicker(
                    host: self.retainedImagePickerHost,
                    permitted: { [weak self] in
                        guard let self,
                              self.currentClubPostImageUploadContext(clubID: clubID, postID: postID) != nil,
                              let approval = self.selectClubPostImageUploadApproval(clubID: clubID) else {
                            return false
                        }
                        return approval.nativePicker
                    }
                )
            },
            makeUploaderForClub: { [weak self] clubID, postID in
                guard let self,
                      let configuration = self.regionalConfiguration?.apiConfiguration else {
                    return ClubPostImageDisabledUploader()
                }
                let transport = self.compositionTransport
                    .scopedForClubPostImageUpload(clubID: clubID)
                    .replacingUnderlying(self.composition.makeClubPostImageUploadTransport())
                return ClubPostImageUploadClient(
                    configuration: configuration,
                    transport: transport,
                    currentContext: { [weak self] in
                        self?.currentClubPostImageUploadContext(clubID: clubID, postID: postID)
                    },
                    currentToken: { [weak self] in self?.token },
                    currentApproval: { [weak self] in
                        self?.selectClubPostImageUploadApproval(clubID: clubID)
                    }
                )
            },
            currentUploadContext: { [weak self] clubID, postID in
                self?.currentClubPostImageUploadContext(clubID: clubID, postID: postID)
            }
        )
    }
    var clubCommunityContext: ClubCommunityContext {
        ClubCommunityContext(
            service: communityService,
            currentSession: { [weak self] in
                guard let self else { throw ClubCommunityFailure.unavailable }; return try self.currentCommunitySession()
            },
            coordinator: communityCoordinator,
            evidence: { [weak self] clubID, post, comment in
                guard let self else { throw ClubCommunityFailure.unavailable }
                return try await self.communityEvidence(clubID: clubID, post: post, comment: comment)
            },
            postImagePicker: makeClubPostImagePickerContext()
        )
    }
    private func communityEvidence(clubID: Int, post: ClubCommunityPost?, comment: ClubCommunityComment?) async throws -> ClubCommunityEvidence {
        let captured = try currentCommunitySession()
        let membership = try await clubDetail(id: clubID)
        guard membership.id == clubID, try currentCommunitySession() == captured else { throw ClubCommunityFailure.stale }
        var freshPost: ClubCommunityPost?
        var freshComment: ClubCommunityComment?
        if let post {
            let page = try await communityService.read(.posts(clubID: clubID, page: 1), session: captured) {
                guard try self.currentCommunitySession() == captured else { throw ClubCommunityFailure.stale }
            }
            guard let exact = page.posts.first(where: { $0.id == post.id }), exact.clubID == clubID else { throw ClubCommunityFailure.stale }
            freshPost = exact
            if let comment {
                let comments = try await communityService.read(.comments(postID: exact.id, page: 1), session: captured) {
                    guard try self.currentCommunitySession() == captured else { throw ClubCommunityFailure.stale }
                }
                guard let exactComment = comments.comments.first(where: { $0.id == comment.id }), exactComment.postID == exact.id else { throw ClubCommunityFailure.stale }
                freshComment = exactComment
            }
        } else if comment != nil { throw ClubCommunityFailure.invalid }
        guard try currentCommunitySession() == captured else { throw ClubCommunityFailure.stale }
        return .init(identity: captured.identity, clubID: clubID, joined: membership.isJoined, owner: membership.isOwner,
            administrator: membership.viewerIsAdmin, post: freshPost, comment: freshComment)
    }
    // Independent personal-sharing approvals. Restoring metadata never grants location access.
    private var personalLocationShareReadApproval: PersonalLocationShareEndpointApproval? = nil
    private var personalLocationShareWriteApproval: PersonalLocationShareEndpointApproval? = nil
    private var personalLocationShareCaptureApproval: PersonalLocationShareCaptureApproval? = nil
    /// Reviewed installation seam; revocation/replacement first retires the old service and sensor synchronously.
    func installReviewedPersonalLocationShareApprovals(read: PersonalLocationShareEndpointApproval?,
        write: PersonalLocationShareEndpointApproval?, capture: PersonalLocationShareCaptureApproval?) throws {
        if let capture, capture.scope != personalLocationShareScope { throw PersonalLocationShareFailure.staleSession }
        retainedPersonalLocationShareHost?.sessionWillChange()
        personalLocationShareReadApproval = read
        personalLocationShareWriteApproval = write
        personalLocationShareCaptureApproval = capture
    }
    private var personalLocationShareEpoch: UInt64 = 0
    private var retainedPersonalLocationShareHost: PersonalLocationShareHost?
    var personalLocationShareScope: PersonalLocationShareScope? {
        guard let account, let token, !token.isEmpty, let namespace = storageScope?.service,
              let baseURL = regionalConfiguration?.apiConfiguration?.baseURL, baseURL.scheme == "https",
              baseURL.user == nil, baseURL.password == nil, baseURL.query == nil, baseURL.fragment == nil else { return nil }
        return try? .init(namespace: namespace + "|" + baseURL.absoluteString,
                          accountId: Int64(account.id), epoch: personalLocationShareEpoch)
    }
    private final class UnavailablePersonalLocationJournal: PersonalLocationShareJournaling {
        func records(scope: PersonalLocationShareScope) throws -> [PersonalLocationSharePendingRecord] { throw PersonalLocationShareFailure.journalUnavailable }
        func put(_ record: PersonalLocationSharePendingRecord, scope: PersonalLocationShareScope) throws { throw PersonalLocationShareFailure.journalUnavailable }
        func remove(requestKey: String, scope: PersonalLocationShareScope) throws { throw PersonalLocationShareFailure.journalUnavailable }
    }
    private lazy var personalLocationShareJournal: any PersonalLocationShareJournaling = {
        guard let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return UnavailablePersonalLocationJournal()
        }
        return PersonalLocationShareFileJournal(directory: root.appendingPathComponent("PersonalLocationSharePending", isDirectory: true))
    }()
    var personalLocationShareHost: PersonalLocationShareHost {
        if let retainedPersonalLocationShareHost { return retainedPersonalLocationShareHost }
        let host = PersonalLocationShareHost(
            baseURL: { [weak self] in self?.regionalConfiguration?.apiConfiguration?.baseURL },
            currentScope: { [weak self] in self?.personalLocationShareScope },
            token: { [weak self] in self?.token }, journal: personalLocationShareJournal,
            readApproval: { [weak self] in self?.personalLocationShareReadApproval },
            writeApproval: { [weak self] in self?.personalLocationShareWriteApproval },
            captureApproval: { [weak self] in self?.personalLocationShareCaptureApproval })
        retainedPersonalLocationShareHost = host
        return host
    }
    private func invalidatePersonalLocationShare() {
        // Shut down under the old identity before replacing account/token; never delete its journal.
        retainedPersonalLocationShareHost?.sessionWillChange()
        personalLocationShareEpoch &+= 1
        personalLocationShareReadApproval = nil
        personalLocationShareWriteApproval = nil
        personalLocationShareCaptureApproval = nil
    }

    private var gate = SessionOperationGate() { didSet { if oldValue.currentStamp != gate.currentStamp { invalidatePersonalLocationShare() }; retainedSocialMemberActions?.synchronizeSession(); synchronizePrivateHome(); synchronizeOwnerDraftBrowser() } }
    private let vault: any AppTokenStorage
    private let composition: AppCompositionRoot
    private let compositionTransport: CompositionHTTPTransport
    private var compositionViewerRevision: UInt64 = 0
    private var sessionDefaults: UserDefaults { composition.storage.defaults }
    private let storageScope:RegionalSessionStorageScope?
    let regionalConfiguration:RegionalConfiguration?
    var operationalMarket:RegionalMarket? { regionalConfiguration?.market ?? RegionalLaunchConfiguration.market }
    var canUsePassword:Bool { storageScope != nil && regionalConfiguration?.availability(of:.usernamePassword) == .available }
    var supportsDomesticPhoneInput:Bool { operationalMarket == .china }
    private let service: AuthService?
    private let accountSessionService: CNAccountSessionService?
    private let activityService: ActivityService?
    private let searchMapService: SearchMapService?
    private let mapPublicLayerService: MapPublicLayerService?
    private let searchMapSelection = ManualMapAreaSelection()
    private let roamMapSelection = ManualMapAreaSelection()
    private var currentSearchMapContext: SearchMapContext {
        if let account, let token, let context = try? SearchMapContext(accountID: account.id, epoch: gate.currentStamp, token: token, role: account.effectiveRole, viewerRevision: compositionViewerRevision, manualMapApprovalRevision: currentManualMapApprovalRevision) { return context }
        return SearchMapContext(guestEpoch: gate.currentStamp)
    }
    /// Re-evaluate current approval at the reader/UI boundary as well as the raw transport.
    /// Service decode/fan-out can suspend after an individual transport returns.
    private var currentManualMapApprovalRevision: UUID? {
        guard composition.reviewed?.reads.contains(.manualMap) == true,
              let context = currentRuntimeDependencyContext,
              let approval = composition.manualMapReadApproval(context), approval.matches(context) else { return nil }
        return approval.revision
    }
    private var isMapPublicLayerReadApproved: Bool {
        guard composition.reviewed?.reads.isDisjoint(with: [.manualMap, .publicMapLayers]) == false,
              let context = currentRuntimeDependencyContext,
              let approval = composition.mapPublicLayerReadApproval(context), approval.matches(context) else { return false }
        return true
    }
    var searchMapHistoryNamespace: String? {
        guard let storageScope else { return nil }
        return storageScope.service + ".search." + (account.map { String($0.id) } ?? "guest")
    }
    lazy var mapPublicLayerCoordinator = MapPublicLayerCoordinator(service: mapPublicLayerService, currentContext: { [weak self] in
        self?.currentSearchMapContext ?? SearchMapContext(guestEpoch: 0)
    }, isApproved: { [weak self] in
        self?.isMapPublicLayerReadApproved == true
    }, onUnauthorized: { [weak self] captured in
        guard let self, self.currentSearchMapContext == captured else { return }
        self.expireIfMatching(error: APIError.unauthorized, stamp: captured.epoch, credential: self.token)
    }, manualAreaSelection: searchMapSelection)
    lazy var searchMapReader = SearchMapSessionReader(service: searchMapService, currentContext: { [weak self] in
        self?.currentSearchMapContext ?? SearchMapContext(guestEpoch: 0)
    }, onUnauthorized: { [weak self] captured in
        guard let self, self.currentSearchMapContext == captured else { return }
        self.expireIfMatching(error: APIError.unauthorized, stamp: captured.epoch, credential: self.token)
    }, manualAreaSelection: searchMapSelection, publicLayerCoordinator: mapPublicLayerCoordinator, topicReader: topicReader)
    private let registrationApproval: RegistrationProductionApproval?
    private let registrationStorefront: () -> String?
    private var registrationJournal: any OperationPendingJournal { composition.storage.operationJournal() }
    private var currentRegistrationProductionSession: RegistrationProductionSession? {
        guard let identity = profileReader.identity, let namespace = storageScope?.service,
              let market = regionalConfiguration?.market, let storefront = registrationStorefront(), let token else { return nil }
        return try? .init(identity: identity, namespace: namespace, market: market, storefront: storefront, token: token)
    }
    private lazy var productionRegistrationService: RegistrationProductionService? = {
        guard let configuration = regionalConfiguration?.apiConfiguration else { return nil }
        return RegistrationProductionFactory.make(configuration: configuration, approval: registrationApproval,
            journal: registrationJournal, current: { [weak self] in self?.currentRegistrationProductionSession })
    }()
    func registrationWaitlistService(activityID: Int) -> (any RegistrationWaitlistServing)? {
        guard case .approved = registrationCreationPolicy(activityID: activityID) else { return nil }
        return productionRegistrationService
    }
    func registrationCreationPolicy(activityID: Int) -> RegistrationUICreationPolicy {
        guard let service = productionRegistrationService, let current = currentRegistrationProductionSession,
              current.identity == service.approval.identity, current.storefront == service.approval.storefront,
              current.market == service.approval.market, current.namespace == service.approval.endpoint.namespace,
              activityID == service.approval.activityID, Date() < service.approval.expiresAt else { return .disabled }
        return .approved(service.approval)
    }
    private let registrationBackend: any RegistrationCoordinatingService
    private var registrationIdentity: ProfileReadIdentity?
    private lazy var retainedRegistration: RegistrationCoordinator = {
        let backend: any RegistrationCoordinatingService = productionRegistrationService.map { $0 as any RegistrationCoordinatingService } ?? registrationBackend
        return RegistrationCoordinator(service: backend)
    }()
    var registrationCoordinator: RegistrationCoordinator { synchronizeRegistration();return retainedRegistration }
    private func synchronizeRegistration() {
        let identity=profileReader.identity
        guard registrationIdentity != identity else { return }
        registrationIdentity=identity
        if let identity,let token { try? retainedRegistration.setAccount(id:identity.accountID,token:token) }
        else { retainedRegistration.clearAccount() }
    }
    // Shop NPC remains node-addressed and dormant. No grant derives from a role/name/image.
    private let shopNPCSessionOwner = ShopNPCSessionOwner()
    private var shopNPCGrants: ShopNPCGrants { runtimeDependencyFactory?.accepted != nil ? runtimeDependencies.shopNPCGrants : ShopNPCGrants() }
    private var shopNPCProductionWritesEnabled: Bool { runtimeDependencyFactory?.accepted?.shopNPCWrites == true }
    func invalidateShopNPCConversations() { shopNPCSessionOwner.invalidate() }
    private func currentShopNPCSession(scope: PlaySessionScope, nodeID: Int,
                                       runtime: PlayExperienceCoordinator, npc: PlayNPCBrief) -> ShopNPCHostSession? {
        guard scope.isValid, runtime.scope == scope, runtime.hasCurrentMediaSnapshot,
              let snapshot = runtime.snapshot, snapshot.availability == .active,
              let node = snapshot.visibleNodes.first(where: { $0.id == nodeID }),
              !snapshot.isLocked(node), node.npc == npc,
              let nodeID = ShopNPCNodeID(nodeID), let account, let token,
              let namespace = storageScope?.service, regionalConfiguration?.apiConfiguration != nil else { return nil }
        let kind: String
        switch scope { case .activity: kind = "activity"; case .topic: kind = "topic" }
        let binding = ShopNPCScope(sessionID: "\(namespace):\(gate.currentStamp):\(kind):\(scope.id)",
            accountID: String(account.id), roleID: account.effectiveRole,
            accessRevision: shopNPCSessionOwner.accessRevision, nodeID: nodeID)
        return try? ShopNPCHostSession(scope: binding, token: token)
    }
    func shopNPCNodeHost(scope: PlaySessionScope, nodeID: Int, runtime: PlayExperienceCoordinator) -> ShopNPCNodeHost? {
        guard let npc = runtime.snapshot?.visibleNodes.first(where: { $0.id == nodeID })?.npc,
              let captured = currentShopNPCSession(scope: scope, nodeID: nodeID, runtime: runtime, npc: npc),
              let configuration = regionalConfiguration?.apiConfiguration else { return nil }
        let identity = "\(captured.scope.sessionID):\(captured.scope.accountID):\(captured.scope.roleID):\(captured.scope.accessRevision):\(nodeID):\(npc.name):\(npc.greeting ?? "")"
        let fallbackTransport = runtimeHTTPTransport
        return ShopNPCNodeHost(identity: identity, name: npc.name, greeting: npc.greeting, makeCoordinator: { [weak self, weak runtime] in
            let current: () -> ShopNPCHostSession? = { [weak self, weak runtime] in
                guard let self, let runtime else { return nil }
                return self.currentShopNPCSession(scope: scope, nodeID: nodeID, runtime: runtime, npc: npc)
            }
            let adapter = ShopNPCAuthenticatedHTTPTransport(configuration: configuration, transport: self?.runtimeDependencyFactory?.transport ?? RuntimeDependencyTransport(configuration: nil, captured: nil, transport: fallbackTransport, current: { nil }),
                productionWritesEnabled: self?.shopNPCProductionWritesEnabled ?? false, currentSession: current,
                currentGrants: { [weak self] in self?.shopNPCGrants ?? .init() },
                onUnauthorized: { [weak self] old in
                    guard let self, current() == old else { return }
                    self.expireIfMatching(error: APIError.unauthorized, stamp: self.gate.currentStamp, credential: self.token)
                })
            let coordinator = ShopNPCCoordinator(scope: captured.scope, grants: self?.shopNPCGrants ?? .init(),
                client: ShopNPCHTTPClient(transport: adapter))
            self?.shopNPCSessionOwner.register(coordinator)
            // Re-resolve node data and identity at navigation time; a stale destination fails closed.
            if current() != captured { coordinator.invalidate() }
            return coordinator
        })
    }

    private var currentPlayerJourneySession: PlayerJourneySession? {
        guard let account, let token, let namespace = storageScope?.service else { return nil }
        return try? PlayerJourneySession(accountID: account.id, epoch: gate.currentStamp, namespace: namespace, token: token)
    }
    lazy var playerJourneyReader = PlayerJourneySessionReader(service: regionalConfiguration?.apiConfiguration.map {
        PlayerJourneyService(configuration: $0, transport: runtimeHTTPTransport)
    }, currentSession: { [weak self] in self?.currentPlayerJourneySession }, onUnauthorized: { [weak self] captured in
        guard let self, self.currentPlayerJourneySession == captured else { return }
        self.expireIfMatching(error: APIError.unauthorized, stamp: captured.epoch, credential: self.token)
    }) // Dedicated history read grant remains off until independently accepted.
    private struct PlayReadApprovalKey: Hashable { let issuance: UUID; let paths: Set<String> }
    /// Called at construction and final projection, outside service decode work as well.
    private var currentPlayReadApprovalKey: PlayReadApprovalKey? {
        guard composition.reviewed?.reads.contains(.playNodesAndRouteState) == true,
              let context = currentRuntimeDependencyContext,
              let approval = compositionTransport.playReadConfiguration(context),
              let issuance = approval.playReadApprovalID,
              approval.matches(context), approval.play.contains(.reads),
              approval.endpoints.paths.contains("api/play/nodes") else { return nil }
        return .init(issuance: issuance,
            paths: approval.endpoints.paths.intersection(["api/play/nodes", "api/play/route-state"]))
    }
    private var playReadDependencyFactory: RuntimeDependencyFactory? {
        guard let api = regionalConfiguration?.apiConfiguration, let context = currentRuntimeDependencyContext else { return nil }
        return RuntimeDependencyFactory(api: api, configuration: compositionTransport.playReadConfiguration(context),
            transport: compositionTransport, current: { [weak self] in self?.currentRuntimeDependencyContext })
    }
    private var playService: PlayService? {
        guard currentPlayReadApprovalKey != nil,
              composition.reviewed?.reads.contains(.playNodesAndRouteState) == true,
              let api = regionalConfiguration?.apiConfiguration,
              let factory = playReadDependencyFactory, factory.accepted?.play.contains(.reads) == true else { return nil }
        return PlayService(configuration: api, transport: factory.transport)
    }
    private struct PlayReaderKey: Hashable { let accountID:Int?;let epoch:UInt64;let role:String?;let viewerRevision:UInt64;let approval:PlayReadApprovalKey?;let scope:PlaySessionScope }
    private var playReaders:[PlayReaderKey:PlaySessionReader]=[:]
    func playReader(for scope:PlaySessionScope) -> PlaySessionReader {
        let key=PlayReaderKey(accountID:account?.id,epoch:gate.currentStamp,role:account?.effectiveRole,viewerRevision:compositionViewerRevision,approval:currentPlayReadApprovalKey,scope:scope)
        if let reader=playReaders[key] { return reader }
        let reader=PlaySessionReader(scope:scope,service:playService,answersEnabled:false,currentSession:{ [weak self] in
            guard let self, self.compositionViewerRevision == key.viewerRevision,
                  key.approval != nil, self.currentPlayReadApprovalKey == key.approval,
                  let account=self.account,let token=self.token else { return nil }
            return try? PlayReadSession(accountID:account.id,epoch:self.gate.currentStamp,token:token)
        },onUnauthorized:{ [weak self] snapshot in
            guard let self, self.compositionViewerRevision == key.viewerRevision,
                  key.approval != nil, self.currentPlayReadApprovalKey == key.approval else { return }
            self.expireIfMatching(error:APIError.unauthorized,stamp:snapshot.epoch,credential:self.token)
        })
        playReaders[key]=reader
        return reader
    }
    // Retained owner/scope-bound durable recovery; all normal-root write grants stay off.
    private var playExperienceCoordinators: [PlayReaderKey: PlayExperienceCoordinator] = [:]
    func playExperience(for scope: PlaySessionScope) -> PlayExperienceCoordinator? {
        guard scope.isValid, let regional = regionalConfiguration,
              let configuration = regional.apiConfiguration, let storageScope else { return nil }
        let key = PlayReaderKey(accountID: account?.id, epoch: gate.currentStamp, role: account?.effectiveRole, viewerRevision: compositionViewerRevision, approval: currentPlayReadApprovalKey, scope: scope)
        if let retained = playExperienceCoordinators[key] { return retained }
        guard key.approval != nil, composition.reviewed?.reads.contains(.playNodesAndRouteState) == true,
              let factory = playReadDependencyFactory, factory.accepted?.play.contains(.reads) == true else { return nil }
        // One selector supplies both the captured storage owner and every later callback.
        // Keep the issuance and ABA fences even when the same account/role returns.
        let current: () -> PlayExperienceSession? = { [weak self] in
            guard let self, !self.committingAuthenticatedSession,
                  self.compositionViewerRevision == key.viewerRevision,
                  key.approval != nil, self.currentPlayReadApprovalKey == key.approval,
                  let account = self.account, let token = self.token,
                  let role = PlayRecoveryAccountRole(rawValue: account.effectiveRole) else { return nil }
            return try? PlayExperienceSession(accountID: account.id, epoch: self.gate.currentStamp,
                namespace: storageScope.service, token: token, role: role.rawValue)
        }
        guard let captured = current(),
              let recovery = try? composition.storage.playRecovery.make(session: captured, scope: scope,
                regionalConfiguration: regional, storageScope: storageScope),
              current() == captured else { return nil }
        // The normal root admits only progress reads. Durable recovery does not grant writes.
        let api = PlayExperienceService(configuration: configuration, transport: factory.transport,
            enabled: factory.accepted?.play.intersection([.reads]) ?? [])
        let coordinator = PlayExperienceCoordinator(scope: scope, service: api,
            recovery: recovery, pausedStorage: recovery,
            currentSession: { current() == captured ? captured : nil },
            onUnauthorized: { [weak self] snapshot in
                guard let self, snapshot == captured, current() == captured else { return }
                self.expireIfMatching(error: APIError.unauthorized, stamp: captured.epoch, credential: captured.token)
            })
        playExperienceCoordinators[key] = coordinator
        registerPlayContinuationScope(scope)
        return coordinator
    }
    // w2-19 source pages/play/merchant: store-day reads share the play read approval; every write gate stays off.
    func playStoreDay(scope: PlaySessionScope, nodeID: Int, registrationID: Int = 0, justScanned: Bool = false) -> PlayStoreDayCoordinator? {
        let key = PlayReaderKey(accountID: account?.id, epoch: gate.currentStamp, role: account?.effectiveRole, viewerRevision: compositionViewerRevision, approval: currentPlayReadApprovalKey, scope: scope)
        guard scope.isValid, nodeID > 0, key.approval != nil, let regional = regionalConfiguration, let api = regional.apiConfiguration,
              let factory = playReadDependencyFactory, factory.accepted?.play.contains(.reads) == true else { return nil }
        let service = PlayStoreDayService(configuration: api, transport: factory.transport, market: regional.market, gates: .disabled, readsEnabled: true,
            currentSession: { [weak self] in
                guard let self, self.playStoreDayFence(key), let account = self.account, let token = self.token else { return nil }
                return try? PlayStoreDaySession(accountID: account.id, epoch: self.gate.currentStamp, token: token)
            },
            onUnauthorized: { [weak self] snapshot in
                guard let self, self.playStoreDayFence(key) else { return }
                self.expireIfMatching(error: APIError.unauthorized, stamp: snapshot.epoch, credential: self.token)
            })
        return PlayStoreDayCoordinator(nodeID: nodeID, scope: scope, registrationID: registrationID, justScanned: justScanned, service: service)
    }
    /// Same viewer-revision and play-read-issuance ABA fence as the play readers above.
    private func playStoreDayFence(_ key: PlayReaderKey) -> Bool {
        key.approval != nil && compositionViewerRevision == key.viewerRevision && currentPlayReadApprovalKey == key.approval
    }
    /// Read-only character card. Approval is the character and rpg/status paths, captured with issuance.
    func characterCardReadback(topicID: Int, activityID: Int?, scope: PlaySessionScope) -> CharacterCardReadback? {
        guard topicID > 0, characterCardScopeMatches(topicID: topicID, activityID: activityID, scope: scope),
              let regional = regionalConfiguration,
              let configuration = regional.apiConfiguration, let storageScope,
              let factory = playReadDependencyFactory, factory.accepted?.play.contains(.reads) == true,
              let approval = characterCardReadApproval else { return nil }
        let current: () -> PlayExperienceSession? = { [weak self] in
            guard let self, !self.committingAuthenticatedSession,
                  self.compositionViewerRevision == approval.viewerRevision,
                  self.characterCardReadApproval == approval,
                  let account = self.account, let token = self.token,
                  let role = PlayRecoveryAccountRole(rawValue: account.effectiveRole) else { return nil }
            return try? PlayExperienceSession(accountID: account.id, epoch: self.gate.currentStamp,
                namespace: storageScope.service, token: token, role: role.rawValue)
        }
        let api = PlayExperienceService(configuration: configuration, transport: factory.transport,
            enabled: factory.accepted?.play.intersection([.reads]) ?? [])
        return CharacterCardReadback(topicID: topicID, activityID: activityID, service: api, currentSession: current,
            onUnauthorized: { [weak self] snapshot in
                guard let self, self.characterCardReadApproval == approval,
                      self.compositionViewerRevision == approval.viewerRevision,
                      current() == snapshot else { return }
                self.expireIfMatching(error: APIError.unauthorized, stamp: snapshot.epoch, credential: snapshot.token)
            })
    }
    private struct CharacterCardReadApproval: Equatable { let issuance: UUID; let viewerRevision: UInt64 }
    private var characterCardReadApproval: CharacterCardReadApproval? {
        guard let context = currentRuntimeDependencyContext,
              let approval = compositionTransport.playReadConfiguration(context),
              let issuance = approval.playReadApprovalID,
              approval.matches(context), approval.play.contains(.reads),
              approval.endpoints.paths.isSuperset(of: CharacterCardReadRoute.paths) else { return nil }
        return .init(issuance: issuance, viewerRevision: compositionViewerRevision)
    }
    private func characterCardScopeMatches(topicID: Int, activityID: Int?, scope: PlaySessionScope) -> Bool {
        switch scope {
        case .topic(let id): return activityID == nil && id == topicID
        case .activity(let id): return activityID == id && id > 0
        }
    }
    // Journey extras are independent of task completion, advanced games and local dice.
    private var retainedJourneyNarratives: [String: JourneyNarrativeCoordinator] = [:]
    var journeyNarrativeImageReader: (any RetainedPublicImageReading)? { runtimeDependencies.journeyNarrativeImageReader }
    private lazy var journeyNarrativeJournal = JourneyStoredNarrativeJournal(
        read: { [weak self] key in try self?.templateAuthoringSecureStorage.read(key) },
        write: { [weak self] data, key in
            guard let self else { throw APIError.notConfigured }
            try self.templateAuthoringSecureStorage.write(data, key: key)
        })
    func journeyNarrative(scope: PlaySessionScope, topicID: Int?, query: JourneyNarrativeQuery) -> JourneyNarrativeCoordinator? {
        guard let topicID, let target = try? JourneyNarrativeScope(scope: scope, topicID: topicID),
              let factory = runtimeDependencyFactory else { return nil }
        let key = playRuntimeKey(scope, suffix: "journey-narrative:\(topicID):\(query.key)")
        if let model = retainedJourneyNarratives[key] { model.synchronize(); return model }
        let model = JourneyNarrativeCoordinator(scope: target, query: query, service: factory.journeyNarrativeService(),
            journal: journeyNarrativeJournal, currentSession: { [weak self] in self?.currentPlayRuntimeSession },
            onUnauthorized: { [weak self] captured in
                guard let self else { return }
                self.expireIfMatching(error: APIError.unauthorized, stamp: captured.epoch, credential: captured.token)
            })
        retainedJourneyNarratives[key] = model; return model
    }
    private var retainedJourneyChecks: [String: JourneyCheckCoordinator] = [:]
    private var retainedJourneyAmbient: [String: JourneyAmbientCoordinator] = [:]
    private lazy var journeySeenStore = JourneyPersistentEggSeenStorage(
        read: { [weak self] key in try self?.templateAuthoringSecureStorage.read(key) },
        write: { [weak self] data, key in
            guard let self else { throw APIError.notConfigured }
            try self.templateAuthoringSecureStorage.write(data, key: key)
        })
    private lazy var journeyCheckJournal = JourneyStoredCheckJournal(
        read: { [weak self] key in try self?.templateAuthoringSecureStorage.read(key) },
        write: { [weak self] data, key in
            guard let self else { throw APIError.notConfigured }
            try self.templateAuthoringSecureStorage.write(data, key: key)
        })
    private func dormantJourneyService() -> JourneyContentService? {
        guard regionalConfiguration?.apiConfiguration != nil, storageScope != nil else { return nil }
        return runtimeDependencyFactory?.journeyService()
    }
    func journeyCheck(scope: PlaySessionScope, topicID: Int?, nodeID: Int) -> JourneyCheckCoordinator? {
        guard scope.isValid, let topicID, topicID > 0, nodeID > 0, let service = dormantJourneyService() else { return nil }
        let key = playRuntimeKey(scope, suffix: "journey:\(topicID):\(nodeID)")
        if let model = retainedJourneyChecks[key] { model.synchronize(); return model }
        let model = JourneyCheckCoordinator(scope: scope, topicID: topicID, nodeID: nodeID, service: service,
            journal: journeyCheckJournal, currentSession: { [weak self] in self?.currentPlayRuntimeSession },
            onUnauthorized: { [weak self] captured in
                guard let self else { return }
                self.expireIfMatching(error: APIError.unauthorized, stamp: captured.epoch, credential: captured.token)
            })
        retainedJourneyChecks[key] = model; return model
    }
    func journeyAmbient(scope: PlaySessionScope) -> JourneyAmbientCoordinator? {
        guard scope.isValid, let service = dormantJourneyService() else { return nil }
        let key = playRuntimeKey(scope, suffix: "journey-ambient")
        if let model = retainedJourneyAmbient[key] { model.synchronize(); return model }
        let model = JourneyAmbientCoordinator(scope: scope, service: service, store: journeySeenStore,
                                            currentSession: { [weak self] in self?.currentPlayRuntimeSession })
        retainedJourneyAmbient[key] = model; return model
    }

    private var retainedPlayAdvanced: [String: PlayAdvancedCoordinator] = [:]
    private var retainedPlayPreferences: [String: PlayPreferenceCoordinator] = [:]
    private var retainedPlaySummaries: [String: PlayOperatingSummaryCoordinator] = [:]
    private var retainedPlayDirectors: [String: PlayDirectorCoordinator] = [:]
    private var retainedPlayPrefabs: [String: PlayPrefabRuntimeCoordinator] = [:]
    private lazy var prefabRuntimeStore = PlayPrefabRuntimeStore(storage: templateAuthoringSecureStorage)
    private let workshopOwnedBinding = WorkshopOwnedSessionBinding()
    private let workshopPurchasedBinding = WorkshopPurchasedSessionBinding()
    private let workshopCreatorPendingBinding = WorkshopCreatorPendingSessionBinding()
    private let workshopCreatorConsentBinding = WorkshopCreatorConsentSessionBinding()
    private let workshopPaidProfessionalBinding = WorkshopPaidProfessionalSessionBinding()
    private let workshopPaidInstalledTextBinding = WorkshopPaidInstalledTextSessionBinding()
    private let workshopPaidInstallBinding = WorkshopPaidInstallSessionBinding()
    private func invalidateWorkshopReadBindings() { workshopCreatorPendingBinding.invalidate(); workshopCreatorConsentBinding.invalidate(); workshopPaidProfessionalBinding.invalidate(); workshopOwnedBinding.invalidate(); workshopPurchasedBinding.invalidate(); workshopPaidInstallBinding.invalidate(); workshopPaidInstalledTextBinding.invalidate() }
    @Published private var workshopOwnedPresentationActive = true
    private var workshopReadConfigurationChanging = false
    private var currentWorkshopOwnedContext: RuntimeDependencyContext? {
        guard workshopOwnedPresentationActive, !workshopReadConfigurationChanging else { return nil }
        return currentRuntimeDependencyContext
    }
    func setWorkshopOwnedPresentationActive(_ active: Bool) {
        if !active { invalidateWorkshopReadBindings() }
        workshopOwnedPresentationActive = active
    }
    @Published private var workshopReadConfigurationRevision: UInt64 = 0
    private var currentWorkshopOwnedApproval: WorkshopOwnedReadApproval? {
        guard let context = currentWorkshopOwnedContext,
              let approval = composition.workshopOwnedReadApproval(context), approval.matches(context) else { return nil }
        return approval
    }
    private var currentWorkshopPurchasedApproval: WorkshopPurchasedReadApproval? {
        guard let context = currentWorkshopOwnedContext,
              let approval = composition.workshopPurchasedReadApproval(context), approval.matches(context) else { return nil }
        return approval
    }
    private var currentWorkshopPaidInstallApproval: WorkshopPaidInstallApproval? {
        guard let context = currentWorkshopOwnedContext,
              let approval = composition.workshopPaidInstallApproval(context), approval.matches(context) else { return nil }
        return approval
    }
    /// Narrow canonical context for this protected read only. Preserve the existing viewer role
    /// whitelist; do not change shared play factories or infer a role from a purchase.
    private var currentWorkshopPaidInstalledTextContext: RuntimeDependencyContext? {
        guard let context = currentWorkshopOwnedContext, ["player", "club", "merchant"].contains(context.role),
              let session = try? PlayExperienceSession(accountID: context.session.accountID, epoch: context.session.epoch,
                namespace: context.session.namespace, token: context.session.token, role: context.role) else { return nil }
        return RuntimeDependencyContext(market: context.market, baseURL: context.baseURL, role: context.role, session: session)
    }
    private var currentWorkshopPaidInstalledTextApproval: WorkshopPaidInstalledTextApproval? {
        guard let context = currentWorkshopPaidInstalledTextContext,
              let approval = composition.workshopPaidInstalledTextApproval(context), approval.matches(context) else { return nil }
        return approval
    }
    @Published private var workshopCreatorConfigurationRevision: UInt64 = 0
    private var workshopCreatorConfigurationChanging = false
    private var currentWorkshopCreatorContext: RuntimeDependencyContext? {
        guard !workshopCreatorConfigurationChanging else { return nil }
        return currentWorkshopPaidInstalledTextContext
    }
    private var currentWorkshopCreatorRead: WorkshopCreatorConsentReadApproval? {
        guard let context = currentWorkshopCreatorContext, let grant = composition.workshopCreatorConsentReadApproval(context), grant.matches(context) else { return nil }
        return grant
    }
    private var currentWorkshopCreatorWrite: WorkshopCreatorConsentWriteApproval? {
        guard let context = currentWorkshopCreatorContext, let grant = composition.workshopCreatorConsentWriteApproval(context), grant.matches(context) else { return nil }
        return grant
    }
    /// Owners of injected grants/target descriptors must enter this boundary before replacement,
    /// including A → nil → A. No selector can recreate a controller during the callback.
    func withWorkshopCreatorConsentConfigurationChange(_ change: () -> Void) {
        workshopCreatorPendingBinding.invalidate(); workshopCreatorConsentBinding.invalidate(); workshopCreatorConfigurationChanging = true
        change(); workshopCreatorConfigurationChanging = false; workshopCreatorConfigurationRevision &+= 1
    }
    private var currentWorkshopCreatorPendingAuthor: WorkshopCreatorPendingAuthorApproval? {
        guard let context = currentWorkshopCreatorContext, let grant = composition.workshopCreatorPendingAuthorApproval(context), grant.matches(context) else { return nil }; return grant
    }
    private var currentWorkshopCreatorPendingList: WorkshopCreatorPendingListApproval? {
        guard let context = currentWorkshopCreatorContext, let grant = composition.workshopCreatorPendingListApproval(context), grant.matches(context) else { return nil }; return grant
    }
    private var currentWorkshopCreatorPendingDetail: WorkshopCreatorPendingDetailApproval? {
        guard let context = currentWorkshopCreatorContext, let grant = composition.workshopCreatorPendingDetailApproval(context), grant.matches(context) else { return nil }; return grant
    }
    private var workshopCreatorPendingRecoveryStorage: any TemplateAuthoringStorage {
#if DEBUG
        if let storage = composition.storage.syntheticWorkshopCreatorPendingRecoveryStorage { return storage }
#endif
        return templateAuthoringSecureStorage
    }
    func makeWorkshopCreatorPendingController(sourceTemplateId: Int64) -> WorkshopCreatorPendingController? {
        let context = currentWorkshopCreatorContext, read = currentWorkshopCreatorRead, write = currentWorkshopCreatorWrite
        let author = currentWorkshopCreatorPendingAuthor, list = currentWorkshopCreatorPendingList, detail = currentWorkshopCreatorPendingDetail
        let viewer = compositionViewerRevision, configuration = workshopCreatorConfigurationRevision, workshop = workshopReadConfigurationRevision
        let revisions = [read?.revision, write?.revision, author?.revision, list?.revision, detail?.revision]
        let current: () -> RuntimeDependencyContext? = { [weak self] in
            guard let self, self.compositionViewerRevision == viewer, self.workshopCreatorConfigurationRevision == configuration,
                  self.workshopReadConfigurationRevision == workshop,
                  [self.currentWorkshopCreatorRead?.revision, self.currentWorkshopCreatorWrite?.revision, self.currentWorkshopCreatorPendingAuthor?.revision,
                   self.currentWorkshopCreatorPendingList?.revision, self.currentWorkshopCreatorPendingDetail?.revision] == revisions else { return nil }
            return self.currentWorkshopCreatorContext
        }
        // Saved declaration status is owner/source metadata and needs only consent-read.
        // Author/list/detail grants remain independently necessary for their own operations.
        let available = read != nil
        return workshopCreatorPendingBinding.make(source: sourceTemplateId, context: available ? context : nil, revisions: revisions) { captured in
            guard let api = regionalConfiguration?.apiConfiguration,
                  let store = try? WorkshopCreatorPendingStore(storage: workshopCreatorPendingRecoveryStorage, context: captured, sourceTemplateId: sourceTemplateId),
                  let declarationStore = try? WorkshopCreatorConsentPendingStore(storage: workshopCreatorPendingRecoveryStorage, context: captured, sourceTemplateId: sourceTemplateId) else { return nil }
            let lease = ContentDraftSessionLease(context: captured, current: current)
            let unauthorized: (RuntimeDependencyContext) -> Void = { [weak self] context in
                guard let self, ContentDraftContextFence.matches(current(), context) else { return }
                self.expireIfMatching(error: APIError.unauthorized, stamp: context.session.epoch, credential: context.session.token)
            }
            let previewService = WorkshopCreatorConsentService(api: api, transport: compositionTransport, lease: lease, read: read, write: write,
                currentRead: { [weak self] in self?.currentWorkshopCreatorRead }, currentWrite: { [weak self] in self?.currentWorkshopCreatorWrite }, onUnauthorized: unauthorized)
            let service = WorkshopCreatorPendingService(api: api, transport: compositionTransport, lease: lease, author: author, list: list, detail: detail,
                currentAuthor: { [weak self] in self?.currentWorkshopCreatorPendingAuthor }, currentList: { [weak self] in self?.currentWorkshopCreatorPendingList },
                currentDetail: { [weak self] in self?.currentWorkshopCreatorPendingDetail }, onUnauthorized: unauthorized)
            return WorkshopCreatorPendingController(sourceTemplateId: sourceTemplateId, service: service, previewService: previewService, lease: lease, store: store, declarationStore: declarationStore,
                canReadProposals: { [weak self] in current() != nil && self?.currentWorkshopCreatorPendingList != nil && self?.currentWorkshopCreatorPendingDetail != nil },
                canAuthor: { [weak self] in current() != nil && self?.currentWorkshopCreatorPendingAuthor != nil }, makeConsent: { [weak self] target, matchesPreview in
                    guard let self, current() != nil,
                          let consentStore = try? WorkshopCreatorConsentPendingStore(storage: self.workshopCreatorPendingRecoveryStorage, context: captured, sourceTemplateId: sourceTemplateId) else { return nil }
                    let consentLease = ContentDraftSessionLease(context: captured, current: current)
                    let consentService = WorkshopCreatorConsentService(api: api, transport: self.compositionTransport, lease: consentLease, read: read, write: write,
                        currentRead: { [weak self] in self?.currentWorkshopCreatorRead }, currentWrite: { [weak self] in self?.currentWorkshopCreatorWrite }, onUnauthorized: unauthorized)
                    return WorkshopCreatorConsentController(sourceTemplateId: sourceTemplateId, service: consentService, lease: consentLease, store: consentStore,
                        targets: { current() == nil ? [] : [target] }, canWrite: { [weak self] in current() != nil && self?.currentWorkshopCreatorWrite != nil },
                        reviewMatchesPreview: matchesPreview)
                })
        }
    }
    func makeWorkshopCreatorConsentController(sourceTemplateId: Int64) -> WorkshopCreatorConsentController? {
        let context = currentWorkshopCreatorContext, read = currentWorkshopCreatorRead, write = currentWorkshopCreatorWrite
        let viewer = compositionViewerRevision, configuration = workshopCreatorConfigurationRevision, workshop = workshopReadConfigurationRevision
        let revisions = [read?.revision, write?.revision]
        let current: () -> RuntimeDependencyContext? = { [weak self] in
            guard let self, self.compositionViewerRevision == viewer, self.workshopCreatorConfigurationRevision == configuration,
                  self.workshopReadConfigurationRevision == workshop, [self.currentWorkshopCreatorRead?.revision, self.currentWorkshopCreatorWrite?.revision] == revisions else { return nil }
            return self.currentWorkshopCreatorContext
        }
        return workshopCreatorConsentBinding.make(source: sourceTemplateId, context: read == nil ? nil : context, revisions: revisions) { captured in
            guard let api = regionalConfiguration?.apiConfiguration,
                  let store = try? WorkshopCreatorConsentPendingStore(storage: templateAuthoringSecureStorage, context: captured, sourceTemplateId: sourceTemplateId) else { return nil }
            let lease = ContentDraftSessionLease(context: captured, current: current)
            let service = WorkshopCreatorConsentService(api: api, transport: compositionTransport, lease: lease, read: read, write: write,
                currentRead: { [weak self] in self?.currentWorkshopCreatorRead }, currentWrite: { [weak self] in self?.currentWorkshopCreatorWrite },
                onUnauthorized: { [weak self] context in
                    guard let self, ContentDraftContextFence.matches(current(), context) else { return }
                    self.expireIfMatching(error: APIError.unauthorized, stamp: context.session.epoch, credential: context.session.token)
                })
            return WorkshopCreatorConsentController(sourceTemplateId: sourceTemplateId, service: service, lease: lease, store: store,
                targets: { [weak self] in
                    guard let self, let context = current() else { return [] }
                    return self.composition.workshopCreatorDeclarationTargets(context, sourceTemplateId)
                }, canWrite: { [weak self] in current() != nil && self?.currentWorkshopCreatorWrite != nil })
        }
    }
    private var currentWorkshopPaidProfessionalReadApproval: WorkshopPaidProfessionalReadApproval? {
        guard let context = currentWorkshopPaidInstalledTextContext,
              let approval = composition.workshopPaidProfessionalReadApproval(context), approval.matches(context) else { return nil }; return approval
    }
    private var currentWorkshopPaidProfessionalWriteApproval: WorkshopPaidProfessionalWriteApproval? {
        guard let context = currentWorkshopPaidInstalledTextContext,
              let approval = composition.workshopPaidProfessionalWriteApproval(context), approval.matches(context) else { return nil }; return approval
    }
    /// Historical recovery needs only its own read grant. Fresh creation separately reuses the
    /// protected body and existing generic-target read approvals, then an explicit write grant.
    func makeWorkshopPaidProfessionalController(reference: WorkshopPaidInstalledTextReference) -> WorkshopPaidProfessionalController? {
        let context = currentWorkshopPaidInstalledTextContext, read = currentWorkshopPaidProfessionalReadApproval
        let write = currentWorkshopPaidProfessionalWriteApproval, body = currentWorkshopPaidInstalledTextApproval
        let install = currentWorkshopPaidInstallApproval, installContext = currentWorkshopOwnedContext
        let revisions = [read?.revision, write?.revision, body?.revision, install?.revision]
        let viewer = compositionViewerRevision, configurationRevision = workshopReadConfigurationRevision
        let current: () -> RuntimeDependencyContext? = { [weak self] in
            guard let self, self.compositionViewerRevision == viewer, self.workshopReadConfigurationRevision == configurationRevision,
                  [self.currentWorkshopPaidProfessionalReadApproval?.revision, self.currentWorkshopPaidProfessionalWriteApproval?.revision,
                   self.currentWorkshopPaidInstalledTextApproval?.revision, self.currentWorkshopPaidInstallApproval?.revision] == revisions else { return nil }
            return self.currentWorkshopPaidInstalledTextContext
        }
        return workshopPaidProfessionalBinding.make(reference: reference, context: read == nil ? nil : context, revisions: revisions) { captured in
            guard let api = regionalConfiguration?.apiConfiguration, let read, read.matches(captured), ContentDraftContextFence.matches(current(), captured),
                  let store = try? WorkshopPaidProfessionalPendingStore(storage: templateAuthoringSecureStorage, context: captured, reference: reference) else { return nil }
            let lease = ContentDraftSessionLease(context: captured, current: current)
            let unauthorized: (RuntimeDependencyContext) -> Void = { [weak self] old in
                guard let self, ContentDraftContextFence.matches(current(), captured), ContentDraftContextFence.matches(old, captured) else { return }
                self.expireIfMatching(error: APIError.unauthorized, stamp: captured.session.epoch, credential: captured.session.token)
            }
            let service = WorkshopPaidProfessionalService(api: api, transport: compositionTransport, lease: lease,
                readApproval: read, currentReadApproval: { [weak self] in self?.currentWorkshopPaidProfessionalReadApproval },
                writeApproval: write, currentWriteApproval: { [weak self] in self?.currentWorkshopPaidProfessionalWriteApproval }, onUnauthorized: unauthorized)
            var preparation: WorkshopPaidProfessionalPreparation?
            if let body, let install, let installContext {
                let bodyReader = WorkshopPaidInstalledTextService(api: api, transport: compositionTransport, lease: lease, approval: body,
                    currentApproval: { [weak self] in self?.currentWorkshopPaidInstalledTextApproval }, onUnauthorized: unauthorized)
                // Retain the existing generic-draft reader's exact context contract; do not change
                // every legacy play/install factory merely to construct this new professional UI.
                let oldCurrent: () -> RuntimeDependencyContext? = { [weak self] in guard current() != nil else { return nil }; return self?.currentWorkshopOwnedContext }
                let oldLease = ContentDraftSessionLease(context: installContext, current: oldCurrent)
                let installReader = WorkshopPaidInstallService(api: api, transport: compositionTransport, lease: oldLease, approval: install,
                    currentApproval: { [weak self] in self?.currentWorkshopPaidInstallApproval }, onUnauthorized: unauthorized)
                preparation = WorkshopPaidProfessionalPreparation(bodyReader: bodyReader, installReader: installReader)
            }
            return WorkshopPaidProfessionalController(reference: reference, service: service, preparation: preparation, store: store, lease: lease)
        }
    }
    func makeWorkshopPaidInstalledTextController(reference: WorkshopPaidInstalledTextReference) -> WorkshopPaidInstalledTextController? {
        let context = currentWorkshopPaidInstalledTextContext, approval = currentWorkshopPaidInstalledTextApproval
        let viewer = compositionViewerRevision, configurationRevision = workshopReadConfigurationRevision
        let current: () -> RuntimeDependencyContext? = { [weak self] in
            guard let self, self.compositionViewerRevision == viewer,
                  self.workshopReadConfigurationRevision == configurationRevision else { return nil }
            return self.currentWorkshopPaidInstalledTextContext
        }
        return workshopPaidInstalledTextBinding.make(reference: reference, context: context, approval: approval,
            api: regionalConfiguration?.apiConfiguration, transport: compositionTransport,
            currentApproval: { [weak self] in self?.currentWorkshopPaidInstalledTextApproval }, current: current,
            onUnauthorized: { [weak self] captured in
                guard let self, ContentDraftContextFence.matches(current(), captured) else { return }
                self.expireIfMatching(error: APIError.unauthorized, stamp: captured.session.epoch, credential: captured.session.token)
            })
    }
    /// Independent install protocol approval; neither paid metadata nor FREE read authority is used.
    func makeWorkshopPaidInstallController(item: WorkshopPurchasedItem) -> WorkshopPaidInstallController? {
        let context = currentWorkshopOwnedContext, approval = currentWorkshopPaidInstallApproval
        let viewer = compositionViewerRevision, configurationRevision = workshopReadConfigurationRevision
        let current: () -> RuntimeDependencyContext? = { [weak self] in
            guard let self, self.compositionViewerRevision == viewer,
                  self.workshopReadConfigurationRevision == configurationRevision else { return nil }
            return self.currentWorkshopOwnedContext
        }
        return workshopPaidInstallBinding.make(item: item, context: context, approval: approval,
            api: regionalConfiguration?.apiConfiguration, transport: compositionTransport, storage: templateAuthoringSecureStorage,
            currentApproval: { [weak self] in self?.currentWorkshopPaidInstallApproval }, current: current,
            onUnauthorized: { [weak self] captured in
                guard let self, ContentDraftContextFence.matches(current(), captured) else { return }
                self.expireIfMatching(error: APIError.unauthorized, stamp: captured.session.epoch, credential: captured.session.token)
            })
    }
    /// Paid ownership metadata uses a separate grant and retained browser; FREE approval is neither required nor sufficient.
    var workshopPurchasedBrowser: WorkshopPurchasedBrowser? {
        let context = currentWorkshopOwnedContext, approval = currentWorkshopPurchasedApproval
        let viewer = compositionViewerRevision, configurationRevision = workshopReadConfigurationRevision
        workshopPurchasedBinding.reconcile(context: context, configurationRevision: approval?.revision) { captured in
            guard let api = regionalConfiguration?.apiConfiguration else { return nil }
            let current: () -> RuntimeDependencyContext? = { [weak self] in
                guard let self, self.compositionViewerRevision == viewer,
                      self.workshopReadConfigurationRevision == configurationRevision else { return nil }
                return self.currentWorkshopOwnedContext
            }
            return WorkshopPurchasedComposition.makeBrowser(context: captured, api: api, transport: compositionTransport,
                approval: approval, currentApproval: { [weak self] in self?.currentWorkshopPurchasedApproval }, current: current,
                onUnauthorized: { [weak self] captured in
                    guard let self, ContentDraftContextFence.matches(current(), captured) else { return }
                    self.expireIfMatching(error: APIError.unauthorized, stamp: captured.session.epoch, credential: captured.session.token)
                })
        }
        return workshopPurchasedBinding.browser
    }
    /// One session-owned instance. A nil/expired/revoked approval never constructs a browser.
    var workshopOwnedBrowser: WorkshopOwnedBrowser? {
        let context = currentWorkshopOwnedContext, approval = currentWorkshopOwnedApproval
        let viewer = compositionViewerRevision, configurationRevision = workshopReadConfigurationRevision
        workshopOwnedBinding.reconcile(context: context, configurationRevision: approval?.revision) { captured in
            guard let api = regionalConfiguration?.apiConfiguration else { return nil }
            let current: () -> RuntimeDependencyContext? = { [weak self] in
                guard let self, self.compositionViewerRevision == viewer,
                      self.workshopReadConfigurationRevision == configurationRevision else { return nil }
                return self.currentWorkshopOwnedContext
            }
            return WorkshopOwnedComposition.makeBrowser(context: captured, api: api, transport: compositionTransport,
                approval: approval, currentApproval: { [weak self] in self?.currentWorkshopOwnedApproval },
                current: current, onUnauthorized: { [weak self] captured in
                    guard let self, ContentDraftContextFence.matches(current(), captured) else { return }
                    self.expireIfMatching(error: APIError.unauthorized, stamp: captured.session.epoch,
                        credential: captured.session.token)
                })
        }
        return workshopOwnedBinding.browser
    }
    /// The owner of an injected reviewed selector must use this boundary BEFORE changing it,
    /// including grant A → nil → A. This revision is only an invalidation signal, never a grant.
    func withWorkshopReadConfigurationChange(_ change: () -> Void) {
        invalidateWorkshopReadBindings()
        workshopReadConfigurationChanging = true
        change()
        workshopReadConfigurationChanging = false
        workshopReadConfigurationRevision &+= 1
    }
    @Published private var ownerDraftPresentationActive = true
    private var retainedOwnerDraftBrowser: (context: RuntimeDependencyContext, browser: OwnerDraftBrowser)?
    private var currentOwnerDraftContext: RuntimeDependencyContext? {
        guard ownerDraftPresentationActive, !committingAuthenticatedSession else { return nil }
        return currentRuntimeDependencyContext
    }
    var ownerDraftBrowser: OwnerDraftBrowser? {
        synchronizeOwnerDraftBrowser()
        if let retainedOwnerDraftBrowser { return retainedOwnerDraftBrowser.browser }
        guard let captured = currentOwnerDraftContext,
              let browser = composition.makeOwnerDraftBrowser(context: captured, transport: compositionTransport,
                current: { [weak self] in self?.currentOwnerDraftContext },
                onUnauthorized: { [weak self] context in
                    guard let self, ContentDraftContextFence.matches(self.currentOwnerDraftContext, context) else { return }
                    self.expireIfMatching(error: APIError.unauthorized, stamp: context.session.epoch, credential: context.session.token)
                }) else { return nil }
        retainedOwnerDraftBrowser = (captured, browser); return browser
    }
    private func synchronizeOwnerDraftBrowser() {
        if let retainedOwnerDraftBrowser,
           !ContentDraftContextFence.matches(currentOwnerDraftContext, retainedOwnerDraftBrowser.context) { invalidateOwnerDraftBrowser() }
    }
    func invalidateOwnerDraftBrowser() {
        retainedOwnerDraftBrowser?.browser.invalidate(); retainedOwnerDraftBrowser = nil
    }
    func setOwnerDraftPresentationActive(_ active: Bool) {
        ownerDraftPresentationActive = active
        if !active { invalidateOwnerDraftBrowser() }
    }
    @Published private var privateHomePresentationActive = true
    private var retainedPrivateHome: (context: RuntimeDependencyContext, coordinator: PrivateHomeCoordinator)?
    private var currentPrivateHomeContext: RuntimeDependencyContext? {
        guard !committingAuthenticatedSession, privateHomePresentationActive else { return nil }
        return currentRuntimeDependencyContext
    }
    /// AccountView receives this exact session-owned instance; no independent UI/service owner.
    var privateHomeCoordinator: PrivateHomeCoordinator? {
        synchronizePrivateHome()
        if let retainedPrivateHome { return retainedPrivateHome.coordinator }
        guard let captured = currentPrivateHomeContext,
              let coordinator = composition.makePrivateHomeCoordinator(context: captured, transport: compositionTransport,
                  current: { [weak self] in self?.currentPrivateHomeContext }) else { return nil }
        retainedPrivateHome = (captured, coordinator)
        return coordinator
    }
    private func synchronizePrivateHome() {
        if let retainedPrivateHome, retainedPrivateHome.context != currentPrivateHomeContext { invalidatePrivateHome() }
    }
    /// An offscreen old root cannot reconstruct a coordinator. Reentry explicitly reactivates
    /// the current session and creates a fresh owner that reloads the exact durable journal.
    func setPrivateHomePresentationActive(_ active: Bool) {
        privateHomePresentationActive = active
        if !active { invalidatePrivateHome() }
    }
    /// Also called when the root leaves (including immutable deployment/realm replacement).
    /// Revokes retained references and clears display only; the durable unknown record survives.
    func invalidatePrivateHome() {
        retainedPrivateHome?.coordinator.invalidate(); retainedPrivateHome = nil
    }
    private var committingAuthenticatedSession = false
    private let injectedRuntimeDependencies: NativeRuntimeDependencies?
    private var retainedDependencyContext: RuntimeDependencyContext?
    private var retainedDependencies: NativeRuntimeDependencies = .dormant
    private var runtimeDependencies: NativeRuntimeDependencies {
        retainedSocialMemberActions?.synchronizeSession()
        guard !committingAuthenticatedSession, let context = currentRuntimeDependencyContext else {
            retainedDependencyContext = nil; retainedDependencies = .dormant
            return .dormant
        }
        if retainedDependencyContext != context {
            retainedDependencyContext = context
            retainedDependencies = injectedRuntimeDependencies ?? composition.sessionDependencies(context)
        }
        return retainedDependencies
    }
    var walkingNavigationFactory: NativeWalkingNavigationFactory { NativeWalkingNavigationFactory(
        dependencies: runtimeDependencies.walkingNavigation, context: { [weak self] in self?.currentRuntimeDependencyContext }) }
    private var runtimeHTTPTransport: any HTTPTransport { compositionTransport }
    private func scopedTransport(_ injected: (any HTTPTransport)?) -> any HTTPTransport {
        guard let injected else { return compositionTransport }
        return compositionTransport.replacingUnderlying(injected)
    }
    var cityPlayerReadIdentity: String {
        guard let context = currentRuntimeDependencyContext,
              let approval = composition.cityPlayerReadApproval(context), approval.matches(context) else { return "disabled-\(gate.currentStamp)-\(compositionViewerRevision)" }
        return "\(gate.currentStamp):\(compositionViewerRevision):\(approval.revision.uuidString)"
    }
    func makeCityPlayerReader() -> CityPlayerReader {
        let context = currentRuntimeDependencyContext, viewer = compositionViewerRevision
        let approval = context.flatMap { composition.cityPlayerReadApproval($0) }
        let available: () -> Bool = { [weak self] in
            guard let self, let context, let approval, self.compositionViewerRevision == viewer,
                  let current = self.currentRuntimeDependencyContext,
                  ContentDraftContextFence.matches(context, current), approval.matches(current) else { return false }
            return self.composition.cityPlayerReadApproval(current)?.revision == approval.revision
        }
        return CityPlayerReader(approval: approval, transport: compositionTransport, isCurrent: available, onUnauthorized: { [weak self] in
            guard let self, let context, available() else { return }
            self.expireIfMatching(error: APIError.unauthorized, stamp: context.session.epoch, credential: context.session.token)
        })
    }
    private var currentRuntimeDependencyContext: RuntimeDependencyContext? {
        guard !committingAuthenticatedSession, let regionalConfiguration, let api = regionalConfiguration.apiConfiguration,
              let session = currentPlayRuntimeSession, let account else { return nil }
        return RuntimeDependencyContext(market: regionalConfiguration.market, baseURL: api.baseURL,
            role: account.effectiveRole, session: session)
    }
    /// This concrete reviewed-composition factory owns UUID issuance and final dispatch.
    private var nativeChannelAppealOwners: [String: NativeChannelAppealFlow] = [:]
    func makeNativeChannelAppealFlow(notice: NativeChannelGovernanceNotice) -> NativeChannelAppealFlow? {
        guard let context = currentRuntimeDependencyContext, let storageScope,
              context.session.accountID == notice.recipientID else { return nil }
        let viewer = compositionViewerRevision
        let key = "\(notice.guildKind):\(notice.guildID):\(notice.actionID)"
        if let existing = nativeChannelAppealOwners[key], existing.isCurrent, existing.notice == notice { return existing }
        nativeChannelAppealOwners = nativeChannelAppealOwners.filter { $0.value.isCurrent }
        let current: () -> Bool = { [weak self] in
            guard let self else { return false }
            return self.compositionViewerRevision == viewer && self.currentRuntimeDependencyContext == context
        }
        let flow = composition.makeNativeChannelAppealFlow(notice: notice, context: context,
            storage: ProjectEditSecureStorage(scope: storageScope), locatorStorage: ProjectEditSecureStorage(scope: storageScope),
            current: current, unauthorized: { [weak self] in
                guard let self, current() else { return }
                self.expireIfMatching(error: APIError.unauthorized, stamp: context.session.epoch, credential: context.session.token)
            })
        if let flow { nativeChannelAppealOwners[key] = flow }; return flow
    }
    private func nativeChannelAttachmentPreview(message:MessagingMessage,current: @escaping ()->Bool) -> NativeChannelAttachmentPreviewFlow? {
        guard let context=currentRuntimeDependencyContext,let factory=businessRuntimeFactory,factory.captured==context,
              let configuration=regionalConfiguration?.apiConfiguration,message.id>0,message.type==2 else{return nil}
        let viewer=compositionViewerRevision
        let active:()->Bool = { [weak self] in
            guard let self else{return false}
            return current() && self.currentRuntimeDependencyContext==context && self.compositionViewerRevision==viewer
        }
        guard let descriptor = compositionTransport.makeNativeChannelAttachmentDescriptorTransport(
            messageID: message.id, context: context, issued: factory.configuration,
            currentRuntime: { [weak self] in self?.currentRuntimeDependencyContext },
            currentConfiguration: { [weak self] in self?.businessRuntimeFactory?.configuration },
            stillCurrent: active),
            let previewFactory = BusinessRuntimeFactory(configuration: factory.configuration, api: configuration,
                transport: descriptor, current: { [weak self] in descriptor.isCurrent ? self?.currentRuntimeDependencyContext : nil }) else { return nil }
        return NativeChannelAttachmentPreviewAssembly.make(message: message, configuration: configuration,
            factory: previewFactory, currentFactory: { [weak self] in descriptor.isCurrent ? self?.businessRuntimeFactory : nil },
            current: { descriptor.isCurrent && active() }, unauthorized: { [weak self] in
                guard let self,active() else{return}
                self.expireIfMatching(error:APIError.unauthorized,stamp:context.session.epoch,credential:context.session.token)
            })
    }

    func nativeChannelMessageExpandedNavigation(for flow: NativeChannelMessageHostFlow,
        contextMessageIsCurrent: ((MessagingMessage) -> Bool)? = nil) -> IMExpandedNavigationContext? {
        guard flow.isCurrent, let context = currentRuntimeDependencyContext,
              flow.reader.identity == MessagingReadIdentity(accountID: context.session.accountID, epoch: context.session.epoch) else { return nil }
        let original = imExpandedNavigation
        let conversationID = flow.history.conversation.id
        let current: () -> Bool = { [weak self, weak flow] in
            guard let self, let flow else { return false }
            return flow.isCurrent && self.currentRuntimeDependencyContext == context
        }
        return .init(coordinator: { id in
            guard current(), id == conversationID else { return nil }
            return self.channelHostExpandedCoordinator(for: id)
        }, uploadCoordinator: { id in
            guard current(), id == conversationID else { return nil }
            return self.channelHostImageUploadCoordinator(for: id)
        }, starter: {
            guard current() else { return nil }
            return original.starter()
        }, topicReader: original.topicReader, attachmentPreview: { [weak self,weak flow] message in
            guard current(),message.conversationID==conversationID,
                  contextMessageIsCurrent?(message) ?? true else{return nil}
            return self?.nativeChannelAttachmentPreview(message:message,current:{
                guard let flow,current() else{return false}
                // An explicitly supplied original context row is an alternative current
                // read provenance, never a media grant or fallback to an unloaded history row.
                if let contextMessageIsCurrent { return flow.isCurrent && contextMessageIsCurrent(message) }
                return flow.isCurrent && flow.history.visibleMessages.contains(message)
            })
        }, videoCoordinator: { id in
            guard current(), id == conversationID else { return nil }
            return self.imVideoCoordinator(for: id)
        }, fileCoordinator: { id in
            guard current(), id == conversationID else { return nil }
            return self.imFileCoordinator(for: id)
        }, voiceCoordinator: { id in
            guard current(), id == conversationID else { return nil }
            return self.imVoiceCoordinator(for: id)
        }, pollCoordinator: { id, reference in
            guard current(), id == conversationID else { return nil }
            return self.channelHostPollCoordinator(for: flow, reference: reference)
        }, chainCoordinator: { [weak self, weak flow] id, reference in
            guard contextMessageIsCurrent == nil, current(), id == conversationID, let flow else { return nil }
            return self?.makeNativeChannelChainFlow(for: flow, reference: reference)
        }, checkinCoordinator: { [weak self, weak flow] id in
            guard contextMessageIsCurrent == nil, current(), id == conversationID, let flow else { return nil }
            return self?.makeNativeChannelCheckinFlow(for: flow)
        }, channelGovernanceDestination: original.channelGovernanceDestination, safetyCoordinator: { id in
            guard current(), id == conversationID else { return nil }
            return original.safetyCoordinator?(id)
        }, channelReadCoordinator: { id in
            guard current(), id == conversationID else { return nil }
            guard let scope = try? NativeChannelNotificationScope(type: 1, value: String(id)) else { return nil }
            return self.makeNativeChannelNotificationFlow(scope: scope, sourceCurrent: current)
        })
    }

    func makeNativeChannelMessageFlow(channels: any NativeChannelManagementIntegrationContextProviding,
        channelID: NativeChannelManagementID, sourceCurrent: @escaping () -> Bool = { false }) async -> NativeChannelMessageHostFlow? {
        guard sourceCurrent(), let context = currentRuntimeDependencyContext, let historyApproval = currentMessagingHistoryReadApproval,
              storageScope != nil else { return nil }
        let viewer = compositionViewerRevision
        let current: () -> RuntimeDependencyContext? = { [weak self] in
            guard let self, sourceCurrent(), self.compositionViewerRevision == viewer else { return nil }
            return self.currentRuntimeDependencyContext
        }
        let historyCurrent: () -> Bool = { [weak self] in
            guard let self else { return false }
            return ContentDraftContextFence.matches(current(), context) && historyApproval.matches(context)
                && self.currentMessagingHistoryReadApproval?.revision == historyApproval.revision
        }
        do {
            let reader = messagingReader
            let rows = try await reader.messagingConversations()
            guard !Task.isCancelled, historyCurrent(),
                  let conversation = rows.first(where: { String($0.id) == channelID.rawValue }) else { return nil }
            let channel = try await channels.currentChannelContext(channelID: channelID)
            guard !Task.isCancelled, historyCurrent(), channels.contextIsCurrent(channel),
                  channel.identity.epoch == context.session.epoch, channel.identity.viewerRevision == viewer,
                  channel.identity.owner == (try NativeChannelManagementOwner(accountID: context.session.accountID, namespace: context.session.namespace, baseURL: context.baseURL)) else { return nil }
            let binding = try await NativeChannelMessageContextAdapter(source: channels).binding(channelID: channelID, conversation: conversation)
            guard !Task.isCancelled, historyCurrent(), channels.contextIsCurrent(channel) else { return nil }
            let selected: () -> NativeChannelMessageHostAuthority? = { [weak self] in
                guard let self, historyCurrent() else { return nil }
                return self.composition.nativeChannelMessageAuthorization(context, viewer, binding)
            }
            guard let source = selected(), source.binding == binding, source.viewerRevision == viewer,
                  ContentDraftContextFence.matches(source.context, context), source.identity != nil else { return nil }
            let available: () -> Bool = {
                guard historyCurrent(), channels.contextIsCurrent(channel) else { return false }
                guard selected() === source else { source.retireObservedSelection(); return false }
                return source.identity != nil
            }
            let received401: () -> Void = { [weak self] in
                guard let self, !Task.isCancelled, available() else { return }
                self.expireIfMatching(error: APIError.unauthorized, stamp: context.session.epoch, credential: context.session.token)
            }
            let read: () -> NativeChannelTextApproval? = { [weak self] in
                guard let value = self?.composition.nativeChannelTextReceiptApproval(context),
                      value.matches(context, operation: .receipt, conversationID: conversation.id) else { return nil }; return value
            }
            let write: () -> NativeChannelTextApproval? = { [weak self] in
                guard let value = self?.composition.nativeChannelTextSendApproval(context),
                      value.matches(context, operation: .send, conversationID: conversation.id) else { return nil }; return value
            }
            let flow = try NativeChannelMessageHostBinding.make(context: context, conversation: conversation, authority: source,
                storage: ProjectEditSecureStorage(scope: storageScope), current: available, onUnauthorized: received401,
                makeOriginal: { active, unauthorized in
                    try self.compositionTransport.makeNativeChannelMessageOriginalAdapters(context: context, binding: binding,
                        currentRuntime: current, stillCurrent: active, read: read, write: write, received401: unauthorized)
                }, makeMutations: { journal, active, unauthorized in
                    try self.compositionTransport.makeNativeChannelMessageDispatcher(authority: source, journal: journal,
                        currentRuntime: current, stillCurrent: active, onUnauthorized: unauthorized)
                })
            if let targets = makeNativeChannelMentionTargets(channels: channels, captured: channel, flow: flow) { flow.attachMentionTargets(targets) }
            return flow
        } catch { return nil }
    }

    func makeNativeChannelMentionTargets(channels: any NativeChannelManagementIntegrationContextProviding,
                                         captured: NativeChannelManagementIntegrationContext,flow: NativeChannelMessageHostFlow) -> NativeChannelMentionTargets? {
        let features: Set<BusinessRuntimeFeature> = [.imChannelMentionMemberRead,.imChannelMentionRoleRead]
        guard let context = currentRuntimeDependencyContext else { return nil }
        let viewer=compositionViewerRevision
        let current: () -> Bool = { [weak self,weak flow] in
            guard let self,let flow else { return false }
            return flow.isCurrent && self.compositionViewerRevision == viewer && self.currentRuntimeDependencyContext == context
        }
        guard let (factory, gate) = channelHostRuntimeFactory(features, current: current) else { return nil }
        let issued = factory.routes(features)
        return try? NativeChannelMentionTargets(binding:flow.coordinator.client.binding,captured:captured,channels:channels,
            context:context,transport:factory.client(features),current:{ gate.isCurrent && current() },
            permits:{ method,path in gate.isCurrent && current() && issued.contains(where:{$0.method == method && $0.path == path}) },
            unauthorized:{ [weak self] in
                guard let self,current() else { return }
                self.expireIfMatching(error:APIError.unauthorized,stamp:context.session.epoch,credential:context.session.token)
            })
    }
    private struct ChannelHostPollKey: Hashable {
        let flow: ObjectIdentifier
        let reference: GroupPollReference?
    }
    private var channelHostPollOwners: [ChannelHostPollKey: GroupPollCoordinator] = [:]
    private func channelHostPollCoordinator(for flow: NativeChannelMessageHostFlow,
        reference: GroupPollReference?) -> GroupPollCoordinator? {
        let key = ChannelHostPollKey(flow: ObjectIdentifier(flow), reference: reference)
        if let existing = channelHostPollOwners[key], existing.isCurrent { return existing }
        channelHostPollOwners = channelHostPollOwners.filter { $0.value.isCurrent }
        let features: Set<BusinessRuntimeFeature> = [.imPollResult, .imPollCreate, .imPollVote, .imPollClose, .imPollCreateReceipt]
        guard flow.isCurrent, let storageScope, let api = regionalConfiguration?.apiConfiguration,
              let (factory, gate) = channelHostRuntimeFactory(features, current: { [weak flow] in flow?.isCurrent == true }),
              let identity = flow.reader.identity,
              let scope = try? IMScope(identity: identity, conversationID: flow.history.conversation.id),
              reference == nil || reference?.conversationID == scope.conversationID else { return nil }
        let captured = factory.captured
        let service = GroupPollService(configuration: api, transport: factory.client(features),
            enabledPaths: Set(factory.routes(features).map(\.path)))
        let client = GroupPollSessionClient(service: service, session: { [weak self] in
            guard gate.isCurrent, let self, self.currentRuntimeDependencyContext == captured else { return nil }
            return try? GroupPollSession(accountID: captured.session.accountID, epoch: captured.session.epoch, token: captured.session.token)
        }, onUnauthorized: { [weak self] value in
            guard gate.isCurrent, let self, self.currentRuntimeDependencyContext == captured else { return }
            self.expireIfMatching(error: APIError.unauthorized, stamp: value.identity.epoch, credential: captured.session.token)
        })
        // Share the protected sidecar for both creator and detail owners. Only the
        // nil-reference creator recovers it; a matching result alone cannot settle
        // its durable create lock without the original request-hash receipt.
        guard let recovery = try? GroupPollCreateRecoveryJournal(storage: ProjectEditSecureStorage(scope: storageScope),
            namespace: storageScope.service, realm: api.baseURL, accountID: captured.session.accountID,
            conversationID: scope.conversationID) else { return nil }
        guard let owner = try? GroupPollCoordinator(scope: scope, reference: reference, client: client,
            reader: flow.reader, journal: composition.storage.operationJournal(), namespace: storageScope.service,
            realm: api.baseURL, creationRecovery: recovery) else { return nil }
        channelHostPollOwners[key] = owner
        return owner
    }

    private var channelHostCoordinators: [IMScope: IMExpandedCoordinator] = [:]
    private var channelHostImages: [IMScope: IMImageUploadCoordinator] = [:]
    private var imVideoCoordinators: [IMScope: IMVideoCoordinator] = [:]
    private var imFileCoordinators: [IMScope: IMFileCoordinator] = [:]
    private var imVoiceCoordinators: [IMScope: IMVoiceCoordinator] = [:]
    private var channelHostWriter: (writer: IMExpandedWriter, gate: NativeChannelHostRuntimeTransport)?
    private var nativeChannelReportOwners: [ObjectIdentifier: NativeChannelReportFlow] = [:]
    private func channelHostRuntimeFactory(_ features: Set<BusinessRuntimeFeature>,
        current: @escaping () -> Bool = { true }) -> (BusinessRuntimeFactory, NativeChannelHostRuntimeTransport)? {
        guard let issued = businessRuntimeFactory, let api = regionalConfiguration?.apiConfiguration else { return nil }
        let context = issued.captured, viewer = compositionViewerRevision
        guard let gate = compositionTransport.makeNativeChannelHostRuntimeTransport(context: context,
            issued: issued.configuration, features: features,
            currentRuntime: { [weak self] in self?.currentRuntimeDependencyContext },
            currentConfiguration: { [weak self] in self?.businessRuntimeFactory?.configuration },
            stillCurrent: { [weak self] in self?.compositionViewerRevision == viewer && current() }),
            let factory = BusinessRuntimeFactory(configuration: issued.configuration, api: api,
                transport: gate, current: { gate.isCurrent ? context : nil }) else { return nil }
        return (factory, gate)
    }

    private var originalChannelHostWriter: IMExpandedWriter {
        // Observe and retire the old issuance before an absent/empty new configuration
        // can short-circuit this getter. Regrant creates a different owner.
        if let cached = channelHostWriter {
            if cached.gate.isCurrent { return cached.writer }
            channelHostWriter = nil
        }
        let features: Set<BusinessRuntimeFeature> = [.imStart, .imRead, .imOrdinaryReadReceipt, .imOrdinaryReadState, .imMute, .imOrdinaryMuteReceipt, .imOrdinaryMuteState, .imSend, .imUpload, .imOrdinarySendReceipt, .imImageUploadReceipt, .imStaticLocationSend, .imStaticLocationReceipt, .imRouteShareRead, .imRouteSend, .imRouteReceipt, .imVoiceSend, .imVoiceReceipt, .imFileSend, .imFileReceipt, .imVideoSend, .imVideoReceipt]
        guard let (factory, gate) = channelHostRuntimeFactory(features), !factory.routes(features).isEmpty,
              let configuration = regionalConfiguration?.apiConfiguration else { return disabledIMWriter }

        let captured = factory.captured
        let service = IMExpandedService(configuration: configuration, transport: factory.client(features),
            approvedMediaOrigins: factory.configuration.imMediaOrigins, writesEnabled: true,
            enabledPaths: Set(factory.routes(features).map(\.path)),
            staticLocationEnabled: factory.permits(.imStaticLocationSend),
            staticLocationReceiptEnabled: factory.permits(.imStaticLocationReceipt),
            ordinarySendEnabled: factory.permits(.imSend),
            ordinaryReceiptEnabled: factory.permits(.imOrdinarySendReceipt),
            imageUploadReceiptEnabled: factory.permits(.imImageUploadReceipt),
            routeShareReadEnabled: factory.permits(.imRouteShareRead),
            routeSendEnabled: factory.permits(.imRouteSend),
            routeReceiptEnabled: factory.permits(.imRouteReceipt),
            voiceSendEnabled: factory.permits(.imVoiceSend), voiceReceiptEnabled: factory.permits(.imVoiceReceipt), fileSendEnabled: factory.permits(.imFileSend), fileReceiptEnabled: factory.permits(.imFileReceipt), videoSendEnabled: factory.permits(.imVideoSend), videoReceiptEnabled: factory.permits(.imVideoReceipt),
            ordinaryMuteRequestEnabled: factory.permits(.imMute),
            ordinaryMuteReceiptEnabled: factory.permits(.imOrdinaryMuteReceipt),
            ordinaryMuteStateEnabled: factory.permits(.imOrdinaryMuteState),
            ordinaryReadRequestEnabled: factory.permits(.imRead),
            ordinaryReadReceiptEnabled: factory.permits(.imOrdinaryReadReceipt),
            ordinaryReadStateEnabled: factory.permits(.imOrdinaryReadState))
        let writer = IMExpandedWriter(service: service, session: { [weak self] in
            guard let self, self.currentRuntimeDependencyContext == captured, gate.isCurrent else { return nil }; return self.currentIMExpandedSession
        }, onUnauthorized: { [weak self] snapshot in
            guard let self, self.currentRuntimeDependencyContext == captured, gate.isCurrent else { return }
            self.expireIfMatching(error: APIError.unauthorized, stamp: snapshot.identity.epoch, credential: self.token)
        })
        channelHostWriter = (writer, gate); return writer
    }
    func channelHostExpandedCoordinator(for conversationID: Int) -> IMExpandedCoordinator? {
        let writer = originalChannelHostWriter
        guard let context = currentRuntimeDependencyContext, let storageScope,
              let identity = writer.identity, let scope = try? IMScope(identity: identity, conversationID: conversationID),
              let recoveryScope = try? NativeChannelTextScope(context: context, conversationID: conversationID) else { return nil }
        if let existing = channelHostCoordinators[scope], existing.isCurrent, existing.writer === writer { return existing }
        let viewer = compositionViewerRevision
        let recovery = IMExpandedRecoveryJournal(storage: ProjectEditSecureStorage(scope: storageScope), scope: recoveryScope)
        let owner = IMExpandedCoordinator(scope: scope, writer: writer, recovery: recovery, stillCurrent: { [weak self] in
            guard let self, self.compositionViewerRevision == viewer,
                  self.currentRuntimeDependencyContext == context else { return false }
            return self.originalChannelHostWriter === writer
        })
        channelHostCoordinators[scope] = owner; return owner
    }
    func channelHostImageUploadCoordinator(for conversationID: Int) -> IMImageUploadCoordinator? {
        guard let context = currentRuntimeDependencyContext, let storageScope,
              let expanded = channelHostExpandedCoordinator(for: conversationID),
              let durable = try? NativeChannelTextScope(context: context, conversationID: conversationID),
              let target = try? ImageUploadTarget(accountID: expanded.scope.identity.accountID,
                namespace: storageScope.service, realm: context.baseURL.absoluteString,
                kind: "im", entityID: conversationID, field: "image") else { return nil }
        let scope = expanded.scope
        if let existing = channelHostImages[scope], existing.isCurrent { return existing }
        let viewer = compositionViewerRevision, writer = expanded.writer
        let current: () -> Bool = { [weak self] in
            guard let self else { return false }
            return self.currentRuntimeDependencyContext == context && self.compositionViewerRevision == viewer && expanded.isCurrent
        }
        let owner = IMImageUploadCoordinator(scope: scope, writer: writer,
            picker: retainedImagePickerHost.imPicker(scope: scope, currentScope: { current() ? scope : nil }, selectionApproval: { [weak self] in
                guard let self, current(), let factory = self.businessRuntimeFactory else { return false }
                return factory.permits(.imUpload) && factory.permits(.imImageUploadReceipt) && factory.configuration.imImageSelection
            }), journal: imageUploadJournal, target: target,
            originalJournal: OrdinaryIMImageJournal(storage: ProjectEditSecureStorage(scope: storageScope), owner: durable),
            expanded: expanded, reader: messagingReader, stillCurrent: current)
        channelHostImages[scope] = owner; return owner
    }
    func imVoiceCoordinator(for conversationID: Int) -> IMVoiceCoordinator? {
        guard let context = currentRuntimeDependencyContext, let storageScope,
              let owner = channelHostExpandedCoordinator(for: conversationID),
              let issuedFactory = businessRuntimeFactory, issuedFactory.captured == context,
              let configuration = regionalConfiguration?.apiConfiguration,
              let durableScope = try? NativeChannelTextScope(context: context, conversationID: conversationID) else { return nil }
        if let existing = imVoiceCoordinators[owner.scope], existing.isCurrent, existing.expanded === owner { return existing }
        let viewer = compositionViewerRevision
        let features: Set<BusinessRuntimeFeature> = [.imVoiceUpload, .imVoiceUploadReceipt, .imVoicePlayback, .imVoicePlaybackStatus]
        guard let (factory, mediaGate) = channelHostRuntimeFactory(features) else { return nil }
        let current: () -> Bool = { [weak self] in
            guard let self else { return false }
            return self.currentRuntimeDependencyContext == context && self.compositionViewerRevision == viewer && owner.isCurrent && mediaGate.isCurrent
        }
        let service = IMVoiceService(configuration: configuration, transport: factory.client(features),
            uploadEnabled: factory.permits(.imVoiceUpload), receiptEnabled: factory.permits(.imVoiceUploadReceipt),
            playbackEnabled: factory.permits(.imVoicePlayback), playbackStatusEnabled: factory.permits(.imVoicePlaybackStatus), session: {
                guard current() else { return nil }
                return try? IMVoiceSession(accountID: context.session.accountID, epoch: context.session.epoch, token: context.session.token)
            }, unauthorized: { [weak self] snapshot in
                guard let self, current() else { return }
                self.expireIfMatching(error: APIError.unauthorized, stamp: snapshot.identity.epoch, credential: context.session.token)
            })
        let voice = IMVoiceCoordinator(scope: owner.scope, expanded: owner, service: service,
            journal: IMVoiceJournal(storage: ProjectEditSecureStorage(scope: storageScope), owner: durableScope), stillCurrent: current)
        imVoiceCoordinators[owner.scope] = voice; return voice
    }
    func imFileCoordinator(for conversationID: Int) -> IMFileCoordinator? {
        guard let context = currentRuntimeDependencyContext, let storageScope,
              let owner = channelHostExpandedCoordinator(for: conversationID),
              let issuedFactory = businessRuntimeFactory, issuedFactory.captured == context,
              let configuration = regionalConfiguration?.apiConfiguration,
              let durableScope = try? NativeChannelTextScope(context: context, conversationID: conversationID) else { return nil }
        if let existing = imFileCoordinators[owner.scope], existing.isCurrent, existing.expanded === owner { return existing }
        let viewer = compositionViewerRevision
        let features: Set<BusinessRuntimeFeature> = [.imFileUpload, .imFileUploadReceipt, .imFileScan, .imFilePreview, .imFilePreviewStatus]
        guard let (factory, mediaGate) = channelHostRuntimeFactory(features) else { return nil }
        let current: () -> Bool = { [weak self] in
            guard let self else { return false }
            return self.currentRuntimeDependencyContext == context && self.compositionViewerRevision == viewer && owner.isCurrent && mediaGate.isCurrent
        }
        let service = IMFileService(configuration: configuration, transport: factory.client(features),
            mediaTransport: ResponseLimitedHTTPTransport(enabled: factory.permits(.imFilePreview), maximumResponseBytes: IMFileSelection.maximumBytes),
            approvedMediaOrigins: factory.configuration.imMediaOrigins,
            uploadEnabled: factory.permits(.imFileUpload), scanEnabled: factory.permits(.imFileScan), receiptEnabled: factory.permits(.imFileUploadReceipt),
            previewEnabled: factory.permits(.imFilePreview), previewStatusEnabled: factory.permits(.imFilePreviewStatus), session: {
                guard current() else { return nil }
                return try? IMFileSession(accountID: context.session.accountID, epoch: context.session.epoch, token: context.session.token)
            }, unauthorized: { [weak self] snapshot in
                guard let self, current() else { return }
                self.expireIfMatching(error: APIError.unauthorized, stamp: snapshot.identity.epoch, credential: context.session.token)
            })
        let file = IMFileCoordinator(scope: owner.scope, expanded: owner, service: service,
            journal: IMFileJournal(storage: ProjectEditSecureStorage(scope: storageScope), owner: durableScope, directory: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("im-file-drafts", isDirectory: true)), stillCurrent: current)
        imFileCoordinators[owner.scope] = file; return file
    }
    func imVideoCoordinator(for conversationID: Int) -> IMVideoCoordinator? {
        guard let context = currentRuntimeDependencyContext, let storageScope,
              let owner = channelHostExpandedCoordinator(for: conversationID),
              let issuedFactory = businessRuntimeFactory, issuedFactory.captured == context,
              let configuration = regionalConfiguration?.apiConfiguration,
              let durableScope = try? NativeChannelTextScope(context: context, conversationID: conversationID) else { return nil }
        if let existing = imVideoCoordinators[owner.scope], existing.isCurrent, existing.expanded === owner { return existing }
        let viewer = compositionViewerRevision
        let features: Set<BusinessRuntimeFeature> = [.imVideoUpload, .imVideoUploadReceipt, .imVideoPolicy, .imVideoPreview, .imVideoPreviewStatus]
        guard let (factory, mediaGate) = channelHostRuntimeFactory(features) else { return nil }
        let current: () -> Bool = { [weak self] in
            guard let self else { return false }
            return self.currentRuntimeDependencyContext == context && self.compositionViewerRevision == viewer && owner.isCurrent && mediaGate.isCurrent
        }
        let service = IMVideoService(configuration: configuration, transport: factory.client(features),
            mediaTransport: ResponseLimitedHTTPTransport(enabled: factory.permits(.imVideoPreview), maximumResponseBytes: IMVideoSelection.maximumBytes),
            approvedMediaOrigins: factory.configuration.imMediaOrigins,
            uploadEnabled: factory.permits(.imVideoUpload), policyEnabled: factory.permits(.imVideoPolicy), receiptEnabled: factory.permits(.imVideoUploadReceipt),
            previewEnabled: factory.permits(.imVideoPreview), previewStatusEnabled: factory.permits(.imVideoPreviewStatus), session: {
                guard current() else { return nil }
                return try? IMVideoSession(accountID: context.session.accountID, epoch: context.session.epoch, token: context.session.token)
            }, unauthorized: { [weak self] snapshot in
                guard let self, current() else { return }
                self.expireIfMatching(error: APIError.unauthorized, stamp: snapshot.identity.epoch, credential: context.session.token)
            })
        let file = IMVideoCoordinator(scope: owner.scope, expanded: owner, service: service,
            journal: IMVideoJournal(storage: ProjectEditSecureStorage(scope: storageScope), owner: durableScope, directory: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("im-video-drafts", isDirectory: true)), stillCurrent: current)
        imVideoCoordinators[owner.scope] = file; return file
    }
    func nativeChannelReportFlow(for flow: NativeChannelMessageHostFlow) -> NativeChannelReportFlow? {
        // Retire a cached report issuance before missing configuration can return early.
        let key = ObjectIdentifier(flow)
        if let existing = nativeChannelReportOwners[key] {
            if existing.isCurrent { return existing }
            nativeChannelReportOwners[key] = nil
        }
        guard flow.isCurrent, let sourceFactory = businessRuntimeFactory, let storageScope,
              flow.reader.identity == MessagingReadIdentity(accountID: sourceFactory.captured.session.accountID,
                                                            epoch: sourceFactory.captured.session.epoch) else { return nil }
        let features: Set<BusinessRuntimeFeature> = [.imReport, .imChannelReportReceipt]
        guard let (factory, reportGate) = channelHostRuntimeFactory(features, current: { [weak flow] in flow?.isCurrent == true }) else { return nil }
        let issued = factory.routes(features)
        guard !issued.isEmpty else { return nil }
        nativeChannelReportOwners = nativeChannelReportOwners.filter { $0.value.isCurrent }
        let context = factory.captured, viewer = compositionViewerRevision
        let current: () -> Bool = { [weak self, weak flow] in
            guard let self, let flow else { return false }
            return reportGate.isCurrent && flow.isCurrent && self.compositionViewerRevision == viewer && self.currentRuntimeDependencyContext == context
        }
        let owner = try? NativeChannelReportFlow(context: context, conversationID: flow.history.conversation.id,
            transport: factory.client(features), storage: ProjectEditSecureStorage(scope: storageScope), current: current,
            permitsWrite: { current() && issued.contains(where: { $0.method == "POST" && $0.path == "api/im/report" }) },
            permitsRead: { path in current() && issued.contains(where: { $0.method == "GET" && $0.path == path }) },
            unauthorized: { [weak self] in
                guard let self, current() else { return }
                self.expireIfMatching(error: APIError.unauthorized, stamp: context.session.epoch, credential: context.session.token)
            })
        if let owner { nativeChannelReportOwners[key] = owner }; return owner
    }
    private func makeNativeChannelCheckinFlow(for flow: NativeChannelMessageHostFlow) -> NativeChannelCheckinFlow? {
        guard flow.isCurrent, let sourceFactory = businessRuntimeFactory, let storageScope,
              sourceFactory.captured == currentRuntimeDependencyContext,
              flow.reader.identity == MessagingReadIdentity(accountID: sourceFactory.captured.session.accountID,
                                                            epoch: sourceFactory.captured.session.epoch) else { return nil }
        let features: Set<BusinessRuntimeFeature> = [.imCheckinStatus, .imCheckinWrite, .imCheckinRank, .imCheckinReceipt]
        guard let (factory, gate) = channelHostRuntimeFactory(features, current: { [weak flow] in flow?.isCurrent == true }) else { return nil }
        let issued = factory.routes(features)
        guard !issued.isEmpty else { return nil }
        let context = sourceFactory.captured, viewer = compositionViewerRevision
        let current: () -> Bool = { [weak self, weak flow] in
            guard let self, let flow else { return false }
            return gate.isCurrent && flow.isCurrent && self.compositionViewerRevision == viewer && self.currentRuntimeDependencyContext == context
                && self.businessRuntimeFactory?.routes(features) == issued
        }
        guard let service = try? NativeChannelCheckinService(context: context, channelID: String(flow.history.conversation.id),
            transport: factory.client(features), permits: { method, path in
                current() && issued.contains(where: { $0.method == method && $0.path == path })
            }, current: current, unauthorized: { [weak self] in
                guard let self, current() else { return }
                self.expireIfMatching(error: APIError.unauthorized, stamp: context.session.epoch, credential: context.session.token)
            }) else { return nil }
        return try? NativeChannelCheckinFlow(service: service, context: context, storage: ProjectEditSecureStorage(scope: storageScope))
    }
    private func makeNativeChannelChainFlow(for flow: NativeChannelMessageHostFlow,
        reference: NativeChannelChainReference?) -> NativeChannelChainFlow? {
        guard flow.isCurrent, let sourceFactory = businessRuntimeFactory, let storageScope,
              sourceFactory.captured == currentRuntimeDependencyContext,
              flow.reader.identity == MessagingReadIdentity(accountID: sourceFactory.captured.session.accountID,
                                                            epoch: sourceFactory.captured.session.epoch),
              reference == nil || reference?.conversationID == String(flow.history.conversation.id) else { return nil }
        let features: Set<BusinessRuntimeFeature> = [.imChainRead, .imChainCreate, .imChainJoin, .imChainWithdraw, .imChainClose, .imChainReceipt]
        guard let (factory, gate) = channelHostRuntimeFactory(features, current: { [weak flow] in flow?.isCurrent == true }) else { return nil }
        let issued = factory.routes(features)
        guard !issued.isEmpty else { return nil }
        let context = sourceFactory.captured, viewer = compositionViewerRevision
        let current: () -> Bool = { [weak self, weak flow] in
            guard let self, let flow else { return false }
            return gate.isCurrent && flow.isCurrent && self.compositionViewerRevision == viewer && self.currentRuntimeDependencyContext == context
                && self.businessRuntimeFactory?.routes(features) == issued
        }
        guard let service = try? NativeChannelChainService(context: context, conversationID: String(flow.history.conversation.id),
            transport: factory.client(features), permits: { method, path in
                current() && issued.contains(where: { $0.method == method && $0.path == path })
            }, current: current, unauthorized: { [weak self] in
                guard let self, current() else { return }
                self.expireIfMatching(error: APIError.unauthorized, stamp: context.session.epoch, credential: context.session.token)
            }) else { return nil }
        return try? NativeChannelChainFlow(service: service, context: context,
            storage: ProjectEditSecureStorage(scope: storageScope), reference: reference)
    }
    func makeNativeChannelNotificationFlow(scope: NativeChannelNotificationScope?, sharedClubDefault: Bool = false,
        sourceCurrent: @escaping @MainActor () -> Bool = { true }) -> NativeChannelNotificationCoordinator? {
        guard let context = currentRuntimeDependencyContext, storageScope != nil else { return nil }
        let viewer = compositionViewerRevision
        let current: () -> RuntimeDependencyContext? = { [weak self] in
            guard let self, self.compositionViewerRevision == viewer, sourceCurrent() else { return nil }
            return self.currentRuntimeDependencyContext
        }
        let selected: () -> (any NativeChannelNotificationAuthorizing)? = { [weak self] in
            guard let self, ContentDraftContextFence.matches(current(), context) else { return nil }
            return self.composition.nativeChannelNotificationAuthorization(context, viewer)
        }
        guard let source = selected() else { return nil }
        let journal = NativeChannelNotificationJournal(
            storage: NativeChannelNotificationProtectedStorage(existing: ProjectEditSecureStorage(scope: storageScope)),
            owner: .init(context: context))
        do {
                guard let dispatcher = self.compositionTransport.makeNativeChannelNotificationDispatcher(
                    context: context, viewerRevision: viewer, source: source, journal: journal,
                    currentRuntime: current,
                    currentViewer: { [weak self] in self?.compositionViewerRevision ?? UInt64.max },
                    selectedSource: selected) else { throw NativeChannelNotificationError.accessClosed }
                let authority = dispatcher.authority
            guard ContentDraftContextFence.matches(authority.context, context),
                  !sharedClubDefault || scope?.type == 2 else { return nil }
            if !authority.allows(sharedClubDefault ? .clubDefaultRead : (scope == nil ? .directory : .preference), scope: scope) {
                let ackAllowed = scope?.type == 1 && authority.allows(.ack, scope: scope)
                let unreadAllowed = scope == nil && authority.allows(.unread, scope: nil)
                if !ackAllowed && !unreadAllowed {
                    guard let original = try journal.restore(), authority.allows(.receipt, scope: original.scope) else { return nil }
                }
            }
            return try NativeChannelNotificationCoordinator(
                client: NativeChannelNotificationService(authority: authority, transport: dispatcher),
                journal: journal, scope: scope, sharedClubDefault: sharedClubDefault)
        } catch { return nil }
    }
    func makeNativeNotificationDeliveryLogFlow() -> NativeNotificationDeliveryLogCoordinator? {
        guard let context = currentRuntimeDependencyContext, storageScope != nil else { return nil }
        let viewer = compositionViewerRevision
        let current: () -> RuntimeDependencyContext? = { [weak self] in
            guard let self, self.compositionViewerRevision == viewer else { return nil }
            return self.currentRuntimeDependencyContext
        }
        let selected: () -> (any NativeChannelNotificationAuthorizing)? = { [weak self] in
            guard let self, ContentDraftContextFence.matches(current(), context) else { return nil }
            return self.composition.nativeChannelNotificationAuthorization(context, viewer)
        }
        guard let source = selected() else { return nil }
        return try? NativeChannelNotificationBinding.makeDeliveryLog(context: context,
            storage: ProjectEditSecureStorage(scope: storageScope), makeDispatcher: { journal in
                guard let dispatcher = self.compositionTransport.makeNativeChannelNotificationDispatcher(
                    context: context, viewerRevision: viewer, source: source, journal: journal,
                    currentRuntime: current,
                    currentViewer: { [weak self] in self?.compositionViewerRevision ?? UInt64.max },
                    selectedSource: selected) else { throw NativeChannelNotificationError.accessClosed }
                return dispatcher
            })
    }
    /// Reporter-owned original receipts remain reachable after the channel host retires.
    /// The local journal supplies only locators; independent exact GET issuance is required.
    func makeNativeChannelReportRecoveryDirectory() -> NativeChannelReportRecoveryDirectory? {
        guard let context = currentRuntimeDependencyContext, let storageScope,
              storageScope.service.utf8.elementsEqual(context.session.namespace.utf8) else { return nil }
        let viewer = compositionViewerRevision
        let current: () -> Bool = { [weak self] in
            guard let self else { return false }
            return self.compositionViewerRevision == viewer && self.currentRuntimeDependencyContext == context
        }
        // Reuse the independently issued exact GET set through the live final-forward gate.
        guard let (factory, gate) = channelHostRuntimeFactory([.imChannelReportReceipt], current: current) else { return nil }
        return NativeChannelReportRecoveryAssembly.make(factory: factory,
            currentFactory: { [weak self] in self?.businessRuntimeFactory },
            storage: ProjectEditSecureStorage(scope: storageScope),
            journalKeys: { try NativeChannelReportJournalKeys.read(scope: storageScope, context: context) },
            current: { gate.isCurrent && current() }, unauthorized: { [weak self] in
                guard let self, current() else { return }
                self.expireIfMatching(error: APIError.unauthorized, stamp: context.session.epoch, credential: context.session.token)
            })
    }

    private var businessRuntimeFactory: BusinessRuntimeFactory? {
        guard let api = regionalConfiguration?.apiConfiguration, storageScope != nil,
              let configuration = runtimeDependencies.businessConfiguration, let context = currentRuntimeDependencyContext,
              configuration.matches(context) else { return nil }
        return BusinessRuntimeFactory(configuration: configuration, api: api,
            transport: runtimeHTTPTransport,
            current: { [weak self] in self?.currentRuntimeDependencyContext })
    }
    private var runtimeDependencyFactory: RuntimeDependencyFactory? {
        guard let api = regionalConfiguration?.apiConfiguration, storageScope != nil else { return nil }
        return RuntimeDependencyFactory(api: api, configuration: runtimeDependencies.configuration,
            transport: runtimeHTTPTransport,
            current: { [weak self] in self?.currentRuntimeDependencyContext })
    }
    private var currentPlayRuntimeSession: PlayExperienceSession? {
        guard let account, let token, let namespace = storageScope?.service else { return nil }
        return try? PlayExperienceSession(accountID: account.id, epoch: gate.currentStamp, namespace: namespace, token: token)
    }
    private func dormantPlayRuntimeService() -> PlayExperienceService? {
        guard regionalConfiguration?.apiConfiguration != nil, storageScope != nil else { return nil }
        return runtimeDependencyFactory?.playService()
    }
    private func playRuntimeKey(_ scope: PlaySessionScope, suffix: String) -> String {
        "\(storageScope?.service ?? "none"):\(gate.currentStamp):\(account?.id ?? 0):\(account?.effectiveRole ?? "none"):\(scope.fields.keys.sorted().joined()):\(scope.id):\(suffix)"
    }
    func playAdvanced(scope: PlaySessionScope, nodeID: Int, topicID: Int?, lifetime: PlayInteractionLifetime? = nil) -> PlayAdvancedCoordinator? {
        guard let lifetime, lifetime.isCurrent, scope.isValid, nodeID > 0, let topicID, topicID > 0, let api = dormantPlayRuntimeService() else { return nil }
        let key = playRuntimeKey(scope, suffix: "advanced:\(nodeID)")
        if let retained = retainedPlayAdvanced[key], retained.readLifetimeID == lifetime.identity || retained.blocksReadRebinding { return retained }
        let activityID: Int
        switch scope { case .activity(let id): activityID = id; case .topic(let id): guard id == topicID else { return nil }; activityID = 0 }
        let model = PlayAdvancedCoordinator(activityID: activityID, topicID: topicID, nodeID: nodeID, service: api.bound(to: lifetime),
            currentSession: { [weak self] in self?.currentPlayRuntimeSession })
        retainedPlayAdvanced[key] = model; return model
    }
    func playPreference(scope: PlaySessionScope, nodeID: Int, lifetime: PlayInteractionLifetime? = nil) -> PlayPreferenceCoordinator? {
        guard let lifetime, lifetime.isCurrent, scope.isValid, nodeID > 0, let api = dormantPlayRuntimeService() else { return nil }
        let key = playRuntimeKey(scope, suffix: "preference:\(nodeID)")
        if let retained = retainedPlayPreferences[key], retained.readLifetimeID == lifetime.identity || retained.blocksReadRebinding { return retained }
        let model = PlayPreferenceCoordinator(scope: scope, nodeID: nodeID, service: api.bound(to: lifetime),
            currentSession: { [weak self] in self?.currentPlayRuntimeSession })
        retainedPlayPreferences[key] = model; return model
    }
    func playOperatingSummary(topicID: Int) -> PlayOperatingSummaryCoordinator? {
        guard !committingAuthenticatedSession, topicID > 0,
              let regional = regionalConfiguration, let storageScope, let account, let token,
              let role = PlayRecoveryAccountRole(rawValue: account.effectiveRole),
              let captured = try? PlayExperienceSession(accountID: account.id, epoch: gate.currentStamp,
                  namespace: storageScope.service, token: token, role: role.rawValue),
              let api = dormantPlayRuntimeService() else { return nil }
        let viewer = compositionViewerRevision
        let key = playRuntimeKey(.topic(topicID), suffix: "summary:\(viewer)")
        if let retained = retainedPlaySummaries[key] { return retained }
        let recovery: any PlayTagRevocationRecovery
        do {
            recovery = try composition.storage.playRecovery.make(session: captured, scope: .topic(topicID),
                regionalConfiguration: regional, storageScope: storageScope)
        } catch { recovery = PlayUnavailableTagRevocationRecovery() }
        let model = PlayOperatingSummaryCoordinator(topicID: topicID, service: api, recovery: recovery,
            currentSession: { [weak self] in
                guard let self, self.matchesContinuationSession(captured, viewerRevision: viewer) else { return nil }
                return captured
            })
        retainedPlaySummaries[key] = model; return model
    }
    /// P056 reuses an already accepted read configuration. This creates no approval
    /// and deliberately exposes no PlayDirectorCoordinator/write API to the club UI.
    private var currentClubTerminalReadLease: ClubTerminalReadLease? {
        guard let context = currentRuntimeDependencyContext,
              let factory = runtimeDependencyFactory, let approved = factory.accepted,
              approved.play.contains(.reads), let issuance = approved.playReadApprovalID,
              approved.endpoints.paths.contains("api/game/session/view") else { return nil }
        return .init(context: context, approvalID: issuance, viewerRevision: compositionViewerRevision,
                     paths: approved.endpoints.paths)
    }
    private func makeClubTerminalProjectionProvider() -> (any ClubTerminalProjectionReading)? {
        guard let lease = currentClubTerminalReadLease, let factory = runtimeDependencyFactory else { return nil }
        return ClubTerminalProjectionProvider(service: factory.playService(), lease: lease,
            current: { [weak self] in self?.currentClubTerminalReadLease })
    }
    private var clubTerminalSessionContext: ClubTerminalSessionContext {
        guard let lease = currentClubTerminalReadLease else { return .init(viewerRevision: compositionViewerRevision) }
        return .init(viewerRevision: compositionViewerRevision, approvalID: lease.approvalID,
                     makeProvider: { [weak self] in self?.makeClubTerminalProjectionProvider() })
    }
    func playDirector(activityID: Int) -> PlayDirectorCoordinator? {
        guard activityID > 0, let api = dormantPlayRuntimeService() else { return nil }
        let key = playRuntimeKey(.activity(activityID), suffix: "director")
        if let retained = retainedPlayDirectors[key] { return retained }
        let model = PlayDirectorCoordinator(activityID: activityID, service: api,
            currentSession: { [weak self] in self?.currentPlayRuntimeSession })
        retainedPlayDirectors[key] = model; return model
    }
    func playPrefab(scope: PlaySessionScope) -> PlayPrefabRuntimeCoordinator? {
        guard scope.isValid, let api = dormantPlayRuntimeService() else { return nil }
        let key = playRuntimeKey(scope, suffix: "prefab")
        if let retained = retainedPlayPrefabs[key] { return retained }
        let model = PlayPrefabRuntimeCoordinator(scope: scope, service: api, provider: scopedPlayDeviceProvider(),
            store: prefabRuntimeStore, currentSession: { [weak self] in self?.currentPlayRuntimeSession })
        retainedPlayPrefabs[key] = model; return model
    }
    private var retainedPlayStillness: [String: PlayStillnessCoordinator] = [:]
    func playStillness(scope: PlaySessionScope, nodeID: Int, configuration: PlayStillnessConfiguration, lifetime: PlayInteractionLifetime? = nil) -> PlayStillnessCoordinator? {
        guard let lifetime, lifetime.isCurrent, scope.isValid, nodeID > 0 else { return nil }
        let key = playRuntimeKey(scope, suffix: "stillness:\(nodeID):\(configuration.durationSeconds):\(configuration.tolerance)")
        if let retained = retainedPlayStillness[key], retained.readLifetimeID == lifetime.identity { return retained }
        retainedPlayStillness[key]?.pause()
        let model = PlayStillnessCoordinator(configuration: configuration, provider: makeRuntimeMotionProvider(), readLifetime: lifetime, currentContext: { [weak self] in
            guard let session = self?.currentPlayRuntimeSession else { return nil }
            return try? PlayDeviceContext(session: session, scope: scope, nodeID: nodeID)
        })
        retainedPlayStillness[key] = model; return model
    }
    // Session-owned dormant hosts. Identity/epoch keys prevent reuse after logout.
    private var retainedPlayPlayers: [String: PlayPlayerGameCoordinator] = [:]
    private var retainedPlayCircles: [String: PlayCircleCoordinator] = [:]
    private var retainedPlayDevices: [String: PlayDeviceCaptureCoordinator] = [:]
    private let unconfiguredPlayNativeDeviceProvider = PlayNativeDeviceProvider(grants: [])
    private var retainedNativePlayDevice: (context: RuntimeDependencyContext, provider: PlayNativeDeviceProvider)?
    var playNativeDeviceProvider: PlayNativeDeviceProvider {
        guard let context = currentRuntimeDependencyContext, let accepted = runtimeDependencyFactory?.accepted else { return unconfiguredPlayNativeDeviceProvider }
        if let retainedNativePlayDevice, retainedNativePlayDevice.context == context { return retainedNativePlayDevice.provider }
        retainedNativePlayDevice?.provider.cancel()
        let provider = PlayNativeDeviceProvider(grants: accepted.devices.intersection([.photo, .scan, .motion]))
        retainedNativePlayDevice = (context, provider); return provider
    }
    private func scopedPlayDeviceProvider() -> any PlayDeviceProviding {
        guard let captured = currentRuntimeDependencyContext, let accepted = runtimeDependencyFactory?.accepted else { return PlayDormantDeviceProvider() }
        return RuntimePlayDeviceProvider(native: playNativeDeviceProvider,
            location: runtimeDependencies.location ?? RuntimeNativeLocationProvider(enabled: accepted.devices.contains(.location)),
            grants: accepted.devices, isCurrent: { [weak self] in self?.currentRuntimeDependencyContext == captured })
    }
    private var retainedNativePlatform: NativePlatformRuntime?
    var nativePlatformRuntime: NativePlatformRuntime? {
        guard let owner = currentPlayRuntimeSession, let api = regionalConfiguration?.apiConfiguration,
              let factory = runtimeDependencyFactory, let accepted = factory.accepted,
              let approval = runtimeDependencies.nativePlatform, approval.validPurpose,
              (approval.stepsEnabled || approval.localRemindersEnabled || approval.enrollment?.enabled == true),
              (approval.enrollment?.requiredPaths ?? []).isSubset(of: accepted.endpoints.paths),
              (approval.enrollment?.enabled != true || approval.enrollment?.isValid == true),
              (!approval.stepsEnabled || accepted.endpoints.paths.contains(NativePlatformService.actionPath)),
              (!approval.localRemindersEnabled || accepted.endpoints.paths.contains(NativePlatformService.windowPath)) else {
            retainedNativePlatform?.invalidate(); retainedNativePlatform = nil; return nil
        }
        if let retainedNativePlatform, retainedNativePlatform.owner == owner { return retainedNativePlatform }
        retainedNativePlatform?.invalidate()
        let current = { [weak self] in self?.currentPlayRuntimeSession }
        let service = NativePlatformService(configuration: api, transport: factory.transport, owner: owner,
            stepsEnabled: approval.stepsEnabled, remindersEnabled: approval.localRemindersEnabled, current: current)
        let enrollment = NativeEnrollmentComposition.make(owner: owner, api: api, transport: factory.transport, approval: approval, current: current)
        guard approval.enrollment?.enabled != true || enrollment != nil else { return nil }
        let runtime = NativePlatformRuntime(owner: owner, acceptance: approval, service: service, current: current,
            makePedometer: { IPhonePedometerProvider(enabled: approval.stepsEnabled) },
            assertion: AppAttestStepAssertionProvider(deviceKeyID: approval.enrolledAppAttestKeyID ?? "", enabled: approval.stepsEnabled),
            reminders: AppleLocalReminderProvider(enabled: approval.localRemindersEnabled),
            enrollment: enrollment)
        retainedNativePlatform = runtime; return runtime
    }
    var playKitArtworkHosts: Set<String> { runtimeDependencyFactory?.accepted?.artworkHosts ?? [] }
    var playKitSpatialApproval: PlayKitSpatialApproval { runtimeDependencyFactory?.accepted?.spatial ?? .init() }
    private var runtimeSensorProviders: [RuntimeSensorReference] = []
    var playKitSensorFactory: (@MainActor () -> any PlayKitSensorProviding)? {
        guard let captured = currentRuntimeDependencyContext, let accepted = runtimeDependencyFactory?.accepted,
              !accepted.sensors.isEmpty else { return nil }
        return { [weak self] in
            guard self?.currentRuntimeDependencyContext == captured else { return PlayKitDormantSensorProvider() }
            let provider = RuntimePlayKitSensorProvider(provider: PlayKitNativeSensorProvider(grants: accepted.sensors),
                isCurrent: { [weak self] in self?.currentRuntimeDependencyContext == captured })
            self?.runtimeSensorProviders.removeAll { $0.value == nil }
            self?.runtimeSensorProviders.append(RuntimeSensorReference(provider))
            return provider
        }
    }
    private func makeRuntimeMotionProvider() -> any PlayMotionSampleProviding {
        guard let captured = currentRuntimeDependencyContext, let accepted = runtimeDependencyFactory?.accepted,
              accepted.sensors.contains(.acceleration) else { return PlayDormantMotionProvider() }
        if let injected = runtimeDependencies.motion { return injected }
        return RuntimeMotionSampleProvider(provider: PlayKitNativeSensorProvider(grants: [.acceleration]),
            isCurrent: { [weak self] in self?.currentRuntimeDependencyContext == captured })
    }
    func playPlayer(scope: PlaySessionScope) -> PlayPlayerGameCoordinator? {
        guard !committingAuthenticatedSession, case .activity(let id) = scope, id > 0,
              let regional = regionalConfiguration, let storageScope, let account, let token,
              let role = PlayRecoveryAccountRole(rawValue: account.effectiveRole),
              let captured = try? PlayExperienceSession(accountID: account.id, epoch: gate.currentStamp,
                  namespace: storageScope.service, token: token, role: role.rawValue),
              let api = dormantPlayRuntimeService() else { return nil }
        // One retained coordinator owns this viewer/activity. A returning role must not
        // revive an old in-memory lease after another viewer has reconciled the journal.
        let viewer = compositionViewerRevision
        let key = playRuntimeKey(scope, suffix: "player:\(viewer)")
        if let retained = retainedPlayPlayers[key] { return retained }
        guard let model = PlayGameSessionJournalFactory.makeCoordinator(scope: scope, service: api,
            session: captured, regionalConfiguration: regional, storageScope: storageScope,
            currentSession: { [weak self] in
                guard let self, self.matchesContinuationSession(captured, viewerRevision: viewer) else { return nil }
                return captured
            }, makeRecovery: { session, scope, regional, storageScope in
                try composition.storage.playRecovery.make(session: session, scope: scope,
                    regionalConfiguration: regional, storageScope: storageScope)
            }) else { return nil }
        // Storage construction grants no read or command capability. No memory fallback.
        retainedPlayPlayers[key] = model; return model
    }
    func playCircle(topicID: Int?) -> PlayCircleCoordinator? {
        guard let id = topicID, id > 0, let api = dormantPlayRuntimeService() else { return nil }
        let key = playRuntimeKey(.topic(id), suffix: "circle")
        if let retained = retainedPlayCircles[key] { return retained }
        let model = PlayCircleCoordinator(topicID: id, service: api, currentSession: { [weak self] in self?.currentPlayRuntimeSession })
        retainedPlayCircles[key] = model; return model
    }
    func playThemeAuxiliary(scope: PlaySessionScope, topicID: Int?) -> PlayThemeAuxiliaryReader? {
        guard scope.isValid, let id = topicID, id > 0, let api = dormantPlayRuntimeService() else { return nil }
        return PlayThemeAuxiliaryReader(service: api, scope: scope, topicID: id,
            current: { [weak self] in self?.currentPlayRuntimeSession })
    }
    var playThemeAuxiliaryProvider: PlayThemeAuxiliaryProvider {
        { [weak self] scope, topicID in self?.playThemeAuxiliary(scope: scope, topicID: topicID) }
    }
    func playDevice(scope: PlaySessionScope, nodeID: Int, lifetime: PlayInteractionLifetime? = nil) -> PlayDeviceCaptureCoordinator {
        let key = playRuntimeKey(scope, suffix: "device:\(nodeID)")
        if let retained = retainedPlayDevices[key], let lifetime, lifetime.isCurrent, retained.readLifetimeID == lifetime.identity { return retained }
        retainedPlayDevices[key]?.cancel()
        let api = lifetime.flatMap { lifetime in lifetime.isCurrent ? dormantPlayRuntimeService()?.bound(to: lifetime) : nil }
        let model = PlayDeviceCaptureCoordinator(provider: scopedPlayDeviceProvider(), filter: PlayNativePhotoFilter.render,
            upload: api?.enabled.contains(.mediaUpload) == true ? { [weak self] bytes, mime, context in
                guard let self, let session = self.currentPlayRuntimeSession,
                      (try? PlayDeviceContext(session: session, scope: scope, nodeID: nodeID)) == context,
                      let api else { throw PlayExperienceError.staleSession }
                return try await api.uploadPhoto(bytes, mimeType: mime, token: session.token)
            } : nil,
            readLifetime: lifetime, current: { [weak self] in
                guard let lifetime, lifetime.isCurrent, let session = self?.currentPlayRuntimeSession else { return nil }
                return try? PlayDeviceContext(session: session, scope: scope, nodeID: nodeID)
            })
        retainedPlayDevices[key] = model; return model
    }
    // Native App WeChat host: the adapter is mounted but all provider configuration,
    // SDK opt-in, service transport and live/legal grants remain unconfigured.
    private let weChatSDKDriver = WeChatNativeSDKDriver()
    private let weChatSDKConfiguration: WeChatSDKConfiguration? = nil
    private let weChatSDKGate = WeChatAppAuthGate()
    private lazy var weChatSDKAdapter = WeChatSDKAuthAdapter(driver: weChatSDKDriver,
        configuration: weChatSDKConfiguration, gate: { [weak self] in self?.weChatSDKGate ?? .init() },
        context: { [weak self] in
            self?.weChatContext ?? WeChatAppAuthContext(session: .init(epoch: 0, accountID: nil, isBusy: true), market: nil, namespace: nil)
        })
    private var weChatContext: WeChatAppAuthContext {
        WeChatAppAuthContext(session: AuthChannelSessionSnapshot(epoch: gate.currentStamp,
            accountID: account?.id, isBusy: isWorking || authChannels.state.isWorking),
            market: operationalMarket, namespace: storageScope?.service)
    }
    lazy var weChatAuth = WeChatAppAuthCoordinator(adapter: weChatSDKAdapter, gate: { [weak self] in self?.weChatSDKGate ?? .init() }, context: { [weak self] in
        self?.weChatContext ?? WeChatAppAuthContext(session: .init(epoch: 0, accountID: nil, isBusy: true), market: nil, namespace: nil)
    }, commit: { [weak self] result, expected in
        guard let self, self.weChatContext == expected, expected.permitsLogin else { return false }
        return try self.commitChannelLogin(result, expected: expected.session)
    })
    private let authChannelService: AuthChannelService?
    var authChannelSnapshot: AuthChannelSessionSnapshot {
        AuthChannelSessionSnapshot(epoch:gate.currentStamp,accountID:account?.id,isBusy:isWorking)
    }
    lazy var authChannels=AuthChannelCoordinator(service:authChannelService,currentSession:{ [weak self] in
        self?.authChannelSnapshot ?? AuthChannelSessionSnapshot(epoch:0,accountID:nil,isBusy:true)
    },commitLogin:{ [weak self] result,expected in
        guard let self else { return false }
        return try self.commitChannelLogin(result, expected: expected)
    })
    private func commitChannelLogin(_ result: LoginResult, expected: AuthChannelSessionSnapshot) throws -> Bool {
        guard self.authChannelSnapshot == expected, self.account == nil, !self.isWorking else { return false }
        try self.vault.write(result.token)
        self.invalidateWorkshopReadBindings()
        self.gate.invalidate()
        sessionDefaults.set(false,forKey:self.restoreBlockedKey)
        self.commitAuthenticatedSession(token: result.token, account: result.account);self.errorKey=nil
        self.participantCoordinator.synchronizeSession();self.synchronizeRegistration()
        self.clubActionCoordinator.synchronizeSession()
        clubManagementCoordinator.synchronizeSession();clubOperationsCoordinator.synchronizeSession();clubGovernanceCoordinator.cancelReview();profileEditCoordinator.synchronizeSession()
        self.merchantOnboardingCoordinator.synchronizeSession()
        return true
    }
    // Source-backed production factory, dormant until exact scoped approvals are injected.
    private var retainedOfficialActions: OfficialActionCoordinator?
    var officialActionCoordinator: OfficialActionCoordinator? {
        if let retainedOfficialActions { return retainedOfficialActions }
        guard let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let directory = root.appendingPathComponent("OfficialActionSafety", isDirectory: true)
        do { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) } catch { return nil }
        let access = OfficialActionProductionFactory(api: regionalConfiguration?.apiConfiguration,
            approval: runtimeDependencies.officialActionApproval, transport: runtimeHTTPTransport,
            current: { [weak self] in self?.currentRuntimeDependencyContext }, identity: { [weak self] in
                guard let self, let account = self.account, self.currentOfficialContext.isAuthenticated, let storageScope = self.storageScope else { return nil }
                return OfficialActionIdentity(accountID: account.id, epoch: self.officialEventReader.scope, namespace: storageScope.service)
            })
        let coordinator = OfficialActionCoordinator(access: access, locks: OfficialActionFileLocks(url: directory.appendingPathComponent("locks.json")))
        retainedOfficialActions = coordinator
        return coordinator
    }
    private let officialEventService:OfficialEventService?
    private var currentOfficialContext:OfficialReadContext {
        if let account,let token,
           let context=try? OfficialReadContext(accountID:account.id,epoch:gate.currentStamp,token:token) {
            return context
        }
        return OfficialReadContext(guestEpoch:gate.currentStamp)
    }
    lazy var officialEventReader=OfficialSessionReader(service:officialEventService,currentContext:{ [weak self] in
        self?.currentOfficialContext ?? OfficialReadContext(guestEpoch:0)
    },onUnauthorized:{ [weak self] captured in
        guard let self,self.currentOfficialContext == captured else { return }
        self.expireIfMatching(error:APIError.unauthorized,stamp:captured.epoch,credential:self.token)
    })
    private let profileWeeklyPointsService: ProfileWeeklyPointsService?
    private var currentProfileWeeklyPointsSession: ProfileWeeklyPointsSession? {
        guard let context = currentRuntimeDependencyContext else { return nil }
        let selected = composition.profileWeeklyPointsReadApproval(context)
        let approvalRevision = selected?.matches(context) == true ? selected?.revision : nil
        return try? ProfileWeeklyPointsSession(accountID: context.session.accountID,
            epoch: gate.currentStamp, viewerRevision: compositionViewerRevision, role: context.role,
            token: context.session.token, approvalRevision: approvalRevision)
    }
    lazy var profileWeeklyPointsReader = ProfileWeeklyPointsSessionReader(service: profileWeeklyPointsService,
        currentSession: { [weak self] in self?.currentProfileWeeklyPointsSession },
        onUnauthorized: { [weak self] captured in
            guard let self, self.currentProfileWeeklyPointsSession == captured else { return }
            self.expireIfMatching(error: APIError.unauthorized, stamp: captured.identity.epoch, credential: self.token)
        })
    /// 我的 header and 当前权益. Identity reuses the bootstrap `user/info` read; role info needs a lease.
    private var memberHomeService: MemberHomeService?
    private var currentMemberHomeSession: MemberHomeSession? {
        guard let account, let token else { return nil }
        let approval = currentRuntimeDependencyContext.flatMap { context in
            composition.memberRoleInfoReadApproval(context).flatMap { $0.matches(context) ? $0.revision : nil }
        }
        return try? MemberHomeSession(accountID: account.id, epoch: gate.currentStamp, token: token, roleInfoApproval: approval)
    }
    lazy var memberHomeReader = MemberHomeSessionReader(service: memberHomeService,
        currentSession: { [weak self] in self?.currentMemberHomeSession },
        onUnauthorized: { [weak self] captured in
            guard let self, self.currentMemberHomeSession == captured else { return }
            self.expireIfMatching(error: APIError.unauthorized, stamp: captured.epoch, credential: self.token)
        })
    private var ownMediaService: OwnMediaService?
    private var currentOwnMediaSession: OwnMediaSession? {
        guard let account, let token else { return nil }
        let approval = currentRuntimeDependencyContext.flatMap { context in
            composition.ownMediaReadApproval(context).flatMap { $0.matches(context) ? $0.revision : nil }
        }
        return try? OwnMediaSession(accountID: account.id, epoch: gate.currentStamp, token: token, approval: approval)
    }
    lazy var ownMediaReader = OwnMediaSessionReader(service: ownMediaService,
        currentSession: { [weak self] in self?.currentOwnMediaSession },
        onUnauthorized: { [weak self] captured in
            guard let self, self.currentOwnMediaSession == captured else { return }
            self.expireIfMatching(error: APIError.unauthorized, stamp: captured.epoch, credential: self.token)
        })
    private let growthCenterService:GrowthCenterService?
    private var currentGrowthCenterSession:GrowthCenterReadSession? {
        guard let account,let token else { return nil }
        let approvalRevision = currentRuntimeDependencyContext.flatMap { context in
            composition.growthNormalReadApproval(context).flatMap { $0.matches(context) ? $0.revision : nil }
        }
        return try? GrowthCenterReadSession(accountID:account.id,epoch:gate.currentStamp,token:token,
            approvalRevision:approvalRevision,viewerRevision:compositionViewerRevision)
    }
    lazy var growthCenterReader=GrowthCenterSessionReader(service:growthCenterService,currentSession:{ [weak self] in self?.currentGrowthCenterSession },onUnauthorized:{ [weak self] captured in
        guard let self,self.currentGrowthCenterSession == captured else { return }
        self.expireIfMatching(error:APIError.unauthorized,stamp:captured.epoch,credential:self.token)
    })
    private var retainedProjectEditors: [String: ProjectEditCoordinator] = [:]
    @Published private var projectConfigurationRevision: UInt64 = 0
    private var projectConfigurationChanging = false
    /// The owner of a reviewed project selector must use this synchronous boundary BEFORE
    /// changing any projectRead/projectWrite or approvedTopicReview*/approvedTopicRelease*
    /// capability, merchantDraftSelectionList/Resolve, ownedTopicCoverApproval, projectStoryImageUploadApproval, projectNodeImageUploadApproval or projectStoryAudioUploadApproval, including A → nil → identical A.
    /// The counter only retires prior contexts. It neither grants routes nor changes stored ownership.
    func withProjectEditConfigurationChange(_ mutation: () -> Void) {
        let alreadyChanging = projectConfigurationChanging
        projectConfigurationChanging = true
        projectConfigurationRevision &+= 1
        retainedProjectEditors.values.forEach { $0.synchronizeSession() }
        retainedProjectEditors.removeAll()
        defer { projectConfigurationRevision &+= 1; projectConfigurationChanging = alreadyChanging }
        mutation()
    }
    var projectEditorContextID: String { "\(gate.currentStamp):\(compositionViewerRevision):\(projectConfigurationRevision)" }
    private lazy var projectStoryAudioJournal = ProjectStoryAudioJournal(storage: ProjectEditSecureStorage(scope: storageScope))
    private lazy var projectStoryImageJournal = ProjectStoryImageJournal(storage: ProjectEditSecureStorage(scope: storageScope))
    private lazy var projectNodeImageJournal = ProjectNodeImageJournal(storage: ProjectEditSecureStorage(scope: storageScope))
    private lazy var ownedTopicCoverJournal = OwnedTopicCoverJournal(storage: ProjectEditSecureStorage(scope: storageScope))
    private lazy var projectReviewJournal = ApprovedTopicReviewJournal(storage: ProjectEditSecureStorage(scope: storageScope))
    private lazy var projectReleaseJournal = ApprovedTopicReleasePublicationJournal(storage: ProjectEditSecureStorage(scope: storageScope))
    private lazy var projectDraftStore = ProjectEditLocalStore(storage: ProjectEditSecureStorage(scope: storageScope))
    private var currentProjectEditSession: ProjectEditSession? {
        guard !projectConfigurationChanging, let account, token != nil, let storageScope else { return nil }
        return try? ProjectEditSession(accountID: account.id, epoch: gate.currentStamp, storageNamespace: storageScope.service, viewerRevision: compositionViewerRevision, configurationRevision: projectConfigurationRevision)
    }
    var projectEditorIsConfigured: Bool { projectRuntimeFactory?.permits(.projectRead) == true }
    func projectEditor(product: ProjectEditProduct, owner: ProjectEditOwner = .personal) -> ProjectEditCoordinator {
        let key = "\(projectEditorContextID):\(account?.id ?? 0):\(account?.effectiveRole ?? "guest"):\(product.rawValue):\(owner.rawValue)"
        if let retained = retainedProjectEditors[key] { return retained }
        let service = projectEditorService(owner: owner)
        var draft = ProjectEditDraft(product: product); draft.owner = owner
        let coordinator = ProjectEditCoordinator(initial: .init(draft: draft), service: service, store: projectDraftStore, releasePreparationSource: makeApprovedReleasePreparationSource(owner: owner), releasePublicationSource: makeApprovedReleasePublicationSource(owner: owner), releasePublicationJournal: projectReleaseJournal, releaseReviewSource: makeApprovedTopicReviewSource(owner: owner), releaseReviewJournal: projectReviewJournal, ownedCoverSource: makeOwnedTopicCoverSource(owner: owner), ownedCoverJournal: ownedTopicCoverJournal, topicImageSource: makeProjectTopicImageSource(owner: owner), storyImageSource: makeProjectStoryImageSource(owner: owner), storyImageJournal: projectStoryImageJournal, nodeImageSource: makeProjectNodeImageSource(owner: owner), nodeImageJournal: projectNodeImageJournal, storyAudioSource: makeProjectStoryAudioSource(owner: owner), storyAudioJournal: projectStoryAudioJournal, merchantDraftSource: makeProjectMerchantDraftSource(),
            currentSession: { [weak self] in self?.currentProjectEditSession })
        retainedProjectEditors[key] = coordinator
        return coordinator
    }
    /// The owned-list scope selects a read, never a mode, version, or write grant.
    func projectEditor(target: ProjectEditRemoteTarget) -> ProjectEditCoordinator? {
        guard creatorContentReader.isAuthenticated, creatorContentReader.isConfigured,
              creatorContentReader.scope == target.readerScope, currentProjectEditSession != nil else { return nil }
        let key = "remote:\(projectEditorContextID):\(account?.id ?? 0):\(account?.effectiveRole ?? "guest"):\(target.owner.rawValue):\(target.topicID)"
        if let retained = retainedProjectEditors[key] { return retained }
        // The placeholder has no displayed/editable snapshot. load() replaces it with
        // the mandatory fresh productType/editScope/revision from edit-detail.
        var placeholder = ProjectEditDraft(); placeholder.owner = target.owner
        let coordinator = ProjectEditCoordinator(initial: .init(topicID: target.topicID, draft: placeholder),
            service: projectEditorService(owner: target.owner), store: projectDraftStore, releasePreparationSource: makeApprovedReleasePreparationSource(owner: target.owner), releasePublicationSource: makeApprovedReleasePublicationSource(owner: target.owner), releasePublicationJournal: projectReleaseJournal, releaseReviewSource: makeApprovedTopicReviewSource(owner: target.owner), releaseReviewJournal: projectReviewJournal, ownedCoverSource: makeOwnedTopicCoverSource(owner: target.owner), ownedCoverJournal: ownedTopicCoverJournal, topicImageSource: makeProjectTopicImageSource(owner: target.owner), storyImageSource: makeProjectStoryImageSource(owner: target.owner), storyImageJournal: projectStoryImageJournal, nodeImageSource: makeProjectNodeImageSource(owner: target.owner), nodeImageJournal: projectNodeImageJournal, storyAudioSource: makeProjectStoryAudioSource(owner: target.owner), storyAudioJournal: projectStoryAudioJournal, merchantDraftSource: makeProjectMerchantDraftSource(),
            currentSession: { [weak self] in self?.currentProjectEditSession })
        retainedProjectEditors[key] = coordinator; return coordinator
    }
    private func makeProjectMerchantDraftSource() -> (any ProjectMerchantDraftReading)? {
        let features: Set<BusinessRuntimeFeature> = [.merchantDraftSelectionList, .merchantDraftSelectionResolve]
        guard let factory = approvedReleaseRuntimeFactory, features.allSatisfy({ factory.permits($0) }),
              let configuration = regionalConfiguration?.apiConfiguration else { return nil }
        let captured = factory.captured, viewerRevision = compositionViewerRevision, configurationRevision = projectConfigurationRevision
        return ProjectMerchantDraftClient(configuration: configuration, approval: factory.approval(features), transport: factory.client(features),
            currentCredentials: { [weak self] in
                guard let self, !self.projectConfigurationChanging, self.projectConfigurationRevision == configurationRevision,
                      self.compositionViewerRevision == viewerRevision, self.currentRuntimeDependencyContext == captured,
                      let current = self.approvedReleaseRuntimeFactory, features.allSatisfy({ current.permits($0) }),
                      let session = self.currentProjectEditSession, let token = self.token else { return nil }
                return try? .init(session: session, token: token)
            }, currentCapability: { [weak self] path in
                guard let self, !self.projectConfigurationChanging, self.projectConfigurationRevision == configurationRevision,
                      self.compositionViewerRevision == viewerRevision, self.currentRuntimeDependencyContext == captured,
                      let current = self.approvedReleaseRuntimeFactory else { return false }
                if path == ProjectMerchantDraftPath.list { return current.permits(.merchantDraftSelectionList) }
                if path == ProjectMerchantDraftPath.resolve { return current.permits(.merchantDraftSelectionResolve) }
                return false
            })
    }
    private var approvedReleaseRuntimeFactory: BusinessRuntimeFactory? {
        guard !projectConfigurationChanging, let api = regionalConfiguration?.apiConfiguration, storageScope != nil,
              let context = currentRuntimeDependencyContext,
              let configuration = (injectedRuntimeDependencies ?? composition.sessionDependencies(context)).businessConfiguration,
              configuration.matches(context) else { return nil }
        return BusinessRuntimeFactory(configuration: configuration, api: api, transport: runtimeHTTPTransport,
            current: { [weak self] in self?.currentRuntimeDependencyContext })
    }
    private func makeProjectStoryAudioSource(owner: ProjectEditOwner) -> (any ProjectStoryAudioUploading)? {
        guard owner == .personal, !projectConfigurationChanging, let context = currentRuntimeDependencyContext, context.market == .china,
              let configuration = regionalConfiguration?.apiConfiguration, let session = currentProjectEditSession,
              let approval = composition.projectStoryAudioUploadApproval(context), approval.matches(configuration: configuration, session: session) else { return nil }
        let revision = projectConfigurationRevision, viewer = compositionViewerRevision
        let currentApproval: () -> ProjectStoryAudioUploadApproval? = { [weak self] in
            guard let self, !self.projectConfigurationChanging, self.projectConfigurationRevision == revision,
                  self.compositionViewerRevision == viewer, self.currentRuntimeDependencyContext == context else { return nil }
            return self.composition.projectStoryAudioUploadApproval(context)
        }
        return ProjectStoryAudioUploadClient(configuration: configuration, approval: approval,
            transport: compositionTransport.replacingUnderlying(composition.makeProjectStoryAudioUploadTransport()),
            credentials: { [weak self] in
                guard let self, currentApproval() == approval, self.currentProjectEditSession == session, let token = self.token else { return nil }
                return try? .init(session: session, token: token)
            }, currentApproval: currentApproval)
    }
    private func makeProjectTopicImageSource(owner: ProjectEditOwner) -> (any ProjectTopicImageUploading)? {
        guard owner == .personal, !projectConfigurationChanging, let context = currentRuntimeDependencyContext, context.market == .china,
              let configuration = regionalConfiguration?.apiConfiguration, let session = currentProjectEditSession,
              let approval = composition.projectTopicImageUploadApproval(context), approval.matches(configuration: configuration, session: session) else { return nil }
        let revision = projectConfigurationRevision, viewer = compositionViewerRevision
        let currentApproval: () -> ProjectTopicImageUploadApproval? = { [weak self] in
            guard let self, !self.projectConfigurationChanging, self.projectConfigurationRevision == revision,
                  self.compositionViewerRevision == viewer, self.currentRuntimeDependencyContext == context else { return nil }
            return self.composition.projectTopicImageUploadApproval(context)
        }
        return ProjectTopicImageUploadClient(configuration: configuration, approval: approval,
            transport: compositionTransport.replacingUnderlying(composition.makeProjectTopicImageUploadTransport()),
            credentials: { [weak self] in
                guard let self, currentApproval() == approval, self.currentProjectEditSession == session, let token = self.token else { return nil }
                return try? .init(session: session, token: token)
            }, currentApproval: currentApproval)
    }
    private func makeProjectStoryImageSource(owner: ProjectEditOwner) -> (any ProjectStoryImageUploading)? {
        guard owner == .personal, !projectConfigurationChanging, let context = currentRuntimeDependencyContext,
              let configuration = regionalConfiguration?.apiConfiguration, let session = currentProjectEditSession,
              let approval = composition.projectStoryImageUploadApproval(context), approval.matches(configuration: configuration, session: session) else { return nil }
        let revision = projectConfigurationRevision, viewer = compositionViewerRevision
        let currentApproval: () -> ProjectStoryImageUploadApproval? = { [weak self] in
            guard let self, !self.projectConfigurationChanging, self.projectConfigurationRevision == revision,
                  self.compositionViewerRevision == viewer, self.currentRuntimeDependencyContext == context else { return nil }
            return self.composition.projectStoryImageUploadApproval(context)
        }
        return ProjectStoryImageUploadClient(configuration: configuration, approval: approval,
            transport: compositionTransport.replacingUnderlying(composition.makeProjectStoryImageUploadTransport()),
            credentials: { [weak self] in
                guard let self, currentApproval() == approval, self.currentProjectEditSession == session, let token = self.token else { return nil }
                return try? .init(session: session, token: token)
            }, currentApproval: currentApproval)
    }
    private func makeProjectNodeImageSource(owner: ProjectEditOwner) -> (any ProjectNodeImageUploading)? {
        guard owner == .personal, !projectConfigurationChanging, let context = currentRuntimeDependencyContext, context.market == .china,
              let configuration = regionalConfiguration?.apiConfiguration, let session = currentProjectEditSession,
              let approval = composition.projectNodeImageUploadApproval(context), approval.matches(configuration: configuration, session: session),
              let checkedTransport = composition.makeProjectNodeImageUploadTransport() else { return nil }
        let revision = projectConfigurationRevision, viewer = compositionViewerRevision
        let currentApproval: () -> ProjectNodeImageUploadApproval? = { [weak self] in
            guard let self, !self.projectConfigurationChanging, self.projectConfigurationRevision == revision,
                  self.compositionViewerRevision == viewer, self.currentRuntimeDependencyContext == context else { return nil }
            return self.composition.projectNodeImageUploadApproval(context)
        }
        return ProjectNodeImageUploadClient(configuration: configuration, approval: approval,
            transport: ProjectNodeImageScopedTransport(baseURL: configuration.baseURL, policy: approval.policy,
                underlying: checkedTransport, current: { currentApproval() == approval }),
            credentials: { [weak self] in
                guard let self, currentApproval() == approval, self.currentProjectEditSession == session, let token = self.token else { return nil }
                return try? .init(session: session, token: token)
            }, currentApproval: currentApproval)
    }
    private func makeOwnedTopicCoverSource(owner: ProjectEditOwner) -> (any OwnedTopicCoverServing)? {
        guard owner == .personal, !projectConfigurationChanging, let context = currentRuntimeDependencyContext,
              let configuration = regionalConfiguration?.apiConfiguration, let session = currentProjectEditSession,
              let approval = composition.ownedTopicCoverApproval(context),
              approval.baseURL == configuration.baseURL, approval.namespace == session.storageNamespace, approval.accountID == session.accountID else { return nil }
        let revision = projectConfigurationRevision, viewer = compositionViewerRevision
        let currentApproval: () -> OwnedTopicCoverApproval? = { [weak self] in
            guard let self, !self.projectConfigurationChanging, self.projectConfigurationRevision == revision,
                  self.compositionViewerRevision == viewer, self.currentRuntimeDependencyContext == context else { return nil }
            return self.composition.ownedTopicCoverApproval(context)
        }
        return OwnedTopicCoverClient(configuration: configuration, approval: approval,
            jsonTransport: compositionTransport.replacingUnderlying(composition.makeOwnedTopicCoverTransport(64 * 1024)),
            imageTransport: compositionTransport.replacingUnderlying(composition.makeOwnedTopicCoverTransport(OwnedTopicCoverClient.maximumContentBytes)),
            currentCredentials: { [weak self] in
                guard let self, currentApproval() == approval, let current = self.currentProjectEditSession, current == session, let token = self.token else { return nil }
                return try? .init(session: current, token: token)
            }, currentApproval: currentApproval)
    }
    private func makeApprovedTopicReviewSource(owner: ProjectEditOwner) -> (any ApprovedTopicReviewServing)? {
        let features: Set<BusinessRuntimeFeature> = [.approvedTopicReviewSources, .approvedTopicReviewPrepare, .approvedTopicReviewSubmit, .approvedTopicReviewStatus, .approvedTopicReviewCurrent]
        guard owner == .personal, let factory = approvedReleaseRuntimeFactory,
              features.contains(where: { factory.permits($0) }), let configuration = regionalConfiguration?.apiConfiguration else { return nil }
        let captured = factory.captured, viewerRevision = compositionViewerRevision, configurationRevision = projectConfigurationRevision
        return ApprovedTopicReviewClient(configuration: configuration, approval: factory.approval(features), transport: factory.client(features),
            currentCredentials: { [weak self] in
                guard let self, !self.projectConfigurationChanging, self.projectConfigurationRevision == configurationRevision, self.compositionViewerRevision == viewerRevision, self.currentRuntimeDependencyContext == captured,
                      let current = self.approvedReleaseRuntimeFactory, features.contains(where: { current.permits($0) }),
                      let session = self.currentProjectEditSession, let token = self.token else { return nil }
                return try? .init(session: session, token: token)
            }, currentCapability: { [weak self] path in
                guard let self, !self.projectConfigurationChanging, self.projectConfigurationRevision == configurationRevision, self.compositionViewerRevision == viewerRevision, self.currentRuntimeDependencyContext == captured, let current = self.approvedReleaseRuntimeFactory else { return false }
                if path == ApprovedTopicReviewPath.sources { return current.permits(.approvedTopicReviewSources) }
                if path == ApprovedTopicReviewPath.prepare { return current.permits(.approvedTopicReviewPrepare) }
                if path == ApprovedTopicReviewPath.submit { return current.permits(.approvedTopicReviewSubmit) }
                if path == ApprovedTopicReviewPath.status { return current.permits(.approvedTopicReviewStatus) }
                if path == ApprovedTopicReviewPath.current { return current.permits(.approvedTopicReviewCurrent) }
                return false
            })
    }
    private func makeApprovedReleasePreparationSource(owner: ProjectEditOwner) -> (any ApprovedTopicReleasePreparing)? {
        guard owner == .personal, let factory = approvedReleaseRuntimeFactory,
              factory.permits(.approvedTopicReleasePrepare), let configuration = regionalConfiguration?.apiConfiguration else { return nil }
        let captured = factory.captured, viewerRevision = compositionViewerRevision, configurationRevision = projectConfigurationRevision
        return ApprovedTopicReleasePreparationClient(configuration: configuration,
            approval: factory.approval([.approvedTopicReleasePrepare]), transport: factory.client([.approvedTopicReleasePrepare]),
            currentCredentials: { [weak self] in
                guard let self, !self.projectConfigurationChanging, self.projectConfigurationRevision == configurationRevision, self.compositionViewerRevision == viewerRevision, self.currentRuntimeDependencyContext == captured,
                      self.approvedReleaseRuntimeFactory?.permits(.approvedTopicReleasePrepare) == true,
                      let session = self.currentProjectEditSession, let token = self.token else { return nil }
                return try? .init(session: session, token: token)
            })
    }
    private func makeApprovedReleasePublicationSource(owner: ProjectEditOwner) -> (any ApprovedTopicReleasePublishing)? {
        guard owner == .personal, let factory = approvedReleaseRuntimeFactory,
              factory.permits(.approvedTopicReleasePublish) || factory.permits(.approvedTopicReleaseStatus),
              let configuration = regionalConfiguration?.apiConfiguration else { return nil }
        let captured = factory.captured, viewerRevision = compositionViewerRevision, configurationRevision = projectConfigurationRevision
        return ApprovedTopicReleasePublicationClient(configuration: configuration,
            approval: factory.approval([.approvedTopicReleasePublish, .approvedTopicReleaseStatus]),
            transport: factory.client([.approvedTopicReleasePublish, .approvedTopicReleaseStatus]),
            currentCredentials: { [weak self] in
                guard let self, !self.projectConfigurationChanging, self.projectConfigurationRevision == configurationRevision, self.compositionViewerRevision == viewerRevision, self.currentRuntimeDependencyContext == captured,
                      let current = self.approvedReleaseRuntimeFactory,
                      current.permits(.approvedTopicReleasePublish) || current.permits(.approvedTopicReleaseStatus),
                      let session = self.currentProjectEditSession, let token = self.token else { return nil }
                return try? .init(session: session, token: token)
            }, currentCapability: { [weak self] path in
                guard let self, !self.projectConfigurationChanging, self.projectConfigurationRevision == configurationRevision, self.compositionViewerRevision == viewerRevision, self.currentRuntimeDependencyContext == captured, let current = self.approvedReleaseRuntimeFactory else { return false }
                if path == ApprovedTopicReleasePublicationPath.publish { return current.permits(.approvedTopicReleasePublish) }
                if path == ApprovedTopicReleasePublicationPath.status { return current.permits(.approvedTopicReleaseStatus) }
                return false
            })
    }
    private var projectRuntimeFactory: BusinessRuntimeFactory? {
        guard !projectConfigurationChanging, let api = regionalConfiguration?.apiConfiguration, storageScope != nil,
              let context = currentRuntimeDependencyContext,
              let configuration = (injectedRuntimeDependencies ?? composition.sessionDependencies(context)).businessConfiguration,
              configuration.matches(context) else { return nil }
        return BusinessRuntimeFactory(configuration: configuration, api: api, transport: runtimeHTTPTransport,
            current: { [weak self] in self?.currentRuntimeDependencyContext })
    }
    private func projectEditorService(owner: ProjectEditOwner) -> any ProjectEditServing {
        let service: any ProjectEditServing
        if let factory = projectRuntimeFactory, factory.permits(.projectRead), let configuration = regionalConfiguration?.apiConfiguration {
            let captured = factory.captured, viewerRevision = compositionViewerRevision, configurationRevision = projectConfigurationRevision
            service = ProjectEditHTTPService(configuration: configuration, transport: factory.client([.projectRead, .projectWrite]),
                owner: owner, approval: factory.approval([.projectWrite]), store: projectDraftStore,
                currentCredentials: { [weak self] in
                    guard let self, !self.projectConfigurationChanging, self.projectConfigurationRevision == configurationRevision, self.compositionViewerRevision == viewerRevision, self.currentRuntimeDependencyContext == captured,
                          self.projectRuntimeFactory?.permits(.projectRead) == true,
                          let session = self.currentProjectEditSession, let token = self.token else { return nil }
                    return try? ProjectEditCredentials(session: session, token: token)
                })
        } else { service = ProjectEditDisabledService() }
        return service
    }
    private var publishingEpochCache: (stamp: UInt64, accountID: Int, role: String, epoch: UUID)?
    var publishingSession: PublishingSession? {
        guard let account, token != nil, let storageScope, let market = operationalMarket else { return nil }
        let role = account.effectiveRole
        if publishingEpochCache?.stamp != gate.currentStamp || publishingEpochCache?.accountID != account.id || publishingEpochCache?.role != role {
            publishingEpochCache = (gate.currentStamp, account.id, role, UUID())
        }
        guard let epoch = publishingEpochCache?.epoch else { return nil }
        return PublishingSession(namespace: storageScope.service, accountID: account.id, epoch: epoch, role: role,
                                 region: market == .china ? .china : .unitedStates)
    }
    private var retainedPublisherLifecycle: (session: PublishingSession, context: PublisherLifecycleHostContext)?
    var publisherLifecycleContext: PublisherLifecycleHostContext? {
        guard let publishingSession, let configuration = regionalConfiguration?.apiConfiguration else {
            retainedPublisherLifecycle?.context.invalidate(); retainedPublisherLifecycle = nil; return nil
        }
        if let retainedPublisherLifecycle, retainedPublisherLifecycle.session == publishingSession { return retainedPublisherLifecycle.context }
        retainedPublisherLifecycle?.context.invalidate()
        guard let factory = runtimeDependencyFactory else { return nil }
        let viewerRevision = compositionViewerRevision
        let context = PublisherLifecycleHostContext(configuration: configuration, transport: factory.transport, creatorReader: creatorContentReader,
            grants: factory.publisherGrants, merchantPartnerReader: readOnlyPublicMerchantHomeContext.reader,
            credentials: { [weak self] in
                guard let self, self.compositionViewerRevision == viewerRevision,
                      let session = self.publishingSession, session == publishingSession, let token = self.token else { return nil }
                return try? PublishingCredentials(session: session, token: token)
            }, freshAuthority: { [weak self] resource, captured in
                guard let self else { throw PublisherLifecycleError.unavailable }
                return try await self.freshPublisherAuthority(resource, session: captured)
            })
        retainedPublisherLifecycle = (publishingSession, context); return context
    }
    func freshPublisherAuthority(_ resource: PublishedResource, session captured: PublishingSession) async throws -> PublisherAuthority {
        let reader = PublisherSourceAuthorityReader(topics: topicReader, clubs: self,
            activityDetail: { [weak self] id in
                guard let self else { throw PublisherLifecycleError.unavailable }; return try await self.activityDetail(id: id)
            }, currentSession: { [weak self] in self?.publishingSession })
        return try await reader.freshAuthority(resource, session: captured)
    }
    /// Existing-content editing is independently approved. Create permission never supplies these grants.
    private let publisherIdentityRegistrationApproval: (RuntimeDependencyContext) -> PublisherIdentityRegistrationGrants
    func makePublisherIdentityRegistrationService() -> PublisherIdentityRegistrationService? {
        guard let captured = publishingSession, let context = currentRuntimeDependencyContext,
              let configuration = regionalConfiguration?.apiConfiguration else { return nil }
        let grants = publisherIdentityRegistrationApproval(context), viewerRevision = compositionViewerRevision
        return PublisherIdentityRegistrationService(configuration: configuration, transport: runtimeHTTPTransport,
            grants: grants, journal: composition.storage.operationJournal(), session: captured, credentials: { [weak self] in
                guard let self, self.publishingSession == captured, self.currentRuntimeDependencyContext == context,
                      self.compositionViewerRevision == viewerRevision, self.publisherIdentityRegistrationApproval(context) == grants, let token = self.token else { return nil }
                return try? PublishingCredentials(session: captured, token: token)
            })
    }
    private let activityCoverApproval: (RuntimeDependencyContext) -> ActivityCoverApproval?
    func makeActivityCoverService() -> ActivityCoverService? {
        guard let captured = publishingSession, let context = currentRuntimeDependencyContext,
              let configuration = regionalConfiguration?.apiConfiguration else { return nil }
        let issued = activityCoverApproval(context), viewerRevision = compositionViewerRevision
        return ActivityCoverService(configuration: configuration, transport: runtimeHTTPTransport, approval: issued,
            currentApproval: { [weak self] in
                guard let self, self.currentRuntimeDependencyContext == context, self.compositionViewerRevision == viewerRevision else { return nil }
                return self.activityCoverApproval(context)
            }, credentials: { [weak self] in
                guard let self, self.publishingSession == captured, self.currentRuntimeDependencyContext == context,
                      self.compositionViewerRevision == viewerRevision, let token = self.token else { return nil }
                return try? PublishingCredentials(session: captured, token: token)
            }, journal: composition.storage.operationJournal())
    }
    private let activityEditingApproval: (RuntimeDependencyContext) -> ActivityEditingGrants
    /// Nil approval keeps coop writes on the dormant path. The slot is read at the POST.
    private let coopFlowExecutionApproval: (RuntimeDependencyContext) -> CoopFlowExecutionApproval?
    private let coopFlowExecutionSlot: CoopFlowExecutionSlot
    /// Closed write approval: chapter invite and accept/reject do not POST.
    private let merchantContentWriteApproval: (RuntimeDependencyContext) -> MerchantContentWriteApproval
    func activityEditingController(id: Int) -> ActivityEditingController? {
        guard let captured = publishingSession, let context = currentRuntimeDependencyContext,
              let configuration = regionalConfiguration?.apiConfiguration else { return nil }
        let grants = activityEditingApproval(context), viewerRevision = compositionViewerRevision
        let service = ActivityEditingService(configuration: configuration, transport: runtimeHTTPTransport,
            grants: grants,
            drafts: ActivityEditingDraftStore(storage: ProjectEditSecureStorage(scope: storageScope),
                journal: composition.storage.operationJournal()),
            credentials: { [weak self] in
                guard let self, self.publishingSession == captured, self.currentRuntimeDependencyContext == context,
                      self.compositionViewerRevision == viewerRevision, self.activityEditingApproval(context) == grants, let token = self.token else { return nil }
                return try? PublishingCredentials(session: captured, token: token)
            })
        return ActivityEditingController(activityID: id, session: captured, service: service)
    }
    /// Pass-through of `activityEditingApproval`. Nil read/update stay closed; this does not approve `api/activity/info` or `api/activity/update`.
    func activityEditingGrants() -> ActivityEditingGrants {
        guard let context = currentRuntimeDependencyContext else { return .init() }
        return activityEditingApproval(context)
    }
    private var retainedPublishingService: (context: RuntimeDependencyContext, service: PublishingService)?
    var publishingService: PublishingService? {
        guard let factory = businessRuntimeFactory, factory.permits(.publishingRead),
              let configuration = regionalConfiguration?.apiConfiguration else { return nil }
        if let retainedPublishingService, retainedPublishingService.context == factory.captured { return retainedPublishingService.service }
        retainedPublishingService?.service.invalidateReviews()
        let captured = factory.captured
        let service = PublishingService(configuration: configuration, transport: factory.client([.publishingRead, .publishingWrite]),
            approval: factory.approval([.publishingWrite]), journal: composition.storage.operationJournal(),
            credentials: { [weak self] in
                guard let self, self.currentRuntimeDependencyContext == captured, let session = self.publishingSession,
                      let token = self.token else { return nil }
                return try? PublishingCredentials(session: session, token: token)
            })
        retainedPublishingService = (captured, service); return service
    }
    /// Separate provider-grant feature; publishing read/write grants never enable AI.
    func makePublishingAuxiliaryService(feature: BusinessRuntimeFeature) -> PublishingAuxiliaryService? {
        guard let factory = businessRuntimeFactory else { return nil }
        let captured = factory.captured
        return factory.publishingAuxiliary(feature: feature, journal: composition.storage.operationJournal(), credentials: { [weak self] in
            guard let self, self.currentRuntimeDependencyContext == captured,
                  let session = self.publishingSession, let token = self.token else { return nil }
            return try? PublishingCredentials(session: session, token: token)
        })
    }
    var publishingAIDraftFactory: (() -> any PublishingAIDraftServing)? {
        guard let factory = businessRuntimeFactory, factory.permits(.publishingAIQuota), factory.permits(.publishingAITheme),
              let configuration = regionalConfiguration?.apiConfiguration,
              let assistance = makePublishingAuxiliaryService(feature: .publishingAITheme) else { return nil }
        let captured = factory.captured
        let quotaTransport = PublishingAIRuntimeTransport(feature: .publishingAIQuota, baseURL: configuration.baseURL, transport: factory.client([.publishingAIQuota]))
        let reads = PublishingService(configuration: configuration, transport: quotaTransport, credentials: { [weak self] in
            guard let self, self.currentRuntimeDependencyContext == captured,
                  let session = self.publishingSession, let token = self.token else { return nil }
            return try? PublishingCredentials(session: session, token: token)
        })
        let client = PublishingAIDraftClient(reads: reads, assistance: assistance)
        return { client }
    }
    lazy var publishingDraftStore = PublishingDraftStore(storage: ProjectEditSecureStorage(scope: storageScope))
    /// Production mounts no read grant or write approval. An approved integration may inject
    /// a read transport; the returned service still has no mutation approval or journal.
    func makePublishingService(readApproval: OperationEndpointApproval? = nil,
                               transport: (any HTTPTransport)? = nil) -> PublishingService? {
        let transport = scopedTransport(transport)
        guard let configuration = regionalConfiguration?.apiConfiguration, let readApproval,
              let scope = storageScope, readApproval.baseURL == configuration.baseURL,
              readApproval.namespace == scope.service else { return nil }
        let guarded = PublishingApprovedReadTransport(configuration: configuration, approval: readApproval,
                                                      transport: transport, currentCredentials: { [weak self] in
                guard let self, let session = self.publishingSession, let token = self.token else { return nil }
                return try? PublishingCredentials(session: session, token: token)
            })
        return PublishingService(configuration: configuration, transport: guarded, credentials: { [weak self] in
            guard let self, let session = self.publishingSession, let token = self.token else { return nil }
            return try? PublishingCredentials(session: session, token: token)
        })
    }
    private let nativeWeChatPaymentDriver = WeChatNativePaymentDriver()
    private lazy var nativeWeChatPaymentAdapter = WeChatSDKPaymentAdapter(driver: nativeWeChatPaymentDriver,
        configuration: runtimeDependencies.weChatPaymentConfiguration,
        allowed: { [weak self] in
            guard let self else { return false }
            if let auth = self.weChatSDKConfiguration, let payment = self.runtimeDependencies.weChatPaymentConfiguration,
               auth.appID != payment.sdk.appID || auth.universalLink != payment.sdk.universalLink { return false }
            let selfPlayAllowed = self.businessRuntimeFactory.map {
                $0.configuration.selfPlayExternalCheckoutApproved && $0.configuration.selfPlayPayment && $0.permits(.topicSelfPlayPay)
            } ?? false
            return selfPlayAllowed || self.orderLifecyclePaymentProviderAllowed
        }, context: { [weak self] in self?.currentRuntimeDependencyContext })
    private let selfPlayOperationGate = TopicSelfPlayOperationGate()
    private var retainedSelfPlayFlows: [String: TopicSelfPlayFlow] = [:]
    func topicSelfPlayFlow(topic: TopicDetail) -> TopicSelfPlayFlow? {
        guard let factory = businessRuntimeFactory, let configuration = regionalConfiguration?.apiConfiguration,
              factory.configuration.selfPlayExternalCheckoutApproved, factory.permits(.topicSelfPlayRead), factory.permits(.topicSelfPlayCreate),
              factory.permits(.topicSelfPlayConsentRead), factory.permits(.topicSelfPlayConsentWrite),
              let document = runtimeDependencies.signupDocument, let directory = safetyDirectory("TopicSelfPlayConsent"),
              let session = publishingSession, ["player", "club"].contains(session.role), topic.selfPlay == 1 else { return nil }
        let captured = factory.captured
        let key = "\(session.storageKey)|\(session.epoch)|\(topic.id)"
        if let retained = retainedSelfPlayFlows[key] { return retained }
        let features: Set<BusinessRuntimeFeature> = [.topicSelfPlayRead, .topicSelfPlayCreate, .topicSelfPlayPay, .topicSelfPlayConsentRead, .topicSelfPlayConsentWrite]
        let transport = TopicSelfPlayRuntimeTransport(baseURL: configuration.baseURL, transport: factory.client(features))
        let compliance = AccountComplianceService(configuration: configuration, transport: transport,
            journal: ComplianceFileJournal(url: directory.appendingPathComponent("operations-v1.json")),
            current: { [weak self] in self?.currentRuntimeDependencyContext == captured ? self?.complianceSession : nil },
            token: { [weak self] in self?.currentRuntimeDependencyContext == captured ? self?.token : nil },
            readsEnabled: true, writesEnabled: true,
            legalApproved: { [weak self] subject, scope in subject == .signup && self?.currentRuntimeDependencyContext == captured && self?.complianceSession == scope })
        let client = TopicSelfPlayHTTPClient(configuration: configuration, transport: transport, consent: compliance,
            complianceSession: { [weak self] in self?.complianceSession }, documentProvider: document, captured: captured,
            current: { [weak self] in self?.currentRuntimeDependencyContext }, credentials: { [weak self] in
                guard let self, self.currentRuntimeDependencyContext == captured, let session = self.publishingSession, let token = self.token else { return nil }
                return try? PublishingCredentials(session: session, token: token)
            })
        let payment: (any TopicSelfPlayPaymentProviding)? = factory.configuration.selfPlayPayment && factory.permits(.topicSelfPlayPay)
            ? (runtimeDependencies.selfPlayPayment ?? nativeWeChatPaymentAdapter) : nil
        let flow = TopicSelfPlayFlow(topic: topic, client: client, provider: payment, journal: TopicSelfPlayDefaultsJournal(defaults: .standard), operationGate: selfPlayOperationGate)
        retainedSelfPlayFlows[key] = flow; return flow
    }
    var couponManagementSession: CouponManagementSession? {
        guard let context = currentRuntimeDependencyContext else { return nil }
        let read = composition.couponReadApproval(context)
        if let read, !read.matches(context) { return nil }
        let candidate = composition.couponWriteApproval(context)
        let write = candidate.flatMap { lease -> CouponManagementWriteApproval? in
            let merchantID = read?.merchantID ?? lease.merchantID
            return lease.matches(context, merchantID: merchantID, path: "/api/coupon/publish") || lease.matches(context, merchantID: merchantID, path: "/api/coupon/stop") ? lease : nil
        }
        return CouponManagementRuntimeIdentity.session(context: context, viewerRevision: compositionViewerRevision, read: read, write: write)
    }
    private lazy var couponManagementLocks = composition.couponLocks()
    private var retainedCouponManagement: (RuntimeDependencyContext?, CouponManagementSession?, CouponManagementCoordinator)?
    /// Retained per full context and lease issuance; escaped old references fail their current closure.
    var couponManagementCoordinator: CouponManagementCoordinator {
        let context = currentRuntimeDependencyContext, session = couponManagementSession
        if let retained = retainedCouponManagement, retained.0 == context, retained.1 == session { return retained.2 }
        retainedCouponManagement?.2.leave()
        let value = makeCouponManagementCoordinator()
        retainedCouponManagement = (context, session, value)
        return value
    }
    func makeCouponManagementCoordinator(readApproval: OperationEndpointApproval? = nil,
                                         transport: (any HTTPTransport)? = nil,
                                         publisher: (any CouponPublisherAuthorizing)? = nil) -> CouponManagementCoordinator {
        let transport = scopedTransport(transport)
        let captured = currentRuntimeDependencyContext, capturedSession = couponManagementSession
        let current: () -> CouponManagementSession? = { [weak self] in
            guard let self, self.currentRuntimeDependencyContext == captured,
                  self.couponManagementSession == capturedSession else { return nil }
            return capturedSession
        }
        var reader: (any CouponManagementTransport)?
        var authorizer: any CouponPublisherAuthorizing = publisher ?? CouponPublisherUnavailable()
        var writeEnabled = false
        if let configuration = regionalConfiguration?.apiConfiguration, let captured,
           let read = composition.couponReadApproval(captured), read.matches(captured),
           let confirmed = transport as? any CouponManagementConfirmedHTTPTransport {
            let write = composition.couponWriteApproval(captured)
            let actions = Set(CouponManagementWriteApproval.Action.allCases.filter {
                write?.matches(captured, merchantID: read.merchantID, path: "/api/coupon/" + $0.rawValue) == true
            })
            writeEnabled = !actions.isEmpty
            reader = CouponManagementRuntimeTransport(configuration: configuration, http: confirmed, actions: actions, commandProtocol: read.commandProtocol, credentials: { [weak self] in
                guard let session = current(), let token = self?.token else { return nil }
                return try? CouponManagementReadCredentials(session: session, token: token)
            })
            authorizer = CouponMerchantPublisherAuthorizer(configuration: configuration, http: transport,
                context: captured, merchantID: read.merchantID, commandProtocol: read.commandProtocol, current: current)
        } else if let configuration = regionalConfiguration?.apiConfiguration, let readApproval,
           let storageScope, readApproval.baseURL == configuration.baseURL, readApproval.namespace == storageScope.service {
            let guarded = CouponManagementApprovedReadTransport(configuration: configuration, approval: readApproval,
                transport: transport, currentSession: current)
            reader = CouponManagementHTTPReadTransport(configuration: configuration, http: guarded, credentials: { [weak self] in
                guard let session = current(), let token = self?.token else { return nil }
                return try? CouponManagementReadCredentials(session: session, token: token)
            })
        }
        return CouponManagementCoordinator(adapter: .init(transport: reader, dormantWritesEnabled: writeEnabled),
            authorizer: authorizer, locks: couponManagementLocks, currentSession: current)
    }
    // Source-backed media composition remains dormant: hardware, upload origins and write grants are empty.
    private var roamMediaScope: RetainedImageScope? {
        guard let wallet = walletCommerceScope, let credentials = currentRetainedImageCredentials else { return nil }
        return try? RetainedImageScope(accountID: wallet.accountID, epoch: wallet.epoch,
            realm: credentials.realm, destination: .stamp, namespace: wallet.namespace)
    }
    var stampCameraEnabled: Bool { businessRuntimeFactory?.configuration.stampCamera == true }
    func makeRoamStampCaptureCoordinator() -> RoamStampCaptureCoordinator? {
        guard let factory = businessRuntimeFactory, let scope = roamMediaScope, let configuration = regionalConfiguration?.apiConfiguration,
              let credentials = currentRetainedImageCredentials else { return nil }
        let current: () -> RetainedImageScope? = { [weak self] in
            guard let self, self.currentRetainedImageCredentials == credentials else { return nil }; return self.roamMediaScope
        }
        let token: () -> String? = { [weak self] in self?.currentRetainedImageCredentials == credentials ? credentials.token : nil }
        let uploader = RetainedImageHTTPUploader(configuration: configuration, transport: factory.client([.stampUpload]),
            enabled: factory.permits(.stampUpload), approvedOrigins: factory.configuration.stampImageOrigins, currentScope: current, token: token)
        let executor = RoamMediaMutationService(configuration: configuration, transport: factory.client([.stampCreate]),
            enabled: factory.permits(.stampCreate), approval: factory.approval([.stampCreate]),
            approvedImageOrigins: factory.configuration.stampImageOrigins, currentScope: current, token: token)
        let storage = StoredRoamStampPending(read: { [unowned self] in try self.imageUploadStorage.read($0) },
            write: { [unowned self] in try self.imageUploadStorage.write($0, key: $1) })
        return RoamStampCaptureCoordinator(scope: scope,
            uploads: RetainedImageUploadCoordinator(uploader: uploader, journal: imageUploadJournal), executor: executor, storage: storage)
    }
    func makeRoamPosterCoordinator(node: RoamNodeDetail) -> RoamPosterCoordinator? {
        guard let mediaScope = roamMediaScope, let configuration = regionalConfiguration?.apiConfiguration,
              let credentials = currentRetainedImageCredentials,
              let scope = try? RetainedImageScope(accountID: mediaScope.accountID, epoch: mediaScope.epoch,
                realm: mediaScope.realm, destination: .roamPoster(poiID: node.poiId), namespace: mediaScope.namespace) else { return nil }
        let executor = RoamMediaMutationService(configuration: configuration, transport: runtimeHTTPTransport,
            enabled: false, approval: nil, currentScope: { [weak self] in
                guard let self, self.currentRetainedImageCredentials == credentials, self.roamMediaScope == mediaScope else { return nil }; return scope
            }, token: { [weak self] in self?.currentRetainedImageCredentials == credentials ? credentials.token : nil })
        return RoamPosterCoordinator(scope: scope, poiID: node.poiId, node: { node }, location: DisabledRoamPosterLocation(),
            executor: executor, journal: composition.storage.operationJournal(), refreshNode: { [weak self] in
                guard let self else { throw APIError.unauthorized }; return try await self.roamReader.roamNodeDetail(id: node.poiId)
            })
    }
    func makeBankWithdrawalContext() -> BankWithdrawalRuntimeContext? {
        guard let factory = businessRuntimeFactory, factory.permits(.bankPrepare), factory.permits(.bankConsentRead),
              let provider = runtimeDependencies.bankDocument, let scope = walletCommerceScope,
              let configuration = regionalConfiguration?.apiConfiguration else { return nil }
        let captured = factory.captured
        let routes = BankWithdrawalRuntimeRoutes(factory: factory)
        let consent = BankWithdrawalConsentReader(configuration: configuration, transport: factory.client([.bankConsentRead]),
            provider: provider, captured: captured, scope: scope, current: { [weak self] in self?.currentRuntimeDependencyContext })
        let adapter = BankWithdrawalAdapter(configuration: configuration,
            transport: factory.client([.bankPrepare, .bankCreate], additionalRoutes: { routes.dynamicRoutes }),
            journal: composition.storage.operationJournal(), enableReviewedWrites: true,
            approvalForPath: { routes.approval(path: $0) }, refreshConsent: { try await consent.refresh() },
            validatedChallenge: { routes.validatedChallenge($0) }, consentEvidence: { consent.evidence },
            currentSession: { [weak self] in
                guard let self, self.currentRuntimeDependencyContext == captured, self.walletCommerceScope == scope,
                      let token = self.token else { return nil }
                return BankWithdrawalSession(scope: scope, token: token)
            })
        return BankWithdrawalRuntimeContext(adapter: adapter, consent: consent)
    }
    private var walletEpochCache: (stamp: UInt64, accountID: Int, epoch: UUID)?
    var walletCommerceScope: WalletCommerceScope? {
        guard let account, token != nil, let storageScope else { return nil }
        if walletEpochCache?.stamp != gate.currentStamp || walletEpochCache?.accountID != account.id {
            walletEpochCache = (gate.currentStamp, account.id, UUID())
        }
        guard let epoch = walletEpochCache?.epoch else { return nil }
        return WalletCommerceScope(namespace: storageScope.service, accountID: account.id, epoch: epoch)
    }
    /// Read issuance is independently selected and defaults nil. No financial writer is installed.
    private var currentWalletHistoryApproval: WalletHistoryReadApproval? {
        guard let context = currentRuntimeDependencyContext,
              let approval = composition.walletHistoryReadApproval(context), approval.matches(context) else { return nil }
        return approval
    }
    var walletHistoryViewIdentity: String {
        "\(gate.currentStamp):\(account?.id ?? 0):\(account?.effectiveRole ?? "guest"):\(compositionViewerRevision):\(currentWalletHistoryApproval?.revision.uuidString ?? "disabled")"
    }
    private var walletHistoryReaderCache: (identity: String, reader: WalletCommerceReader)?
    var walletHistoryReader: WalletCommerceReader {
        let identity = walletHistoryViewIdentity
        if let cached = walletHistoryReaderCache, cached.identity == identity { return cached.reader }
        let reader = makeWalletHistoryReader()
        walletHistoryReaderCache = (identity, reader)
        return reader
    }
    /// Existing financial consumers retain their original scope and lifecycle.
    lazy var walletCommerceReader = makeWalletCommerceReader()
    /// Public contact approval/transport is not supplied by current deployment composition.
    /// Does not grant wallet reads or any financial command.
    lazy var withdrawalSupportReader = makeWithdrawalSupportReader()
    func makeWithdrawalSupportReader(source: WithdrawalSupportReader.Source? = nil,
                                     approval: @escaping () -> WithdrawalSupportApproval? = { nil }) -> WithdrawalSupportReader {
        WithdrawalSupportReader(source: source, approval: approval, session: { [weak self] in self?.walletCommerceScope })
    }
    func makeWalletCommerceReader(readApproval: OperationEndpointApproval? = nil,
                                  transport: (any HTTPTransport)? = nil) -> WalletCommerceReader {
        let transport = scopedTransport(transport)
        var service: WalletCommerceService?
        if let configuration = regionalConfiguration?.apiConfiguration, let readApproval,
           let storageScope, readApproval.baseURL == configuration.baseURL,
           readApproval.namespace == storageScope.service {
            let guarded = WalletCommerceApprovedReadTransport(configuration: configuration, approval: readApproval,
                transport: transport, currentSession: { [weak self] in
                    guard let self, let scope = self.walletCommerceScope, let token = self.token else { return nil }
                    return (scope, token)
                })
            service = WalletCommerceService(configuration: configuration, transport: guarded)
        }
        return WalletCommerceReader(service: service, onUnauthorized: { [weak self] captured in
            guard let self, self.walletCommerceScope == captured else { return }
            self.expireIfMatching(error: APIError.unauthorized, stamp: self.gate.currentStamp, credential: self.token)
        }, session: { [weak self] in
            guard let self, let scope = self.walletCommerceScope, let token = self.token else { return nil }
            return (scope, token)
        })
    }
    func makeWalletHistoryReader() -> WalletCommerceReader {
        let transport = scopedTransport(nil)
        let approval = currentWalletHistoryApproval
        let readApproval = approval?.endpoints
        let capturedContext = currentRuntimeDependencyContext
        let viewerRevision = compositionViewerRevision
        // History lifetime is independent of the durable financial command owner key.
        // A fresh reader gets a fresh presentation scope; old readers never adopt a new lease.
        let historyScope = walletCommerceScope.map { WalletCommerceScope(namespace: $0.namespace, accountID: $0.accountID, epoch: UUID()) }
        let currentSession: () -> (scope: WalletCommerceScope, token: String)? = { [weak self] in
            guard let self, let capturedContext, let historyScope,
                  self.compositionViewerRevision == viewerRevision,
                  let currentContext = self.currentRuntimeDependencyContext,
                  ContentDraftContextFence.matches(capturedContext, currentContext),
                  let token = self.token else { return nil }
            guard self.currentWalletHistoryApproval?.revision == approval?.revision else { return nil }
            return (historyScope, token)
        }
        var service: WalletCommerceService?
        if let configuration = regionalConfiguration?.apiConfiguration, let readApproval,
           let storageScope, readApproval.baseURL == configuration.baseURL,
           readApproval.namespace == storageScope.service {
            let guarded = WalletCommerceApprovedReadTransport(configuration: configuration, approval: readApproval,
                transport: transport, currentSession: currentSession)
            service = WalletCommerceService(configuration: configuration, transport: guarded)
        }
        return WalletCommerceReader(service: service, onUnauthorized: { [weak self] captured in
            guard let self, currentSession()?.scope == captured else { return }
            self.expireIfMatching(error: APIError.unauthorized, stamp: self.gate.currentStamp, credential: self.token)
        }, session: currentSession)
    }
    private var retainedTemplateAuthors: [Int: TemplateAuthoringCoordinator] = [:]
    private var retainedTemplateShelf: (identity: String, coordinator: TemplateAuthoringCoordinator)?
    private var currentTemplateShelfReadApproval: TemplateShelfReadApproval? {
        guard let context = currentRuntimeDependencyContext,
              let approval = composition.templateShelfReadApproval(context), approval.matches(context) else { return nil }
        return approval
    }
    private func makeTemplateShelfReadTransport() -> TemplateShelfReadTransport? {
        guard let approval = currentTemplateShelfReadApproval,
              let configuration = regionalConfiguration?.apiConfiguration else { return nil }
        let revision = compositionViewerRevision
        return TemplateShelfReadTransport(configuration: configuration, http: runtimeHTTPTransport, approval: approval,
            current: { [weak self] in
                guard let self, self.compositionViewerRevision == revision,
                      self.currentTemplateShelfReadApproval?.revision == approval.revision else { return nil }
                return self.currentRuntimeDependencyContext
            }, onUnauthorized: { [weak self] in
                guard let self, self.compositionViewerRevision == revision,
                      self.currentTemplateShelfReadApproval?.revision == approval.revision else { return }
                self.expireIfMatching(error: APIError.unauthorized, stamp: approval.context.session.epoch, credential: approval.context.session.token)
            })
    }
    func makeOwnedTemplateConfigurationHost() -> OwnedTemplateConfigurationHost {
        OwnedTemplateConfigurationHost(transport: makeTemplateShelfReadTransport())
    }
    private var retainedOwnedMemberReader: (identity: String, reader: OwnedMemberTemplateReader)?
    func makeOwnedMemberTemplateReader() -> OwnedMemberTemplateReader {
        let identity = templateShelfViewIdentity
        if let retainedOwnedMemberReader, retainedOwnedMemberReader.identity == identity { return retainedOwnedMemberReader.reader }
        let reader = OwnedMemberTemplateReader(transport: makeTemplateShelfReadTransport(), authenticated: { [weak self] in self?.account != nil && self?.token != nil })
        retainedOwnedMemberReader = (identity, reader); return reader
    }
    private lazy var templateAuthoringSecureStorage = TemplateAuthoringSecureStorage(scope: storageScope)
    private lazy var templateAuthoringDraftStore = TemplateAuthoringLocalStore(storage: templateAuthoringSecureStorage)
    lazy var prefabPreviewStore = PrefabPreviewStore(storage: templateAuthoringSecureStorage)
    var currentTemplateAuthoringSession: TemplateAuthoringSession? {
        guard let account, token != nil, let storageScope else { return nil }
        return try? TemplateAuthoringSession(accountID: account.id, namespace: storageScope.service,
                                             epoch: gate.currentStamp, authorizationRevision: account.effectiveRole)
    }
    var templateShelfViewIdentity: String {
        templateAuthoringViewIdentity + ":\(compositionViewerRevision):" + (currentTemplateShelfReadApproval?.revision.uuidString ?? "disabled")
    }
    func templateShelfCoordinator() -> TemplateAuthoringCoordinator {
        let identity = templateShelfViewIdentity
        if let retainedTemplateShelf, retainedTemplateShelf.identity == identity { return retainedTemplateShelf.coordinator }
        retainedTemplateShelf?.coordinator.shelfReader.leave()
        retainedTemplateShelf?.coordinator.leaveShelfScreen()
        // Independent read adapter: local editor and mutation journals are not reconfigured.
        let adapter = TemplateAuthoringAdapter(shelfReadTransport: makeTemplateShelfReadTransport())
        let coordinator = TemplateAuthoringCoordinator(adapter: adapter, store: templateAuthoringDraftStore,
            currentSession: { [weak self] in
                guard let self, self.templateShelfViewIdentity == identity else { return nil }
                return self.currentTemplateAuthoringSession
            })
        retainedTemplateShelf = (identity, coordinator)
        return coordinator
    }
    var templateAuthoringViewIdentity: String {
        currentTemplateAuthoringSession.map { $0.ownerKey + ":\($0.epoch):" + $0.authorizationRevision } ?? "signed-out"
    }
    func templateAuthoringEditor(adopting source: DiscoveryPlayTemplate? = nil) -> TemplateAuthoringCoordinator {
        let key = source?.id ?? 0
        let coordinator: TemplateAuthoringCoordinator
        if let retained = retainedTemplateAuthors[key] { coordinator = retained }
        else {
            // Production stays hard-off; exact wire adapters are authored but not mounted.
            coordinator = TemplateAuthoringCoordinator(adapter: TemplateAuthoringAdapter(), store: templateAuthoringDraftStore,
                                                       currentSession: { [weak self] in self?.currentTemplateAuthoringSession })
            retainedTemplateAuthors[key] = coordinator
        }
        coordinator.open(seed: source.flatMap { try? TemplateAuthoringDraft.adopt($0) })
        return coordinator
    }
    private let creatorContentService:CreatorContentService?
    private var currentCreatorContentSession:CreatorContentReadSession? {
        guard let account,let token else { return nil }
        return try? CreatorContentReadSession(accountID:account.id,epoch:gate.currentStamp,token:token)
    }
    lazy var creatorContentReader=CreatorContentSessionReader(service:creatorContentService,currentSession:{ [weak self] in self?.currentCreatorContentSession },onUnauthorized:{ [weak self] captured in
        guard let self,self.currentCreatorContentSession == captured else { return }
        self.expireIfMatching(error:APIError.unauthorized,stamp:captured.epoch,credential:self.token)
    })
    // No API/media approval is inferred from the account route.
    private var currentObjectCardSession: ObjectCardSession? {
        guard let account, let token else { return nil }
        return try? ObjectCardSession(accountID: account.id, epoch: gate.currentStamp, token: token)
    }
    lazy var objectCardReader = makeObjectCardReader()
    func makeObjectCardReader() -> ObjectCardSessionReader {
        ObjectCardSessionReader(serviceProvider: { [weak self] in
            guard let self else { return nil }
            return SocialReaderProductionFactory(configuration: self.regionalConfiguration?.apiConfiguration,
                approval: self.runtimeDependencies.socialReaderApproval, apiTransport: self.runtimeHTTPTransport,
                current: { [weak self] in self?.currentRuntimeDependencyContext }).objectCards()
        }, currentSession: { [weak self] in self?.currentObjectCardSession },
        currentContext: { [weak self] in self?.currentRuntimeDependencyContext },
        onUnauthorized: { [weak self] captured in
            guard let self, self.currentObjectCardSession == captured else { return }
            self.expireIfMatching(error: APIError.unauthorized, stamp: captured.epoch, credential: self.token)
        })
    }
    private var currentCouponCodeSession: CouponCodeSession? {
        guard let account, let token, let namespace = storageScope?.service else { return nil }
        return try? CouponCodeSession(accountID: account.id, epoch: gate.currentStamp, namespace: namespace,
            role: account.effectiveRole, token: token, viewerRevision: compositionViewerRevision)
    }
    func makeCouponCodeCoordinator(historyID: Int) -> CouponCodeCoordinator {
        CouponCodeCoordinator(historyID: historyID,
            service: CouponCodeApprovedService(configuration: regionalConfiguration?.apiConfiguration,
                approval: runtimeDependencies.couponCodeApproval, transport: runtimeHTTPTransport,
                current: { [weak self] in self?.currentRuntimeDependencyContext }),
            currentSession: { [weak self] in self?.currentCouponCodeSession },
            onUnauthorized: { [weak self] captured in
                guard let self, self.currentCouponCodeSession == captured else { return }
                self.expireIfMatching(error: APIError.unauthorized, stamp: captured.epoch, credential: captured.token)
            })
    }
    func makeNonCashRewardService() -> NonCashRewardService? {
        guard runtimeDependencies.nonCashRewardApproved, let configuration = regionalConfiguration?.apiConfiguration else { return nil }
        return NonCashRewardService(configuration: configuration, transport: runtimeHTTPTransport)
    }
    func makeRewardPledgeClient() -> RewardPledgeClient? {
        guard rewardCaller().anyOpen, let configuration = regionalConfiguration?.apiConfiguration else { return nil }
        return RewardPledgeClient(configuration: configuration, transport: runtimeHTTPTransport)
    }
    func makeRewardPledgeEntry() -> RewardPledgeEntry? {
        guard let client = makeRewardPledgeClient(), account != nil, token != nil else { return nil }
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent((storageScope?.service ?? "unconfigured") + "/reward-pledge-unknown.json")
        return RewardPledgeEntry(client: client, journalURL: url, current: { [weak self] in self?.rewardCaller() },
                                  coupons: { [weak self] in
                                      guard let self else { return .failure(.closed("not open")) }
                                      return await self.publishedStoreCoupons()
                                  },
                                  access: { [weak self] in
                                      guard let self, let revision = self.storageScope?.service, !revision.isEmpty,
                                            let account = self.account else { return nil }
                                      guard let access = try? await self.merchantAccess(), access.active,
                                            let store = access.merchantID, store > 0,
                                            let owner = access.ownerMemberID, owner > 0,
                                            let principal = access.principalMemberID, principal == account.id else { return nil }
                                      return RewardPledgeAccessBind(storeID: String(store), ownerID: String(owner),
                                                                     principalID: String(principal), revision: revision)
                                  })
    }
    private func rewardCaller() -> RewardPledgeCaller {
        let deps = runtimeDependencies
        return RewardPledgeCaller(accountID: account.map { String($0.id) } ?? "", epoch: gate.currentStamp,
                                  region: operationalMarket?.rawValue ?? "", token: token ?? "",
                                  read: deps.nonCashRewardApproved, claim: deps.nonCashRewardClaimApproved,
                                  preview: deps.nonCashRewardPreviewApproved, redeem: deps.nonCashRewardRedeemApproved,
                                  draft: deps.nonCashRewardDraftApproved, freeze: deps.nonCashRewardFreezeApproved,
                                  hold: deps.nonCashRewardHoldApproved, withdrawVersion: deps.nonCashRewardWithdrawApproved,
                                  expire: deps.nonCashRewardExpireApproved, returnPool: deps.nonCashRewardReturnApproved,
                                  support: deps.nonCashRewardCaseApproved, stats: deps.nonCashRewardStatsApproved,
                                  catalog: deps.nonCashRewardCatalogApproved, manage: deps.nonCashRewardManageApproved)
    }
    func publishedStoreCoupons() async -> Result<[CouponDefinition], RewardPledgeFailure> {
        let coordinator = makeCouponManagementCoordinator()
        await coordinator.load()
        guard coordinator.issue == nil else { return .failure(.closed("not open")) }
        return .success(coordinator.rows)
    }
    private func rewardPledgePermits(_ operation: String) -> Bool {
        let caller = rewardCaller()
        switch operation {
        case "read", "detail": return caller.read
        case "catalog", "offer": return caller.catalog
        case "claim", "recover": return caller.claim
        case "preview", "store", "resolve": return caller.preview
        case "redeem": return caller.redeem
        case "draft", "submit", "confirm": return caller.draft
        case "manage", "readPledge": return caller.manage || caller.draft
        case "freeze", "review": return caller.freeze
        case "hold": return caller.hold
        case "withdraw": return caller.withdrawVersion
        case "expire": return caller.expire
        case "return": return caller.returnPool
        case "case": return caller.support
        case "stats": return caller.stats
        default: return false
        }
    }
    private var currentNonCashRewardSession: NonCashRewardReadSession? {
        guard let account, let token else { return nil }
        return try? NonCashRewardReadSession(accountID: account.id, epoch: gate.currentStamp, token: token)
    }
    lazy var nonCashRewardReader = NonCashRewardSessionReader(service: { [weak self] in self?.makeNonCashRewardService() },
        currentSession: { [weak self] in self?.currentNonCashRewardSession },
        onUnauthorized: { [weak self] captured in
            guard let self, self.currentNonCashRewardSession == captured else { return }
            self.expireIfMatching(error: APIError.unauthorized, stamp: captured.epoch, credential: self.token)
        })
    private let accountCollectionService:AccountCollectionService?
    private var currentAccountCollectionSession:AccountCollectionReadSession? {
        guard let account,let token else { return nil }
        return try? AccountCollectionReadSession(accountID:account.id,epoch:gate.currentStamp,token:token)
    }
    lazy var accountCollectionReader=AccountCollectionSessionReader(service:accountCollectionService,currentSession:{ [weak self] in self?.currentAccountCollectionSession },onUnauthorized:{ [weak self] captured in
        guard let self,self.currentAccountCollectionSession == captured else { return }
        self.expireIfMatching(error:APIError.unauthorized,stamp:captured.epoch,credential:self.token)
    })
    lazy var profileOwnedCouponReader = ProfileOwnedCouponReader(service: accountCollectionService,
        current: { [weak self] in self?.currentRuntimeDependencyContext },
        viewerRevision: { [weak self] in self?.compositionViewerRevision ?? 0 },
        access: { [weak self] context in
            guard let self, let current = self.currentRuntimeDependencyContext,
                  ContentDraftContextFence.matches(context, current) else { return nil }
            return self.composition.profileOwnedCouponReadAccess(context)
        }, onUnauthorized: { [weak self] captured in
            guard let self, let current = self.currentRuntimeDependencyContext,
                  ContentDraftContextFence.matches(captured, current) else { return }
            self.expireIfMatching(error: APIError.unauthorized, stamp: captured.session.epoch, credential: captured.session.token)
        })
    func makeProfilePublicInfoReader(memberID: Int) -> ProfilePublicInfoReader? {
        guard let context = currentRuntimeDependencyContext else { return nil }
        let viewer = compositionViewerRevision
        guard let target = try? ProfilePublicInfoTarget(memberID: memberID, context: context, viewerRevision: viewer,
            current: { [weak self] in
                guard let self, let current = self.currentRuntimeDependencyContext else { return false }
                return self.compositionViewerRevision == viewer && ContentDraftContextFence.matches(context, current)
            }) else { return nil }
        return ProfilePublicInfoReader(target: target, configuration: regionalConfiguration?.apiConfiguration,
            transport: compositionTransport.scopedForProfilePublicInfo(target), access: { [weak self] captured in
                guard let self, let current = self.currentRuntimeDependencyContext,
                      ContentDraftContextFence.matches(captured, current) else { return nil }
                return self.composition.profilePublicInfoReadAccess(captured)
            }, onUnauthorized: { [weak self] captured in
                guard let self, let current = self.currentRuntimeDependencyContext,
                      ContentDraftContextFence.matches(captured, current) else { return }
                self.expireIfMatching(error: APIError.unauthorized, stamp: captured.session.epoch, credential: captured.session.token)
            })
    }
    func makeProfileGuideReader() -> ProfileGuideListReader? {
        guard let context = currentRuntimeDependencyContext else { return nil }
        let viewer = compositionViewerRevision
        return ProfileGuideListReader(context: context, viewerRevision: viewer,
            service: regionalConfiguration?.apiConfiguration.map { SocialAccountService(configuration: $0, transport: compositionTransport) },
            current: { [weak self] in
                guard let self, let current = self.currentRuntimeDependencyContext else { return false }
                return self.compositionViewerRevision == viewer && ContentDraftContextFence.matches(context, current)
            }, access: { [weak self] captured in
                guard let self, let current = self.currentRuntimeDependencyContext,
                      ContentDraftContextFence.matches(captured, current) else { return nil }
                return self.composition.profileGuideReadAccess(captured)
            }, onUnauthorized: { [weak self] captured in
                guard let self, let current = self.currentRuntimeDependencyContext,
                      ContentDraftContextFence.matches(captured, current) else { return }
                self.expireIfMatching(error: APIError.unauthorized, stamp: captured.session.epoch, credential: captured.session.token)
            })
    }
    func makeProfileGuideArticleReader(_ selection: ProfileGuideArticleSelection) -> ProfileGuideArticleReader {
        ProfileGuideArticleReader(selection: selection,
            service: regionalConfiguration?.apiConfiguration.map { SocialAccountService(configuration: $0, transport: compositionTransport.scopedForProfileGuide(selection)) },
            access: { [weak self] captured in
                guard let self, let current = self.currentRuntimeDependencyContext,
                      self.compositionViewerRevision == selection.viewerRevision,
                      ContentDraftContextFence.matches(captured, current) else { return nil }
                return self.composition.profileGuideReadAccess(captured)
            }, onUnauthorized: { [weak self] captured in
                guard let self, let current = self.currentRuntimeDependencyContext,
                      ContentDraftContextFence.matches(captured, current) else { return }
                self.expireIfMatching(error: APIError.unauthorized, stamp: captured.session.epoch, credential: captured.session.token)
            })
    }
    lazy var profileFavoritesReader = ProfileFavoritesReader(service: accountCollectionService,
        current: { [weak self] in self?.currentRuntimeDependencyContext },
        viewerRevision: { [weak self] in self?.compositionViewerRevision ?? 0 },
        access: { [weak self] context in
            guard let self, let fresh = self.currentRuntimeDependencyContext,
                  ContentDraftContextFence.matches(context, fresh) else { return nil }
            return self.composition.profileFavoritesReadAccess(context)
        }, onUnauthorized: { [weak self] captured in
            guard let self, let fresh = self.currentRuntimeDependencyContext,
                  ContentDraftContextFence.matches(captured, fresh) else { return }
            self.expireIfMatching(error: APIError.unauthorized, stamp: captured.session.epoch, credential: captured.session.token)
        })
    private let favoriteRemovalPendingState = ProfileFavoriteRemovalPendingState()
    private var favoriteRemovalControllerCache: (context: RuntimeDependencyContext, scope: UUID,
        revisions: [UUID], controller: ProfileFavoriteRemovalController)?
    func makeProfileFavoriteRemovalController(scope: UUID) -> ProfileFavoriteRemovalController? {
        var retained = false
        defer {
            if !retained {
                if let old = favoriteRemovalControllerCache?.controller, let id = old.presentationID { old.retire(id) }
                favoriteRemovalControllerCache = nil
            }
        }
        guard let context = currentRuntimeDependencyContext, let api = regionalConfiguration?.apiConfiguration,
              profileFavoritesReader.isConfigured, profileFavoritesReader.scope == scope else { return nil }
        let accesses = composition.profileFavoriteRemovalAccesses(context, scope).filter {
            $0.matches(context, collectionScope: scope, postID: $0.approval.postID)
        }
        guard !accesses.isEmpty, Set(accesses.map { $0.approval.postID }).count == accesses.count else { return nil }
        let revisions = accesses.map(\.revision)
        if let cached = favoriteRemovalControllerCache, cached.context == context, cached.scope == scope,
           cached.revisions == revisions { retained = true; return cached.controller }
        if let old = favoriteRemovalControllerCache?.controller, let id = old.presentationID { old.retire(id) }
        favoriteRemovalControllerCache = nil
        let currentScope: () -> UUID? = { [weak self] in
            guard let self, self.profileFavoritesReader.isConfigured else { return nil }
            return self.profileFavoritesReader.scope
        }
        let select: (RuntimeDependencyContext, UUID) -> [ProfileFavoriteRemovalAccess] = { [weak self] context, scope in
            self?.composition.profileFavoriteRemovalAccesses(context, scope) ?? []
        }
        guard let transport = composition.favoriteRemovalTransport(accesses: accesses, context: context,
            collectionScope: scope, current: { [weak self] in self?.currentRuntimeDependencyContext },
            currentScope: currentScope, select: select) else { return nil }
        let controller = ProfileFavoriteRemovalController(configuration: api, approvals: accesses.map(\.approval),
            transport: transport, journal: composition.storage.operationJournal(), current: { [weak self] in
                guard let self, let fresh = self.currentRuntimeDependencyContext,
                      ContentDraftContextFence.matches(context, fresh), currentScope() == scope else { return nil }
                let latest = select(fresh, scope)
                guard accesses.allSatisfy({ captured in
                    captured.matches(fresh, collectionScope: scope, postID: captured.approval.postID) &&
                    latest.filter { $0.approval.postID == captured.approval.postID }.count == 1 &&
                    latest.contains(where: { $0 === captured })
                }) else { return nil }
                return try? ProfileFavoriteRemovalSession(identity: .init(accountID: fresh.session.accountID,
                    epoch: fresh.session.epoch, role: fresh.role), namespace: fresh.session.namespace,
                    collectionScope: scope, market: fresh.market, token: fresh.session.token)
            }, onUnauthorized: { [weak self] in
                guard let self, let fresh = self.currentRuntimeDependencyContext,
                      ContentDraftContextFence.matches(context, fresh) else { return }
                self.expireIfMatching(error: APIError.unauthorized, stamp: context.session.epoch, credential: context.session.token)
            }, pendingState: favoriteRemovalPendingState)
        favoriteRemovalControllerCache = (context, scope, revisions, controller)
        retained = true
        return controller
    }
    func makeProfileFavoriteDetailReader(_ selection: ProfileFavoritePostSelection) -> ProfileFavoriteDetailReader {
        let api = regionalConfiguration?.apiConfiguration
        let service = api.map {
            SquareService(configuration: $0, transport: compositionTransport.scopedForProfileFavorite(selection))
        }
        return ProfileFavoriteDetailReader(selection: selection, service: service,
            current: { [weak self] in self?.currentRuntimeDependencyContext },
            viewerRevision: { [weak self] in self?.compositionViewerRevision ?? 0 },
            access: { [weak self] context in
                guard let self, let fresh = self.currentRuntimeDependencyContext,
                      ContentDraftContextFence.matches(context, fresh) else { return nil }
                return self.composition.profileFavoriteDetailAccess(context)
            }, onUnauthorized: { [weak self] captured in
                guard let self, let fresh = self.currentRuntimeDependencyContext,
                      ContentDraftContextFence.matches(captured, fresh) else { return }
                self.expireIfMatching(error: APIError.unauthorized, stamp: captured.session.epoch, credential: captured.session.token)
            })
    }
    func makeProfileFavoriteTopicReader(_ selection: ProfileFavoriteTopicSelection) -> ProfileFavoriteTopicReader {
        let api = regionalConfiguration?.apiConfiguration
        let service = api.map {
            TopicService(configuration: $0, transport: compositionTransport.scopedForProfileFavoriteTopic(selection))
        }
        return ProfileFavoriteTopicReader(selection: selection, service: service,
            current: { [weak self] in self?.currentRuntimeDependencyContext },
            viewerRevision: { [weak self] in self?.compositionViewerRevision ?? 0 },
            access: { [weak self] context in
                guard let self, let fresh = self.currentRuntimeDependencyContext,
                      ContentDraftContextFence.matches(context, fresh) else { return nil }
                return self.composition.profileFavoriteTopicReadAccess(context)
            }, onUnauthorized: { [weak self] captured in
                guard let self, let fresh = self.currentRuntimeDependencyContext,
                      ContentDraftContextFence.matches(captured, fresh) else { return }
                self.expireIfMatching(error: APIError.unauthorized, stamp: captured.session.epoch, credential: captured.session.token)
            })
    }
    private let cooperationService:CooperationService?
    private var currentCooperationSession:CooperationReadSession? {
        guard let account,let token else { return nil }
        return try? CooperationReadSession(accountID:account.id,epoch:gate.currentStamp,token:token)
    }
    lazy var cooperationReader=CooperationSessionReader(service:cooperationService,currentSession:{ [weak self] in self?.currentCooperationSession },onUnauthorized:{ [weak self] captured in
        guard let self,self.currentCooperationSession == captured else { return }
        self.expireIfMatching(error:APIError.unauthorized,stamp:captured.epoch,credential:self.token)
    })
    private let socialAccountService: SocialAccountService?
    private var currentSocialAccountSession: SocialAccountSession {
        if let account, let token, let snapshot = try? SocialAccountSession(accountID: account.id, epoch: gate.currentStamp, role: account.effectiveRole, token: token) { return snapshot }
        return SocialAccountSession(guestEpoch: gate.currentStamp)
    }
    lazy var socialAccountReader = SocialAccountSessionReader(service: socialAccountService, currentSession: { [weak self] in
        self?.currentSocialAccountSession ?? SocialAccountSession(guestEpoch: 0)
    }, onUnauthorized: { [weak self] captured in
        guard let self, self.currentSocialAccountSession == captured else { return }
        self.expireIfMatching(error: APIError.unauthorized, stamp: captured.identity.epoch, credential: self.token)
    })
    private var currentProfileInviteHistoryAccess: ProfileInviteHistoryReadAccess? {
        guard let context = currentRuntimeDependencyContext,
              let selected = composition.profileInviteHistoryReadAccess(context),
              selected.matches(context) else { return nil }
        return selected
    }
    lazy var profileInviteHistoryReader = ProfileInviteHistoryReader(base: socialAccountReader,
        currentAccess: { [weak self] in self?.currentProfileInviteHistoryAccess })
    // Only exact member-action grants can authorize this path; Square writes stay separate.
    private var socialMemberActionJournal: any OperationPendingJournal { composition.storage.operationJournal() }
    private var retainedSocialMemberActions: SocialMemberActionSessionOwner?
    private var socialMemberActions: SocialMemberActionSessionOwner {
        if let retainedSocialMemberActions { return retainedSocialMemberActions }
        let owner = SocialMemberActionSessionOwner(configuration: regionalConfiguration?.apiConfiguration,
            transport: runtimeHTTPTransport, journal: socialMemberActionJournal,
            current: { [weak self] in self?.currentRuntimeDependencyContext },
            currentIdentity: { [weak self] in self?.currentSocialAccountSession.identity ?? .init(accountID: nil, epoch: 0) },
            approvals: { [weak self] context in
                guard let self, self.currentRuntimeDependencyContext == context else { return [] }
                return self.runtimeDependencies.socialMemberActionApprovals
            }, onUnauthorized: { [weak self] captured in
                guard let self, self.currentRuntimeDependencyContext == captured else { return }
                self.expireIfMatching(error: APIError.unauthorized, stamp: captured.session.epoch, credential: captured.session.token)
            })
        retainedSocialMemberActions = owner
        return owner
    }
    var socialActionAccess: any SocialActionAccess { socialMemberActions.access }
    var socialActionCoordinator: SocialActionCoordinator { socialMemberActions.coordinator }
    // Preserve the independent media reader's account identity; history approval
    // neither enables nor revokes its separately approved media-origin transport.
    private var currentMessageMediaIdentity: MessagingReadIdentity? {
        guard let account, let token else { return nil }
        return (try? MessagingReadSession(accountID: account.id, epoch: gate.currentStamp, token: token))?.identity
    }
    // Explicit media-origin approval and bounded streaming are required before live preview reads.
    lazy var socialMessageMediaReader = makeSocialMessageMediaReader()
    func makeSocialMessageMediaReader() -> SocialMessageMediaReader {
        SocialMessageMediaReader(serviceProvider: { [weak self] in
            guard let self else { return nil }
            return SocialReaderProductionFactory(configuration: self.regionalConfiguration?.apiConfiguration,
                approval: self.runtimeDependencies.socialReaderApproval,
                apiTransport: self.runtimeHTTPTransport, mediaTransport: self.runtimeHTTPTransport,
                current: { [weak self] in self?.currentRuntimeDependencyContext }).messageMedia()
        }, currentIdentity: { [weak self] in self?.currentMessageMediaIdentity },
        currentContext: { [weak self] in self?.currentRuntimeDependencyContext }, onUnauthorized: { [weak self] captured in
            guard let self, self.currentMessageMediaIdentity == captured else { return }
            self.expireIfMatching(error: APIError.unauthorized, stamp: captured.epoch, credential: self.token)
        })
    }
    // Square workspace and governance stay distinct from Club and legacy SocialAction.
    private var currentSquareWorkspaceSession: SquareWorkspaceSession? {
        guard let account, token != nil, let storageScope else { return nil }
        return try? SquareWorkspaceSession(accountID: account.id, namespace: storageScope.service, epoch: gate.currentStamp)
    }
    private lazy var squareWorkspaceStore = SquareWorkspaceStore(storage: SquareWorkspaceSecureStorage(scope: storageScope))
    private var retainedSquareWorkspace: SquareWorkspaceCoordinator?
    func squareWorkspace() -> SquareWorkspaceCoordinator? {
        guard let identity = currentSquareWorkspaceSession else { retainedSquareWorkspace = nil; return nil }
        if let model = retainedSquareWorkspace, model.session == identity { return model }
        let model = SquareWorkspaceCoordinator(session: identity, store: squareWorkspaceStore,
            currentSession: { [weak self] in self?.currentSquareWorkspaceSession },
            token: { [weak self] in
                guard let self, self.currentSquareWorkspaceSession == identity else { return nil }
                return self.token
            }) // service nil, live/media/legal grants all off.
        retainedSquareWorkspace = model; return model
    }
    private var currentSquareGovernanceIdentity: SquareGovernanceIdentity? {
        guard let account, token != nil, let storageScope else { return nil }
        return .init(accountID: account.id, epoch: gate.currentStamp, namespace: storageScope.service)
    }
    private var retainedSquareReports: SquareReportCoordinator?
    private var retainedSquareReportBaseURL: URL?
    func squareReportContext() -> SquareReportContext? {
        guard let configuration = regionalConfiguration?.apiConfiguration else { return nil }
        if retainedSquareReports == nil || retainedSquareReportBaseURL != configuration.baseURL {
            retainedSquareReports = SquareReportCoordinator(service: .init(configuration: configuration, transport: runtimeHTTPTransport))
            retainedSquareReportBaseURL = configuration.baseURL
        }
        guard let coordinator = retainedSquareReports else { return nil }
        let captured = currentSquareGovernanceIdentity
        let access = SquareReportSessionAccess(identity: { [weak self] in self?.currentSquareGovernanceIdentity },
            token: { [weak self] in
                guard let self, self.currentSquareGovernanceIdentity == captured else { return nil }; return self.token
            }, subject: { [weak self] target in
                guard let self, let captured, self.currentSquareGovernanceIdentity == captured else { throw SquareReportFailure.signedOut }
                let value = try await self.socialActionAccess.snapshot(target: target, generation: .communityV1)
                guard self.currentSquareGovernanceIdentity == captured else { throw CancellationError() }; return value
            })
        return .init(coordinator: coordinator, access: access) // Default policy reads and report writes remain OFF.
    }
    private var retainedSquareGovernance: SquareGovernanceCoordinator?
    func squareGovernance() -> SquareGovernanceCoordinator? {
        if let model = retainedSquareGovernance { return model }
        guard let configuration = regionalConfiguration?.apiConfiguration else { return nil }
        let model = SquareGovernanceCoordinator(service: .init(baseURL: configuration.baseURL, transport: runtimeHTTPTransport))
        retainedSquareGovernance = model; return model // reads and every operation grant off.
    }
    func squareGovernanceAccess(postID: Int? = nil) -> SquareGovernanceSessionAccess {
        let captured = currentSquareGovernanceIdentity
        return SquareGovernanceSessionAccess(identity: { [weak self] in self?.currentSquareGovernanceIdentity },
            token: { [weak self] in
                guard let self, self.currentSquareGovernanceIdentity == captured else { return nil }
                return self.token
            }, freshComments: { [weak self] in
                guard let self, let captured, self.currentSquareGovernanceIdentity == captured else { throw SquareGovernanceFailure.signedOut }
                guard let postID, postID > 0 else { return [] }
                // Fresh exact-post author + fresh comments, never cached UI or an inferred moderator role.
                let readScope = self.squareReader.scope
                let post = try await self.squareReader.squareDetail(route: .init(id: postID, generation: .communityV1))
                guard self.currentSquareGovernanceIdentity == captured, self.squareReader.scope == readScope, post.id == postID else { throw CancellationError() }
                let page = try await self.squareReader.squareComments(route: .init(id: postID, generation: .communityV1), pageNumber: 1)
                guard self.currentSquareGovernanceIdentity == captured, self.squareReader.scope == readScope else { throw CancellationError() }
                return page.items.map { SquareGovernanceComment(comment: $0, post: post) }
            })
    }
    private let squareService:SquareService?
    private var currentSquareSession:SquareReadSession? {
        guard let account,let token else { return nil }
        return try? SquareReadSession(accountID:account.id,epoch:gate.currentStamp,token:token)
    }
    lazy var squareReader=SquareSessionReader(service:squareService,currentSession:{ [weak self] in self?.currentSquareSession },onUnauthorized:{ [weak self] captured in
        guard let self,self.currentSquareSession == captured else { return }
        self.expireIfMatching(error:APIError.unauthorized,stamp:captured.epoch,credential:self.token)
    })
    // Team reads require a separately injected, revocable exact-context lease.
    // Source write adapters exist, but no production write approval is supplied here.
    private let teamService = TeamReadOnlyService()
    private lazy var teamJournal = TeamDefaultsJournal(defaults: composition.storage.defaults)
    private var currentTeamSession: TeamSession? {
        guard let account, let token, let storageScope, let market = operationalMarket else { return nil }
        return try? TeamSession(account: account, epoch: gate.currentStamp, region: market.rawValue,
                                storageNamespace: storageScope.service, token: token, viewerRevision: compositionViewerRevision)
    }
    private var currentTeamReadApproval: TeamReadApproval? {
        guard let context = currentRuntimeDependencyContext,
              let approval = composition.teamReadApproval(context), approval.matches(context) else { return nil }
        return approval
    }
    var teamViewIdentity: String {
        "\(gate.currentStamp):\(account?.id ?? 0):\(account?.effectiveRole ?? "guest"):\(operationalMarket?.rawValue ?? "unconfigured"):\(compositionViewerRevision):\(currentTeamReadApproval?.revision.uuidString ?? "disabled")"
    }
    var nearbyTeamSession: NearbyTeamSession? { currentTeamSession.map { NearbyTeamSession(teamSession: $0) } }
    var nearbyTeamQueryContext: NearbyQueryContext? {
        guard let area = roamArea else { return nil }
        return NearbyTeamBridge.roamQuery(latitude: area.coordinate.latitude, longitude: area.coordinate.longitude)
    }
    lazy var nearbyTeamCoordinator = makeNearbyTeamCoordinator()
    func makeNearbyTeamCoordinator(readApproval: OperationEndpointApproval? = nil,
                                   writeApproval: OperationEndpointApproval? = nil,
                                   writeEvidence: ((NearbyTeamReview) async throws -> NearbyTeamWriteEvidence)? = nil,
                                   transport: (any HTTPTransport)? = nil) -> NearbyTeamCoordinator {
        let transport = scopedTransport(transport)
        // No default caller supplies an operation grant or evidence loader; writes remain off.
        let writer: NearbyTeamHTTPWriteAdapter?
        if let writeApproval, let writeEvidence, let configuration = regionalConfiguration?.apiConfiguration {
            writer = NearbyTeamHTTPWriteAdapter(configuration: configuration, transport: transport, approval: writeApproval,
                journal: NearbyTeamDefaultsDispatchJournal(defaults: .standard),
                currentSession: { [weak self] in self?.nearbyTeamSession },
                token: { [weak self] captured in guard let self, self.nearbyTeamSession == captured else { return nil }; return self.token },
                freshEvidence: writeEvidence)
        } else { writer = nil }
        let service: NearbyTeamService
        if let readApproval, let configuration = regionalConfiguration?.apiConfiguration {
            let reader = NearbyTeamHTTPReadTransport(configuration: configuration, transport: transport, approval: readApproval,
                currentSession: { [weak self] in self?.nearbyTeamSession },
                token: { [weak self] captured in guard let self, self.nearbyTeamSession == captured else { return nil }; return self.token })
            service = NearbyTeamService(readTransport: reader, liveReadGrant: true, writeAdapter: writer)
        } else { service = NearbyTeamService(writeAdapter: writer) }
        return NearbyTeamCoordinator(service: service, session: nearbyTeamSession)
    }
    func makeTeamCoordinator(readApproval: OperationEndpointApproval? = nil,
                             creationSource: OrderLifecycleTeamSource? = nil) -> TeamCoordinator {
        // Default callers provide neither deployment approval nor a registration source.
        // An approved read factory is reusable without silently enabling any write endpoint.
        let reader: TeamReadOnlyService
        var coordinatorSession: () -> TeamSession? = { [weak self] in self?.currentTeamSession }
        if let approval = currentTeamReadApproval, let configuration = regionalConfiguration?.apiConfiguration {
            // Capture this issuance. An old coordinator cannot silently adopt a replacement
            // lease, role refresh, new owner or session. The outer transport checks it again.
            let viewerRevision = compositionViewerRevision
            coordinatorSession = { [weak self] in
                    guard let self, self.compositionViewerRevision == viewerRevision,
                          self.currentTeamReadApproval?.revision == approval.revision else { return nil }
                    return self.currentTeamSession
                }
            reader = TeamReadOnlyService(configuration: configuration, transport: runtimeHTTPTransport,
                readApproval: approval.endpoints, currentSession: coordinatorSession, requiresIDMembership: true)
        } else if let readApproval, let configuration = regionalConfiguration?.apiConfiguration {
            reader = TeamReadOnlyService(configuration: configuration, transport: runtimeHTTPTransport,
                readApproval: readApproval, currentSession: { [weak self] in self?.currentTeamSession },
                creationLoader: { [weak self] ownerID, session in
                    guard let self, self.currentTeamSession == session, let token = self.token,
                          let creationSource, creationSource.context.ownerID == ownerID,
                          readApproval.allows(configuration: configuration, namespace: session.storageNamespace,
                              accountID: session.accountID, path: "api/registration/info"),
                          let service = self.orderLifecycleService else { throw TeamFailure.notConfigured }
                    let detail = try await service.detail(id: creationSource.registrationID, token: token)
                    guard !Task.isCancelled, self.currentTeamSession == session,
                          let source = detail.teamCreationSource, source.registrationID == creationSource.registrationID,
                          source.context.ownerID == ownerID else { throw TeamFailure.stale }
                    return source.context
                })
        } else { reader = teamService }
        return TeamCoordinator(service: reader, journal: teamJournal,
            currentSession: coordinatorSession,
            onUnauthorized: { [weak self] captured in
                guard let self, self.currentTeamSession == captured else { return }
                self.expireIfMatching(error: APIError.unauthorized, stamp: captured.epoch, credential: self.token)
            })
    }
    private let orderLifecycleService: OrderLifecycleService?
    private var currentOrderLifecycleSession: OrderLifecycleSession? {
        guard let account, let token else { return nil }
        let contextID = currentRuntimeDependencyContext.map {
            [$0.market.rawValue, $0.baseURL.absoluteString, $0.session.namespace, $0.role].map { "\($0.utf8.count):\($0)" }.joined(separator: "|")
        } ?? account.effectiveRole
        let replayContext = currentRuntimeDependencyContext.map { OrderLifecycleReplayContext(context: $0) }
        return try? OrderLifecycleSession(accountID: account.id, epoch: gate.currentStamp, token: token,
            contextID: contextID, replayContext: replayContext)
    }
    lazy var orderLifecycleReader = OrderLifecycleSessionReader(service: orderLifecycleService,
        currentSession: { [weak self] in self?.currentOrderLifecycleSession },
        onUnauthorized: { [weak self] captured in
            guard let self, self.currentOrderLifecycleSession == captured else { return }
            self.expireIfMatching(error: APIError.unauthorized, stamp: captured.epoch, credential: self.token)
        })
    // Default nil configuration cannot construct a writer. One file survives account
    // switches/relaunch; its keys bind exact origin, market, namespace, account and order.
    private lazy var orderLifecycleJournal: OrderLifecycleFileJournal? = {
        guard let directory = safetyDirectory("OrderLifecycle") else { return nil }
        return OrderLifecycleFileJournal(url: directory.appendingPathComponent("orders-v1.json"))
    }()
    private var orderLifecyclePaymentProviderAllowed: Bool {
        guard let configuration = runtimeDependencies.orderLifecycleConfiguration,
              let context = currentRuntimeDependencyContext, configuration.matches(context),
              configuration.externalCheckoutApproved, configuration.devicePaymentApproved else { return false }
        return configuration.approvals.contains { $0.action == .payment && $0.expiresAt > Date() }
    }
    private func makeOrderLifecycleDispatcher() -> OrderLifecycleProductionDispatcher? {
        guard let api = regionalConfiguration?.apiConfiguration, let journal = orderLifecycleJournal else { return nil }
        return OrderLifecycleProductionFactory.make(configuration: runtimeDependencies.orderLifecycleConfiguration,
            api: api, transport: runtimeHTTPTransport, journal: journal,
            document: runtimeDependencies.signupDocument,
            provider: runtimeDependencies.selfPlayPayment ?? nativeWeChatPaymentAdapter,
            sharedGate: selfPlayOperationGate, selfPlayJournal: TopicSelfPlayDefaultsJournal(defaults: .standard),
            current: { [weak self] in self?.currentRuntimeDependencyContext },
            reviewScope: { [weak self] in self?.orderLifecycleReader.scope ?? UUID() })
    }
    lazy var orderLifecycleCoordinator = OrderLifecycleCoordinator(reader: orderLifecycleReader,
        production: { [weak self] in self?.makeOrderLifecycleDispatcher() })
    func makeVerificationCodeCoordinator(target: VerificationCodeTarget) -> VerificationCodeCoordinator {
        VerificationCodeCoordinator(target: target,
            service: VerificationCodeHTTPService(configuration: regionalConfiguration?.apiConfiguration,
                approval: runtimeDependencies.verificationCodeApproval, kind: target.kind,
                transport: runtimeHTTPTransport, current: { [weak self] in self?.currentRuntimeDependencyContext }),
            current: { [weak self] in self?.currentRuntimeDependencyContext },
            onUnauthorized: { [weak self] captured in
                guard let self, self.currentRuntimeDependencyContext == captured else { return }
                self.expireIfMatching(error: APIError.unauthorized, stamp: captured.session.epoch, credential: captured.session.token)
            })
    }
    private let ticketWalletService:TicketWalletService?
    private var currentTicketWalletSession:TicketWalletReadSession? {
        guard let account,let token else { return nil }
        return try? TicketWalletReadSession(accountID:account.id,epoch:gate.currentStamp,token:token,viewerRevision:compositionViewerRevision,role:account.effectiveRole)
    }
    lazy var ticketWalletReader=TicketWalletSessionReader(service:ticketWalletService,currentSession:{ [weak self] in self?.currentTicketWalletSession },onUnauthorized:{ [weak self] captured in
        guard let self,self.currentTicketWalletSession == captured else { return }
        self.expireIfMatching(error:APIError.unauthorized,stamp:captured.epoch,credential:self.token)
    })
    /// Normal-screen diagnostics reflect both exact composition grants and the mounted services.
    /// They do not create approvals or bypass the transport's final identity checks.
    var homeReadAvailability: AppCompositionRoot.ReadAvailability {
        let availability = composition.readAvailability(.home, identity: compositionTransport.current())
        guard availability == .available else { return availability }
        return homeFeedService != nil ? .available : .serviceUnavailable
    }
    var activityListReadAvailability: AppCompositionRoot.ReadAvailability {
        let availability = composition.readAvailability(.home, identity: compositionTransport.current())
        guard availability == .available else { return availability }
        return activityService != nil ? .available : .serviceUnavailable
    }
    var contentDetailReadAvailability: AppCompositionRoot.ReadAvailability {
        let availability = composition.readAvailability(.contentDetail, identity: compositionTransport.current())
        guard availability == .available else { return availability }
        return activityService != nil && topicService != nil && currentTopicSession != nil ? .available : .serviceUnavailable
    }
    private let homeFeedService:HomeFeedService?
    private var currentHomeFeedSession:HomeFeedSession? {
        guard let account,let token else { return nil }
        return try? HomeFeedSession(accountID:account.id,epoch:gate.currentStamp,token:token,
            role:account.effectiveRole,viewerRevision:compositionViewerRevision)
    }
    lazy var homeFeedReader=HomeFeedSessionReader(service:homeFeedService,currentSession:{ [weak self] in self?.currentHomeFeedSession },onUnauthorized:{ [weak self] captured in
        guard let self,self.currentHomeFeedSession == captured else { return }
        self.expireIfMatching(error:APIError.unauthorized,stamp:captured.epoch,credential:self.token)
    })
    private let topicService: TopicService?
    private var currentTopicSession: TopicReadSession? {
        guard let account, let token else { return nil }
        return try? TopicReadSession(accountID:account.id,epoch:gate.currentStamp,token:token,
            role:account.effectiveRole,viewerRevision:compositionViewerRevision)
    }
    lazy var topicReader=TopicSessionReader(service:topicService,currentSession:{ [weak self] in
        self?.currentTopicSession
    },onUnauthorized:{ [weak self] snapshot in
        guard let self,self.currentTopicSession == snapshot else { return }
        self.expireIfMatching(error:APIError.unauthorized,stamp:snapshot.epoch,credential:self.token)
    })
    private let publicTemplateDetails = PublicTemplateDetailOwner()
    private let discoveryService: DiscoveryService?
    private let profileService: ProfileService?
    @Published private(set) var participantRevision: UInt64=0
    /// No capability is issued by a login, profile row, role or shipped configuration.
    @Published var participantAccessSelector: (RuntimeDependencyContext) -> ProfileParticipantAccess? = { _ in nil } {
        didSet { retainedParticipantHost.invalidateAccess() }
    }
    private lazy var retainedParticipantHost = ProfileParticipantHost(
        current: { [weak self] in self?.currentRuntimeDependencyContext },
        viewer: { [weak self] in self?.compositionViewerRevision ?? 0 },
        access: { [weak self] context in self?.participantAccessSelector(context) },
        makeTransport: { [weak self] context, access, current in
            guard let self else { return nil }
            return self.compositionTransport.makeProfileParticipantTransport(context: context, access: access,
                currentRuntime: { [weak self] in self?.currentRuntimeDependencyContext }, stillCurrent: current)
        }, changed: { [weak self] in self?.participantRevision &+= 1 },
        unauthorized: { [weak self] context, viewer in
            guard let self, self.compositionViewerRevision == viewer,
                  ContentDraftContextFence.matches(self.currentRuntimeDependencyContext, context) else { return }
            self.expireIfMatching(error: APIError.unauthorized, stamp: context.session.epoch, credential: context.session.token)
        })
    var participantReader: any ProfileReading { retainedParticipantHost.reader }
    var participantWriter: any ParticipantWriting { retainedParticipantHost.writer }
    var participantCoordinator: ParticipantMutationCoordinator { retainedParticipantHost.coordinator }
    private var retainedMerchantOverview: (context: RuntimeDependencyContext, revision: UInt64, approval: UUID, reader: MerchantOverviewReader)?
    var merchantOverviewReader: MerchantOverviewReader? {
        guard let context = currentRuntimeDependencyContext, let api = regionalConfiguration?.apiConfiguration,
              let approval = runtimeDependencies.merchantOverviewReadApproval, approval.matches(context) else {
            retainedMerchantOverview = nil; return nil
        }
        let revision = compositionViewerRevision
        if let old = retainedMerchantOverview, old.context == context, old.revision == revision,
           old.approval == approval.revision { return old.reader }
        let isCurrent: () -> Bool = { [weak self] in
            guard let self, self.compositionViewerRevision == revision, self.currentRuntimeDependencyContext == context,
                  let issued = self.runtimeDependencies.merchantOverviewReadApproval else { return false }
            return issued.revision == approval.revision && issued.matches(context)
        }
        let transport = compositionTransport.scopedForMerchantOverview(approval: approval, context: context, approved: isCurrent)
        let reader = MerchantOverviewReader(configuration: api, transport: transport, token: context.session.token,
            revision: revision, current: isCurrent, unauthorized: { [weak self] in
                guard let self, isCurrent() else { return }
                self.expireIfMatching(error: APIError.unauthorized, stamp: context.session.epoch, credential: context.session.token)
            })
        retainedMerchantOverview = (context, revision, approval.revision, reader); return reader
    }
    private var retainedMerchantPrediction: (context: RuntimeDependencyContext, revision: UInt64, approval: UUID, reader: MerchantPredictionReader)?
    var merchantPredictionReader: MerchantPredictionReader? {
        guard let context = currentRuntimeDependencyContext, let api = regionalConfiguration?.apiConfiguration,
              let approval = runtimeDependencies.merchantPredictionReadApproval, approval.matches(context) else {
            retainedMerchantPrediction = nil; return nil
        }
        let revision = compositionViewerRevision
        if let old = retainedMerchantPrediction, old.context == context, old.revision == revision,
           old.approval == approval.revision { return old.reader }
        // Same context-immutable dependency policy as other runtime dependencies; no hot revocation provider.
        let isCurrent: () -> Bool = { [weak self] in
            guard let self, self.compositionViewerRevision == revision, self.currentRuntimeDependencyContext == context,
                  let issued = self.runtimeDependencies.merchantPredictionReadApproval else { return false }
            return issued.revision == approval.revision && issued.matches(context)
        }
        let transport = compositionTransport.scopedForMerchantPrediction(approval: approval, context: context, approved: isCurrent)
        // Ephemeral read-only review identity, never a persistent settlement-lock namespace.
        // isCurrent binds the complete deployment, viewer and lease; no writer is constructed.
        let reader = MerchantPredictionReader(configuration: api, transport: transport, token: context.session.token,
            current: isCurrent, unauthorized: { [weak self] in
                guard let self, isCurrent() else { return }
                self.expireIfMatching(error: APIError.unauthorized, stamp: context.session.epoch, credential: context.session.token)
            }, reviewScope: try? MerchantMarketingScope(namespace: "prediction-review-" + approval.revision.uuidString,
                accountID: context.session.accountID, epoch: context.session.epoch, token: context.session.token))
        retainedMerchantPrediction = (context, revision, approval.revision, reader); return reader
    }
    var merchantProjectWorkspaceReadFactory: MerchantProjectWorkspaceReadFactory? {
        guard let context = currentRuntimeDependencyContext, let api = regionalConfiguration?.apiConfiguration,
              let approval = runtimeDependencies.merchantProjectWorkspaceReadApproval, approval.matches(context),
              let browse = runtimeDependencies.merchantProjectBrowseApproval, browse.matches(context) else { return nil }
        let revision = compositionViewerRevision
        let current: () -> Bool = { [weak self] in
            guard let self, self.compositionViewerRevision == revision, self.currentRuntimeDependencyContext == context,
                  let live = self.runtimeDependencies.merchantProjectWorkspaceReadApproval,
                  let list = self.runtimeDependencies.merchantProjectBrowseApproval else { return false }
            return live.revision == approval.revision && live.matches(context) && list.revision == browse.revision && list.matches(context)
        }
        let make: (Int, Int, @escaping () -> Bool) -> (any MerchantContentServing)? = { [weak self] topicID, merchantID, presentationCurrent in
            guard let self, topicID > 0, merchantID > 0, current(), presentationCurrent(),
                  let captured = try? MerchantContentSession(accountID: context.session.accountID, epoch: context.session.epoch,
                    storageScope: context.session.namespace, token: context.session.token) else { return nil }
            let valid = { current() && presentationCurrent() }
            let scoped = self.compositionTransport.scopedForMerchantProjectWorkspace(approval: approval, context: context,
                topicID: topicID, approved: valid)
            let source = MerchantContentService(configuration: api, transport: MerchantProjectCookieFreeTransport(underlying: scoped),
                currentSession: { valid() ? captured : nil }, execution: .disabled, requiredMerchantID: merchantID,
                onUnauthorized: { [weak self] _ in
                    guard let self, valid() else { return }
                    self.expireIfMatching(error: APIError.unauthorized, stamp: context.session.epoch, credential: context.session.token)
                })
            return MerchantProjectWorkspaceReadService(source: source, topicID: topicID, merchantID: merchantID, current: valid)
        }
        return .init(id: approval.revision, make: make, participants: merchantProjectParticipantsReadFactory)
    }
    private var merchantProjectParticipantsReadFactory: MerchantProjectParticipantsReadFactory? {
        guard let context = currentRuntimeDependencyContext, let api = regionalConfiguration?.apiConfiguration,
              let approval = runtimeDependencies.merchantProjectParticipantsReadApproval, approval.matches(context),
              let workspace = runtimeDependencies.merchantProjectWorkspaceReadApproval, workspace.matches(context),
              let browse = runtimeDependencies.merchantProjectBrowseApproval, browse.matches(context) else { return nil }
        let revision = compositionViewerRevision
        let current: () -> Bool = { [weak self] in
            guard let self, self.compositionViewerRevision == revision, self.currentRuntimeDependencyContext == context,
                  let live = self.runtimeDependencies.merchantProjectParticipantsReadApproval,
                  let home = self.runtimeDependencies.merchantProjectWorkspaceReadApproval,
                  let list = self.runtimeDependencies.merchantProjectBrowseApproval else { return false }
            return live.revision == approval.revision && live.matches(context) && home.revision == workspace.revision
                && home.matches(context) && list.revision == browse.revision && list.matches(context)
        }
        return .init(id: approval.revision) { [weak self] topicID, merchantID, parentSnapshot, presentationCurrent in
            guard let self, topicID > 0, merchantID > 0, current(), presentationCurrent(),
                  MerchantProjectWorkspacePresentation.matches(snapshot: parentSnapshot, topicID: topicID, merchantID: merchantID),
                  MerchantOrdinaryParticipantsProjection.allowsHost(parentSnapshot.value),
                  let captured = try? MerchantContentSession(accountID: context.session.accountID, epoch: context.session.epoch,
                    storageScope: context.session.namespace, token: context.session.token) else { return nil }
            let valid = { current() && presentationCurrent() }
            let scoped = self.compositionTransport.scopedForMerchantProjectParticipants(approval: approval, context: context,
                topicID: topicID, approved: valid)
            let source = MerchantContentService(configuration: api, transport: MerchantProjectCookieFreeTransport(underlying: scoped),
                currentSession: { valid() ? captured : nil }, execution: .disabled, requiredMerchantID: merchantID,
                onUnauthorized: { [weak self] _ in
                    guard let self, valid() else { return }
                    self.expireIfMatching(error: APIError.unauthorized, stamp: context.session.epoch, credential: context.session.token)
                })
            return MerchantProjectParticipantsReadService(source: source, topicID: topicID, merchantID: merchantID, current: valid)
        }
    }
    private struct MerchantProjectCookieFreeTransport: HTTPTransport {
        let underlying: any HTTPTransport
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            var exact = request; exact.httpShouldHandleCookies = false
            return try await underlying.send(exact)
        }
    }
    private var retainedMerchantProjectBrowse: (context: RuntimeDependencyContext, revision: UInt64, approval: UUID, reader: MerchantProjectBrowseReader)?
    // Uses the existing context-immutable dependency policy, not a hot-reloaded grant provider.
    var merchantProjectBrowseReader: MerchantProjectBrowseReader? {
        guard let context = currentRuntimeDependencyContext, let api = regionalConfiguration?.apiConfiguration,
              let approval = runtimeDependencies.merchantProjectBrowseApproval, approval.matches(context) else {
            retainedMerchantProjectBrowse = nil; return nil
        }
        let revision = compositionViewerRevision
        if let old = retainedMerchantProjectBrowse, old.context == context, old.revision == revision,
           old.approval == approval.revision { return old.reader }
        let isCurrent: () -> Bool = { [weak self] in
            guard let self, self.compositionViewerRevision == revision, self.currentRuntimeDependencyContext == context,
                  let live = self.runtimeDependencies.merchantProjectBrowseApproval else { return false }
            return live.revision == approval.revision && live.matches(context)
        }
        let transport = compositionTransport.scopedForMerchantProjectBrowse(approval: approval, context: context, approved: isCurrent)
        let reader = MerchantProjectBrowseReader(configuration: api, transport: transport, token: context.session.token,
            revision: revision, current: isCurrent, unauthorized: { [weak self] in
                guard let self, isCurrent() else { return }
                self.expireIfMatching(error: APIError.unauthorized, stamp: context.session.epoch, credential: context.session.token)
            })
        retainedMerchantProjectBrowse = (context, revision, approval.revision, reader); return reader
    }
    private let merchantService: MerchantService?
    private let merchantEngagementService: MerchantEngagementService?
    lazy var merchantEngagementReader = MerchantEngagementSessionReader(
        service: merchantEngagementService,
        session: { [weak self] in self?.currentMerchantBusinessSession },
        productionService: { [weak self] command, merchantID in self?.merchantEngagementFactory?.service(for: command, merchantID: merchantID) },
        devicePermission: { [weak self] action, merchantID in self?.merchantEngagementFactory?.permitsDevice(action, merchantID: merchantID) == true },
        runtimeContext: { [weak self] in self?.currentRuntimeDependencyContext },
        onUnauthorized: { [weak self] captured in
            guard let self, self.currentMerchantBusinessSession == captured else { return }
            self.expireIfMatching(error: APIError.unauthorized, stamp: captured.epoch, credential: self.token)
        })
    private var merchantEngagementFactory: MerchantEngagementProductionFactory? {
        guard let api = regionalConfiguration?.apiConfiguration else { return nil }
        return .init(api: api, approval: runtimeDependencies.merchantEngagementApproval,
                     transport: runtimeHTTPTransport, current: { [weak self] in self?.currentRuntimeDependencyContext })
    }
    lazy var merchantExportRecovery = MerchantExportFileRecoveryStore(
        url: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent((storageScope?.service ?? "unconfigured") + "/MerchantBusiness/export-tasks-v1.json"))
    private let merchantBusinessService: MerchantBusinessService?
    private var currentMerchantBusinessSession: MerchantBusinessSession? {
        guard let account, let token else { return nil }
        return try? MerchantBusinessSession(accountID: account.id, epoch: gate.currentStamp, token: token)
    }
    lazy var merchantBusinessReader = MerchantBusinessSessionReader(service: merchantBusinessService,
        verificationService: { [weak self] in self?.makeMerchantVerificationService() },
        currentSession: { [weak self] in self?.currentMerchantBusinessSession },
        productionService: { [weak self] mutation, merchantID in
            guard let self, let api = self.regionalConfiguration?.apiConfiguration else { return nil }
            return MerchantBusinessProductionFactory(api: api, approval: self.runtimeDependencies.merchantBusinessApproval,
                transport: self.runtimeHTTPTransport, current: { [weak self] in self?.currentRuntimeDependencyContext }).service(for: mutation, merchantID: merchantID)
        }, runtimeContext: { [weak self] in self?.currentRuntimeDependencyContext },
        onUnauthorized: { [weak self] captured in
            guard let self, self.currentMerchantBusinessSession == captured else { return }
            self.expireIfMatching(error: APIError.unauthorized, stamp: captured.epoch, credential: self.token)
        })
    lazy var merchantBusinessJournal = MerchantBusinessFileIntentStore(
        url: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent((storageScope?.service ?? "unconfigured") + "/MerchantBusiness/intents-v1.json"))
    private func makeMerchantVerificationService() -> MerchantBusinessService? {
        guard let factory = businessRuntimeFactory, factory.permits(.directVerification),
              factory.routes([.directVerification]).contains(where: { MerchantVerificationHTTPTransport.paths.contains($0.path) }),
              let configuration = regionalConfiguration?.apiConfiguration else { return nil }
        let client = factory.client([.directVerification])
        return MerchantBusinessService(configuration: configuration, readTransport: client,
            verificationTransport: MerchantVerificationHTTPTransport(baseURL: configuration.baseURL, transport: client))
    }
    var verificationCameraEnabled: Bool { businessRuntimeFactory?.configuration.verificationCamera == true }
    private var retainedNativeVerification: (context: RuntimeDependencyContext, flow: NativeVerificationWorkflow)?
    private lazy var disabledNativeVerification = NativeVerificationWorkflow(reader: merchantBusinessReader, journal: merchantBusinessJournal, redemption: nil)
    var nativeVerificationFlow: NativeVerificationWorkflow {
        guard let factory = businessRuntimeFactory, let service = makeMerchantVerificationService() else { return disabledNativeVerification }
        if let retainedNativeVerification, retainedNativeVerification.context == factory.captured { return retainedNativeVerification.flow }
        retainedNativeVerification?.flow.deactivate()
        let captured = factory.captured
        let redemption = MerchantRedemptionCoordinator(service: service, journal: merchantBusinessJournal,
            currentSession: { [weak self] in
                guard let self, self.currentRuntimeDependencyContext == captured else { return nil }; return self.currentMerchantBusinessSession
            })
        let flow = NativeVerificationWorkflow(reader: merchantBusinessReader, journal: merchantBusinessJournal, redemption: redemption)
        retainedNativeVerification = (captured, flow); return flow
    }
    private var currentMerchantContentSession: MerchantContentSession? {
        guard let account, let token, let storageScope else { return nil }
        return try? MerchantContentSession(accountID: account.id, epoch: gate.currentStamp,
            storageScope: storageScope.service, token: token)
    }
    lazy var merchantContentJournal = MerchantContentFilePendingStorage(
        url: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent((storageScope?.service ?? "unconfigured") + "/MerchantContent/pending-v1.json"))
    // Execution stays the init default, which is closed. The offline harness is not passed.
    // The file journal is what a new detail, a refresh, and a process restart read.
    // Only a matching chapter-invitation readback removes a record.
    lazy var merchantContentService = MerchantContentService(configuration: regionalConfiguration?.apiConfiguration,
        transport: runtimeHTTPTransport, currentSession: { [weak self] in self?.currentMerchantContentSession },
        journal: merchantContentJournal,
        onUnauthorized: { [weak self] captured in
            guard let self, self.currentMerchantContentSession == captured else { return }
            self.expireIfMatching(error: APIError.unauthorized, stamp: captured.epoch, credential: self.token)
        },
        writeApproval: { [weak self] in
            guard let self, let context = self.currentRuntimeDependencyContext else { return .init() }
            return self.merchantContentWriteApproval(context)
        })
    private var retainedNearbyMerchants: (context: RuntimeDependencyContext, revision: UInt64, coordinator: NearbyMerchantCoordinator)?
    var nearbyMerchantCoordinator: NearbyMerchantCoordinator? {
        guard let captured = currentRuntimeDependencyContext, let api = regionalConfiguration?.apiConfiguration else { return nil }
        let revision = compositionViewerRevision
        let isCurrent: () -> Bool = { [weak self] in
            self?.compositionViewerRevision == revision && self?.currentRuntimeDependencyContext == captured
        }
        let transport: any HTTPTransport
        if let configuration = runtimeDependencies.configuration {
            transport = compositionTransport.scopedForNearbyMerchants(configuration: configuration, context: captured)
        } else { transport = compositionTransport }
        let factory = RuntimeDependencyFactory(api: api, configuration: runtimeDependencies.configuration,
            transport: transport, current: { isCurrent() ? captured : nil })
        if let retainedNearbyMerchants, retainedNearbyMerchants.context == captured,
           retainedNearbyMerchants.revision == revision { return retainedNearbyMerchants.coordinator }
        retainedNearbyMerchants?.coordinator.cancel()
        let reader = CoopFlowSessionReader(service: CoopFlowService(configuration: api, transport: factory.transport),
            current: { [weak self] in isCurrent() ? self?.currentCooperationFlowSession : nil }, unauthorized: { [weak self] old in
                guard let self, isCurrent(), self.currentCooperationFlowSession == old else { return }
                self.expireIfMatching(error: APIError.unauthorized, stamp: old.epoch, credential: self.token)
            })
        let model = NearbyMerchantCoordinator(reader: reader,
            location: runtimeDependencies.location ?? RuntimeNativeLocationProvider(enabled: factory.allowsNearbyLocation),
            approved: { factory.allowsNearbyLocation && isCurrent() })
        retainedNearbyMerchants = (captured, revision, model); return model
    }
    private let cooperationFlowService: CoopFlowService?
    private var currentCooperationFlowSession: CoopFlowSession? {
        guard let account, let token else { return nil }
        return try? CoopFlowSession(accountID: account.id, epoch: gate.currentStamp, token: token)
    }
    lazy var cooperationFlowReader = CoopFlowSessionReader(service: cooperationFlowService,
        current: { [weak self] in self?.currentCooperationFlowSession },
        unauthorized: { [weak self] captured in
            guard let self, self.currentCooperationFlowSession == captured else { return }
            self.expireIfMatching(error: APIError.unauthorized, stamp: captured.epoch, credential: self.token)
        })
    /// Real withdraw port behind `CoopFlowService.permitsDispatch`. The production
    /// service is built with the closed defaults, so the POST does not leave.
    lazy var offerWithdrawalExecutor: any MerchantOfferWithdrawalExecuting = makeOfferWithdrawalExecutor()
    private func makeOfferWithdrawalExecutor() -> any MerchantOfferWithdrawalExecuting {
        guard let service = cooperationFlowService else { return MerchantOfferWithdrawalDormantExecutor() }
        let reader = cooperationFlowReader
        return MerchantOfferWithdrawalProtectedExecutor.gated(service: service, reader: reader,
            coopSession: { [weak self] in self?.currentCooperationFlowSession },
            locks: CoopFlowFileLocks(url: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent((storageScope?.service ?? "unconfigured") + "/CoopFlow/offer-withdraw-locks-v1.json")),
            topic: { [weak self] topicID in
                guard let self else { return nil }
                let snapshot = try await self.merchantContentService.load(.chapters(topicID: topicID))
                let topic = snapshot.value["topic"]
                guard let product = topic["productType"].integer, let life = topic["lifecycle"].integer else { return nil }
                let circle = topic["circleThemeCode"].text?.trimmingCharacters(in: .whitespacesAndNewlines)
                return MerchantOfferWithdrawalTopicFacts(productType: product, lifecycle: life, circleThemeCode: circle.flatMap { $0.isEmpty ? nil : $0 })
            })
    }
    private let merchantOperationsService: MerchantOperationsService?
    private var currentMerchantOperationsSession: MerchantOperationsSession? {
        guard let account, let token else { return nil }
        return try? MerchantOperationsSession(accountID: account.id, epoch: gate.currentStamp, token: token, storageNamespace: storageScope?.service ?? "", viewerRevision: compositionViewerRevision)
    }
    lazy var merchantOperationsReader = MerchantOperationsSessionReader(service: merchantOperationsService, currentSession: { [weak self] in
        self?.currentMerchantOperationsSession
    }, onUnauthorized: { [weak self] captured in
        guard let self, self.currentMerchantOperationsSession == captured else { return }
        self.expireIfMatching(error: APIError.unauthorized, stamp: captured.epoch, credential: self.token)
    })
    private let merchantOnboardingService: MerchantOnboardingService?
    private var currentMerchantOnboardingSession: MerchantOnboardingSession? {
        guard let account, let token else { return nil }
        return try? MerchantOnboardingSession(accountID: account.id, epoch: gate.currentStamp, token: token)
    }
    lazy var merchantOnboardingAdapter = MerchantOnboardingSessionAdapter(service: merchantOnboardingService, currentSession: { [weak self] in
        self?.currentMerchantOnboardingSession
    }, onUnauthorized: { [weak self] snapshot in
        guard let self, self.currentMerchantOnboardingSession == snapshot else { return }
        self.expireIfMatching(error: APIError.unauthorized, stamp: snapshot.identity.epoch, credential: self.token)
    })
    // Retained outside navigation so unresolved submissions cannot be replayed by reopening.
    lazy var merchantOnboardingCoordinator = MerchantOnboardingCoordinator(server: merchantOnboardingAdapter)
    private let clubService: ClubService?
    private let clubOperationsService: ClubOperationsService?
    private let clubGovernanceService: ClubGovernanceService?
    private var currentClubGovernanceSession: ClubGovernanceSession? {
        guard let account, let token else { return nil }
        return try? ClubGovernanceSession(accountID: account.id, epoch: gate.currentStamp, token: token, storageNamespace: storageScope?.service ?? "")
    }
    lazy var clubGovernanceAccess = ClubGovernanceSessionAccess(service: clubGovernanceService, currentSession: { [weak self] in
        self?.currentClubGovernanceSession
    }, productionService: { [weak self] command in
        guard let self, let api = self.regionalConfiguration?.apiConfiguration else { return nil }
        return ClubGovernanceProductionFactory(api: api, approval: self.runtimeDependencies.clubGovernanceApproval,
            transport: self.runtimeHTTPTransport, current: { [weak self] in self?.currentRuntimeDependencyContext }).service(for: command)
    }, runtimeContext: { [weak self] in self?.currentRuntimeDependencyContext }, viewerRevision: { [weak self] in self?.compositionViewerRevision ?? 0 }, onUnauthorized: { [weak self] identity in
        guard let self, self.currentClubGovernanceSession?.identity == identity else { return }
        self.expireIfMatching(error: APIError.unauthorized, stamp: identity.epoch, credential: self.token)
    })
    // Session-lived: unresolved operations cannot be replayed by reopening a sheet.
    lazy var clubGovernanceCoordinator = ClubGovernanceCoordinator(access: clubGovernanceAccess,
        journal: ClubGovernanceFileIntentStore(directory: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClubGovernanceIntents", isDirectory: true)))
    lazy var clubOwnerRefundCoordinator = ClubOwnerRefundCoordinator(
        access: ClubOwnerRefundConfiguredAccess(fallback: ClubOwnerRefundReadOnlyAccess(governance: clubGovernanceAccess),
            configuration: regionalConfiguration?.apiConfiguration, approval: runtimeDependencies.ownerRefundApproval,
            transport: runtimeHTTPTransport, current: { [weak self] in self?.currentRuntimeDependencyContext },
            onUnauthorized: { [weak self] captured in
                guard let self, self.currentRuntimeDependencyContext == captured else { return }
                self.expireIfMatching(error: APIError.unauthorized, stamp: captured.session.epoch, credential: captured.session.token)
            }),
        locks: ClubOwnerRefundFileLocks(directory: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("ClubOwnerRefundLocks", isDirectory: true)))
    private var contextualOperationJournal: any OperationPendingJournal { composition.storage.operationJournal() }
    private lazy var clubOpsTimeHost: ClubOpsTimeHost? = regionalConfiguration?.apiConfiguration.map {
        ClubOpsTimeHost(service: ClubOpsTimeConfiguredService(configuration: $0, approval: runtimeDependencies.clubOpsTimeApproval,
            transport: runtimeHTTPTransport, current: { [weak self] in self?.currentRuntimeDependencyContext },
            onUnauthorized: { [weak self] captured in
                guard let self, self.currentRuntimeDependencyContext == captured else { return }
                self.expireIfMatching(error: APIError.unauthorized, stamp: captured.session.epoch, credential: captured.session.token)
            }), journal: contextualOperationJournal)
    }
    var clubGovernanceContext: ClubGovernanceContext { .init(viewerRevision: compositionViewerRevision, access: clubGovernanceAccess, coordinator: clubGovernanceCoordinator, enrollmentProfile: .init(reader: socialAccountReader, squareReader: squareReader, actions: socialActionCoordinator), ownerRefund: clubOwnerRefundCoordinator, opsTimeFactory: { [weak self] in self?.clubOpsTimeHost?.coordinator(activityID: $0) }, topicDestination: { [weak self] id in
        guard let self else { return AnyView(EmptyView()) }
        return AnyView(SessionTopicDetailView(id: id, session: self))
    }, storyTemplates: clubStoryTemplateContext(viewerRevision: compositionViewerRevision), terminalSessions: clubTerminalSessionContext, ownerFunds: clubOwnerFundsContext()) }
    private var currentClubOperationsSession: ClubOperationsSession? {
        guard let account, let token else { return nil }
        return try? ClubOperationsSession(accountID: account.id, epoch: gate.currentStamp, token: token, storageNamespace: storageScope?.service ?? "")
    }
    lazy var clubOperationsAccess = ClubOperationsSessionAccess(service: clubOperationsService, currentSession: { [weak self] in self?.currentClubOperationsSession }, onUnauthorized: { [weak self] captured in
        guard let self, self.currentClubOperationsSession == captured else { return }
        self.expireIfMatching(error: APIError.unauthorized, stamp: captured.identity.epoch, credential: self.token)
    })
    lazy var clubOperationsCoordinator = ClubOperationsCoordinator(access: clubOperationsAccess)
    var clubOperationsContext: ClubOperationsContext { .init(access: clubOperationsAccess, coordinator: clubOperationsCoordinator) }
    private let clubManagementService:ClubManagementService?
    private var currentClubManagementSession:ClubManagementSession? {
        guard let account,let token else { return nil }
        return try? ClubManagementSession(accountID:account.id,epoch:gate.currentStamp,token:token)
    }
    lazy var clubManagementAccess=ClubManagementSessionAccess(service:clubManagementService,currentSession:{ [weak self] in self?.currentClubManagementSession },onUnauthorized:{ [weak self] captured in
        guard let self,self.currentClubManagementSession == captured else { return }
        self.expireIfMatching(error:APIError.unauthorized,stamp:captured.identity.epoch,credential:self.token)
    })
    lazy var clubManagementCoordinator=ClubManagementCoordinator(access:clubManagementAccess,onMembershipChanged:{ [weak self] _ in self?.clubMembershipRevision &+= 1 })
    var clubManagementContext:ClubManagementContext { .init(access:clubManagementAccess,coordinator:clubManagementCoordinator,viewerRevision:compositionViewerRevision,operations:clubOperationsContext,governance:clubGovernanceContext) }
    lazy var contextualReviews: ContextualReviewHost? = regionalConfiguration?.apiConfiguration.map {
        ContextualReviewHost(writer: ContextualReviewConfiguredWriter(configuration: $0, approval: runtimeDependencies.contextualReviewApproval,
            transport: runtimeHTTPTransport, current: { [weak self] in self?.currentRuntimeDependencyContext },
            onUnauthorized: { [weak self] captured in
                guard let self, self.currentRuntimeDependencyContext == captured else { return }
                self.expireIfMatching(error: APIError.unauthorized, stamp: captured.session.epoch, credential: captured.session.token)
            }), journal: contextualOperationJournal)
    }
    private let profileEditService:ProfileEditService?
    private var currentProfileEditSession:ProfileEditSession? {
        guard let account,let token else { return nil }
        return try? ProfileEditSession(accountID:account.id,epoch:gate.currentStamp,token:token,viewerRevision:compositionViewerRevision)
    }
    lazy var profileEditCoordinator=ProfileEditCoordinator(service:profileEditService,currentSession:{ [weak self] in self?.currentProfileEditSession },onUnauthorized:{ [weak self] captured in
        guard let self,self.currentProfileEditSession == captured else { return }
        self.expireIfMatching(error:APIError.unauthorized,stamp:captured.identity.epoch,credential:self.token)
    },onSaved:{ [weak self] in Task { await self?.refreshOwnAccount() } })
    func refreshOwnAccount() async {
        guard let accountSessionService, accountSessionService.storageScope == storageScope,
              let credential=token,let accountID=account?.id else { return }
        let stamp=gate.currentStamp
        do {
            let fresh=try await accountSessionService.currentAccount(token:credential)
            guard !Task.isCancelled,gate.currentStamp == stamp,token == credential,account?.id == accountID,fresh.id == accountID else { return }
            account=fresh
        } catch { expireIfMatching(error:error,stamp:stamp,credential:credential) }
    }
    private let clubActionService: ClubActionService?
    @Published private(set) var clubMembershipRevision: UInt64 = 0
    private var currentClubActionSession: ClubActionSession? {
        guard let account, let token else { return nil }
        return try? ClubActionSession(account: account, epoch: gate.currentStamp, token: token)
    }
    lazy var clubActionWriter = ClubActionSessionWriter(service: clubActionService, currentSession: { [weak self] in
        self?.currentClubActionSession
    }, onUnauthorized: { [weak self] snapshot in
        // Compare the whole captured snapshot, including credential and verified role.
        // A late failure can never expire a replacement account or token.
        guard let self, self.currentClubActionSession == snapshot else { return }
        self.expireIfMatching(error: APIError.unauthorized, stamp: snapshot.identity.epoch, credential: self.token)
    })
    lazy var clubActionCoordinator = ClubActionCoordinator(writer: clubActionWriter, reader: clubReader, onMembershipChanged: { [weak self] _ in
        self?.clubMembershipRevision &+= 1
    })
    private let roamLiveDependencies: NativeRoamLiveDependencies
    private var retainedRoamLiveSession: RoamLiveSessionController?
    func makeRoamLiveSessionController() -> RoamLiveSessionController {
        if let existing = retainedRoamLiveSession { return existing }
        let storage = RoamHistoryKeychainStorage()
        let journal = RoamLiveJournal(storage: storage)
        var liveService: RoamLiveService?
        var location: (any RoamDeviceLocationProviding)?
        if let snapshot = currentRoamExperienceSession, let api = regionalConfiguration?.apiConfiguration,
           let approval = roamLiveDependencies.approval, approval.allows(snapshot.identity, api: api),
           let transport = roamLiveDependencies.transport, let makeLocation = roamLiveDependencies.makeLocation {
            liveService = RoamLiveService(api: api, approval: approval, transport: scopedTransport(transport),
                currentSession: { [weak self] in self?.currentRoamExperienceSession })
            location = makeLocation()
        }
        let controller = RoamLiveSessionController(service: liveService, location: location, journal: journal, history: roamHistoryStore)
        retainedRoamLiveSession = controller
        return controller
    }
    private let roamExperienceService: RoamExperienceService?
    private var currentRoamExperienceSession: RoamExperienceSession? {
        guard let account, let token, let storageScope,
              let regional = regionalConfiguration, let configuration = regional.apiConfiguration,
              storageScope.matches(configuration: regional),
              let scope = try? RoamHistoryScope(market: regional.market.rawValue,
                  deployment: configuration.baseURL, accountID: account.id, namespace: storageScope.service) else { return nil }
        return try? RoamExperienceSession(scope: scope, epoch: gate.currentStamp, token: token)
    }
    private lazy var roamHistoryStore = RoamHistoryStore(storage: RoamHistoryKeychainStorage(), currentScope: { [weak self] in
        self?.currentRoamExperienceSession?.identity.scope
    })
    lazy var roamExperienceReader = RoamExperienceSessionReader(service: roamExperienceService, store: roamHistoryStore,
        localJournal: RoamLiveJournal(storage: RoamHistoryKeychainStorage()),
        currentSession: { [weak self] in self?.currentRoamExperienceSession }, onUnauthorized: { [weak self] captured in
            guard let self, self.currentRoamExperienceSession == captured else { return }
            self.expireIfMatching(error: APIError.unauthorized, stamp: captured.identity.epoch, credential: self.token)
        })
    lazy var roamAlbumMetadataReader = RoamAlbumMetadataReader(service: roamExperienceService,
        current: { [weak self] in self?.currentRuntimeDependencyContext },
        viewerRevision: { [weak self] in self?.compositionViewerRevision ?? 0 },
        access: { [weak self] context in
            guard let self, let current = self.currentRuntimeDependencyContext,
                  ContentDraftContextFence.matches(context, current) else { return nil }
            return self.composition.roamAlbumMetadataReadAccess(context)
        }, onUnauthorized: { [weak self] captured in
            guard let self, let current = self.currentRuntimeDependencyContext,
                  ContentDraftContextFence.matches(captured, current) else { return }
            self.expireIfMatching(error: APIError.unauthorized, stamp: captured.session.epoch, credential: captured.session.token)
        })
    lazy var roamTileMemoryReader = RoamTileMemoryReader(service: roamExperienceService,
        current: { [weak self] in self?.currentRuntimeDependencyContext },
        viewerRevision: { [weak self] in self?.compositionViewerRevision ?? 0 },
        access: { [weak self] context in
            guard let self, let current = self.currentRuntimeDependencyContext,
                  ContentDraftContextFence.matches(context, current) else { return nil }
            return self.composition.roamTileMemoryReadAccess(context)
        }, onUnauthorized: { [weak self] captured in
            guard let self, let current = self.currentRuntimeDependencyContext,
                  ContentDraftContextFence.matches(captured, current) else { return }
            self.expireIfMatching(error: APIError.unauthorized, stamp: captured.session.epoch, credential: captured.session.token)
        })
    lazy var roamSessionFactReader = RoamSessionFactReader(service: roamExperienceService,
        current: { [weak self] in self?.currentRuntimeDependencyContext },
        viewerRevision: { [weak self] in self?.compositionViewerRevision ?? 0 },
        access: { [weak self] context in
            guard let self, let current = self.currentRuntimeDependencyContext,
                  ContentDraftContextFence.matches(context, current) else { return nil }
            return self.composition.roamSessionFactReadAccess(context)
        }, onUnauthorized: { [weak self] captured in
            guard let self, let current = self.currentRuntimeDependencyContext,
                  ContentDraftContextFence.matches(captured, current) else { return }
            self.expireIfMatching(error: APIError.unauthorized, stamp: captured.session.epoch, credential: captured.session.token)
        })
    /// Passport tools (那年今日 / 月度回顾 / 探索目标 / 时光胶囊 / 导出). Read access routes through
    /// AppCompositionRoot and enforces read-only scope (!access.allowsWrites); default composition
    /// supplies nil so unapproved sessions fail closed as not configured, and writes need a separate grant.
    private var roamPrivateToolsAccess: (RuntimeDependencyContext) -> RoamPrivateToolsAccess? {
        { [weak self] context in
            guard let self, let current = self.currentRuntimeDependencyContext,
                  ContentDraftContextFence.matches(context, current),
                  let access = self.composition.roamPrivateToolsReadAccess(context),
                  access.matches(context), !access.allowsWrites else { return nil }
            return access
        }
    }
    private var roamPassportToolsReadAccessSelector: (RuntimeDependencyContext) -> RoamPassportToolsReadAccess? {
        { [weak self] context in
            guard let self, let current = self.currentRuntimeDependencyContext,
                  ContentDraftContextFence.matches(context, current),
                  let access = self.composition.roamPassportToolsReadAccess(context),
                  access.matches(context) else { return nil }
            return access
        }
    }
    lazy var roamPassportToolsReader = RoamPassportToolsSessionReader(
        service: regionalConfiguration?.apiConfiguration.map { RoamPassportToolsService(configuration: $0, transport: compositionTransport) },
        current: { [weak self] in self?.currentRuntimeDependencyContext }, access: roamPrivateToolsAccess,
        readAccess: roamPassportToolsReadAccessSelector,
        onUnauthorized: { [weak self] captured in
            guard let self, let current = self.currentRuntimeDependencyContext, ContentDraftContextFence.matches(captured, current) else { return }
            self.expireIfMatching(error: APIError.unauthorized, stamp: captured.session.epoch, credential: captured.session.token)
        })
    lazy var roamPrivateToolsReader = RoamPrivateToolsSessionReader(
        service: regionalConfiguration?.apiConfiguration.map { RoamPrivateToolsService(configuration: $0, transport: compositionTransport) },
        current: { [weak self] in self?.currentRuntimeDependencyContext }, access: roamPrivateToolsAccess,
        onUnauthorized: { [weak self] captured in
            guard let self, let current = self.currentRuntimeDependencyContext, ContentDraftContextFence.matches(captured, current) else { return }
            self.expireIfMatching(error: APIError.unauthorized, stamp: captured.session.epoch, credential: captured.session.token)
        })
    lazy var roamNearbyEventsReader = RoamNearbyEventsReader(configuration: regionalConfiguration?.apiConfiguration,
        transport: compositionTransport.scopedForManualMap(roamMapSelection),
        current: { [weak self] in self?.currentRuntimeDependencyContext },
        viewerRevision: { [weak self] in self?.compositionViewerRevision ?? 0 },
        area: { [weak self] in self?.roamMapSelection.snapshot },
        access: { [weak self] context in
            guard let self, let current = self.currentRuntimeDependencyContext,
                  ContentDraftContextFence.matches(context, current) else { return nil }
            return self.composition.roamNearbyEventsReadAccess(context)
        }, onUnauthorized: { [weak self] captured in
            guard let self, let current = self.currentRuntimeDependencyContext,
                  ContentDraftContextFence.matches(captured, current) else { return }
            self.expireIfMatching(error: APIError.unauthorized, stamp: captured.session.epoch, credential: captured.session.token)
        })
    lazy var roamNearbyPlayersReader = RoamNearbyPlayersReader(configuration: regionalConfiguration?.apiConfiguration,
        transport: compositionTransport.scopedForManualMap(roamMapSelection),
        current: { [weak self] in self?.currentRuntimeDependencyContext },
        viewerRevision: { [weak self] in self?.compositionViewerRevision ?? 0 },
        area: { [weak self] in self?.roamMapSelection.snapshot },
        access: { [weak self] context in
            guard let self, let current = self.currentRuntimeDependencyContext,
                  ContentDraftContextFence.matches(context, current) else { return nil }
            return self.composition.roamNearbyPlayersReadAccess(context)
        }, onUnauthorized: { [weak self] captured in
            guard let self, let current = self.currentRuntimeDependencyContext,
                  ContentDraftContextFence.matches(captured, current) else { return }
            self.expireIfMatching(error: APIError.unauthorized, stamp: captured.session.epoch, credential: captured.session.token)
        })
    /// Roam home 附近活动 peek: separate approval, manual roam centre, no default grant.
    lazy var roamEntryNearbyReader = RoamEntryNearbyReader(configuration: regionalConfiguration?.apiConfiguration,
        transport: compositionTransport.scopedForManualMap(roamMapSelection),
        current: { [weak self] in self?.currentRuntimeDependencyContext },
        viewerRevision: { [weak self] in self?.compositionViewerRevision ?? 0 },
        area: { [weak self] in self?.roamMapSelection.snapshot },
        access: { [weak self] context in
            guard let self, let current = self.currentRuntimeDependencyContext,
                  ContentDraftContextFence.matches(context, current) else { return nil }
            return self.composition.roamEntryNearbyReadAccess(context)
        }, onUnauthorized: { [weak self] captured in
            guard let self, let current = self.currentRuntimeDependencyContext,
                  ContentDraftContextFence.matches(captured, current) else { return }
            self.expireIfMatching(error: APIError.unauthorized, stamp: captured.session.epoch, credential: captured.session.token)
        })
    /// The peek's team layer: a separate coordinator so the nearby page's own list is untouched.
    /// nil means the team read failed; an unconfigured team read contributes no teams.
    func roamEntryTeams(area: RoamSearchArea) async -> [NearbyTeam]? {
        let reader = makeNearbyTeamCoordinator()
        reader.bind(nearbyTeamSession)
        guard reader.configured, reader.authenticated else { return [] }
        await reader.loadNearby(.init(latitude: area.coordinate.latitude, longitude: area.coordinate.longitude, radius: RoamEntryNearbyRoute.radius))
        return reader.messageKey == nil ? reader.teams : nil
    }
    private let roamService: RoamService?
    // Exact dormant IM adapter exists, but ordinary production composition has no live grant.
    private var imExpandedCoordinators: [IMScope: IMExpandedCoordinator] = [:]
    private var imImageCoordinators: [IMScope: IMImageUploadCoordinator] = [:]
    private var imStarters: [MessagingReadIdentity: IMConversationStarter] = [:]
    private var retainedIMWriter: (context: RuntimeDependencyContext, writer: IMExpandedWriter)?
    private lazy var disabledIMWriter = IMExpandedWriter(service: nil, session: { [weak self] in self?.currentIMExpandedSession })
    private var currentIMExpandedSession: IMExpandedSession? {
        guard let account, let token else { return nil }
        return try? IMExpandedSession(accountID: account.id, epoch: gate.currentStamp, token: token)
    }
    var imExpandedWriter: IMExpandedWriter {
        let features: Set<BusinessRuntimeFeature> = [.imStart, .imRead, .imMute, .imSend, .imUpload]
        guard let factory = businessRuntimeFactory, !factory.routes(features).isEmpty,
              let configuration = regionalConfiguration?.apiConfiguration else { return disabledIMWriter }
        if let retainedIMWriter, retainedIMWriter.context == factory.captured { return retainedIMWriter.writer }
        let captured = factory.captured
        let service = IMExpandedService(configuration: configuration, transport: factory.client(features),
            approvedMediaOrigins: factory.configuration.imMediaOrigins, writesEnabled: true,
            enabledPaths: Set(factory.routes(features).map(\.path)))
        let writer = IMExpandedWriter(service: service, session: { [weak self] in
            guard let self, self.currentRuntimeDependencyContext == captured else { return nil }; return self.currentIMExpandedSession
        }, onUnauthorized: { [weak self] snapshot in
            guard let self, self.currentRuntimeDependencyContext == captured else { return }
            self.expireIfMatching(error: APIError.unauthorized, stamp: snapshot.identity.epoch, credential: self.token)
        })
        retainedIMWriter = (captured, writer); return writer
    }
    func imExpandedCoordinator(for conversationID: Int) -> IMExpandedCoordinator? {
        guard let identity = imExpandedWriter.identity, let scope = try? IMScope(identity: identity, conversationID: conversationID) else { return nil }
        if let existing = imExpandedCoordinators[scope] { return existing }
        let owner = IMExpandedCoordinator(scope: scope, writer: imExpandedWriter)
        imExpandedCoordinators[scope] = owner; return owner
    }
    func imImageUploadCoordinator(for conversationID: Int) -> IMImageUploadCoordinator? {
        guard let identity = imExpandedWriter.identity, let scope = try? IMScope(identity: identity, conversationID: conversationID) else { return nil }
        if let existing = imImageCoordinators[scope] { return existing }
        guard let namespace = storageScope?.service, let realm = regionalConfiguration?.apiConfiguration?.baseURL.absoluteString,
              let target = try? ImageUploadTarget(accountID: identity.accountID, namespace: namespace, realm: realm,
                kind: "im", entityID: conversationID, field: "image") else { return nil }
        let owner = IMImageUploadCoordinator(scope: scope, writer: imExpandedWriter, picker: retainedImagePickerHost.imPicker(scope: scope, currentScope: { [weak self] in
            guard let self, self.imExpandedWriter.identity == scope.identity else { return nil }; return scope
        }, selectionApproval: { [weak self] in
            guard let self, self.imExpandedWriter.identity == scope.identity, let factory = self.businessRuntimeFactory else { return false }
            return factory.permits(.imUpload) && factory.configuration.imImageSelection
        }), journal: imageUploadJournal, target: target)
        imImageCoordinators[scope] = owner; return owner
    }
    func imConversationStarter() -> IMConversationStarter? {
        guard let identity = imExpandedWriter.identity else { return nil }
        if let existing = imStarters[identity] { return existing }
        let owner = IMConversationStarter(identity: identity, writer: imExpandedWriter)
        imStarters[identity] = owner; return owner
    }
    // w2-20: IM safety (delete/report/block/unblock) and unread-total stay dormant
    // unless the reviewed business runtime grants each exact path.
    private var imSafetyOwners: [IMScope: IMSafetyCoordinator] = [:]
    private var currentIMSafetySession: IMSafetySession? {
        guard let account, let token else { return nil }
        return try? IMSafetySession(accountID: account.id, epoch: gate.currentStamp, token: token)
    }
    private func imRuntimePaths(_ features: Set<BusinessRuntimeFeature>) -> (BusinessRuntimeFactory, APIConfiguration, Set<String>)? {
        guard let factory = businessRuntimeFactory, let configuration = regionalConfiguration?.apiConfiguration else { return nil }
        let paths = Set(factory.routes(features).map(\.path))
        return paths.isEmpty ? nil : (factory, configuration, paths)
    }
    var imSafetyWriter: IMSafetyWriter {
        let features: Set<BusinessRuntimeFeature> = [.imDelete, .imReport, .imBlock, .imUnblock]
        guard let runtime = imRuntimePaths(features) else {
            return IMSafetyWriter(service: nil, session: { [weak self] in self?.currentIMSafetySession })
        }
        let (factory, configuration, paths) = runtime
        let captured = factory.captured
        return IMSafetyWriter(service: IMSafetyService(configuration: configuration, transport: factory.client(features), enabledPaths: paths),
            session: { [weak self] in
                guard let self, self.currentRuntimeDependencyContext == captured else { return nil }; return self.currentIMSafetySession
            }, onUnauthorized: { [weak self] snapshot in
                guard let self, self.currentRuntimeDependencyContext == captured else { return }
                self.expireIfMatching(error: APIError.unauthorized, stamp: snapshot.identity.epoch, credential: self.token)
            })
    }
    func imSafetyCoordinator(for conversationID: Int) -> IMSafetyCoordinator? {
        let reader = messagingReader
        guard let identity = reader.identity, let scope = try? IMScope(identity: identity, conversationID: conversationID) else { return nil }
        if let existing = imSafetyOwners[scope], existing.isCurrent { return existing }
        let owner = IMSafetyCoordinator(scope: scope, writer: imSafetyWriter, reader: reader)
        imSafetyOwners[scope] = owner; return owner
    }
    var imUnreadTotalReader: IMUnreadTotalReader {
        guard let runtime = imRuntimePaths([.imUnreadTotal]) else {
            return IMUnreadTotalReader(service: nil, session: { nil })
        }
        let (factory, configuration, paths) = runtime
        let captured = factory.captured
        return IMUnreadTotalReader(service: IMUnreadTotalService(configuration: configuration, transport: factory.client([.imUnreadTotal]), enabledPaths: paths),
            session: { [weak self] in
                guard let self, self.currentRuntimeDependencyContext == captured else { return nil }; return self.currentIMSafetySession
            })
    }
    private var clubChatOwners: [Int: ClubChatCoordinator] = [:]
    func clubChatCoordinator(clubID: Int) -> ClubChatCoordinator? {
        if let owner = clubChatOwners[clubID], owner.isCurrent { return owner }
        guard let account, let token, let configuration = regionalConfiguration?.apiConfiguration,
              let snapshot = try? GroupPollSession(accountID: account.id, epoch: gate.currentStamp, token: token) else { return nil }
        let captured = currentRuntimeDependencyContext, factory = businessRuntimeFactory
        let transport: any HTTPTransport
        if let factory { transport = factory.client([.clubChat]) } else { transport = runtimeHTTPTransport }
        let service = ClubChatService(configuration: configuration, transport: transport, enabled: factory?.permits(.clubChat) == true,
            session: { [weak self] in
                guard let self, self.currentRuntimeDependencyContext == captured, let account = self.account, let token = self.token else { return nil }
                return try? GroupPollSession(accountID: account.id, epoch: self.gate.currentStamp, token: token)
            }, onUnauthorized: { [weak self] value in
                guard let self, self.currentRuntimeDependencyContext == captured else { return }
                self.expireIfMatching(error: APIError.unauthorized, stamp: value.identity.epoch, credential: self.token)
            })
        guard let owner = try? ClubChatCoordinator(clubID: clubID, identity: snapshot.identity, service: service, clubs: clubReader, messages: messagingReader) else { return nil }
        clubChatOwners[clubID] = owner; return owner
    }
    private struct GroupPollOwnerKey: Hashable { let scope: IMScope; let reference: GroupPollReference? }
    private var groupPollOwners: [GroupPollOwnerKey: GroupPollCoordinator] = [:]
    func groupPollCoordinator(conversationID: Int, reference: GroupPollReference?) -> GroupPollCoordinator? {
        guard let account, let token, let storageScope,
              let configuration = regionalConfiguration?.apiConfiguration,
              let snapshot = try? GroupPollSession(accountID: account.id, epoch: gate.currentStamp, token: token),
              let scope = try? IMScope(identity: snapshot.identity, conversationID: conversationID) else { return nil }
        let key = GroupPollOwnerKey(scope: scope, reference: reference)
        if let owner = groupPollOwners[key], owner.isCurrent { return owner }
        groupPollOwners = groupPollOwners.filter { $0.value.isCurrent }
        let captured = currentRuntimeDependencyContext
        let features: Set<BusinessRuntimeFeature> = [.imPollResult, .imPollCreate, .imPollVote, .imPollClose, .imPollCreateReceipt]
        let pollRuntime = channelHostRuntimeFactory(features)
        let service: GroupPollService?
        if let (factory, _) = pollRuntime {
            service = GroupPollService(configuration: configuration, transport: factory.client(features),
                enabledPaths: Set(factory.routes(features).map(\.path)))
        } else { service = nil }
        let client = GroupPollSessionClient(service: service, session: { [weak self] in
            guard pollRuntime?.1.isCurrent ?? true, let self, self.currentRuntimeDependencyContext == captured, let account = self.account, let token = self.token else { return nil }
            return try? GroupPollSession(accountID: account.id, epoch: self.gate.currentStamp, token: token)
        }, onUnauthorized: { [weak self] value in
            guard pollRuntime?.1.isCurrent ?? true, let self, self.currentRuntimeDependencyContext == captured else { return }
            self.expireIfMatching(error: APIError.unauthorized, stamp: value.identity.epoch, credential: self.token)
        })
        // All real app entries share the same original create lock and protected
        // payload. A normal message detail must not clear a host-created draft.
        guard let recovery = try? GroupPollCreateRecoveryJournal(storage: ProjectEditSecureStorage(scope: storageScope),
            namespace: storageScope.service, realm: configuration.baseURL, accountID: account.id,
            conversationID: conversationID),
              let owner = try? GroupPollCoordinator(scope: scope, reference: reference, client: client,
            reader: messagingReader, journal: composition.storage.operationJournal(), namespace: storageScope.service,
            realm: configuration.baseURL, creationRecovery: recovery) else { return nil }
        // A disabled explanatory owner must not become a permanent nil-service
        // cache entry if the separately issued configuration later changes.
        if pollRuntime != nil { groupPollOwners[key] = owner }; return owner
    }
    private let messagingService: MessagingService?
    private let messageActionService: MessageActionService?
    private struct MessageSenderKey: Hashable { let accountID:Int;let conversationID:Int }
    private var messageSenders:[MessageSenderKey:MessageActionCoordinator]=[:]
    lazy var messageWriter=MessageSessionWriter(service:messageActionService,currentSession:{ [weak self] in
        guard let self,let account=self.account,let token=self.token else { return nil }
        return try? MessageActionSession(accountID:account.id,epoch:self.gate.currentStamp,token:token)
    },onUnauthorized:{ [weak self] snapshot in
        guard let self else { return }
        self.expireIfMatching(error:APIError.unauthorized,stamp:snapshot.identity.epoch,credential:self.token)
    })
    func messageSender(for conversationID:Int) -> MessageActionCoordinator? {
        // A history lease is never a writer grant. Keep the legacy composer dormant
        // unless the independent business configuration includes the exact send feature.
        guard conversationID>0,let account, let factory = businessRuntimeFactory,
              !factory.routes([.imSend]).isEmpty else { return nil }
        let key=MessageSenderKey(accountID:account.id,conversationID:conversationID)
        if let sender=messageSenders[key] { return sender }
        let sender=MessageActionCoordinator(accountID:account.id,conversationID:conversationID,writer:messageWriter)
        messageSenders[key]=sender;return sender
    }
    private var currentMessagingHistoryReadApproval: MessagingHistoryReadApproval? {
        guard let context = currentRuntimeDependencyContext,
              let approval = composition.messagingHistoryReadApproval(context), approval.matches(context) else { return nil }
        return approval
    }
    var messagingViewIdentity: String {
        "\(gate.currentStamp):\(account?.id ?? 0):\(compositionViewerRevision):\(currentMessagingHistoryReadApproval?.revision.uuidString ?? "disabled")"
    }
    /// Each reader is bound to one exact issuance. Retained screens can never adopt
    /// a reissued lease or a role A -> B -> A identity with the same account/token.
    var messagingReader: MessagingSessionReader {
        guard let context = currentRuntimeDependencyContext, let approval = currentMessagingHistoryReadApproval else {
            return MessagingSessionReader(service: nil, currentSession: { nil })
        }
        let viewerRevision = compositionViewerRevision
        let available: () -> Bool = { [weak self] in
            guard let self, self.compositionViewerRevision == viewerRevision,
                  ContentDraftContextFence.matches(self.currentRuntimeDependencyContext, context),
                  approval.matches(context), self.currentMessagingHistoryReadApproval?.revision == approval.revision else { return false }
            return true
        }
        return MessagingSessionReader(service: messagingService, currentSession: {
            guard available() else { return nil }
            return try? MessagingReadSession(accountID: context.session.accountID,
                epoch: context.session.epoch, token: context.session.token)
        }, isAvailable: available, onUnauthorized: { [weak self] snapshot in
            guard let self, available() else { return }
            self.expireIfMatching(error: APIError.unauthorized, stamp: snapshot.identity.epoch, credential: context.session.token)
        })
    }
    @Published var roamArea: RoamSearchArea? { didSet { roamMapSelection.select(roamArea) } }
    lazy var roamReader=RoamSessionReader(service:roamService,currentSession:{ [weak self] in
        guard let self, let account=self.account, let token=self.token else { return nil }
        return try? RoamReadSession(accountID:account.id,epoch:self.gate.currentStamp,token:token,role:account.effectiveRole,viewerRevision:self.compositionViewerRevision,areaRevision:self.roamMapSelection.revision,manualMapApprovalRevision:self.currentManualMapApprovalRevision)
    },searchArea:{ [weak self] in self?.roamArea },onUnauthorized:{ [weak self] snapshot in
        guard let self else { return }
        self.expireIfMatching(error:APIError.unauthorized,stamp:snapshot.identity.epoch,credential:self.token)
    })
    lazy var clubReader=ClubSessionReader(service:clubService,currentSession:{ [weak self] in
        guard let self else { return ClubReadSession(guestEpoch:0) }
        if let account=self.account, let token=self.token,
           let snapshot=try? ClubReadSession(accountID:account.id,epoch:self.gate.currentStamp,token:token) { return snapshot }
        return ClubReadSession(guestEpoch:self.gate.currentStamp)
    },onUnauthorized:{ [weak self] snapshot in
        guard let self else { return }
        self.expireIfMatching(error:APIError.unauthorized,stamp:snapshot.identity.epoch,credential:self.token)
    })
    private var merchantAccessRecord: (stamp:UInt64, access:MerchantAccess)?
    @Published private var merchantClubAccessRevision: UInt64 = 0
    var isSignedIn: Bool { account != nil && token != nil }
    var sessionRevision: UInt64 { gate.currentStamp }
    var contentDetailRevision: UInt64 { compositionViewerRevision }
    private var currentOwnedOrderSession: OwnedOrderReadSession? {
        guard let context = currentRuntimeDependencyContext,
              let approval = composition.ownedOrderReadApproval(context), approval.matches(context) else { return nil }
        return .init(context: context, viewerRevision: compositionViewerRevision, approvalRevision: approval.revision)
    }
    private var ownedOrderSignedInIdentity: ProfileReadIdentity? {
        guard let account, let token, AuthRequestBuilder.isValidToken(token),
              ["player", "club", "merchant"].contains(account.effectiveRole), !committingAuthenticatedSession else { return nil }
        return .init(accountID: account.id, epoch: gate.currentStamp, viewerRevision: compositionViewerRevision)
    }
    lazy var ownedOrderReader = OwnedOrderSessionReader(service: profileService,
        current: { [weak self] in self?.currentOwnedOrderSession },
        signedInIdentity: { [weak self] in self?.ownedOrderSignedInIdentity },
        onUnauthorized: { [weak self] captured in
            guard let self, self.currentOwnedOrderSession == captured else { return }
            self.expireIfMatching(error: APIError.unauthorized, stamp: captured.context.session.epoch, credential: captured.context.session.token)
        })
    lazy var profileReader = ProfileSessionReader(service:profileService, currentSession:{ [weak self] in
        guard let self, let account=self.account, let token=self.token else { return nil }
        return try? ProfileReadSession(accountID:account.id,epoch:self.gate.currentStamp,token:token)
    }, onUnauthorized:{ [weak self] snapshot in
        guard let self else { return }
        self.expireIfMatching(error:APIError.unauthorized,stamp:snapshot.identity.epoch,credential:self.token)
    })
    // Default-off source adapters share the existing account/session/token owner.
    private var retainedCompliance: AccountComplianceCoordinator?
    private var retainedComplianceService: AccountComplianceService?
    private var retainedMarketing: MerchantMarketingCoordinator?
    private var retainedDoorQueue: DoorReferralQueue?
    private var retainedDoorCoordinator: DoorEntryCoordinator?
    private var doorEpoch = UUID()
    private var entryObservedStamp: UInt64 = 0
    private var entryObservedAccountID: Int?
    private var entryObservedRole: String?
    private var entryObservedToken: String?
    @Published private(set) var restorationFinished = false
    @Published private(set) var nativeEntry: NativeEntryPresentation?
    let nativeEntryLinkPolicy = NativeEntryLinkPolicy(verifiedHTTPSOrigins: [])
    var doorReferralSession: DoorReferralSession {
        DoorReferralSession(accountID: account?.id, epoch: doorEpoch, token: token, restored: restorationFinished)
    }
    private var complianceSession: ComplianceSession? {
        guard let account, token != nil, let market = operationalMarket, let namespace = storageScope?.service else { return nil }
        return ComplianceSession(accountID: account.id, epoch: gate.currentStamp, market: market.rawValue, namespace: namespace)
    }
    private func safetyDirectory(_ component: String) -> URL? {
        guard let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let directory = root.appendingPathComponent(component, isDirectory: true)
        do { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true); return directory }
        catch { return nil }
    }
    var accountComplianceCoordinator: AccountComplianceCoordinator? {
        if let retainedCompliance { return retainedCompliance }
        guard let configuration = regionalConfiguration?.apiConfiguration, let authChannelService,
              let directory = safetyDirectory("AccountComplianceSafety") else { return nil }
        let service = AccountComplianceService(configuration: configuration, transport: runtimeHTTPTransport,
            journal: ComplianceFileJournal(url: directory.appendingPathComponent("operations-v1.json")),
            current: { [weak self] in self?.complianceSession }, token: { [weak self] in self?.token },
            readsEnabled: false, writesEnabled: false, legalApproved: { _, _ in false }, authoritativeMerchantID: { nil })
        let coordinator = AccountComplianceCoordinator(service: service, auth: authChannelService,
            effects: DormantComplianceRoamEffects(), current: { [weak self] in self?.complianceSession },
            invalidateSession: { [weak self] captured in
                guard let self, self.complianceSession == captured else { return }
                self.expireIfMatching(error: APIError.unauthorized, stamp: captured.epoch, credential: self.token)
            })
        retainedComplianceService = service; retainedCompliance = coordinator; return coordinator
    }
    func complianceSignupContext() -> (AccountComplianceService, ComplianceSession)? {
        _ = accountComplianceCoordinator
        guard let service = retainedComplianceService, let session = complianceSession else { return nil }
        return (service, session)
    }
    var merchantMarketingCoordinator: MerchantMarketingCoordinator {
        if let retainedMarketing { return retainedMarketing }
        let service = MerchantMarketingService(configuration: regionalConfiguration?.apiConfiguration,
            transport: runtimeHTTPTransport, gates: .init(reads: false, insight: false, settlement: false), locks: nil,
            currentSession: { [weak self] in
                guard let self, let account = self.account, let token = self.token, let namespace = self.storageScope?.service else { return nil }
                return try? MerchantMarketingScope(namespace: namespace, accountID: account.id, epoch: self.gate.currentStamp, token: token)
            }, onUnauthorized: { [weak self] captured in
                guard let self, self.account?.id == captured.accountID, self.token == captured.token else { return }
                self.expireIfMatching(error: APIError.unauthorized, stamp: captured.epoch, credential: captured.token)
            })
        let model = MerchantMarketingCoordinator(service: service); retainedMarketing = model; return model
    }
    private func prepareDoorRuntime() {
        guard retainedDoorQueue == nil, let configuration = regionalConfiguration?.apiConfiguration, let namespace = storageScope?.service,
              let directory = safetyDirectory("DoorReferralSafety/" + namespace) else { return }
        let service = DoorReferralService(configuration: configuration, transport: runtimeHTTPTransport, scanEnabled: false, bindingEnabled: false,
            currentSession: { [weak self] in self?.doorReferralSession ?? DoorReferralSession(accountID: nil, epoch: UUID(), token: nil, restored: false) })
        retainedDoorQueue = DoorReferralQueue(store: DoorReferralFileStore(url: directory.appendingPathComponent("referrals-v1.json")), service: service,
            currentSession: { [weak self] in self?.doorReferralSession ?? DoorReferralSession(accountID: nil, epoch: UUID(), token: nil, restored: false) })
        retainedDoorCoordinator = DoorEntryCoordinator(session: doorReferralSession, service: service)
    }
    var doorReferralQueue: DoorReferralQueue? { prepareDoorRuntime(); return retainedDoorQueue }
    var doorEntryCoordinator: DoorEntryCoordinator? { prepareDoorRuntime(); return retainedDoorCoordinator }
    func receiveNativeURL(_ url: URL) {
        if nativeWeChatPaymentDriver.handle(url, adapter: nativeWeChatPaymentAdapter) { return }
        if weChatSDKDriver.handle(url, adapter: weChatSDKAdapter) { return }
        guard let intent = nativeEntryLinkPolicy.parse(url) else {
            receiveNativeIntent(.routeError(.unsupported)); return
        }
        receiveNativeIntent(intent)
    }
    func receiveWeChatUserActivity(_ activity: NSUserActivity) {
        if nativeWeChatPaymentDriver.handle(activity, adapter: nativeWeChatPaymentAdapter) { return }
        _ = weChatSDKDriver.handle(activity, adapter: weChatSDKAdapter)
    }
    func receiveNativeIntent(_ intent: NativeEntryIntent) {
        if case .door(let door) = intent {
            prepareDoorRuntime()
            if let inviter = door.inviter, !inviter.isEmpty { try? retainedDoorQueue?.capture(inviter) }
            retainedDoorCoordinator?.updateSession(doorReferralSession)
            retainedDoorCoordinator?.receive(door)
        }
        nativeEntry = NativeEntryPresentation(intent: intent)
    }
    func dismissNativeEntry() { retainedDoorCoordinator?.cancel(); nativeEntry = nil }
    private func synchronizeAccountMarketingEntry() {
        synchronizePrivateHome()
        synchronizeOwnerDraftBrowser()
        let identityChanged = entryObservedStamp != gate.currentStamp || entryObservedAccountID != account?.id || entryObservedToken != token || entryObservedRole != account?.effectiveRole
        if identityChanged {
            publicTemplateDetails.invalidate()
            // Account refresh can change roles without advancing the login operation gate.
            // Preserve an ABA fence even when the same account/role/token later returns.
            compositionViewerRevision &+= 1
            socialAccountReader.invalidatePresentation()
            retainedNativeVerification?.flow.deactivate(); retainedNativeVerification = nil
            retainedPublishingService?.service.invalidateReviews(); retainedPublishingService = nil
            clubChatOwners.removeAll(); groupPollOwners.removeAll(); retainedIMWriter = nil; imExpandedCoordinators.removeAll(); imImageCoordinators.removeAll(); imStarters.removeAll()
            retainedProjectEditors.values.forEach { $0.synchronizeSession() }; retainedProjectEditors.removeAll()
            retainedRoamLiveSession?.invalidate(); retainedRoamLiveSession = nil
            retainedNativePlatform?.invalidate(); retainedNativePlatform = nil
            runtimeSensorProviders.forEach { $0.value?.cancel() }; runtimeSensorProviders.removeAll()
            retainedNativePlayDevice?.provider.cancel(); retainedNativePlayDevice = nil
            retainedPlayDevices.values.forEach { $0.cancel() }; retainedPlayDevices.removeAll()
            retainedPlayStillness.values.forEach { $0.pause() }; retainedPlayStillness.removeAll()
            retainedPlayPrefabs.values.forEach { $0.cancelDeviceWork() }; retainedPlayPrefabs.removeAll()
            playReaders.removeAll()
            playExperienceCoordinators.values.forEach { $0.invalidate() }; playExperienceCoordinators.removeAll()
            retainedNearbyMerchants?.coordinator.cancel(); retainedNearbyMerchants = nil
            publicMerchantReviewEpoch = UUID(); retainedPublicMerchantReviews?.invalidate(); retainedImageContextCache?.invalidate()
            retainedPublisherLifecycle?.context.invalidate(); retainedPublisherLifecycle = nil
            merchantNPCSessionOwner.invalidate(); merchantNPCAccess = nil
            invalidateShopNPCConversations()
            platformConsumers.invalidate()
            retainedMerchantPublicFactory = nil
            publicMerchantReviewReader = DisabledPublicMerchantReviewReader()
            let oldAccount = entryObservedAccountID
            entryObservedStamp = gate.currentStamp; entryObservedAccountID = account?.id; entryObservedToken = token; entryObservedRole = account?.effectiveRole
            doorEpoch = UUID(); retainedCompliance?.invalidate(); retainedMarketing?.sessionChanged()
            if restorationFinished, let entry = nativeEntry, case .door = entry.intent { dismissNativeEntry() }
            // Guest invitation survives initial login; an existing account's route cannot jump accounts.
            if oldAccount != nil, oldAccount != account?.id { dismissNativeEntry() }
        }
        retainedDoorCoordinator?.updateSession(doorReferralSession)
    }

    private var token: String? { willSet { if token != newValue { invalidatePersonalLocationShare() }; if token.map({ Data($0.utf8) }) != newValue.map({ Data($0.utf8) }) { invalidateWorkshopReadBindings() }; invalidateOwnerDraftBrowser(); if token != newValue { invalidateShopNPCConversations(); platformConsumers.invalidate() } } didSet { _ = runtimeDependencies; synchronizeAccountMarketingEntry() } }
    private var didBootstrap = false
    private let restoreBlockedKey:String
    var isConfigured: Bool { storageScope != nil }

    init(composition: AppCompositionRoot? = nil, runtimeDependencies: NativeRuntimeDependencies? = nil, roamLiveDependencies: NativeRoamLiveDependencies? = nil,
         registrationApproval: RegistrationProductionApproval? = nil,
         activityCoverApproval: @escaping (RuntimeDependencyContext) -> ActivityCoverApproval? = { _ in nil },
         activityEditingApproval: @escaping (RuntimeDependencyContext) -> ActivityEditingGrants = { _ in .init() },
         coopFlowExecutionApproval: @escaping (RuntimeDependencyContext) -> CoopFlowExecutionApproval? = { _ in nil },
         merchantContentWriteApproval: @escaping (RuntimeDependencyContext) -> MerchantContentWriteApproval = { _ in .init() },
         publisherIdentityRegistrationApproval: @escaping (RuntimeDependencyContext) -> PublisherIdentityRegistrationGrants = { _ in .init() },
         registrationStorefront: @escaping () -> String? = { nil }) {
        let composition = composition ?? RegionalLaunchConfiguration.composition
        self.activityCoverApproval = activityCoverApproval
        self.activityEditingApproval = activityEditingApproval
        self.coopFlowExecutionApproval = coopFlowExecutionApproval
        self.merchantContentWriteApproval = merchantContentWriteApproval
        let coopSlot = CoopFlowExecutionSlot()
        self.coopFlowExecutionSlot = coopSlot
        self.publisherIdentityRegistrationApproval = publisherIdentityRegistrationApproval
        self.registrationApproval = registrationApproval; self.registrationStorefront = registrationStorefront
        self.roamLiveDependencies = roamLiveDependencies ?? .dormant
        self.composition = composition
        self.compositionTransport = composition.transport()
        self.injectedRuntimeDependencies = runtimeDependencies
        let regional=composition.reviewed?.regional
        regionalConfiguration=regional
        let scope=composition.reviewed?.storageScope
        storageScope=scope
        vault=composition.storage.tokenStore(scope)
        restoreBlockedKey=scope?.restoreBlockedKey ?? "session.unconfigured.preventRestore"
        // An endpoint alone cannot authorize restoring/sending a persisted credential.
        if let scope, let regional, let configuration=regional.apiConfiguration {
            let transport=compositionTransport
            accountSessionService=try? CNAccountSessionService(configuration:regional,storageScope:scope,transport:transport)
            service=regional.availability(of:.usernamePassword) == .available ? AuthService(configuration:configuration,transport:transport) : nil
            authChannelService=regional.canUseDomesticChinaPhone ? AuthChannelService(configuration:configuration,transport:transport) : nil
            searchMapService=composition.reviewed?.reads.isDisjoint(with: [.homeAndSearch, .manualMap, .publicMapLayers]) == false ? SearchMapService(configuration:configuration,transport:transport.scopedForManualMap(searchMapSelection)) : nil
            mapPublicLayerService=composition.reviewed?.reads.isDisjoint(with: [.manualMap, .publicMapLayers]) == false ? MapPublicLayerService(configuration:configuration,transport:transport.scopedForManualMap(searchMapSelection)) : nil
            activityService=ActivityService(configuration:configuration,transport:transport)
            registrationBackend=RegistrationService(configuration:configuration,transport:transport)
            homeFeedService=composition.reviewed?.reads.contains(.homeAndSearch) == true ? HomeFeedService(configuration:configuration,transport:transport) : nil
            orderLifecycleService=OrderLifecycleService(configuration:configuration,transport:transport)
            ticketWalletService=TicketWalletService(configuration:configuration,transport:transport)
            squareService=SquareService(configuration:configuration,transport:transport)
            socialAccountService=SocialAccountService(configuration:configuration,transport:transport)
            officialEventService=OfficialEventService(configuration:configuration,transport:transport)
            profileWeeklyPointsService = ProfileWeeklyPointsService(configuration: configuration, transport: transport)
            do {
                let transport = transport.growthNormalReadTransport(approval: composition.growthNormalReadApproval)
                growthCenterService=GrowthCenterService(configuration:configuration,transport:transport)
            }
            memberHomeService = MemberHomeService(configuration: configuration, transport: transport)
            ownMediaService = OwnMediaService(configuration: configuration, transport: transport)
            creatorContentService=CreatorContentService(configuration:configuration,transport:transport)
            accountCollectionService=AccountCollectionService(configuration:configuration,transport:transport)
            cooperationService=CooperationService(configuration:configuration,transport:transport)
            topicService=TopicService(configuration:configuration,transport:transport)
            discoveryService=DiscoveryService(configuration:configuration,transport:transport)
            profileService=ProfileService(configuration:configuration,transport:transport)
            merchantService=MerchantService(configuration:configuration,transport:transport)
            merchantEngagementService=MerchantEngagementService(configuration:configuration,readTransport:transport)
            merchantBusinessService=MerchantBusinessService(configuration:configuration,readTransport:transport)
            cooperationFlowService=CoopFlowService(configuration:configuration,transport:transport,
                executionApproval: { coopSlot.current() })
            merchantOperationsService=MerchantOperationsService(configuration:configuration,transport:transport)
            merchantOnboardingService=MerchantOnboardingService(configuration:configuration,transport:transport)
            clubService=ClubService(configuration:configuration,transport:transport)
            clubManagementService=ClubManagementService(configuration:configuration,transport:transport)
            clubOperationsService=ClubOperationsService(configuration:configuration,transport:transport)
            clubGovernanceService=ClubGovernanceService(configuration:configuration,transport:transport)
            profileEditService=ProfileEditService(configuration:configuration,transport:transport)
            clubActionService=ClubActionService(configuration:configuration,transport:transport)
            roamService=RoamService(configuration:configuration,transport:transport.scopedForManualMap(roamMapSelection))
            roamExperienceService=RoamExperienceService(configuration:configuration,transport:transport)
            messagingService=MessagingService(configuration:configuration,transport:transport)
            messageActionService=MessageActionService(configuration:configuration,transport:transport)
        } else { service=nil;accountSessionService=nil;authChannelService=nil;activityService=nil;searchMapService=nil;mapPublicLayerService=nil;registrationBackend=UnconfiguredRegistrationBackend();homeFeedService=nil;orderLifecycleService=nil;ticketWalletService=nil;squareService=nil;socialAccountService=nil;cooperationService=nil;accountCollectionService=nil;officialEventService=nil;growthCenterService=nil;profileWeeklyPointsService=nil;creatorContentService=nil;topicService=nil;discoveryService=nil;profileService=nil;merchantService=nil;merchantOperationsService=nil;merchantBusinessService=nil;merchantEngagementService=nil;cooperationFlowService=nil;merchantOnboardingService=nil;clubService=nil;clubManagementService=nil;clubOperationsService=nil;clubGovernanceService=nil;profileEditService=nil;clubActionService=nil;roamService=nil;roamExperienceService=nil;messagingService=nil;messageActionService=nil }
        coopFlowExecutionSlot.current = { [weak self] in
            guard let self, let context = self.currentRuntimeDependencyContext else { return nil }
            return self.coopFlowExecutionApproval(context)
        }
        compositionTransport.projectEditConfigurationRevision = { [weak self] in
            guard let self, !self.projectConfigurationChanging else { return nil }; return self.projectConfigurationRevision
        }
        compositionTransport.projectEditConfiguration = { [weak self] context in
            guard let self, !self.projectConfigurationChanging, self.currentRuntimeDependencyContext == context else { return nil }
            return (self.injectedRuntimeDependencies ?? self.composition.sessionDependencies(context)).businessConfiguration
        }
        compositionTransport.projectStoryAudioUploadApproval = { [weak self] context in
            guard let self, !self.projectConfigurationChanging, self.currentRuntimeDependencyContext == context else { return nil }
            return self.composition.projectStoryAudioUploadApproval(context)
        }
        compositionTransport.projectTopicImageUploadApproval = { [weak self] context in
            guard let self, !self.projectConfigurationChanging, self.currentRuntimeDependencyContext == context else { return nil }
            return self.composition.projectTopicImageUploadApproval(context)
        }
        compositionTransport.projectStoryImageUploadApproval = { [weak self] context in
            guard let self, !self.projectConfigurationChanging, self.currentRuntimeDependencyContext == context else { return nil }
            return self.composition.projectStoryImageUploadApproval(context)
        }
        compositionTransport.ownedTopicCoverConfigurationRevision = { [weak self] in
            guard let self, !self.projectConfigurationChanging else { return nil }; return self.projectConfigurationRevision
        }
        compositionTransport.ownedTopicCoverApproval = { [weak self] context in
            guard let self, !self.projectConfigurationChanging, self.currentRuntimeDependencyContext == context else { return nil }
            return self.composition.ownedTopicCoverApproval(context)
        }
        compositionTransport.approvedReleaseConfigurationRevision = { [weak self] in
            guard let self, !self.projectConfigurationChanging else { return nil }; return self.projectConfigurationRevision
        }
        compositionTransport.approvedReleaseConfiguration = { [weak self] context in
            guard let self, !self.projectConfigurationChanging, self.currentRuntimeDependencyContext == context else { return nil }
            return (self.injectedRuntimeDependencies ?? self.composition.sessionDependencies(context)).businessConfiguration
        }
        compositionTransport.playReadConfiguration = { [weak self] context in
            guard let self, self.currentRuntimeDependencyContext == context else { return nil }
            // Re-read the reviewed selector at the boundary: retained providers must not
            // keep a revoked read grant alive for an otherwise unchanged viewer.
            return (self.injectedRuntimeDependencies ?? self.composition.sessionDependencies(context)).configuration
        }
        compositionTransport.publisherIdentityRegistrationApproval = { [weak self] context in
            guard let self, self.currentRuntimeDependencyContext == context else { return .init() }
            return self.publisherIdentityRegistrationApproval(context)
        }
        compositionTransport.activityCoverApproval = { [weak self] context in
            guard let self, self.currentRuntimeDependencyContext == context else { return nil }
            return self.activityCoverApproval(context)
        }
        compositionTransport.activityEditingApproval = { [weak self] context in
            guard let self, self.currentRuntimeDependencyContext == context else { return .init() }
            return self.activityEditingApproval(context)
        }
        compositionTransport.chapterInviteExecution = { [weak self] context in
            guard let self, self.currentRuntimeDependencyContext == context else { return false }
            return self.merchantContentWriteApproval(context).chapterInvite
        }
        compositionTransport.chapterRespondExecution = { [weak self] context in
            guard let self, self.currentRuntimeDependencyContext == context else { return false }
            return self.merchantContentWriteApproval(context).chapterRespond
        }
        compositionTransport.offerWithdrawExecution = { [weak self] context, id, reason in
            guard let self, self.currentRuntimeDependencyContext == context,
                  let approval = self.coopFlowExecutionApproval(context) else { return false }
            return approval.permits(.withdrawOffer(id: id, reason: reason), endpoint: context.baseURL)
        }
        compositionTransport.rewardPledgePermit = { [weak self] operation in
            self?.rewardPledgePermits(operation) == true
        }
        compositionTransport.current = { [weak self] in
            guard let self, !self.committingAuthenticatedSession else { return nil }
            return .init(epoch: self.gate.currentStamp, accountID: self.account?.id,
                         role: self.account?.effectiveRole, token: self.token,
                         viewerRevision: self.compositionViewerRevision)
        }
    }

    private func commitAuthenticatedSession(token: String, account: Account) {
        // Never build account-bound clients with the old account and the new credential.
        committingAuthenticatedSession = true
        self.token = token; self.account = account
        committingAuthenticatedSession = false
        _ = runtimeDependencies
    }

    func bootstrap() async {
        guard !didBootstrap else { return }
        didBootstrap=true
        defer { restorationFinished = true; synchronizeAccountMarketingEntry() }
        guard let accountSessionService, accountSessionService.storageScope == storageScope else { return }
        if sessionDefaults.bool(forKey:restoreBlockedKey) {
            try? vault.clear()
            return
        }
        invalidateWorkshopReadBindings()
        let operation=gate.begin(.bootstrap)
        clubActionCoordinator.synchronizeSession()
        clubManagementCoordinator.synchronizeSession();clubOperationsCoordinator.synchronizeSession();clubGovernanceCoordinator.cancelReview();profileEditCoordinator.synchronizeSession()
        merchantOnboardingCoordinator.synchronizeSession()
        isWorking=true
        defer { if gate.isCurrent(operation) { isWorking=false;gate.finish(operation) } }
        do {
            guard let saved=try vault.read() else { return }
            let restored=try await accountSessionService.currentAccount(token:saved)
            guard !Task.isCancelled, gate.isCurrent(operation) else { return }
            commitAuthenticatedSession(token: saved, account: restored)
            participantCoordinator.synchronizeSession();synchronizeRegistration()
            clubActionCoordinator.synchronizeSession()
            clubManagementCoordinator.synchronizeSession();clubOperationsCoordinator.synchronizeSession();clubGovernanceCoordinator.cancelReview();profileEditCoordinator.synchronizeSession()
            merchantOnboardingCoordinator.synchronizeSession()
        } catch {
            guard !Task.isCancelled, !(error is CancellationError), gate.isCurrent(operation) else { return }
            if error as? APIError == .unauthorized {
                sessionDefaults.set(true,forKey:restoreBlockedKey)
                try? vault.clear()
            }
            // Offline or server failure never silently deletes a valid saved credential.
            errorKey=Self.messageKey(for:error)
        }
    }

    func login(username:String,password:String) async {
        guard !isWorking, !authChannels.state.isWorking, !weChatAuth.isWorking else { return }
        guard let service else { errorKey="auth.notConfigured";return }
        invalidateWorkshopReadBindings()
        let operation=gate.begin(.login)
        clubActionCoordinator.synchronizeSession()
        clubManagementCoordinator.synchronizeSession();clubOperationsCoordinator.synchronizeSession();clubGovernanceCoordinator.cancelReview();profileEditCoordinator.synchronizeSession()
        merchantOnboardingCoordinator.synchronizeSession()
        isWorking=true;errorKey=nil
        defer { if gate.isCurrent(operation) { isWorking=false;gate.finish(operation) } }
        do {
            let result=try await service.login(username:username,password:password)
            guard gate.isCurrent(operation) else { return }
            try vault.write(result.token)
            sessionDefaults.set(false,forKey:restoreBlockedKey)
            commitAuthenticatedSession(token: result.token, account: result.account)
            participantCoordinator.synchronizeSession();synchronizeRegistration()
            clubActionCoordinator.synchronizeSession()
            clubManagementCoordinator.synchronizeSession();clubOperationsCoordinator.synchronizeSession();clubGovernanceCoordinator.cancelReview();profileEditCoordinator.synchronizeSession()
            merchantOnboardingCoordinator.synchronizeSession()
        } catch {
            guard gate.isCurrent(operation) else { return }
            errorKey=Self.messageKey(for:error)
        }
    }

    func cancelPendingLogin() {
        nativeWeChatPaymentAdapter.cancelPending()
        weChatAuth.cancel()
        // Close must invalidate SMS login immediately, before SwiftUI dismisses its sheet.
        // Transport cancellation is best-effort; the coordinator generation fences late replies.
        authChannels.cancel()
        if gate.activeKind == .login { invalidateWorkshopReadBindings() }
        if gate.cancelLogin() { isWorking=false;errorKey=nil;clubActionCoordinator.synchronizeSession()
        clubManagementCoordinator.synchronizeSession();clubOperationsCoordinator.synchronizeSession();clubGovernanceCoordinator.cancelReview();profileEditCoordinator.synchronizeSession();merchantOnboardingCoordinator.synchronizeSession() }
    }

    func logout() async {
        retainedPersonalLocationShareHost?.prepareLogout()
        nativeWeChatPaymentAdapter.cancelPending()
        weChatAuth.cancel()
        authChannels.cancel()
        let oldToken=token
        invalidateWorkshopReadBindings()
        gate.invalidate()
        // Persist a non-secret tombstone before deletion. A Keychain failure cannot
        // silently restore a logged-out account at the next cold start.
        sessionDefaults.set(true,forKey:restoreBlockedKey)
        roamArea=nil;searchMapSelection.select(nil);token=nil;account=nil;isWorking=false;errorKey=nil
        participantCoordinator.synchronizeSession();synchronizeRegistration()
        clubActionCoordinator.synchronizeSession()
        clubManagementCoordinator.synchronizeSession();clubOperationsCoordinator.synchronizeSession();clubGovernanceCoordinator.cancelReview();profileEditCoordinator.synchronizeSession()
        merchantOnboardingCoordinator.synchronizeSession()
        do { try vault.clear() } catch { errorKey="auth.storageError" }
        if let accountSessionService, accountSessionService.storageScope == storageScope, let oldToken {
            // Captured old credential only. Completion cannot mutate a newer login.
            try? await accountSessionService.logout(token:oldToken)
        }
    }

    func activities(page:Int,keyword:String) async throws -> [ActivitySummary] {
        guard let activityService else { throw APIError.notConfigured }
        let stamp = gate.currentStamp, credential = token, viewerRevision = compositionViewerRevision
        do {
            let result = try await activityService.list(page:page,keyword:keyword,token:credential)
            try Task.checkCancellation()
            guard gate.isCurrent(stamp), credential == token,
                  viewerRevision == compositionViewerRevision else { throw CancellationError() }
            return result
        } catch {
            guard gate.isCurrent(stamp), credential == token,
                  viewerRevision == compositionViewerRevision, !Task.isCancelled else { throw CancellationError() }
            expireIfMatching(error:error,stamp:stamp,credential:credential)
            throw error
        }
    }

    func activityDetail(id:Int) async throws -> ActivityDetailAccess {
        guard account != nil, let credential = token else { throw APIError.unauthorized }
        guard let activityService else { throw APIError.notConfigured }
        let stamp = gate.currentStamp, viewerRevision = compositionViewerRevision
        do {
            let result = try await activityService.detail(id:id,token:credential)
            try Task.checkCancellation()
            guard gate.isCurrent(stamp), credential == token,
                  viewerRevision == compositionViewerRevision else { throw CancellationError() }
            return result
        } catch {
            guard gate.isCurrent(stamp), credential == token,
                  viewerRevision == compositionViewerRevision, !Task.isCancelled else { throw CancellationError() }
            expireIfMatching(error:error,stamp:stamp,credential:credential)
            throw error
        }
    }

    private func expireIfMatching(error:Error,stamp:UInt64,credential:String?) {
        guard error as? APIError == .unauthorized, credential != nil,
              gate.isCurrent(stamp), credential == token else { return }
        nativeWeChatPaymentAdapter.cancelPending()
        invalidateWorkshopReadBindings()
        gate.invalidate()
        sessionDefaults.set(true,forKey:restoreBlockedKey)
        roamArea=nil;searchMapSelection.select(nil);token=nil;account=nil;isWorking=false;errorKey="auth.expired"
        participantCoordinator.synchronizeSession();synchronizeRegistration()
        clubActionCoordinator.synchronizeSession()
        clubManagementCoordinator.synchronizeSession();clubOperationsCoordinator.synchronizeSession();clubGovernanceCoordinator.cancelReview();profileEditCoordinator.synchronizeSession()
        merchantOnboardingCoordinator.synchronizeSession()
        try? vault.clear()
    }

    private static func messageKey(for error:Error) -> String {
        if error is KeychainTokenStore.StoreError { return "auth.storageError" }
        switch error as? APIError {
        case .notConfigured, .invalidConfiguration: return "auth.notConfigured"
        case .unauthorized: return "auth.expired"
        case .invalidRequest: return "auth.invalidInput"
        case .malformedResponse: return "auth.invalidResponse"
        case .businessCode: return "auth.loginRejected"
        default: return "auth.networkError"
        }
    }
}

// Views never own credentials; every completion is bound to the captured session.
extension AppSession: DiscoveryReading, MerchantReading {
    private func readDiscovery<Value>(expiresSession: Bool = true,
        _ operation:(DiscoveryService,String?) async throws -> Value) async throws -> Value {
        guard let discoveryService else { throw APIError.notConfigured }
        let stamp=gate.currentStamp, credential=token, viewerRevision=compositionViewerRevision
        do {
            let value=try await operation(discoveryService,credential)
            try Task.checkCancellation()
            guard gate.isCurrent(stamp), credential == token,
                  viewerRevision == compositionViewerRevision else { throw CancellationError() }
            return value
        } catch {
            // Fence identity-only refreshes before unauthorized expiration, including ABA.
            guard gate.isCurrent(stamp), credential == token,
                  viewerRevision == compositionViewerRevision, !Task.isCancelled else { throw CancellationError() }
            if expiresSession { expireIfMatching(error:error,stamp:stamp,credential:credential) }
            throw error
        }
    }
    func discoveryBanners() async throws -> [DiscoveryBanner] { try await readDiscovery { try await $0.banners(token:$1) } }
    func discoveryCategories(type:Int?) async throws -> [DiscoveryCategory] { try await readDiscovery { try await $0.categories(type:type,token:$1) } }
    func templateMetadataDictionary(kind: TemplateMetadataKind) async throws -> [TemplateMetadataOption] {
        try await readDiscovery { try await $0.templateMetadataDictionary(kind: kind, token: $1) }
    }
    func templateMetadataDictionaryRequest(kind: TemplateMetadataKind) -> DiscoveryReadRequest<[TemplateMetadataOption]> {
        templateMetadataRequest { try await $0.templateMetadataDictionary(kind: kind, token: $1) }
    }
    func templateMetadataCategoriesRequest() -> DiscoveryReadRequest<[DiscoveryCategory]> {
        templateMetadataRequest { try await $0.categories(type: 4, token: $1) }
    }
    func projectMetadataCategoriesRequest() -> DiscoveryReadRequest<[DiscoveryCategory]> {
        templateMetadataRequest { try await $0.categories(type: 1, token: $1) }
    }
    // Only an accepted, still-present selector can expire its captured identity.
    private func templateMetadataRequest<Value>(
        _ operation: @escaping (DiscoveryService, String?) async throws -> Value
    ) -> DiscoveryReadRequest<Value> {
        let stamp = gate.currentStamp, credential = token, viewerRevision = compositionViewerRevision
        return DiscoveryReadRequest(read: { [weak self] in
            guard let self, self.gate.isCurrent(stamp), credential == self.token,
                  viewerRevision == self.compositionViewerRevision else { throw CancellationError() }
            return try await self.readDiscovery(expiresSession: false, operation)
        }, onUnauthorized: { [weak self] in
            guard let self, viewerRevision == self.compositionViewerRevision else { return }
            self.expireIfMatching(error: APIError.unauthorized, stamp: stamp, credential: credential)
        })
    }
    func discoveryTemplateHome() async throws -> DiscoveryTemplateHome { try await readDiscovery { try await $0.templateHome(token:$1) } }
    func discoveryPlayTemplates(keyword:String,packType:DiscoveryPackType?) async throws -> [DiscoveryPlayTemplate] { try await readDiscovery { try await $0.playTemplates(keyword:keyword,packType:packType,token:$1) } }
    func publicTopicTemplateCoordinator(id: Int) -> PublicTopicTemplateCoordinator {
        makePublicTopicTemplateCoordinator(id: id) { [weak self] id in
            guard let self else { throw CancellationError() }
            // The coordinator expires only an accepted current-generation failure.
            return try await self.readPublicTopicTemplate(id: id, expiresSession: false)
        }
    }
    /// Shared owner construction permits offline lifecycle tests without granting an HTTP route.
    func makePublicTopicTemplateCoordinator(id: Int,
        read: @escaping @MainActor (Int) async throws -> PublicTopicTemplateDetail) -> PublicTopicTemplateCoordinator {
        publicTemplateDetails.synchronize(PublicTemplateViewerContext(
            accountID: account?.id, role: account?.effectiveRole,
            realm: regionalConfiguration?.apiConfiguration?.baseURL.absoluteString ?? "",
            revision: gate.currentStamp))
        let stamp = gate.currentStamp, credential = token, epoch = publicTemplateDetails.epoch
        return publicTemplateDetails.coordinator(id: id, onUnauthorized: { [weak self] in
            guard let self, self.publicTemplateDetails.epoch == epoch else { return }
            self.expireIfMatching(error: APIError.unauthorized, stamp: stamp, credential: credential)
        }, read: read)
    }
    func discoveryTopicTemplateDetail(id: Int) async throws -> PublicTopicTemplateDetail {
        try await readPublicTopicTemplate(id: id, expiresSession: true)
    }
    private func readPublicTopicTemplate(id: Int, expiresSession: Bool) async throws -> PublicTopicTemplateDetail {
        guard let discoveryService else { throw APIError.notConfigured }
        let stamp = gate.currentStamp, credential = token, epoch = publicTemplateDetails.epoch
        func current() -> Bool {
            gate.isCurrent(stamp) && credential == token && epoch == publicTemplateDetails.epoch
        }
        do {
            let result = try await discoveryService.publicTopicTemplate(id: id, token: credential)
            try Task.checkCancellation()
            guard current() else { throw CancellationError() }
            return result
        } catch {
            // A revoked role's late 401 must not expire the new viewer context.
            guard current(), !Task.isCancelled else { throw CancellationError() }
            if expiresSession { expireIfMatching(error: error, stamp: stamp, credential: credential) }
            throw error
        }
    }
    func discoveryTopicTemplates() async throws -> [DiscoveryTopicTemplate] { try await readDiscovery { try await $0.topicTemplates(token:$1) } }
    func publicTopicTemplateCatalogRequest() -> DiscoveryReadRequest<[DiscoveryTopicTemplate]> {
        let stamp = gate.currentStamp, credential = token, viewerRevision = compositionViewerRevision
        return DiscoveryReadRequest(read: { [weak self] in
            guard let self, self.gate.isCurrent(stamp), credential == self.token,
                  viewerRevision == self.compositionViewerRevision else { throw CancellationError() }
            return try await self.readDiscovery(expiresSession: false) { try await $0.topicTemplates(token: $1) }
        }, onUnauthorized: { [weak self] in
            guard let self, viewerRevision == self.compositionViewerRevision else { return }
            self.expireIfMatching(error: APIError.unauthorized, stamp: stamp, credential: credential)
        })
    }
    func discoveryPlayTemplate(id:Int) async throws -> DiscoveryPlayTemplate { try await readDiscovery { try await $0.playTemplate(id:id,token:$1) } }
    func discoveryPlayTemplateRead(id:Int) async throws -> DiscoveryPlayTemplateRead { try await readDiscovery { try await $0.playTemplateRead(id:id,token:$1) } }

    private func readMerchant<Value>(access:MerchantAccess?=nil, expectedDiscoveryScope: ClubDiscoveryScope? = nil,_ operation:(MerchantService,String) async throws -> Value) async throws -> Value {
        guard let merchantService else { throw APIError.notConfigured }
        guard account != nil, let credential=token else { throw APIError.unauthorized }
        let stamp=gate.currentStamp
        if let access {
            guard let record=merchantAccessRecord, record.stamp == stamp, record.access == access else { throw MerchantReadError.accessDenied }
        }
        do {
            let value=try await operation(merchantService,credential)
            try Task.checkCancellation()
            guard gate.isCurrent(stamp), credential == token,
                  expectedDiscoveryScope == nil || expectedDiscoveryScope == clubDiscoveryScope else { throw CancellationError() }
            return value
        } catch {
            guard expectedDiscoveryScope == nil || !Task.isCancelled else { throw CancellationError() }
            guard gate.isCurrent(stamp), credential == token,
                  expectedDiscoveryScope == nil || expectedDiscoveryScope == clubDiscoveryScope else { throw CancellationError() }
            expireIfMatching(error:error,stamp:stamp,credential:credential)
            throw error
        }
    }
    func merchantAccess() async throws -> MerchantAccess {
        merchantClubAccessRevision &+= 1
        merchantAccessRecord=nil
        let localityScope = clubDiscoveryScope
        let access=try await readMerchant(expectedDiscoveryScope: localityScope) { try await $0.access(token:$1) }
        guard clubDiscoveryScope == localityScope else { throw CancellationError() }
        merchantAccessRecord=(gate.currentStamp,access)
        merchantClubAccessRevision &+= 1
        return access
    }
    func merchantDashboard(access:MerchantAccess) async throws -> MerchantDashboard { try await readMerchant(access:access) { try await $0.dashboard(access:access,token:$1) } }
    func merchantTodo(access:MerchantAccess) async throws -> MerchantTodo { try await readMerchant(access:access) { try await $0.todo(access:access,token:$1) } }
    func merchantEvents(access:MerchantAccess) async throws -> [MerchantEvent] { try await readMerchant(access:access) { try await $0.events(access:access,token:$1) } }
    func merchantOrders(access:MerchantAccess,filter:MerchantOrderFilter) async throws -> [MerchantOrder] { try await readMerchant(access:access) { try await $0.orders(access:access,filter:filter,token:$1) } }
    func merchantProjects(access:MerchantAccess) async throws -> MerchantProjectPage { try await readMerchant(access:access) { try await $0.projects(access:access,token:$1) } }
}

extension AppSession: ClubReading {
    var isClubConfigured: Bool { clubReader.isClubConfigured }
    var clubIdentity: ClubReadIdentity { clubReader.clubIdentity }
    var clubDiscoveryScope: ClubDiscoveryScope {
        let merchantID = merchantAccessRecord.flatMap { $0.stamp == gate.currentStamp ? $0.access.merchantID : nil }
        return .init(identity: clubIdentity, role: account?.effectiveRole,
                     viewerRevision: compositionViewerRevision, merchantID: merchantID,
                     merchantRevision: merchantClubAccessRevision)
    }
    func clubMerchantLocality() async throws -> MerchantClubLocality {
        let captured = clubDiscoveryScope, credential = token
        guard captured.isMerchantViewer, let credential else { throw APIError.unauthorized }
        guard let merchantOnboardingService else { throw APIError.notConfigured }
        try Task.checkCancellation()
        do {
            let result = try await merchantOnboardingService.clubLocality(token: credential)
            guard !Task.isCancelled, clubDiscoveryScope == captured, token == credential else { throw CancellationError() }
            guard captured.merchantID == nil || captured.merchantID == result.merchantID else { throw MerchantReadError.accessDenied }
            return result
        } catch {
            guard !Task.isCancelled, clubDiscoveryScope == captured, token == credential else { throw CancellationError() }
            // Locality is optional presentation. In particular a superseded request's 401
            // must not expire a live session; the per-view generation accepts only its own result.
            throw error
        }
    }
    func clubHome() async throws -> ClubHome { try await clubReader.clubHome() }
    func clubOwned() async throws -> [ClubRecord] { try await clubReader.clubOwned() }
    func clubDirectory(name:String?) async throws -> [ClubRecord] { try await clubReader.clubDirectory(name:name) }
    func clubDetail(id:Int) async throws -> ClubRecord { try await clubReader.clubDetail(id:id) }
    func clubMembers(id:Int) async throws -> ClubMemberDirectory { try await clubReader.clubMembers(id:id) }
}

@MainActor private struct UnconfiguredRegistrationBackend:RegistrationCoordinatingService {
    func quote(_ selection:RegistrationQuoteRequest,token:String) async throws -> RegistrationQuote { throw APIError.notConfigured }
    func create(_ intent:RegistrationCreateIntent,token:String) async throws -> RegistrationCreateResult { throw APIError.notConfigured }
    func readStatus(registrationID:Int,token:String) async throws -> RegistrationStatusSnapshot { throw APIError.notConfigured }
}

// Registration intent is navigation only; merchant authorization still comes from access/me.
extension AppSession: MerchantOnboardingObserving {}

extension AppSession {
    var currentHomeContinuationOwnerScope: HomeContinuationOwnerScope? {
        guard isSignedIn, let account else { return nil }
        return HomeContinuationOwnerScope(
            accountID: account.id,
            sessionRevision: sessionRevision,
            journeyScope: playerJourneyReader.scope
        )
    }

    private static func playContinuationDefaultsKeys(
        namespace: String,
        accountID: Int,
        role: String
    ) -> (scopesKey: String, titlesKey: String)? {
        guard !namespace.isEmpty, accountID > 0,
              let parsedRole = PlayRecoveryAccountRole(rawValue: role) else { return nil }
        let prefix = "play.continuation.\(namespace).\(accountID).\(parsedRole.rawValue)"
        return ("\(prefix).scopes", "\(prefix).titles")
    }

    private func playContinuationDefaultsKeys() -> (scopesKey: String, titlesKey: String)? {
        guard let storageScope, let account else { return nil }
        return Self.playContinuationDefaultsKeys(
            namespace: storageScope.service,
            accountID: account.id,
            role: account.effectiveRole
        )
    }

    private static func encodeContinuationScopeToken(_ scope: PlaySessionScope) -> String {
        switch scope {
        case .activity(let id): return "activity:\(id)"
        case .topic(let id): return "topic:\(id)"
        }
    }

    private static func decodeContinuationScopeToken(_ token: String) -> PlaySessionScope? {
        let parts = token.split(separator: ":", maxSplits: 1)
        guard parts.count == 2, let id = Int(parts[1]), id > 0 else { return nil }
        switch parts[0] {
        case "activity": return .activity(id)
        case "topic": return .topic(id)
        default: return nil
        }
    }

    private func matchesContinuationSession(_ expected: PlayExperienceSession, viewerRevision: UInt64) -> Bool {
        guard !committingAuthenticatedSession,
              isSignedIn,
              let currentStorage = storageScope,
              let currentAccount = account,
              let currentToken = token,
              currentStorage.service == expected.namespace,
              currentAccount.id == expected.accountID,
              gate.currentStamp == expected.epoch,
              currentToken == expected.token,
              currentAccount.effectiveRole == expected.role,
              compositionViewerRevision == viewerRevision else {
            return false
        }
        return true
    }

    private func persistPlayContinuationScope(
        _ scope: PlaySessionScope,
        title: String? = nil,
        expectedSession: PlayExperienceSession,
        expectedViewerRevision: UInt64
    ) {
        guard scope.isValid,
              matchesContinuationSession(expectedSession, viewerRevision: expectedViewerRevision),
              let keys = Self.playContinuationDefaultsKeys(
                  namespace: expectedSession.namespace,
                  accountID: expectedSession.accountID,
                  role: expectedSession.role
              ) else { return }
        let token = Self.encodeContinuationScopeToken(scope)
        var existing = sessionDefaults.stringArray(forKey: keys.scopesKey) ?? []
        if !existing.contains(token) {
            existing.append(token)
            sessionDefaults.set(existing, forKey: keys.scopesKey)
        }
        if let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty {
            var titles = (sessionDefaults.dictionary(forKey: keys.titlesKey) as? [String: String]) ?? [:]
            titles[token] = trimmed
            sessionDefaults.set(titles, forKey: keys.titlesKey)
        }
    }

    func registerPlayContinuationScope(_ scope: PlaySessionScope, title: String? = nil) {
        guard !committingAuthenticatedSession,
              let storageScope,
              let account,
              let token,
              let role = PlayRecoveryAccountRole(rawValue: account.effectiveRole),
              let playSession = try? PlayExperienceSession(
                  accountID: account.id,
                  epoch: gate.currentStamp,
                  namespace: storageScope.service,
                  token: token,
                  role: role.rawValue
              ) else { return }
        persistPlayContinuationScope(
            scope,
            title: title,
            expectedSession: playSession,
            expectedViewerRevision: compositionViewerRevision
        )
    }

    func loadPausedContinueRuns(
        participations: [ParticipationRecord] = [],
        additionalScopes: [PlaySessionScope] = []
    ) async -> [PlayContinueRun] {
        guard !committingAuthenticatedSession,
              let regional = regionalConfiguration,
              let capturedStorageScope = storageScope,
              let capturedAccount = account,
              let capturedToken = token,
              let role = PlayRecoveryAccountRole(rawValue: capturedAccount.effectiveRole),
              let playSession = try? PlayExperienceSession(
                  accountID: capturedAccount.id,
                  epoch: gate.currentStamp,
                  namespace: capturedStorageScope.service,
                  token: capturedToken,
                  role: role.rawValue
              ) else {
            return []
        }
        let capturedViewerRevision = compositionViewerRevision
        let capturedApprovalKey = currentPlayReadApprovalKey

        let keys = Self.playContinuationDefaultsKeys(
            namespace: playSession.namespace,
            accountID: playSession.accountID,
            role: playSession.role
        )
        let persistedTokens = keys.flatMap { sessionDefaults.stringArray(forKey: $0.scopesKey) } ?? []
        let persistedTitles = keys.flatMap { sessionDefaults.dictionary(forKey: $0.titlesKey) as? [String: String] } ?? [:]

        var titlesByScope: [PlaySessionScope: String] = [:]
        for (tokenKey, storedTitle) in persistedTitles {
            if let scope = Self.decodeContinuationScopeToken(tokenKey) {
                titlesByScope[scope] = storedTitle
            }
        }
        for record in participations {
            if let scope = record.destination,
               let name = record.name?.trimmingCharacters(in: .whitespacesAndNewlines),
               !name.isEmpty {
                titlesByScope[scope] = name
                persistPlayContinuationScope(
                    scope,
                    title: name,
                    expectedSession: playSession,
                    expectedViewerRevision: capturedViewerRevision
                )
            }
        }

        var candidateScopes: [PlaySessionScope] = []
        var seen = Set<PlaySessionScope>()
        func appendScope(_ scope: PlaySessionScope) {
            guard scope.isValid, seen.insert(scope).inserted else { return }
            candidateScopes.append(scope)
        }

        for record in participations {
            if let scope = record.destination { appendScope(scope) }
        }
        for scope in additionalScopes {
            appendScope(scope)
        }
        for tokenKey in persistedTokens {
            if let scope = Self.decodeContinuationScopeToken(tokenKey) {
                appendScope(scope)
            }
        }
        for (key, _) in playExperienceCoordinators
        where key.accountID == playSession.accountID && key.epoch == playSession.epoch && key.role == playSession.role && key.viewerRevision == capturedViewerRevision {
            appendScope(key.scope)
        }

        var runs: [PlayContinueRun] = []
        for scope in candidateScopes {
            guard !Task.isCancelled,
                  matchesContinuationSession(playSession, viewerRevision: capturedViewerRevision) else {
                return []
            }
            let readerKey = PlayReaderKey(
                accountID: playSession.accountID,
                epoch: playSession.epoch,
                role: playSession.role,
                viewerRevision: capturedViewerRevision,
                approval: capturedApprovalKey,
                scope: scope
            )
            let retained = playExperienceCoordinators[readerKey]
            if let retained, retained.clock.phase == .paused || retained.clock.phase == .running {
                runs.append(
                    PlayContinueRun(
                        scope: scope,
                        elapsedSeconds: retained.clock.elapsedSeconds,
                        title: titlesByScope[scope]
                    )
                )
                continue
            }
            // If an in-memory coordinator for this session already loaded and explicitly ended the run, do not resurrect it.
            if let retained, retained.phase != .idle && retained.clock.phase == .idle {
                continue
            }
            guard let recovery = try? composition.storage.playRecovery.make(
                session: playSession,
                scope: scope,
                regionalConfiguration: regional,
                storageScope: capturedStorageScope
            ) else {
                continue
            }
            let storageKey = PlayRunStorageKey.make(session: playSession, scope: scope)
            let paused = try? await recovery.read(key: storageKey)
            guard !Task.isCancelled,
                  matchesContinuationSession(playSession, viewerRevision: capturedViewerRevision) else {
                return []
            }
            if let paused,
               let snapshot = paused.value,
               snapshot.owner.matches(playSession),
               let record = snapshot.record {
                persistPlayContinuationScope(
                    scope,
                    title: titlesByScope[scope],
                    expectedSession: playSession,
                    expectedViewerRevision: capturedViewerRevision
                )
                runs.append(
                    PlayContinueRun(
                        scope: scope,
                        elapsedSeconds: record.elapsedSeconds,
                        title: titlesByScope[scope]
                    )
                )
            }
        }
        return runs
    }

    func hasResumablePlayState(for scope: PlaySessionScope) async -> Bool {
        let runs = await loadPausedContinueRuns(additionalScopes: [scope])
        return runs.contains { $0.scope == scope }
    }
}
