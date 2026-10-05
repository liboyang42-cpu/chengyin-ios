#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
/// Locally authored payment-only bridge. No SDK or signed request is persisted.
@interface QFWeChatPaymentBridge : NSObject
@property(nonatomic, readonly) BOOL sdkLinked;
@property(nonatomic, readonly) BOOL installedAndSupported;
- (BOOL)registerAppID:(NSString *)appID universalLink:(NSString *)universalLink
    pasteboardReadApproved:(BOOL)approved NS_SWIFT_NAME(register(appID:universalLink:pasteboardReadApproved:));
- (void)sendPartnerID:(NSString *)partnerID prepayID:(NSString *)prepayID nonce:(NSString *)nonce
    timestamp:(uint32_t)timestamp package:(NSString *)package signature:(NSString *)signature
    launched:(void (^)(BOOL))launched response:(void (^)(int32_t))response
    NS_SWIFT_NAME(send(partnerID:prepayID:nonce:timestamp:package:signature:launched:response:));
- (BOOL)handleURL:(NSURL *)url NS_SWIFT_NAME(handle(url:));
- (BOOL)handleUserActivity:(NSUserActivity *)activity NS_SWIFT_NAME(handle(userActivity:));
- (void)detach;
@end
NS_ASSUME_NONNULL_END
