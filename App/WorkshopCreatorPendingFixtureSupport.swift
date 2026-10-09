#if DEBUG
import SwiftUI

/// Synthetic-only transport. Every path stays in memory; it is never returned by normal composition.
@MainActor final class WorkshopCreatorPendingFixtureWire: HTTPTransport {
    var requests: [URLRequest] = [], authorBodies: [Data] = [], declarationBodies: [Data] = []
    var commands: [String: WorkshopCreatorPendingCommand] = [:], records: [String: [String: Any]] = [:], details: [String: [String: Any]] = [:]
    var declarationRecords: [String: [String: Any]] = [:]
    var loseAuthorResponse = false, rejectSource = false, delay = false
    var suspended: CheckedContinuation<(Data, Int), Never>?
    var role = "player"
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        if delay { delay = false; return await withCheckedContinuation { suspended = $0 } }
        let path = request.url?.path ?? "", end = request.url?.lastPathComponent ?? ""
        if path.contains("/creator/") {
            if end == "preview" {
                guard !rejectSource else { return (Data(), 409) }
                return (try WorkshopCreatorPendingFixtureData.envelope(WorkshopCreatorPendingFixtureData.preview()), 200)
            }
            if end == "author" {
                let body = request.httpBody!, command = try WorkshopCreatorPendingWire.decode(WorkshopCreatorPendingCommand.self, data: body)
                authorBodies.append(body)
                if let old = commands[command.requestId] { guard old == command else { return (Data(), 409) } }
                else {
                    guard !rejectSource else { return (Data(), 409) }
                    let created = Date(), metadata = try WorkshopCreatorPendingFixtureData.metadata(command, createdAt: created)
                    commands[command.requestId] = command; records[command.requestId] = metadata
                    details[command.requestId] = try WorkshopCreatorPendingFixtureData.detail(command, createdAt: created)
                }
                if loseAuthorResponse { throw WorkshopCreatorConsentIssue.unknown }
                return (try WorkshopCreatorPendingFixtureData.envelope(records[command.requestId]!), 200)
            }
            if end == "list" {
                guard !rejectSource else { return (Data(), 409) }
                let items = records.values.sorted { ($0["targetId"] as! String) < ($1["targetId"] as! String) }
                return (try WorkshopCreatorPendingFixtureData.envelope(WorkshopCreatorPendingFixtureData.page(items: items)), 200)
            }
            if end == "detail" {
                guard !rejectSource else { return (Data(), 409) }
                let query = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
                guard let detail = details.values.first(where: { ($0["targetId"] as? String) == (query["targetId"] as? String) && ($0["revision"] as? String) == (query["expectedRevision"] as? String) }) else { return (Data(), 409) }
                return (try WorkshopCreatorPendingFixtureData.envelope(detail), 200)
            }
            if end == "declare" {
                declarationBodies.append(request.httpBody!)
                let c = try WorkshopCreatorWire.decode(WorkshopCreatorDeclarationCommand.self, data: request.httpBody!)
                guard !rejectSource else { return (Data(), 409) }
                let receipt: [String: Any] = ["schema": "w18-creator-public-use-declaration-receipt-v1", "state": "CREATOR_DECLARED_PENDING_PACKAGE_REVIEW",
                    "sourceTemplateId": c.sourceTemplateId, "templateHash": c.expectedTemplateHash, "offerVersion": c.offerVersion, "termsVersion": c.termsVersion,
                    "declaredAt": WorkshopCreatorPendingFixtureData.timestamp(Date()), "disclosureVersion": WorkshopCreatorDisclosure.version, "disclosureHash": WorkshopCreatorDisclosure.hash,
                    "packageReviewed": false, "listed": false, "licenseIssued": false,
                    "consentReference": ["scope": "BUYER_OWN_PUBLISHED_THEMES", "consentId": "60000000-0000-4000-8000-000000000001", "creatorMemberId": 7,
                        "moduleId": c.moduleId, "versionId": c.versionId, "contentHash": c.expectedPackageContentHash, "termsDocumentHash": c.termsDocumentHash, "recordHash": String(repeating: "b", count: 64)]]
                declarationRecords[c.requestId] = receipt
                return (try WorkshopCreatorPendingFixtureData.envelope(receipt), 200)
            }
            if end == "status" {
                let q = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
                if let id = q["requestId"] as? String, let receipt = declarationRecords[id] { return (try WorkshopCreatorPendingFixtureData.envelope(receipt), 200) }
                return (try WorkshopCreatorPendingFixtureData.envelope(["schema": "w18-creator-public-use-declaration-status-v1", "state": "NOT_FOUND", "requestId": q["requestId"]!]), 200)
            }
            throw APIError.invalidRequest
        }
        switch end {
        case "phone": return (Data("{\"code\":200,\"token\":\"synthetic-7\",\"data\":{\"id\":7,\"role\":\"\(role)\"}}".utf8), 200)
        case "userInfo": return (Data("{\"code\":200,\"appUser\":{\"userId\":7,\"role\":\"\(role)\"}}".utf8), 200)
        default: throw APIError.invalidRequest
        }
    }
    func resume401() { let old = suspended; suspended = nil; old?.resume(returning: (Data(), 401)) }
}
@MainActor final class WorkshopCreatorPendingFixtureHarness: ObservableObject {
    @MainActor private final class Vault: AppTokenStorage {
        var token: String?
        func read() throws -> String? { token }; func write(_ value: String) throws { token = value }; func clear() throws { token = nil }
    }
    let wire = WorkshopCreatorPendingFixtureWire(), base = URL(string: "https://example.com/native")!, suite = "creator-pending-" + UUID().uuidString
    private let vault = Vault()
    /// One recovery lifetime per harness, retained through Back and fresh controller selection.
    let recoveryStorage = TemplateAuthoringMemoryStorage()
    let deployment: ReviewedAppDeployment
    var session: AppSession!
    var read: WorkshopCreatorConsentReadApproval?, write: WorkshopCreatorConsentWriteApproval?
    var author: WorkshopCreatorPendingAuthorApproval?, list: WorkshopCreatorPendingListApproval?, detail: WorkshopCreatorPendingDetailApproval?
    @Published var ready = false
    init() {
        deployment = try! .init(market: .china, baseURL: base.absoluteString, approvedBaseURLs: [.china: [base.absoluteString]], verifiedCapabilities: [.domesticChinaPhone], bundleIdentifier: "test.creator.pending", realm: "synthetic-" + UUID().uuidString.lowercased())
        var storage = AppScopedStorageFactory(defaults: UserDefaults(suiteName: suite)!, tokenStore: { [vault] _ in vault })
        storage.syntheticWorkshopCreatorPendingRecoveryStorage = recoveryStorage
        session = AppCompositionRoot(deployment: .reviewed(deployment), storage: storage, makeTransport: { [wire] in wire },
            workshopCreatorPendingAuthorApproval: { [weak self] _ in self?.author }, workshopCreatorPendingListApproval: { [weak self] _ in self?.list }, workshopCreatorPendingDetailApproval: { [weak self] _ in self?.detail },
            workshopCreatorConsentReadApproval: { [weak self] _ in self?.read }, workshopCreatorConsentWriteApproval: { [weak self] _ in self?.write }).makeSession()
    }
    func context() throws -> RuntimeDependencyContext { .init(market: .china, baseURL: base, role: wire.role, session: try .init(accountID: 7, epoch: session.sessionRevision, namespace: deployment.storageScope.service, token: "synthetic-7", role: wire.role)) }
    func login() async { await session.authChannels.loginWithPhone(phone: "10000000000", code: "123456") }
    func approve(authoring: Bool = true, listing: Bool = true, detailing: Bool = true, declaring: Bool = true) throws {
        let c = try context()
        let r = try WorkshopCreatorConsentReadApproval(context: c, expiresAt: .distantFuture), w = declaring ? try WorkshopCreatorConsentWriteApproval(context: c, expiresAt: .distantFuture) : nil
        let a = authoring ? try WorkshopCreatorPendingAuthorApproval(context: c, expiresAt: .distantFuture) : nil
        let l = listing ? try WorkshopCreatorPendingListApproval(context: c, expiresAt: .distantFuture) : nil
        let d = detailing ? try WorkshopCreatorPendingDetailApproval(context: c, expiresAt: .distantFuture) : nil
        session.withWorkshopCreatorConsentConfigurationChange { read = r; write = w; author = a; list = l; detail = d }
    }
    func fill(_ controller: WorkshopCreatorPendingController) {
        controller.form.termsDocument = "Synthetic complete creator terms.\nExact second line."
        controller.form.commercialUse = "ALLOWED"; controller.form.adaptation = "LOCAL_ADAPTATION"; controller.form.translation = "PROHIBITED"
        controller.form.allowedRegions = "CN"; controller.form.buyerKinds = "INDIVIDUAL"; controller.form.themeLimit = "1"; controller.form.merchantLimit = "0"; controller.form.runLimit = "-1"
        controller.form.priceMinor = "1499"; controller.form.currency = "CNY"; controller.form.expiresAt = WorkshopCreatorPendingFixtureData.timestamp(Date().addingTimeInterval(86_400))
    }
    func clean() {
        recoveryStorage.values.removeAll()
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
    }
}
@MainActor struct WorkshopCreatorPendingFixtureView: View {
    let selection: WorkshopCreatorConsentSelection
    @ObservedObject var harness: WorkshopCreatorPendingFixtureHarness
    var body: some View {
        Group {
            if harness.ready, let controller = harness.session.makeWorkshopCreatorPendingController(sourceTemplateId: Int64(selection.source.rawValue)) {
                WorkshopCreatorPendingView(controller: controller, appearance: selection.pendingAppearance)
            } else { ProgressView() }
        }.task {
            guard !harness.ready else { return }; await harness.login(); try? harness.approve()
            if ProcessInfo.processInfo.arguments.contains("--creator-pending-filled"), let controller = harness.session.makeWorkshopCreatorPendingController(sourceTemplateId: Int64(selection.source.rawValue)) { harness.fill(controller) }
            harness.wire.loseAuthorResponse = ProcessInfo.processInfo.arguments.contains("--creator-pending-unknown")
            harness.ready = true
        }
    }
}
#endif
