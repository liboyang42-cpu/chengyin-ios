import Foundation
import SwiftUI

@MainActor struct NativeWebhookManagementView: View {
    @ObservedObject var model: NativeWebhookViewModel
    var body: some View {
        List {
            if model.coordinator == nil {
                ContentUnavailableView(nativeWebhookLocalized("d7.webhook.unavailable"), systemImage: "point.3.connected.trianglepath.dotted")
                    .accessibilityIdentifier("webhook.source.unavailable")
            } else {
                Section {
                    Picker(nativeWebhookLocalized("d7.webhook.family"), selection: Binding(get: { model.coordinator?.family ?? .subscription }, set: { family in
                        Task { await model.switchFamily(family) }
                    })) {
                        Text(nativeWebhookLocalized("d7.webhook.family.outgoing")).tag(NativeWebhookFamily.subscription)
                        Text(nativeWebhookLocalized("d7.webhook.family.incoming")).tag(NativeWebhookFamily.endpoint)
                    }
                    .pickerStyle(.segmented).disabled(model.coordinator?.busy == true)
                    .accessibilityIdentifier("webhook.family")
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
                NativeWebhookStatusSection(model: model)
                if model.coordinator?.pending != nil {
                    Section(nativeWebhookLocalized("d7.webhook.pending.title")) {
                        Button(nativeWebhookLocalized("d7.webhook.resume.continue")) { Task { await model.openRecovery() } }
                            .disabled(!model.available || model.coordinator?.busy == true)
                            .accessibilityIdentifier("webhook.pending.recover")
                    }
                }
                if let coordinator = model.coordinator, model.available {
                    Section {
                        if coordinator.resources.isEmpty && !coordinator.busy {
                            ContentUnavailableView(nativeWebhookLocalized("d7.webhook.list.empty"), systemImage: "point.3.connected.trianglepath.dotted")
                                .accessibilityIdentifier("webhook.resources.empty")
                        }
                        ForEach(coordinator.resources) { resource in
                            NavigationLink(value: NativeWebhookDestination.resource(resource.id)) {
                                LabeledContent {
                                    Text(resource.status == .active ? nativeWebhookLocalized("d7.webhook.status.on") : nativeWebhookLocalized("d7.webhook.status.off"))
                                } label: {
                                    Text(resource.name).fixedSize(horizontal: false, vertical: true)
                                    if let host = resource.urlHost { Text(verbatim: host).fixedSize(horizontal: false, vertical: true) }
                                }
                            }
                            .disabled(coordinator.busy)
                            .accessibilityIdentifier("webhook.resource.\(resource.id.rawValue)")
                        }
                        if coordinator.hasMoreResources {
                            Button(nativeWebhookLocalized("d7.webhook.loadMore")) { Task { await coordinator.load(nextPage: true) } }
                                .disabled(coordinator.busy).accessibilityIdentifier("webhook.resources.more")
                        }
                    }
                    Section {
                        Button(nativeWebhookLocalized("d7.webhook.add")) { model.edit() }.nativeChannelFlowAction()
                            .disabled(!model.canMutate).accessibilityIdentifier("webhook.resource.create")
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                } else if model.coordinator?.busy == false {
                    ContentUnavailableView(nativeWebhookLocalized("d7.webhook.list.loadFailed"), systemImage: "exclamationmark.circle",
                        description: Text(verbatim: nativeWebhookLocalized("d7.webhook.list.loadFailed.message")))
                }
                Section {
                    Button(nativeWebhookLocalized("d7.webhook.reload")) { Task { await model.coordinator?.load() } }
                        .disabled(model.coordinator?.busy == true).accessibilityIdentifier("webhook.resources.refresh")
                }
            }
        }
        .nativeChannelFlowPage()
        .navigationTitle(nativeWebhookLocalized("d7.webhook.title"))
        .refreshable { await model.coordinator?.load() }
        .accessibilityIdentifier("webhook.resources")
    }
}

@MainActor struct NativeWebhookResourceDetail: View {
    @ObservedObject var model: NativeWebhookViewModel
    let resourceID: NativeWebhookID
    @State private var testEvent = ""
    var body: some View {
        Form {
            NativeWebhookStatusSection(model: model)
            if let coordinator = model.coordinator, let resource = coordinator.selected,
               resource.id == resourceID, model.available {
                Section {
                    LabeledContent(nativeWebhookLocalized("d7.webhook.field.name"), value: resource.name)
                    LabeledContent(nativeWebhookLocalized("d7.webhook.field.status"), value: resource.status == .active ? nativeWebhookLocalized("d7.webhook.status.on") : nativeWebhookLocalized("d7.webhook.status.off"))
                    if let time = resource.updatedAt { NativeWebhookTimeRow(label: nativeWebhookLocalized("d7.webhook.field.updated"), time: time) }
                }
                if coordinator.family == .subscription {
                    Section {
                        if let host = resource.urlHost { LabeledContent(nativeWebhookLocalized("d7.webhook.field.url"), value: host) }
                        if let failures = resource.failCount { LabeledContent(nativeWebhookLocalized("d7.webhook.field.failures"), value: String(failures)) }
                        if let error = resource.lastError { LabeledContent(nativeWebhookLocalized("d7.webhook.field.lastError"), value: error) }
                        if let time = resource.lastDeliveryAt { NativeWebhookTimeRow(label: nativeWebhookLocalized("d7.webhook.field.lastDelivery"), time: time) }
                        NavigationLink(nativeWebhookLocalized("d7.webhook.deliveries.title"), value: NativeWebhookDestination.deliveryLog)
                            .disabled(coordinator.busy)
                            .accessibilityIdentifier("webhook.deliveryLogs.open")
                    }
                    Section(nativeWebhookLocalized("d7.webhook.events")) {
                        let options = coordinator.context?.eventCatalogue.options ?? []
                        if (resource.events ?? []).isEmpty { Text(verbatim: "—").foregroundStyle(.secondary) }
                        ForEach(resource.events ?? [], id: \.self) { event in
                            Text(verbatim: options.first(where: { $0.id == event })?.title ?? event).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    testSection(resource, coordinator: coordinator)
                } else {
                    Section {
                        if let prefix = resource.tokenPrefix { LabeledContent(nativeWebhookLocalized("d7.webhook.field.token"), value: prefix) }
                        if let rate = resource.rateLimitPerMinute { LabeledContent(nativeWebhookLocalized("d7.webhook.field.rateLimit"), value: String(rate)) }
                        if let ips = resource.allowedIPs {
                            LabeledContent(nativeWebhookLocalized("d7.webhook.field.allowedIPs"), value: ips.isEmpty ? nativeWebhookLocalized("d7.webhook.field.allowedIPs.any") : ips.joined(separator: "\n"))
                        }
                        if let time = resource.lastCalledAt { NativeWebhookTimeRow(label: nativeWebhookLocalized("d7.webhook.field.lastUsed"), time: time) }
                        NavigationLink(nativeWebhookLocalized("d7.webhook.inbound.title"), value: NativeWebhookDestination.inboundLog)
                            .disabled(coordinator.busy)
                            .accessibilityIdentifier("webhook.inboundLogs.open")
                    }
                }
                Section {
                    Button(nativeWebhookLocalized("d7.webhook.edit")) { model.edit(resource) }
                        .accessibilityIdentifier("webhook.resource.edit")
                    Button(resource.status == .active ? nativeWebhookLocalized("d7.webhook.turnOff") : nativeWebhookLocalized("d7.webhook.turnOn")) {
                        model.setActive(resource.status != .active, resource: resource)
                    }.accessibilityIdentifier("webhook.resource.toggle")
                    Button(coordinator.family == .subscription ? nativeWebhookLocalized("d7.webhook.resetSecret") : nativeWebhookLocalized("d7.webhook.resetURLAndSecret")) {
                        model.action(.rotate, resource: resource)
                    }.accessibilityIdentifier("webhook.resource.rotate")
                }
                .disabled(!model.canMutate)
                Section {
                    Button(nativeWebhookLocalized("d7.webhook.delete"), role: .destructive) { model.action(.delete, resource: resource) }
                        .accessibilityIdentifier("webhook.resource.delete")
                }
                .disabled(!model.canMutate)
                if coordinator.pending != nil {
                    Section { Button(nativeWebhookLocalized("d7.webhook.resume.continue")) { Task { await model.openRecovery() } }
                        .disabled(coordinator.busy).accessibilityIdentifier("webhook.detail.recover") }
                }
                Section {
                    Button(nativeWebhookLocalized("d7.webhook.reload")) { Task { await coordinator.select(resourceID) } }
                        .disabled(coordinator.busy).accessibilityIdentifier("webhook.detail.refresh")
                }
            } else if model.coordinator?.busy == false {
                ContentUnavailableView(nativeWebhookLocalized("d7.webhook.detail.loadFailed"), systemImage: "exclamationmark.circle",
                    description: Text(verbatim: nativeWebhookLocalized("d7.webhook.goBack")))
            }
        }
        .nativeChannelFlowPage()
        .navigationTitle(nativeWebhookLocalized("d7.webhook.detail.title"))
        .task(id: resourceID) { await model.coordinator?.select(resourceID) }
        .accessibilityIdentifier("webhook.detail")
    }
    @ViewBuilder private func testSection(_ resource: NativeWebhookResource, coordinator: NativeWebhookCoordinator) -> some View {
        Section(nativeWebhookLocalized("d7.webhook.test")) {
            if let options = coordinator.context?.eventCatalogue.options {
                let subscribed = options.filter { resource.events?.contains($0.id) == true }
                Picker(nativeWebhookLocalized("d7.webhook.test.event"), selection: $testEvent) {
                    Text(nativeWebhookLocalized("d7.webhook.test.choose")).tag("")
                    ForEach(subscribed) { option in Text(option.title).tag(option.id) }
                }.accessibilityIdentifier("webhook.test.event")
                Button(nativeWebhookLocalized("d7.webhook.test.send")) { model.action(.test(eventType: testEvent), resource: resource) }
                    .disabled(!model.canMutate || resource.status != .active || !subscribed.contains(where: { $0.id == testEvent }))
                    .accessibilityIdentifier("webhook.test.prepare")
            } else {
                Text(nativeWebhookLocalized("d7.webhook.events.unavailable"))
                    .accessibilityIdentifier("webhook.events.unavailable")
            }
        }
    }
}
