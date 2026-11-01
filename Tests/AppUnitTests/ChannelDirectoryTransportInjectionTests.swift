import XCTest
@testable import Questify

@MainActor final class ChannelDirectoryTransportInjectionTests: XCTestCase {
    func testSelectedChannelAndSpaceUseTheOriginalTransport() async throws {
        let configuration = try APIConfiguration(baseURL: URL(string: "https://api.example.test/prod-api")!)
        let transport = DirectoryInjectionTransport(body: detail(version: "4", guild: "12", kind: 1))
        let request = ChannelDirectoryTransportInjection.request(
            configuration: configuration, transport: transport, token: "token",
            accountID: 7, epoch: 1, channelID: 21, spaceID: 12, kind: 1)
        XCTAssertEqual(transport.paths, [])
        let history = MessagingHistoryView(conversationID: 30, reader: DirectoryInjectionReader(), directory: request)
        XCTAssertEqual(history.conversationID, 30)
        XCTAssertEqual(history.directory?.channelID, 21)
        XCTAssertEqual(history.directory?.spaceID, 12)
        XCTAssertEqual(history.directory?.kind, 1)
        XCTAssertEqual(history.directory?.token, "token")
        XCTAssertEqual(history.directory?.accountID, 7)
        XCTAssertEqual(history.directory?.epoch, 1)
        XCTAssertNotEqual(history.conversationID, 21)
        guard let directory = history.directory else {
            XCTFail("missing directory request")
            return
        }
        let page = try await ChannelAdmissionParent.page(
            configuration: directory.configuration, transport: directory.transport, token: directory.token,
            accountID: directory.accountID, epoch: directory.epoch,
            channelID: directory.channelID, spaceID: directory.spaceID, kind: directory.kind)
        XCTAssertEqual(transport.paths, ["GET api/channels/21"])
        XCTAssertFalse(transport.paths.contains { $0.contains("api/native/spaces/admission") || $0.contains("api/im/") })
        XCTAssertEqual(page.catalog?.channelID, 21)
        XCTAssertEqual(page.catalog?.rules.publishedVersion, 4)
        XCTAssertEqual(page.catalog?.rules.expectedVersion, 4)
        XCTAssertNil(page.catalog?.rules.pendingVersion)
        XCTAssertEqual(page.spaceID, 12)
        XCTAssertEqual(page.kind, 1)
    }

    func testVersionZeroOrAnotherGuildDoesNotOpen() async throws {
        let configuration = try APIConfiguration(baseURL: URL(string: "https://api.example.test/prod-api")!)
        let unpublished = DirectoryInjectionTransport(body: detail(version: "0", guild: "12", kind: 1))
        let request = try XCTUnwrap(ChannelDirectoryTransportInjection.request(
            configuration: configuration, transport: unpublished, token: "token",
            accountID: 7, epoch: 0, channelID: 21, spaceID: 12, kind: 1))
        XCTAssertEqual(request.epoch, 0)
        var opened = false
        do {
            _ = try await ChannelAdmissionParent.page(
                configuration: request.configuration, transport: request.transport, token: request.token,
                accountID: request.accountID, epoch: request.epoch,
                channelID: request.channelID, spaceID: request.spaceID, kind: request.kind)
            opened = true
        } catch let error as ChannelDirectoryCatalogFailure {
            XCTAssertEqual(error, .unpublished)
        }
        XCTAssertFalse(opened)
        XCTAssertEqual(unpublished.paths, ["GET api/channels/21"])

        let otherGuild = DirectoryInjectionTransport(body: detail(version: "4", guild: "99", kind: 1))
        let foreign = try XCTUnwrap(ChannelDirectoryTransportInjection.request(
            configuration: configuration, transport: otherGuild, token: "token",
            accountID: 7, epoch: 1,
            selection: ChannelDirectorySelection(channelID: 21, spaceID: 12, kind: 1)))
        opened = false
        do {
            _ = try await ChannelAdmissionParent.page(
                configuration: foreign.configuration, transport: foreign.transport, token: foreign.token,
                accountID: foreign.accountID, epoch: foreign.epoch,
                channelID: foreign.channelID, spaceID: foreign.spaceID, kind: foreign.kind)
            opened = true
        } catch let error as ChannelDirectoryCatalogFailure {
            XCTAssertEqual(error, .wrongSpace)
        }
        XCTAssertFalse(opened)
        XCTAssertEqual(otherGuild.paths, ["GET api/channels/21"])
    }

