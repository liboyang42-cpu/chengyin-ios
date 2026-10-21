#import "QFWeChatPaymentBridge.h"
#if TARGET_OS_SIMULATOR
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static void (*qf_orig_layoutSubviews)(id, SEL);

static BOOL qf_hasVisibleControl(UIView *view) {
    if (view.hidden || view.alpha < 0.01) { return NO; }
    if ([view isKindOfClass:[UIControl class]] && view.bounds.size.width > 1.0 && view.bounds.size.height > 1.0) {
        return YES;
    }
    for (UIView *sub in view.subviews) {
        if (qf_hasVisibleControl(sub)) { return YES; }
    }
    return NO;
}

static void qf_hideIfOversizedEmptyToolbar(UIView *view) {
    if (!view || view.bounds.size.height <= 200.0) { return; }
    NSString *cls = NSStringFromClass([view class]);
    BOOL isToolbar = [view isKindOfClass:[UIToolbar class]]
        || ([cls rangeOfString:@"Toolbar" options:NSCaseInsensitiveSearch].location != NSNotFound)
        || [[view accessibilityIdentifier] isEqualToString:@"Toolbar"];
    if (isToolbar && !qf_hasVisibleControl(view)) {
        view.accessibilityElementsHidden = YES;
        view.isAccessibilityElement = NO;
        view.accessibilityContainerType = UIAccessibilityContainerTypeNone;
        view.hidden = YES;
        view.alpha = 0.0;
    }
}

static void qf_swizzled_layoutSubviews(UIView *self, SEL _cmd) {
    qf_orig_layoutSubviews(self, _cmd);
    qf_hideIfOversizedEmptyToolbar(self);
    for (UIView *sub in self.subviews) {
        qf_hideIfOversizedEmptyToolbar(sub);
    }
}

__attribute__((constructor))
static void qf_installSimulatorToolbarAccessibilityFix(void) {
    Method m1 = class_getInstanceMethod([UIView class], @selector(layoutSubviews));
    if (m1) {
        qf_orig_layoutSubviews = (void (*)(id, SEL))method_getImplementation(m1);
        method_setImplementation(m1, (IMP)qf_swizzled_layoutSubviews);
    }
}
#endif

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
