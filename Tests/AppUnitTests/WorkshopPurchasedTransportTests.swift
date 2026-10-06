import XCTest
@testable import Questify

@MainActor final class WorkshopPurchasedTransportTests: XCTestCase {
    private let base=URL(string:"https://example.com/native")!
    private func deployment()throws->ReviewedAppDeployment{try .init(market:.china,baseURL:base.absoluteString,approvedBaseURLs:[.china:[base.absoluteString]],verifiedCapabilities:[.domesticChinaPhone],bundleIdentifier:"test.workshop.purchased",realm:"synthetic")}
    private func context(_ d:ReviewedAppDeployment,role:String="player")throws->RuntimeDependencyContext{.init(market:.china,baseURL:base,role:role,session:try .init(accountID:7,epoch:1,namespace:d.storageScope.service,token:"synthetic"))}
    private func request(path:String="list",body:String="")->URLRequest{
        var r=URLRequest(url:base.appendingPathComponent("api/workshop/purchased/"+path));r.httpMethod="POST";r.httpBody=Data(body.utf8);r.setValue("synthetic",forHTTPHeaderField:"Authorization");r.setValue(String(body.utf8.count),forHTTPHeaderField:"Content-Length");r.setValue("application/x-www-form-urlencoded; charset=utf-8",forHTTPHeaderField:"Content-Type");r.cachePolicy = .reloadIgnoringLocalCacheData;r.setValue("no-store",forHTTPHeaderField:"Cache-Control");r.setValue("no-cache",forHTTPHeaderField:"Pragma");return r
    }
    private func bind(_ t:CompositionHTTPTransport,role:String="player"){t.current={.init(epoch:1,accountID:7,role:role,token:"synthetic")}}
    private final class Wire:HTTPTransport{var calls=0;func send(_ request:URLRequest)async throws->(Data,Int){calls += 1;return(Data(),200)}}
    private func rejects(_ t:CompositionHTTPTransport,_ r:URLRequest)async{do{_=try await t.send(r);XCTFail("forbidden paid route")}catch{}}
    func testFreeOwnedApprovalCannotReadPurchasedLibrary()async throws{
        let d=try deployment(),wire=Wire(),free=try WorkshopOwnedReadApproval(context:context(d),expiresAt:.distantFuture)
        let t=CompositionHTTPTransport(deployment:d,underlying:wire,workshopOwnedReadApproval:{_ in free});bind(t)
        await rejects(t,request());await rejects(t,request(path:"detail",body:"license_id=w18-paid-11"));XCTAssertEqual(wire.calls,0)
    }
    func testExactPaidListDetailAndCursorOnlyWithCanonicalFullContext()async throws{
        let d=try deployment()
        for role in ["player","merchant","club"]{
            let wire=Wire(),expected=try context(d,role:role),grant=try WorkshopPurchasedReadApproval(context:expected,expiresAt:.distantFuture);var seen=0
            let t=CompositionHTTPTransport(deployment:d,underlying:wire,workshopPurchasedReadApproval:{actual in seen += 1;XCTAssertEqual(actual,expected);return actual==expected ? grant:nil});bind(t,role:role)
            _=try await t.send(request());_=try await t.send(request(body:"before_order_line_id=50"));_=try await t.send(request(path:"detail",body:"license_id=w18-paid-11"));XCTAssertEqual(wire.calls,3);XCTAssertGreaterThanOrEqual(seen,6)
        }
    }
    func testReadApprovalCannotExpandIntoCheckoutInstallFreeOrProtectedContent()async throws{
        let d=try deployment(),wire=Wire(),grant=try WorkshopPurchasedReadApproval(context:context(d),expiresAt:.distantFuture)
        let t=CompositionHTTPTransport(deployment:d,underlying:wire,workshopPurchasedReadApproval:{_ in grant});bind(t)
        for path in ["buy","quote","pay","install","refund","installed-text","claim"]{await rejects(t,request(path:path))}
        var free=request();free.url=base.appendingPathComponent("api/workshop/owned/list");await rejects(t,free);XCTAssertEqual(wire.calls,0)
    }
    func testForgedOwnersAmbiguousFormsAndIncorrectHeadersCannotDispatch()async throws{
        let d=try deployment(),wire=Wire(),grant=try WorkshopPurchasedReadApproval(context:context(d),expiresAt:.distantFuture),t=CompositionHTTPTransport(deployment:d,underlying:wire,workshopPurchasedReadApproval:{_ in grant});bind(t)
        var invalid=[request(body:"owner=7"),request(body:"before_order_line_id=0"),request(body:"before_order_line_id=01"),request(body:"before_order_line_id=9223372036854775808"),request(path:"detail",body:"license_id=w18-paid-11&owner=7"),request(path:"detail",body:"license_id=%77%31%38-paid-11"),request(path:"detail",body:"license_id=w18-paid-11&license_id=w18-paid-11")]
        var r=request();r.setValue(nil,forHTTPHeaderField:"Content-Length");invalid.append(r)
        r=request();r.httpBodyStream=InputStream(data:Data());invalid.append(r)
        r=request();r.url=URL(string:r.url!.absoluteString+"?owner=7");invalid.append(r)
        r=request();r.httpMethod="GET";invalid.append(r)
        r=request();r.setValue("chunked",forHTTPHeaderField:"Transfer-Encoding");invalid.append(r)
        for request in invalid { XCTAssertNil(WorkshopPurchasedReadRoute(request:request,baseURL:base));await rejects(t,request) };XCTAssertEqual(wire.calls,0)
    }
    func testCopiedTransportKeepsIndependentPaidSelector()async throws{
        let d=try deployment(),first=Wire(),second=Wire(),grant=try WorkshopPurchasedReadApproval(context:context(d),expiresAt:.distantFuture)
        let transport=CompositionHTTPTransport(deployment:d,underlying:first,workshopPurchasedReadApproval:{_ in grant});bind(transport)
        _=try await transport.replacingUnderlying(second).send(request());XCTAssertEqual(first.calls,0);XCTAssertEqual(second.calls,1)
    }
}
