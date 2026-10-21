#import "QFWeChatPaymentBridge.h"

// Payment has an independent compile-time opt-in. BUILD_WITHOUT_PAY SDKs remain off.
#if defined(QUESTIFY_WECHAT_PAYMENT_SDK_APPROVED) && QUESTIFY_WECHAT_PAYMENT_SDK_APPROVED == 1 && __has_include(<WechatOpenSDK/WXApi.h>)
#import <WechatOpenSDK/WXApi.h>
#if !defined(BUILD_WITHOUT_PAY)
#define QF_HAS_WECHAT_PAYMENT 1
#else
#define QF_HAS_WECHAT_PAYMENT 0
#endif
#else
#define QF_HAS_WECHAT_PAYMENT 0
#endif

#if QF_HAS_WECHAT_PAYMENT
@interface QFWeChatPaymentBridge () <WXApiDelegate>
#else
@interface QFWeChatPaymentBridge ()
#endif
@property(nonatomic, copy, nullable) void (^paymentResponse)(int32_t);
@property(nonatomic, copy, nullable) void (^launchResult)(BOOL);
@property(nonatomic, strong, nullable) NSUUID *generation;
@property(nonatomic, copy, nullable) NSURL *routedURL;
@property(nonatomic) BOOL pasteboardReadApproved;
@end

@implementation QFWeChatPaymentBridge
- (BOOL)sdkLinked { return QF_HAS_WECHAT_PAYMENT; }
- (BOOL)registerAppID:(NSString *)appID universalLink:(NSString *)universalLink pasteboardReadApproved:(BOOL)approved {
    NSAssert([NSThread isMainThread], @"Payment bridge must run on main thread");
    self.pasteboardReadApproved = approved;
#if QF_HAS_WECHAT_PAYMENT
    return [WXApi registerApp:appID universalLink:universalLink];
#else
    return NO;
#endif
}
- (BOOL)installedAndSupported {
    NSAssert([NSThread isMainThread], @"Payment bridge must run on main thread");
#if QF_HAS_WECHAT_PAYMENT
    return [WXApi isWXAppInstalled] && [WXApi isWXAppSupportApi];
#else
    return NO;
#endif
}
- (void)sendPartnerID:(NSString *)partnerID prepayID:(NSString *)prepayID nonce:(NSString *)nonce
    timestamp:(uint32_t)timestamp package:(NSString *)package signature:(NSString *)signature
    launched:(void (^)(BOOL))launched response:(void (^)(int32_t))response {
    NSAssert([NSThread isMainThread], @"Payment bridge must run on main thread");
    if (self.generation) { launched(NO); return; }
#if QF_HAS_WECHAT_PAYMENT
    NSUUID *generation = [NSUUID UUID]; self.generation = generation;
    self.paymentResponse = response; self.launchResult = launched;
    PayReq *request = [[PayReq alloc] init];
    request.partnerId = partnerID; request.prepayId = prepayID; request.nonceStr = nonce;
    request.timeStamp = timestamp; request.package = package; request.sign = signature;
    __weak QFWeChatPaymentBridge *weakSelf = self;
    [WXApi sendReq:request completion:^(BOOL success) {
        dispatch_async(dispatch_get_main_queue(), ^{
            QFWeChatPaymentBridge *strongSelf = weakSelf;
            if (!strongSelf || ![strongSelf.generation isEqual:generation]) { return; }
            void (^completion)(BOOL) = strongSelf.launchResult; strongSelf.launchResult = nil;
            if (completion) { completion(success); }
        });
    }];
#else
    launched(NO);
#endif
}
- (BOOL)handleURL:(NSURL *)url {
    NSAssert([NSThread isMainThread], @"Payment bridge must run on main thread");
#if QF_HAS_WECHAT_PAYMENT
    if (!self.generation) { return NO; }
    self.routedURL = url; return [WXApi handleOpenURL:url delegate:self];
#else
    return NO;
#endif
}
- (BOOL)handleUserActivity:(NSUserActivity *)activity {
    NSAssert([NSThread isMainThread], @"Payment bridge must run on main thread");
#if QF_HAS_WECHAT_PAYMENT
    if (!self.generation) { return NO; }
    self.routedURL = activity.webpageURL; return [WXApi handleOpenUniversalLink:activity delegate:self];
#else
    return NO;
#endif
}
- (void)detach {
    NSAssert([NSThread isMainThread], @"Payment bridge must run on main thread");
    self.generation = nil; self.paymentResponse = nil; self.launchResult = nil; self.routedURL = nil;
}
#if QF_HAS_WECHAT_PAYMENT
- (void)onResp:(BaseResp *)response {
    if (![NSThread isMainThread] || ![response isKindOfClass:[PayResp class]]) { return; }
    // PayResp has no order identifier or OAuth state. Never manufacture either.
    int32_t errorCode = response.errCode; NSUUID *generation = self.generation;
    __weak QFWeChatPaymentBridge *weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        QFWeChatPaymentBridge *strongSelf = weakSelf;
        if (!generation || ![strongSelf.generation isEqual:generation]) { return; }
        if (strongSelf.paymentResponse) { strongSelf.paymentResponse(errorCode); }
    });
}
- (void)onNeedGrantReadPasteBoardPermissionWithURL:(NSURL *)openURL
    completion:(WXGrantReadPasteBoardPermissionCompletion)completion {
    if (![NSThread isMainThread] || !self.generation || !self.pasteboardReadApproved || ![self.routedURL isEqual:openURL]) { return; }
    completion();
}
#endif
@end