    func testHomeOpenerPassesTheChannelAlreadyOnTheConversation() async throws {
        let configuration = try APIConfiguration(baseURL: URL(string: "https://api.example.test/prod-api")!)
        let transport = DirectoryInjectionTransport(body: detail(version: "4", guild: "12", kind: 1))
        let service = MessagingService(configuration: configuration, transport: transport)
        let session = try MessagingReadSession(accountID: 7, epoch: 1, token: "token")
        let reader = MessagingSessionReader(service: service, currentSession: { session })
        let conversation = try JSONDecoder().decode(MessagingConversation.self, from: Data(
            #"{"conversationId":30,"type":4,"channel_id":21,"guild_kind":1,"guild_id":"12"}"#.utf8))
        let request = messagingHistoryDirectoryRequest(reader: reader, conversation: conversation)
        XCTAssertEqual(transport.paths, [])
        XCTAssertEqual(request?.channelID, 21)
        XCTAssertEqual(request?.spaceID, 12)
        XCTAssertEqual(request?.kind, 1)
        XCTAssertEqual(request?.accountID, 7)
        XCTAssertEqual(request?.token, "token")
        XCTAssertNotEqual(request?.channelID, conversation.id)
        let history = MessagingHistoryView(conversationID: conversation.id, conversation: conversation, reader: reader, directory: request)
        XCTAssertEqual(history.directory?.channelID, 21)
        guard let directory = history.directory else {
            XCTFail("missing directory request")
            return
        }
        let page = try await ChannelAdmissionParent.page(
            configuration: directory.configuration, transport: directory.transport, token: directory.token,
            accountID: directory.accountID, epoch: directory.epoch,
            channelID: directory.channelID, spaceID: directory.spaceID, kind: directory.kind)
        XCTAssertEqual(transport.paths, ["GET api/channels/21"])
        XCTAssertFalse(transport.paths.contains { $0.contains("api/native/spaces/admission") || $0.contains("api/im/") })
        XCTAssertEqual(page.catalog?.channelID, 21)
        XCTAssertEqual(page.spaceID, 12)
    }

    func testHomeOpenerLeavesDirectoryNilWithoutGuildKindOrGuildId() throws {
        let configuration = try APIConfiguration(baseURL: URL(string: "https://api.example.test/prod-api")!)
        let transport = DirectoryInjectionTransport(body: Data())
        let service = MessagingService(configuration: configuration, transport: transport)
        let session = try MessagingReadSession(accountID: 7, epoch: 1, token: "token")
        let reader = MessagingSessionReader(service: service, currentSession: { session })
        let group = try JSONDecoder().decode(MessagingConversation.self, from: Data(
            #"{"conversationId":30,"type":4,"counterparty":{"bizKey":"club_7","id":12}}"#.utf8))
        XCTAssertEqual(group.kind, .group)
        XCTAssertNil(group.directoryContext)
        XCTAssertNil(messagingHistoryDirectoryRequest(reader: reader, conversation: group))
        let history = MessagingHistoryView(conversationID: group.id, conversation: group, reader: reader, directory: nil)
        XCTAssertNil(history.directory)
        XCTAssertEqual(history.conversationID, 30)
        let bare = MessagingSessionReader(service: nil, currentSession: { nil })
        let carried = try JSONDecoder().decode(MessagingConversation.self, from: Data(
            #"{"conversationId":30,"type":4,"channel_id":21,"guild_kind":1,"guild_id":12}"#.utf8))
        XCTAssertNil(messagingHistoryDirectoryRequest(reader: bare, conversation: carried))
        XCTAssertEqual(transport.paths, [])
    }

    func testCallerStillDoesNotOpenVersionZeroOrAnotherGuild() async throws {
        let configuration = try APIConfiguration(baseURL: URL(string: "https://api.example.test/prod-api")!)
        let unpublished = DirectoryInjectionTransport(body: detail(version: "0", guild: "12", kind: 1))
        let service = MessagingService(configuration: configuration, transport: unpublished)
        let session = try MessagingReadSession(accountID: 7, epoch: 0, token: "token")
        let reader = MessagingSessionReader(service: service, currentSession: { session })
        let conversation = try JSONDecoder().decode(MessagingConversation.self, from: Data(
            #"{"conversationId":30,"channel_id":21,"guild_kind":1,"guild_id":12}"#.utf8))
        let request = try XCTUnwrap(messagingHistoryDirectoryRequest(reader: reader, conversation: conversation))
        var opened = false
        do {
            _ = try await ChannelAdmissionParent.page(
                configuration: request.configuration, transport: request.transport, token: request.token,
                accountID: request.accountID, epoch: request.epoch,
                channelID: request.channelID, spaceID: request.spaceID, kind: request.kind)
            opened = true
        } catch let error as ChannelDirectoryCatalogFailure {
            XCTAssertEqual(error, .unpublished)
        }
        XCTAssertFalse(opened)
        let other = DirectoryInjectionTransport(body: detail(version: "4", guild: "99", kind: 1))
        let foreignReader = MessagingSessionReader(service: MessagingService(configuration: configuration, transport: other), currentSession: { session })
        let foreign = try XCTUnwrap(messagingHistoryDirectoryRequest(reader: foreignReader, conversation: conversation))
        opened = false
        do {
            _ = try await ChannelAdmissionParent.page(
                configuration: foreign.configuration, transport: foreign.transport, token: foreign.token,
                accountID: foreign.accountID, epoch: foreign.epoch,
                channelID: foreign.channelID, spaceID: foreign.spaceID, kind: foreign.kind)
            opened = true
        } catch let error as ChannelDirectoryCatalogFailure {
            XCTAssertEqual(error, .wrongSpace)
        }
        XCTAssertFalse(opened)
        XCTAssertEqual(unpublished.paths, ["GET api/channels/21"])
        XCTAssertEqual(other.paths, ["GET api/channels/21"])
        XCTAssertFalse((unpublished.paths + other.paths).contains { $0.contains("api/native/spaces/admission") })
    }

    func testClosedSelectionDoesNotInventATokenOrSend() throws {
        let configuration = try APIConfiguration(baseURL: URL(string: "https://api.example.test/prod-api")!)
        let transport = DirectoryInjectionTransport(body: Data())
        XCTAssertNil(ChannelDirectoryTransportInjection.request(
            configuration: configuration, transport: transport, token: "token",
            accountID: 7, epoch: 1, channelID: 0, spaceID: 12, kind: 1))
        XCTAssertNil(ChannelDirectoryTransportInjection.request(
            configuration: configuration, transport: transport, token: "token",
            accountID: 7, epoch: 1, channelID: 21, spaceID: 0, kind: 1))
        XCTAssertNil(ChannelDirectoryTransportInjection.request(
            configuration: configuration, transport: transport, token: "token",
            accountID: 7, epoch: 1, channelID: 21, spaceID: 12, kind: 2))
        XCTAssertNil(ChannelDirectoryTransportInjection.request(
            configuration: configuration, transport: transport, token: "token",
            accountID: 0, epoch: 1, channelID: 21, spaceID: 12, kind: 1))
        XCTAssertNil(ChannelDirectoryTransportInjection.request(
            configuration: configuration, transport: transport, token: " ",
            accountID: 7, epoch: 1, channelID: 21, spaceID: 12, kind: 1))
        XCTAssertEqual(transport.paths, [])
    }

    private func detail(version: String, guild: String, kind: Int) -> Data {
        let json = """
        {"code":200,"data":{"id":"21","guild_kind":\(kind),"guild_id":"\(guild)","version":"\(version)","message_container":{"id":"30","conversation_type":"5"}}}
        """
        return Data(json.utf8)
    }
}

private final class DirectoryInjectionTransport: HTTPTransport {
    let body: Data
    private(set) var paths: [String] = []
    init(body: Data) { self.body = body }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        let path = request.url?.path ?? ""
        let trimmed = path.hasPrefix("/prod-api/") ? String(path.dropFirst("/prod-api/".count)) : path
        paths.append("\(request.httpMethod ?? "") \(trimmed)")
        return (body, 200)
    }
}

@MainActor private final class DirectoryInjectionReader: MessagingReading {
    var isConfigured: Bool { false }
    var identity: MessagingReadIdentity? { nil }
    func messagingConversations() async throws -> [MessagingConversation] { [] }
    func messagingMessages(conversationID: Int, cursor: Int) async throws -> MessagingPage {
        try JSONDecoder().decode(MessagingPage.self, from: Data(#"{"list":[],"hasMore":false}"#.utf8))
    }
}
