import Foundation
import CryptoKit

public enum MerchantOfferWithdrawalOriginalFailure:Error {case unavailable,invalid,stale,unknown,persistence}
/// Only original actor/MMS/offer/UUID/digests; no withdrawal reason body, prices, policy statements or credentials.
public struct MerchantOfferWithdrawalOriginalPending:Codable,Equatable {
    public let version:Int,accountID:Int,merchantID:Int,offerID:Int
    public let namespace:String,realm:String,requestID:UUID,intentSHA256:String,reasonSHA256:String,expectedSHA256:String
    public init(accountID:Int,merchantID:Int,offerID:Int,namespace:String,realm:String,requestID:UUID,intentSHA256:String,reasonSHA256:String,expectedSHA256:String)throws{
        version=1;self.accountID=accountID;self.merchantID=merchantID;self.offerID=offerID;self.namespace=namespace;self.realm=realm;self.requestID=requestID
        self.intentSHA256=intentSHA256;self.reasonSHA256=reasonSHA256;self.expectedSHA256=expectedSHA256;try validate()
    }
    public static func hash(_ s:String)->Bool{s.count==64 && s.utf8.allSatisfy{(48...57).contains($0)||(97...102).contains($0)}}
    public func validate()throws{
        guard version==1,accountID>0,merchantID>0,offerID>0,!namespace.isEmpty,namespace.utf8.count<=4096,
            let u=URL(string:realm),u.scheme=="https",u.host != nil,u.user==nil,u.password==nil,u.query==nil,u.fragment==nil,Self.hash(intentSHA256),
            Self.hash(expectedSHA256),Self.hash(reasonSHA256) else{throw MerchantOfferWithdrawalOriginalFailure.invalid}
    }
}
