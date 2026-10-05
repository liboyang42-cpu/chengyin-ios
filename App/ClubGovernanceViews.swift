import SwiftUI

/// Mount independently of legacy isOwner/viewerIsAdmin. access/me decides each row.
struct ClubGovernanceEntryButton: View {
    let clubID: Int
    let identity: ClubReadIdentity?
    let access: any ClubGovernanceAccess
    let coordinator: ClubGovernanceCoordinator
    var enrollmentProfile: ClubEnrollmentProfileContext? = nil
    var ownerRefund: ClubOwnerRefundCoordinator? = nil
    var opsTimeFactory: ((Int) -> ClubOpsTimeCoordinator?)? = nil
    var customerTopics = ClubCustomerTopicContext()
    @State private var presented = false
    var body: some View {
        Button { presented = true } label: { Label("club.gov.workspace", systemImage: "person.3.sequence.fill") }
            .accessibilityIdentifier("club.gov.open")
            .sheet(isPresented: $presented) {
                NavigationStack { ClubGovernanceWorkspaceView(clubID: clubID, identity: identity, access: access, coordinator: coordinator) }
                    .environment(\.clubEnrollmentProfile, enrollmentProfile)
                    .environment(\.clubOwnerRefundCoordinator, ownerRefund)
                    .environment(\.clubOpsTimeFactory, opsTimeFactory)
                    .environment(\.clubCustomerTopics, customerTopics)
            }
    }
}
struct ClubGovernanceHomeEntries: View {
    var feedContext = ClubGovernanceFeedContext()
    let identity: ClubReadIdentity?
    let access: any ClubGovernanceAccess
    let coordinator: ClubGovernanceCoordinator
    var body: some View {
        NavigationLink { ClubGovernanceReadView(operation: .hostStatus, scope: .init(), identity: identity, access: access, coordinator: coordinator) } label: { Label("club.gov.hostStatus", systemImage: "person.badge.plus") }
            .accessibilityIdentifier("club.gov.openHost")
        NavigationLink { ClubGovernanceReadView(operation: .feed, scope: .init(), identity: identity, access: access, coordinator: coordinator)
                .environment(\.clubGovernanceFeed, feedContext) } label: { Label("club.gov.feed", systemImage: "text.bubble") }
            .accessibilityIdentifier("club.gov.openFeed")
    }
}
struct ClubGovernanceWorkspaceView: View {
    let clubID: Int
    let identity: ClubReadIdentity?
    let access: any ClubGovernanceAccess
    let coordinator: ClubGovernanceCoordinator
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ClubGovernanceReadView(operation: .access, scope: .init(clubID: clubID), identity: identity, access: access, coordinator: coordinator)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("club.gov.close") { dismiss() } } }
    }
}

struct ClubGovernanceFormRoute: Identifiable {
    let id = UUID()
    let operation: ClubGovernanceMutation
    let scope: ClubGovernanceScope
    var seed: [String: ClubGovernanceValue] = [:]
}

