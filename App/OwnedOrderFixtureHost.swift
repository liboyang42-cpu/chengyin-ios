#if DEBUG
import SwiftUI

/// Synthetic wire and memory vault; actual AppSession/Account/profile screens. No live grant.
@MainActor struct OwnedOrderFixtureHost: View {
    @StateObject private var session: AppSession
    @StateObject private var wire: OwnedOrderFixtureWire
    private let grants: OwnedOrderFixtureGrants
    private let guest: Bool
    @State private var ready = false
    init() {
        let args=ProcessInfo.processInfo.arguments
        guest=args.contains("--orders-guest")
        let wire=OwnedOrderFixtureWire(),grants=OwnedOrderFixtureGrants(enabled:!args.contains("--orders-unapproved"))
        self.grants=grants
        let deployment=try! ReviewedAppDeployment(market:.china,baseURL:"https://example.test/native",approvedBaseURLs:[.china:["https://example.test/native"]],verifiedCapabilities:[.domesticChinaPhone],bundleIdentifier:"test.orders-fixture",realm:"synthetic")
        let vault=OwnedOrderFixtureVault(),defaults=UserDefaults(suiteName:"orders-fixture-"+UUID().uuidString)!
        let root=AppCompositionRoot(deployment:.reviewed(deployment),storage:.init(defaults:defaults,tokenStore:{_ in vault}),makeTransport:{wire},ownedOrderReadApproval:{grants.approval($0)})
        _session=StateObject(wrappedValue:root.makeSession());_wire=StateObject(wrappedValue:wire)
    }
    var body: some View {
        Group {
            if ready {
                if let account=session.account {AccountView(account:account).environmentObject(session)}
                else {NavigationStack{SessionOwnedOrdersView(session:session)}}
            } else {ProgressView()}
        }
        .safeAreaInset(edge:.bottom) {
            HStack {
                Text(verbatim:String(wire.reads)).accessibilityIdentifier("orders.fixture.reads")
                Text(verbatim:String(wire.otherRequests)).accessibilityIdentifier("orders.fixture.other")
                Text(verbatim:session.isSignedIn ? "signed-in":"guest").accessibilityIdentifier("orders.fixture.identity")
                if wire.paused {Button{wire.release401()}label:{Text(verbatim:"Release")}.accessibilityIdentifier("orders.fixture.release")}
                Button{grants.retained?.revoke()}label:{Text(verbatim:"Revoke")}.accessibilityIdentifier("orders.fixture.revoke")
                Button{if let approval=grants.retained{approval.expireIfNeeded(now:approval.expiresAt)}}label:{Text(verbatim:"Expire")}.accessibilityIdentifier("orders.fixture.expire")
                Button{Task{await session.logout()}}label:{Text(verbatim:"Sign out")}.accessibilityIdentifier("orders.fixture.signOut")
            }.font(.caption)
        }
        .task {if !guest{await session.authChannels.loginWithPhone(phone:"10000000000",code:"123456")};ready=true}
    }
}
@MainActor private final class OwnedOrderFixtureGrants {
    let enabled:Bool;var retained:OwnedOrderReadApproval?
    init(enabled:Bool){self.enabled=enabled}
    func approval(_ context:RuntimeDependencyContext)->OwnedOrderReadApproval?{
        guard enabled else{return nil}
        if retained == nil || !ContentDraftContextFence.matches(retained?.context,context){retained?.revoke();retained=try? .init(context:context,expiresAt:Date().addingTimeInterval(600))}
        return retained
    }
}
@MainActor private final class OwnedOrderFixtureVault:AppTokenStorage {
    var value:String?;func read()throws->String?{value};func write(_ token:String)throws{value=token};func clear()throws{value=nil}
}
@MainActor private final class OwnedOrderFixtureWire:ObservableObject,HTTPTransport {
    @Published private(set) var reads=0
    @Published private(set) var otherRequests=0
    @Published private(set) var paused=false
    private var failed=false,didPause=false
    private var pending:CheckedContinuation<(Data,Int),Error>?
    func release401(){let saved=pending;pending=nil;paused=false;saved?.resume(returning:(Data(#"{"code":401}"#.utf8),200))}
    func send(_ request:URLRequest)async throws->(Data,Int){
        let path=request.url!.path,args=ProcessInfo.processInfo.arguments,json:String
        if path.hasSuffix("/phone"){json = #"{"code":200,"token":"synthetic-7","data":{"id":7,"role":"player"}}"#}
        else if path.hasSuffix("/userInfo"){json = #"{"code":200,"appUser":{"userId":7,"role":"player"}}"#}
        else if path.hasSuffix("/logout"){json = #"{"code":200}"#}
        else if path.hasSuffix("/registration/list") || path.hasSuffix("/registration/info"){
            reads += 1;let detail=path.hasSuffix("/info")
            if detail,args.contains("--orders-current401"){return(Data(#"{"code":401}"#.utf8),401)}
            if detail,(args.contains("--orders-fail-once") || args.contains("--orders-pause-retry")),!failed{failed=true;return(Data(),503)}
            if detail,args.contains("--orders-pause-retry"),!didPause{didPause=true;return try await withCheckedThrowingContinuation{pending=$0;paused=true}}
            let owner=args.contains("--orders-mixed-owner") ? 8:7,name=detail ? "Fresh owner detail":"My synthetic registration"
            let row="{\"id\":41,\"memberId\":\(owner),\"cmsActivity\":{\"name\":\"\(name)\"},\"registrationStatus\":2,\"paymentStatus\":0,\"payableAmount\":9007199254740993.0123456,\"pointUsed\":120,\"pointsReturned\":0,\"refundApplication\":{\"payoutStatus\":0,\"refundAmount\":3.21}}"
            if detail{json="{\"code\":200,\"data\":\(row)}"}
            else if args.contains("--orders-empty"){json = #"{"code":200,"data":{"rows":[],"total":0}}"#}
            else{json="{\"code\":200,\"data\":{\"rows\":[\(row)],\"total\":1}}"}
        }else{otherRequests += 1;throw APIError.notConfigured}
        return(Data(json.utf8),200)
    }
}
#endif
