import XCTest
@testable import Questify

@MainActor final class ChannelAdmissionGovernanceEntryTests: XCTestCase {
    func testEntryUsesTheSameCurrentCatalogAndDoesNotSend() throws {
        let configuration = try APIConfiguration(baseURL: URL(string: "https://api.example.test/prod-api")!)
        let transport = EntryIdleTransport()
        let current = try catalog(published: 3, pending: 4, expected: 3)
        XCTAssertThrowsError(try ChannelAdmissionGovernanceEntry.make(
            configuration: configuration, transport: transport, token: "token", accountID: 7, epoch: 1,
            catalog: current, kind: 2, spaceID: 12)) {
            XCTAssertEqual($0 as? ChannelAuthorizationError, .invalidCatalog)
        }
        let stale = try catalog(published: 3, pending: 4, expected: 2)
        XCTAssertThrowsError(try ChannelAdmissionGovernanceEntry.make(
            configuration: configuration, transport: transport, token: "token", accountID: 7, epoch: 1,
            catalog: stale, kind: 1, spaceID: 12)) {
            XCTAssertEqual($0 as? ChannelAuthorizationError, .rulesCASConflict)
        }
        let page = try ChannelAdmissionGovernanceEntry.make(
            configuration: configuration, transport: transport, token: "token", accountID: 7, epoch: 1,
            catalog: current, kind: 1, spaceID: 12)
        XCTAssertEqual(page.catalog, current)
        XCTAssertEqual(page.kind, 1)
        XCTAssertEqual(page.spaceID, 12)
        XCTAssertFalse(transport.sent)
        let route = ChannelAdmissionRoute(
            configuration: configuration, transport: transport, token: "token", accountID: 7, epoch: 1,
            catalog: current, kind: 1, spaceID: 12)
        let routed = try route.page()
        XCTAssertEqual(routed.catalog, current)
        XCTAssertFalse(transport.sent)
    }

    func testParentReadsTheDirectoryOnceAndOpensThatVersion() async throws {
        let configuration = try APIConfiguration(baseURL: URL(string: "https://api.example.test/prod-api")!)
        let transport = ParentDirectoryTransport(body: directoryDetail(version: "4", guild: "12"))
        let page = try await ChannelAdmissionParent.page(
            configuration: configuration, transport: transport, token: "token",
            accountID: 7, epoch: 1, channelID: 21, spaceID: 12, kind: 1)
        XCTAssertEqual(transport.requests, [("GET", "api/channels/21")])
        XCTAssertEqual(page.catalog?.channelID, 21)
        XCTAssertEqual(page.catalog?.rules.publishedVersion, 4)
        XCTAssertEqual(page.catalog?.rules.expectedVersion, 4)
        XCTAssertNil(page.catalog?.rules.pendingVersion)
        XCTAssertEqual(page.kind, 1)
        XCTAssertEqual(page.spaceID, 12)

        let unpublished = ParentDirectoryTransport(body: directoryDetail(version: "0", guild: "12"))
        var opened = false
        do {
            _ = try await ChannelAdmissionParent.page(
                configuration: configuration, transport: unpublished, token: "token",
                accountID: 7, epoch: 1, channelID: 21, spaceID: 12, kind: 1)
            opened = true
        } catch let error as ChannelDirectoryCatalogFailure {
            XCTAssertEqual(error, .unpublished)
        } catch {
            XCTFail("\(error)")
        }
        XCTAssertFalse(opened)
        XCTAssertEqual(unpublished.requests, [("GET", "api/channels/21")])

        let otherGuild = ParentDirectoryTransport(body: directoryDetail(version: "4", guild: "99"))
        opened = false
        do {
            _ = try await ChannelAdmissionParent.page(
                configuration: configuration, transport: otherGuild, token: "token",
                accountID: 7, epoch: 1, channelID: 21, spaceID: 12, kind: 1)
            opened = true
        } catch let error as ChannelDirectoryCatalogFailure {
            XCTAssertEqual(error, .wrongSpace)
        } catch {
            XCTFail("\(error)")
        }
        XCTAssertFalse(opened)
        XCTAssertEqual(otherGuild.requests, [("GET", "api/channels/21")])
    }

    private func directoryDetail(version: String, guild: String) -> Data {
        let json = """
        {"code":200,"data":{"id":"21","guild_kind":1,"guild_id":"\(guild)","version":"\(version)","message_container":{"id":"30","conversation_type":"5"}}}
        """
        return Data(json.utf8)
    }

    private func catalog(published: Int, pending: Int?, expected: Int) throws -> ChannelCatalogEntry {
        try ChannelCatalogEntry(
            channelID: 21, conversationID: 12, kind: .group,
            rules: try ChannelRulesCAS(publishedVersion: published, pendingVersion: pending, expectedVersion: expected))
    }
}

private final class ParentDirectoryTransport: HTTPTransport {
    let body: Data
    private(set) var requests: [(String, String)] = []
    init(body: Data) { self.body = body }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        let path = request.url?.path ?? ""
        let trimmed = path.hasPrefix("/prod-api/") ? String(path.dropFirst("/prod-api/".count)) : path
        requests.append((request.httpMethod ?? "", trimmed))
        return (body, 200)
    }
}

private final class EntryIdleTransport: HTTPTransport {
    private(set) var sent = false
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        sent = true
        XCTFail("opening the admission page must not send")
        return (Data(), 500)
    }
}