struct ClubGovernanceReadView: View {
    @Environment(\.clubOpsTimeFactory) private var opsTimeFactory
    @Environment(\.clubCustomerTopics) private var customerTopics
    @Environment(\.clubGovernanceFeed) private var feedContext
    let operation: ClubGovernanceRead
    let scope: ClubGovernanceScope
    let identity: ClubReadIdentity?
    let access: any ClubGovernanceAccess
    let coordinator: ClubGovernanceCoordinator
    @State private var snapshot: ClubGovernanceSnapshot?
    @State private var snapshotContext: ClubGovernanceReadContext?
    @State private var snapshotGeneration: UInt64 = 0
    @State private var customerTopic: ClubCustomerHistoryTopicRoute?
    @State private var feedClub: ClubFeedClubRoute?
    @State private var feedMediaScope = UUID()
    private var readContext: ClubGovernanceReadContext {
        .init(operation: operation, scope: scope, identity: identity, viewerRevision: operation == .feed ? feedContext.viewerRevision : customerTopics.viewerRevision,
              authorizationGeneration: access.authorizationGeneration,
              readerIdentity: operation == .feed ? feedContext.readerIdentity : nil, accessIdentity: ObjectIdentifier(access))
    }
    @State private var failure: ClubGovernanceFailure?
    @State private var loading = false
    @State private var generation: UInt64 = 0
    @State private var filter = "all"
    @State private var topicCustomerFilter: ClubTopicCustomerFilter = .all
    @State private var keyword = ""
    @State private var sort = "composite"
    @State private var page = 1
    @State private var editor: ClubGovernanceFormRoute?
    private var title: LocalizedStringKey { LocalizedStringKey("club.gov." + operation.rawValue) }
    var body: some View {
        List {
            if loading { ProgressView().accessibilityIdentifier("club.gov.loading") }
            if let failure {
                Section { Text(LocalizedStringKey(failure.localizationKey)).accessibilityIdentifier("club.gov.error"); if let message = failure.message { Text(verbatim: message).textSelection(.enabled) } }
            }
            if operation == .customers {
                Section {
                    Picker("club.gov.filter", selection: $filter) {
                        ForEach(["all", "repeat", "new", "remark"], id: \.self) { Text(LocalizedStringKey("club.gov.filter." + $0)).tag($0) }
                    }
                    .onChange(of: filter) { _, _ in Task { await load() } }
                    TextField("club.gov.keyword", text: $keyword).submitLabel(.search).onSubmit { Task { await load() } }
                    Button("club.gov.search") { Task { await load() } }.disabled(loading)
                }
            }
            if operation == .topicCustomers {
                Section {
                    Picker("club.gov.filter", selection: $topicCustomerFilter) {
                        ForEach(ClubTopicCustomerFilter.allCases, id: \.rawValue) { item in
                            Text(LocalizedStringKey(item.localizationKey)).tag(item)
                        }
                    }.accessibilityIdentifier("club.gov.topicCustomers.filter")
                        .onChange(of: topicCustomerFilter) { _, _ in Task { await load() } }
                    Text("club.gov.topicCustomers.countScope").font(.footnote).foregroundStyle(.secondary)
                }
            }
            if operation == .leaderboard {
                Picker("club.gov.sort", selection: $sort) { ForEach(["composite", "mileage", "pace", "duration"], id: \.self) { Text(LocalizedStringKey("club.gov.sort." + $0)).tag($0) } }
                    .onChange(of: sort) { _, _ in Task { await load() } }
            }
            if let snapshot, snapshotContext == readContext, identity == access.identity { content(snapshot) }
            if operation == .posts, snapshot != nil {
                Section {
                    HStack {
                        Button("club.gov.previous") { page -= 1; Task { await load() } }.disabled(page <= 1 || loading).accessibilityIdentifier("club.gov.previous")
                        Spacer(); Text(page, format: .number)
                        Button("club.gov.next") { page += 1; Task { await load() } }.disabled(loading || (snapshot?.value.array ?? snapshot?.value["rows"].array ?? []).count < 20).accessibilityIdentifier("club.gov.next")
                    }
                }
            }
            if !loading { Button("club.gov.refresh") { Task { await load() } }.accessibilityIdentifier("club.gov.refresh") }
        }
        .navigationTitle(title)
        .sheet(item: $editor) { route in NavigationStack { ClubGovernanceCommandForm(route: route, identity: identity, access: access, coordinator: coordinator) } }
        .navigationDestination(item: $customerTopic) { target in
            if let destination = customerTopics.destination, current(target) {
                destination(target.topicID).id(target.id)
            }
        }
        .navigationDestination(item: $feedClub) { target in
            if let destination = feedContext.destination, current(target) {
                destination(target.clubID).id(target.id)
            }
        }
        .task(id: readContext) { snapshot = nil; editor = nil; customerTopic = nil; feedClub = nil; coordinator.cancelReview(); await load() }
        .onChange(of: readContext) { _, _ in invalidateRead() }
        .onChange(of: identity) { _, _ in invalidateRead() }
        .onDisappear { generation &+= 1 }
        .refreshable { await load() }
    }
    private func load() async {
        generation &+= 1; let revision = generation; let expected = identity; let context = readContext
        snapshot = nil; failure = nil; loading = true
        snapshotContext = nil; customerTopic = nil; feedClub = nil; feedMediaScope = UUID()
        guard expected?.isSignedIn == true else { loading = false; failure = .signedOut; return }
        var options: [String: ClubGovernanceValue] = [:]
        if operation == .customers { options = ["filter": .string(filter), "keyword": .string(keyword)] }
        if operation == .topicCustomers { options = topicCustomerFilter.options }
        if operation == .leaderboard { options = ["sortBy": .string(sort)] }
        if operation == .feed { options = ["limit": .integer(20)] }
        if operation == .posts { options = ["pageNum": .integer(page), "pageSize": .integer(20)] }
        do {
            let result = try await access.read(operation, scope: scope, options: options) {
                guard revision == generation, context == readContext, expected == identity,
                      access.identity == expected, !Task.isCancelled else { throw CancellationError() }
            }
            guard revision == generation, context == readContext, expected == identity, access.identity == expected, !Task.isCancelled else { return }
            guard context.accepts(result) else { throw ClubGovernanceFailure.targetChanged }
            snapshotContext = context; snapshotGeneration = revision; snapshot = result
        } catch {
            guard revision == generation, context == readContext, expected == identity, access.identity == expected, !Task.isCancelled else { return }
            failure = error as? ClubGovernanceFailure ?? .malformed
        }
        if revision == generation { loading = false }
    }
    private func invalidateRead() {
        generation &+= 1; snapshot = nil; snapshotContext = nil; failure = nil; editor = nil; customerTopic = nil; feedClub = nil; feedMediaScope = UUID(); coordinator.cancelReview()
    }
    private func current(_ target: ClubFeedClubRoute) -> Bool {
        identity == access.identity && access.isConfigured && snapshotContext == readContext &&
        feedContext.destination != nil &&
        target.isCurrent(snapshot: snapshot, context: readContext, snapshotGeneration: snapshotGeneration)
    }
    private func feedClubRoute(_ post: ClubFeedPost) -> ClubFeedClubRoute? {
        guard let snapshot, snapshotContext == readContext, identity == access.identity,
              access.isConfigured, feedContext.destination != nil else { return nil }
        return .init(post: post, snapshot: snapshot, context: readContext, snapshotGeneration: snapshotGeneration)
    }
    private func selectFeedClub(_ target: ClubFeedClubRoute) {
        guard feedClub == nil, current(target) else { return }
        feedClub = target
    }
    private func current(_ target: ClubCustomerHistoryTopicRoute) -> Bool {
        identity == access.identity && access.isConfigured && snapshotContext == readContext &&
        target.isCurrent(snapshot: snapshot, context: readContext, snapshotGeneration: snapshotGeneration)
    }
    private func customerTopicRoute(_ row: ClubGovernanceValue) -> ClubCustomerHistoryTopicRoute? {
        guard operation == .customer, let snapshot, snapshotContext == readContext,
              customerTopics.destination != nil, identity == access.identity, access.isConfigured else { return nil }
        return .init(record: row, snapshot: snapshot, context: readContext, snapshotGeneration: snapshotGeneration)
    }
    private func selectCustomerTopic(_ target: ClubCustomerHistoryTopicRoute) {
        guard customerTopic == nil, current(target) else { return }
        customerTopic = target
    }
    private func link(_ target: ClubGovernanceRead, _ targetScope: ClubGovernanceScope? = nil) -> some View {
        NavigationLink { ClubGovernanceReadView(operation: target, scope: targetScope ?? scope, identity: identity, access: access, coordinator: coordinator) } label: { Label(LocalizedStringKey("club.gov." + target.rawValue), systemImage: "chevron.right.circle") }
            .accessibilityIdentifier("club.gov.route." + target.rawValue)
    }
    @ViewBuilder private func enrollmentLink(focusTopicID: Int? = nil) -> some View {
        if let clubID = scope.clubID {
            NavigationLink {
                ClubEnrollmentView(clubID: clubID, focusTopicID: focusTopicID, identity: identity, access: access, coordinator: coordinator)
            } label: { Label("club.enroll.title", systemImage: "list.bullet.clipboard") }
                .accessibilityIdentifier("club.enroll.open")
        }
    }
    private func edit(_ operation: ClubGovernanceMutation, scope: ClubGovernanceScope? = nil, seed: [String: ClubGovernanceValue] = [:]) -> some View {
        Button(LocalizedStringKey("club.gov.action." + operation.rawValue)) { editor = .init(operation: operation, scope: scope ?? self.scope, seed: seed) }
            .accessibilityIdentifier("club.gov.action." + operation.rawValue)
    }
    @ViewBuilder private func content(_ snapshot: ClubGovernanceSnapshot) -> some View {
        let value = snapshot.value
        if operation == .access {
            Section("club.gov.roles") {
                ForEach(snapshot.permissions?.roleCodes ?? [], id: \.self) { code in
                    if ["CLUB_OWNER", "CLUB_CO_OWNER", "CLUB_OPERATOR", "CLUB_MEMBER", "EVENT_LEAD", "EVENT_CHECKIN"].contains(code) { Text(LocalizedStringKey("club.gov.role." + code)) }
                    else { Text(verbatim: code) }
                }
            }
            Section("club.gov.workspace") {
                if snapshot.permissions?.allows("club:member:list:read", scope: scope) == true { enrollmentLink() }
                ForEach([ClubGovernanceRead.stats, .customers, .settlement, .eventTopics, .series, .bans, .cases, .roles, .audienceCounts, .topics, .editions, .dissolutionBlockers, .leaderboard, .posts], id: \.rawValue) { read in
                    if snapshot.permissions?.allows(read.permission, scope: scope) == true { link(read) }
                }
            }
            if let events = snapshot.permissions?.eventAccesses, !events.isEmpty {
                Section("club.gov.delegatedEvents") {
                    ForEach(Array(events.enumerated()), id: \.offset) { _, event in
                        if let activityID = event["activityId"].int, let topicID = event["topicId"].int {
                            let target = ClubGovernanceScope(clubID: scope.clubID, topicID: topicID, activityID: activityID)
                            NavigationLink { ClubGovernanceEventView(scope: target, identity: identity, access: access, coordinator: coordinator) } label: { Text("club.gov.eventID \(activityID)") }
                        }
                    }
                }
            }
        } else if operation == .hostStatus {
            ClubGovernanceFactRows(value: value, fields: ["accountRole", "registered"])
            if value["accountRole"] == .string("merchant") { Text("club.gov.hostMerchantBlocked") }
            else if value["accountRole"] == .string("club") { Text("club.gov.hostExisting") }
            else { edit(.hostApply); Text("club.gov.identityGate") }
        } else if operation == .roster {
            ForEach(["registered", "waitlist", "arrived", "noShow"], id: \.self) { bucket in
                Section(LocalizedStringKey("club.gov." + bucket)) {
                    ForEach(Array((value[bucket].array ?? []).enumerated()), id: \.offset) { _, row in
                        ClubGovernanceFactRows(value: row, fields: ["nickname", "memberId", "state", "correctionVersion"])
                        if let memberID = row["memberId"].int, let version = row["correctionVersion"].int {
                            edit(.correctAttendance, scope: .init(clubID: scope.clubID, activityID: scope.activityID, memberID: memberID), seed: ["expectedVersion": .integer(version)])
                        }
                    }
                }
            }
        } else if operation == .roles {
            Section("club.gov.roleDefinitions") { ForEach(Array((value["roles"].array ?? []).enumerated()), id: \.offset) { _, row in ClubGovernanceFactRows(value: row, fields: ["name", "roleCode", "scopeType"]) } }
            Section { edit(.assignRole) }
            Section("club.gov.assignments") { ForEach(Array((value["assignments"].array ?? []).enumerated()), id: \.offset) { _, row in
                ClubGovernanceFactRows(value: row, fields: ["memberName", "roleName", "scopeType", "scopeId", "version"])
                edit(.revokeRole, seed: ["assignmentId": row["id"], "version": row["version"]])
            } }
        } else if operation == .topicOverview {
            ClubGovernanceFactRows(value: value, fields: ["name", "title", "auditStatus", "rejectReason", "status", "startDate", "endDate", "playModeText", "storyReady", "gameConfiguredCount"])
            Section { link(.topicStats); link(.topicSettings); link(.topicCustomers); link(.recruit); enrollmentLink(focusTopicID: scope.topicID) }
            Section { NavigationLink("context.rules.title") { ClubOperatingRulesView() }.accessibilityIdentifier("club.context.openRules") }
            Section("club.gov.story") {
                NavigationLink { ClubGovernanceStoryView(value: value, scope: scope, identity: identity, access: access, coordinator: coordinator) } label: { Label("club.gov.story", systemImage: "book.pages") }.accessibilityIdentifier("club.gov.openStory")
            }
            Section("club.gov.events") { ForEach(Array((value["activityList"].array ?? []).enumerated()), id: \.offset) { _, row in
                if let id = row["id"].int {
                    let target = ClubGovernanceScope(clubID: scope.clubID, topicID: scope.topicID, activityID: id)
                    if let startDate = row["startDate"].string, ClubOpsTimeRequest.date(startDate) != nil {
                        NavigationLink("context.ops.title") {
                            ClubOpsTimeView(activityID: id, original: startDate, owner: opsTimeFactory?(id)) { Task { await load() } }
                        }.accessibilityIdentifier("club.context.editOps.\(id)")
                    }
                    NavigationLink { ClubGovernanceEventView(scope: target, identity: identity, access: access, coordinator: coordinator) } label: { Text(verbatim: row["name"].string ?? "#\(id)") }
                }
            } }
        } else if operation == .audienceCounts {
            Section { ClubGovernanceFactRows(value: value["counts"], fields: ["ALL_MEMBERS", "ADMINS", "REGISTERED", "WAITLIST", "NO_SHOW", "INACTIVE"], showUnknown: true); edit(.sendNotification) }
        } else if operation == .dissolutionBlockers {
            Section("club.gov.deposits") { dataRows(value["deposits"].array ?? []) }
            Section("club.gov.settlements") { dataRows(value["settlements"].array ?? []) }
            Text("club.gov.financialGate"); edit(.dissolve)
        } else if operation == .settlement {
            ClubGovernanceFactRows(value: value, fields: ["settledAmountText", "settledAmountStatus", "unverifiedSettledCount"], showUnknown: true)
            Text("club.gov.financialGate")
            dataRows(value["topics"].array ?? [])
        } else if operation == .feed {
            if let feed = try? ClubFeedPresentation(snapshot: snapshot) {
                if feed.posts.isEmpty {
                    if feed.clubCount == 0 {
                        Text("club.gov.noJoinedClubs").accessibilityIdentifier("club.feed.emptyNoClubs")
                    } else {
                        Text("club.gov.empty").accessibilityIdentifier("club.feed.emptyPosts")
                    }
                }
                ForEach(feed.posts) { post in
                    let target = feedClubRoute(post)
                    ClubGovernanceFeedPostView(post: post, mediaScope: feedMediaScope, imageReader: feedContext.imageReader ?? RetainedPublicImageReader(),
                        openClub: target.map { route in { selectFeedClub(route) } })
                }
            } else { Text("club.gov.malformed").accessibilityIdentifier("club.feed.malformed") }
        } else if operation == .customer {
            ClubGovernanceFactRows(value: value["summary"], fields: ["displayName", "phoneText", "arrivedCount", "pendingCount", "refundedCount", "paidAmount"], showUnknown: true)
            ClubGovernanceFactRows(value: value, fields: ["remark"])
            if let tags = value["tags"].array { ForEach(Array(tags.enumerated()), id: \.offset) { _, tag in Text(verbatim: tag.string ?? tag["name"].string ?? "") } }
            if value["canEdit"] == .bool(true) { edit(.saveCustomer, seed: ["remark": value["remark"], "tags": value["tags"]]) }
            dataRows(value["records"].array ?? [])
        } else {
            ClubGovernanceFactRows(value: value, fields: ClubGovernanceFactRows.summaryFields)
            if operation == .customers { ClubGovernanceFactRows(value: value, fields: ["total", "monthNew"]) }
            dataRows(value.array ?? value["items"].array ?? value["rows"].array ?? value["topics"].array ?? value["nodes"].array ?? [])
            if operation == .topicSettings {
                if value["canManage"] == .bool(true) { edit(.saveTopicSettings, seed: ["coopOpen": value["coopOpen"], "pinned": value["pinned"], "memberOnly": value["memberOnly"]]); edit(.endTopic) }
                Section("club.gov.chapters") { ForEach(Array((value["chapters"].array ?? []).enumerated()), id: \.offset) { _, row in
                    ClubGovernanceFactRows(value: row, fields: ["name", "category", "recruiting", "merchantCount", "finishTime"])
                    if let id = row["chapterId"].int, value["canManage"] == .bool(true) {
                        let target = ClubGovernanceScope(clubID: scope.clubID, topicID: scope.topicID, chapterID: id)
                        edit(.chapterRecruit, scope: target); edit(.chapterFinish, scope: target)
                    }
                } }
            }
            if operation == .topicCustomers {
                ClubGovernanceFactRows(value: value, fields: ["soldCount", "pendingCount", "verifiedCount"], showUnknown: true)
                ForEach(Array((value["sessions"].array ?? []).enumerated()), id: \.offset) { _, session in
                ClubGovernanceFactRows(value: session, fields: ["timeText", "name"]); dataRows(session["rows"].array ?? [])
            } }
            if operation == .checkin, let clubID = scope.clubID, let registrationID = scope.registrationID,
               let target = try? ClubOwnerRefundTarget(clubID: clubID, registrationID: registrationID) {
                Section {
                    ClubOwnerRefundPanel(target: target, identity: identity, sourceCanRefund: value["canRefund"] == .bool(true), onReadback: { Task { await load() } })
                }
            }
            if operation == .registrations { enrollmentLink(focusTopicID: scope.topicID) }
            if operation == .seriesDetail { edit(.updateSeries, seed: value.object ?? [:]); link(.occurrences) }
            if operation == .occurrenceStatus && value["activityCancelled"] == .bool(false) { edit(.cancelOccurrence) }
            if operation == .cases { edit(.report); edit(.appeal) }
            if operation == .bans { link(.members) }
            if operation == .notificationStatus && (value["failedCount"].int ?? 0) > 0 { Text("club.gov.deliveryPending"); edit(.retryNotification) }
        }
    }
    @ViewBuilder private func dataRows(_ rows: [ClubGovernanceValue]) -> some View {
        if rows.isEmpty { Text("club.gov.empty").foregroundStyle(.secondary) }
        ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
            Section {
                if let target = customerTopicRoute(row) {
                    Button { selectCustomerTopic(target) } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            ClubGovernanceFactRows(value: row, fields: ClubGovernanceFactRows.summaryFields)
                            Label("topic.detail", systemImage: "chevron.right.circle")
                        }
                    }.accessibilityIdentifier("club.gov.customer.topic.\(target.topicID)")
                } else {
                    ClubGovernanceFactRows(value: row, fields: ClubGovernanceFactRows.summaryFields, showUnknown: operation == .leaderboard || operation == .occurrences)
                }
                if operation == .customers, let id = row["memberId"].int { link(.customer, .init(clubID: scope.clubID, memberID: id)) }
                if [.topics, .eventTopics].contains(operation), let id = row["id"].int {
                    let target = ClubGovernanceScope(clubID: scope.clubID, topicID: id)
                    link(.topicOverview, target)
                    if operation == .eventTopics { edit(.createSeries, scope: target) }
                }
                if operation == .series, let id = row["id"].int { link(.seriesDetail, .init(clubID: scope.clubID, topicID: row["topicId"].int, seriesID: id)) }
                if operation == .occurrences, let id = row["activityId"].int {
                    NavigationLink { ClubGovernanceEventView(scope: .init(clubID: scope.clubID, topicID: scope.topicID, activityID: id), identity: identity, access: access, coordinator: coordinator) } label: { Text("club.gov.eventID \(id)") }
                }
                if operation == .members, let id = row["memberId"].int, row["isOwner"] == .bool(false) {
                    edit(.ban, seed: ["targetMemberId": .integer(id)])
                    if snapshot?.permissions?.roleCodes.contains("CLUB_OWNER") == true { edit(.transferOwner, seed: ["targetMemberId": .integer(id)]) }
                }
                if operation == .bans, row["sourceType"] == .string("CLUB"), row["status"] == .string("ACTIVE") { edit(.unban, seed: ["banId": row["id"], "version": row["version"]]) }
                if operation == .editions, let topicID = row["topicId"].int {
                    let target = ClubGovernanceScope(clubID: scope.clubID, topicID: topicID)
                    edit(.reportHours, scope: target); edit(.submitEvidence, scope: target); Text("club.gov.compensationGate")
                }
            }
        }
    }
}

