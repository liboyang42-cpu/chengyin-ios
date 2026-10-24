import XCTest
@testable import QuestifyCore

final class ChannelDirectoryCatalogProducerTests: XCTestCase {
    func testDirectoryDetailBecomesTheCurrentCatalog() async throws {
        let configuration = try APIConfiguration(baseURL: URL(string: "https://api.example.test/prod-api")!)
        let transport = DirectoryTransport(body: detail(version: "4", guild: "12", channel: "21", conversation: "30"))
        let catalog = try await ChannelDirectoryCatalogProducer.catalog(
            configuration: configuration, transport: transport, token: "token",
            channelID: 21, spaceID: 12, kind: 1)
        XCTAssertEqual(catalog.channelID, 21)
        XCTAssertEqual(catalog.conversationID, 30)
        XCTAssertEqual(catalog.rules.publishedVersion, 4)
        XCTAssertEqual(catalog.rules.expectedVersion, 4)
        XCTAssertNil(catalog.rules.pendingVersion)
        XCTAssertEqual(transport.paths, ["api/channels/21"])
        let wrong = DirectoryTransport(body: detail(version: "4", guild: "99", channel: "21", conversation: "30"))
        do {
            _ = try await ChannelDirectoryCatalogProducer.catalog(
                configuration: configuration, transport: wrong, token: "token",
                channelID: 21, spaceID: 12, kind: 1)
            XCTFail("another space")
        } catch let error as ChannelDirectoryCatalogFailure {
            XCTAssertEqual(error, .wrongSpace)
        }
        let unpublished = DirectoryTransport(body: detail(version: "0", guild: "12", channel: "21", conversation: "30"))
        do {
            _ = try await ChannelDirectoryCatalogProducer.catalog(
                configuration: configuration, transport: unpublished, token: "token",
                channelID: 21, spaceID: 12, kind: 1)
            XCTFail("unpublished")
        } catch let error as ChannelDirectoryCatalogFailure {
            XCTAssertEqual(error, .unpublished)
        }
    }

    private func detail(version: String, guild: String, channel: String, conversation: String) -> Data {
        let json = """
        {"code":200,"data":{"id":"\(channel)","guild_kind":1,"guild_id":"\(guild)","version":"\(version)","message_container":{"id":"\(conversation)","conversation_type":"5"}}}
        """
        return Data(json.utf8)
    }
}

private final class DirectoryTransport: HTTPTransport {
    let body: Data
    private(set) var paths: [String] = []
    init(body: Data) { self.body = body }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        paths.append(request.url?.path.replacingOccurrences(of: "/prod-api/", with: "") ?? "")
        return (body, 200)
    }
}
