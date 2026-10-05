#import "QFWeChatSDKBridge.h"

// The opt-in flag AND linked official header are required. No SDK is vendored here.
#if defined(QUESTIFY_WECHAT_SDK_APPROVED) && QUESTIFY_WECHAT_SDK_APPROVED == 1 && __has_include(<WechatOpenSDK/WXApi.h>)
#import <WechatOpenSDK/WXApi.h>
#define QF_HAS_WECHAT_SDK 1
#else
#define QF_HAS_WECHAT_SDK 0
#endif

#if QF_HAS_WECHAT_SDK
@interface QFWeChatSDKBridge () <WXApiDelegate>
#else
@interface QFWeChatSDKBridge ()
#endif
@property(nonatomic, copy, nullable) void (^authResponse)(NSString * _Nullable, NSString * _Nullable, int32_t);
@property(nonatomic, copy, nullable) void (^launchResult)(BOOL);
@property(nonatomic, strong, nullable) NSUUID *generation;
@property(nonatomic) BOOL pasteboardReadApproved;
@property(nonatomic, copy, nullable) NSURL *routedURL;
@end

@implementation QFWeChatSDKBridge
- (BOOL)sdkLinked {
    return QF_HAS_WECHAT_SDK;
}
- (BOOL)registerAppID:(NSString *)appID universalLink:(NSString *)universalLink pasteboardReadApproved:(BOOL)approved {
    NSAssert([NSThread isMainThread], @"WeChat bridge must run on main thread");
    self.pasteboardReadApproved = approved;
#if QF_HAS_WECHAT_SDK
    return [WXApi registerApp:appID universalLink:universalLink];
#else
    return NO;
#endif
}
- (BOOL)installedAndSupported {
    NSAssert([NSThread isMainThread], @"WeChat bridge must run on main thread");
#if QF_HAS_WECHAT_SDK
    return [WXApi isWXAppInstalled] && [WXApi isWXAppSupportApi];
#else
    return NO;
#endif
}
- (void)sendState:(NSString *)state scope:(NSString *)scope launched:(void (^)(BOOL))launched
    response:(void (^)(NSString * _Nullable, NSString * _Nullable, int32_t))response {
    NSAssert([NSThread isMainThread], @"WeChat bridge must run on main thread");
    [self detach];
#if QF_HAS_WECHAT_SDK
    NSUUID *generation = [NSUUID UUID];
    self.generation = generation; self.authResponse = response; self.launchResult = launched;
    SendAuthReq *request = [[SendAuthReq alloc] init];
    request.scope = scope; request.state = state;
    request.nonautomatic = YES; // Explicit user authorization on every attempt.
    __weak QFWeChatSDKBridge *weakSelf = self;
    [WXApi sendReq:request completion:^(BOOL success) {
        dispatch_async(dispatch_get_main_queue(), ^{
            QFWeChatSDKBridge *strongSelf = weakSelf;
            if (!strongSelf || ![strongSelf.generation isEqual:generation]) { return; }
            void (^completion)(BOOL) = strongSelf.launchResult;
            strongSelf.launchResult = nil;
            if (completion) { completion(success); }
        });
    }];
#else
    launched(NO);
#endif
}
- (BOOL)handleURL:(NSURL *)url {
    NSAssert([NSThread isMainThread], @"WeChat bridge must run on main thread");
#if QF_HAS_WECHAT_SDK
    if (!self.generation) { return NO; }
    self.routedURL = url;
    return [WXApi handleOpenURL:url delegate:self];
#else
    return NO;
#endif
}
- (BOOL)handleUserActivity:(NSUserActivity *)activity {
    NSAssert([NSThread isMainThread], @"WeChat bridge must run on main thread");
#if QF_HAS_WECHAT_SDK
    if (!self.generation) { return NO; }
    self.routedURL = activity.webpageURL;
    return [WXApi handleOpenUniversalLink:activity delegate:self];
#else
    return NO;
#endif
}
- (void)detach {
    NSAssert([NSThread isMainThread], @"WeChat bridge must run on main thread");
    self.generation = nil; self.authResponse = nil; self.launchResult = nil; self.routedURL = nil;
}
#if QF_HAS_WECHAT_SDK
- (void)onResp:(BaseResp *)response {
    if (![response isKindOfClass:[SendAuthResp class]]) { return; }
    SendAuthResp *auth = (SendAuthResp *)response;
    NSString *state = [auth.state copy];
    NSString *code = [auth.code copy];
    int32_t errorCode = auth.errCode;
    // UIKit-origin URL processing is on main. A defensive async hop only carries
    // copied primitives, never vendor objects or a fabricated correlation state.
    __weak QFWeChatSDKBridge *weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        QFWeChatSDKBridge *strongSelf = weakSelf;
        if (strongSelf.authResponse) { strongSelf.authResponse(state, code, errorCode); }
    });
}
- (void)onNeedGrantReadPasteBoardPermissionWithURL:(NSURL *)openURL
    completion:(WXGrantReadPasteBoardPermissionCompletion)completion {
    // The default is refusal. Off-main requests are refused rather than allowing a
    // delayed permission callback to read clipboard data for a newer login attempt.
    if (![NSThread isMainThread] || !self.generation || !self.pasteboardReadApproved ||
        ![self.routedURL isEqual:openURL]) { return; }
    completion();
    // The vendor documents that not invoking completion denies clipboard reads.
    // Denied requests remain bounded by the existing coordinator timeout.
}
#endif
@end