struct ClubGovernanceEventView: View {
    let scope: ClubGovernanceScope
    let identity: ClubReadIdentity?
    let access: any ClubGovernanceAccess
    let coordinator: ClubGovernanceCoordinator
    var body: some View {
        List {
            ForEach([ClubGovernanceRead.roster, .occurrenceStatus, .roles, .audienceCounts, .topicStats], id: \.rawValue) { operation in
                NavigationLink { ClubGovernanceReadView(operation: operation, scope: scope, identity: identity, access: access, coordinator: coordinator) } label: { Text(LocalizedStringKey("club.gov." + operation.rawValue)) }
            }
            if scope.topicID != nil {
                NavigationLink { ClubGovernanceCommandForm(route: .init(operation: .issueGroupCode, scope: scope), identity: identity, access: access, coordinator: coordinator) } label: { Label("club.gov.action.issueGroupCode", systemImage: "qrcode") }
            }
        }.navigationTitle("club.gov.events")
    }
}

struct ClubGovernanceStoryView: View {
    let value: ClubGovernanceValue
    let scope: ClubGovernanceScope
    let identity: ClubReadIdentity?
    let access: any ClubGovernanceAccess
    let coordinator: ClubGovernanceCoordinator
    var body: some View {
        List {
            if identity == access.identity, identity?.isSignedIn == true {
            Text("club.gov.storyProjection")
            ForEach(Array((value["chaptersList"].array ?? []).enumerated()), id: \.offset) { _, chapter in
                Section {
                    ClubGovernanceFactRows(value: chapter, fields: ["title", "name", "description", "totalTime"])
                    ForEach(Array((chapter["nodes"].array ?? []).enumerated()), id: \.offset) { _, node in
                        ClubGovernanceFactRows(value: node, fields: ["title", "name", "description", "totalTime"])
                        ForEach(Array((node["cmsMemberTemplate"].object == nil ? [] : [node["cmsMemberTemplate"]]).enumerated()), id: \.offset) { _, template in
                            ClubGovernanceFactRows(value: template, fields: ["title", "validationMethodStr", "players", "duration", "difficulty"])
                            if [1, 3].contains(template["validationMethod"].int ?? -1), let nodeID = node["id"].int {
                                NavigationLink { ClubGovernanceReadView(operation: .nodeAnswer, scope: .init(clubID: scope.clubID, topicID: scope.topicID, nodeID: nodeID), identity: identity, access: access, coordinator: coordinator) } label: { Text("club.gov.nodeAnswer") }
                            }
                        }
                    }
                }
            }
            } else { Text("club.gov.signedOut") }
        }.navigationTitle("club.gov.story").accessibilityIdentifier("club.gov.story")
    }
}

