#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
/// Locally authored bridge. Vendor selectors are isolated in the conditional .m file.
/// Construction has no provider side effects. All methods except construction require main thread.
@interface QFWeChatSDKBridge : NSObject
@property(nonatomic, readonly) BOOL sdkLinked;
@property(nonatomic, readonly) BOOL installedAndSupported;
- (BOOL)registerAppID:(NSString *)appID universalLink:(NSString *)universalLink
    pasteboardReadApproved:(BOOL)pasteboardReadApproved
    NS_SWIFT_NAME(register(appID:universalLink:pasteboardReadApproved:));
- (void)sendState:(NSString *)state scope:(NSString *)scope
    launched:(void (^)(BOOL))launched
    response:(void (^)(NSString * _Nullable, NSString * _Nullable, int32_t))response
    NS_SWIFT_NAME(send(state:scope:launched:response:));
- (BOOL)handleURL:(NSURL *)url NS_SWIFT_NAME(handle(url:));
- (BOOL)handleUserActivity:(NSUserActivity *)activity NS_SWIFT_NAME(handle(userActivity:));
- (void)detach;
@end
NS_ASSUME_NONNULL_END
