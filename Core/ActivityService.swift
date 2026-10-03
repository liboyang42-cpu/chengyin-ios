import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Read operations only. No registration, review, cancellation, payment or retrying writes.
public struct ActivityService {
    private let configuration: APIConfiguration
    private let transport: any HTTPTransport
    public init(configuration:APIConfiguration, transport:any HTTPTransport) {
        self.configuration=configuration;self.transport=transport
    }
    private func post<Response: Decodable>(_ path:String, fields:[String:String], token:String?) async throws -> Response {
        let request=try AuthRequestBuilder.makeFormRequest(url:configuration.baseURL.appendingPathComponent(path),fields:fields,token:token)
        let (data,status)=try await transport.send(request)
        if status == 401 { throw APIError.unauthorized }
        guard (200..<300).contains(status) else { throw APIError.httpStatus(status) }
        do { return try JSONDecoder().decode(Response.self,from:data) }
        catch let error as APIError { throw error }
        catch { throw APIError.malformedResponse }
    }
    public func list(page:Int=1,pageSize:Int=10,keyword:String?=nil,token:String?=nil) async throws -> [ActivitySummary] {
        guard page > 0, (1...100).contains(pageSize) else { throw APIError.invalidRequest }
        var fields=["is_my":"0","pageNum":String(page),"pageSize":String(pageSize)]
        if let keyword, !keyword.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty { fields["keyword"]=keyword }
        let response:ActivityListResponse=try await post("api/activity/list",fields:fields,token:token)
        return response.rows
    }
    private struct DetailResponse: Decodable {
        let access: ActivityDetailAccess
        enum CodingKeys: String, CodingKey { case code,data }
        init(from decoder:Decoder) throws {
            let c=try decoder.container(keyedBy:CodingKeys.self)
            let code=try c.decode(Int.self,forKey:.code)
            if code == 401 { throw APIError.unauthorized }
            guard code == 200 else { throw APIError.businessCode(code) }
            access=try c.decode(ActivityDetailAccess.self,forKey:.data)
        }
    }
    public func detail(id:Int,token:String?=nil) async throws -> ActivityDetailAccess {
        guard id > 0 else { throw APIError.invalidRequest }
        let response:DetailResponse=try await post("api/activity/info",fields:["id":String(id)],token:token)
        if case .allowed(let detail) = response.access, detail.summary.id != id { throw APIError.malformedResponse }
        // Club gates intentionally contain no activity ID or full-detail fields.
        return response.access
    }
}