struct ClubGovernanceFactRows: View {
    let value: ClubGovernanceValue
    let fields: [String]
    var showUnknown = false
    static let summaryFields = ["name", "title", "topicName", "merchantName", "displayName", "nickname", "memberName", "content", "remark", "status", "statusCode", "statusText", "state", "occurrenceAt", "startDate", "signupCount", "refundedCount", "lockReason", "recurrenceType", "defaultLeadMemberId", "defaultCapacity", "offerMinutes", "waitlistEnabled", "version", "banReason", "sourceType", "expiresAt", "reason", "decisionReason", "roleCode", "topicId", "registrationId", "memberId", "total", "monthNew", "verifiedCount", "pendingCount", "score", "clearCount", "mileage", "durationMin", "hostedCount", "pace", "completionDuration", "settledAmountText", "amountText", "amountStatus", "originalAmountText", "executedAdjustmentText", "netAmountText", "arrivedText", "paidText", "depositStatus", "amount", "direction", "retryable", "orderNo", "ticketText", "orderTimeText", "paidAmountText", "verifyTimeText", "storeName", "operatorName", "railStep", "phoneText", "coopOpen", "pinned", "memberOnly", "canManage", "nodeCount", "sessionHeadcount", "pendingVerifyCount", "verifiedByMeCount", "totalCount", "successCount", "failedCount", "question", "answerReveal", "feedbackText"]
    var body: some View {
        ForEach(fields, id: \.self) { key in
            if let text = value[key].text, !text.isEmpty {
                LabeledContent(LocalizedStringKey("club.gov.field." + key)) { Text(verbatim: text).textSelection(.enabled) }.accessibilityIdentifier("club.gov.fact." + key)
            } else if let flag = value[key].bool {
                LabeledContent(LocalizedStringKey("club.gov.field." + key)) { Text(flag ? "club.gov.yes" : "club.gov.no") }
            } else if let values = value[key].array, values.allSatisfy({ $0.text != nil }) {
                LabeledContent(LocalizedStringKey("club.gov.field." + key)) { Text(verbatim: values.compactMap(\.text).joined(separator: ", ")).textSelection(.enabled) }
            } else if showUnknown && value.object?.keys.contains(key) == true && value[key] == .null {
                LabeledContent(LocalizedStringKey("club.gov.field." + key)) { Text("club.gov.unknownValue") }
            }
        }
        if let hints = value["hints"].array { ForEach(Array(hints.enumerated()), id: \.offset) { _, hint in if let text = hint.string { Text(verbatim: text) } } }
    }
}
