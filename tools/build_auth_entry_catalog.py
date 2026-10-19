#!/usr/bin/env python3
"""Writes Resources/AuthEntry.xcstrings (w2-01 entry/auth copy). zh copy follows the mini-program verbatim where it exists."""
import json,pathlib,sys
S={
"authEntry.gate.title":("Privacy and location","隐私与定位"),
"authEntry.gate.body":("Questify uses your location only after you start roaming or confirm location during play, to check in at points and record your trail. Recording continues while the screen is locked or the app is in the background, and stops when you end roaming or pause or end play. Home reads your current location only after you grant location access, and only to recommend nearby activities. Sharing your location with nearby users is off by default and needs separate consent; when on, it shows a blurred neighbourhood location, your nickname, avatar and this roam's information, and you can turn it off at any time without affecting your own trail. Photo judging, object cards, NPC chat and the AI creation assistant send the photos or text you submit to a third-party model provider (DeepSeek); voice cloning sends your recording to Alibaba Cloud's speech model (Tongyi CosyVoice) to create a voice. Photo and voice processing each need separate consent, and results are used only for that feature.",
 "城瘾在你主动开启漫游、或在游玩中确认开启定位后使用定位，用于到点打卡和记录足迹；锁屏或切到后台后仍记录，结束漫游、暂停或结束游玩即停止。首页在你授权定位后读取当前位置，仅用于推荐附近活动。向附近用户分享位置默认关闭，需另行单独同意；开启后展示街区模糊位置、昵称、头像及本次漫游信息，可随时关闭，关闭不影响自己的轨迹。拍照判定、识物成卡、NPC 对话和 AI 创作助手会把你提交的照片或文字发送给第三方模型服务商（DeepSeek）处理，声音复刻会把录音发送给阿里云语音模型（通义 CosyVoice）生成音色；照片与声音处理均需另行单独同意，结果仅用于本次功能。"),
"authEntry.gate.openPrivacyGuide":("View the Privacy Protection Guidelines","查看《用户隐私保护指引》"),
"authEntry.gate.openAgreement":("Read the User Service Agreement","阅读《用户服务协议》"),
"authEntry.gate.checkbox":("I have read and agree to the User Service Agreement and the privacy protection guidelines","我已阅读并同意《用户服务协议》及隐私保护指引"),
"authEntry.gate.decline":("Not now","暂不同意"),
"authEntry.gate.agree":("Agree and continue","同意并继续"),
"authEntry.gate.checkRequired":("Please read and check the User Service Agreement first.","请先阅读并勾选用户服务协议"),
"authEntry.gate.localOnly":("Your choice is saved on this device. The consent record has not been sent to the server yet.","你的选择已保存在本机，同意记录尚未提交到服务端。"),
"authEntry.gate.requiredForSignIn":("Before signing in, please agree to the User Service Agreement and the privacy protection guidelines. You can keep browsing without signing in.","登录前需要先同意《用户服务协议》及隐私保护指引；不登录也可以继续浏览。"),
"authEntry.gate.review":("Review and agree","阅读并同意"),
"authEntry.privacy.title":("Privacy protection","隐私保护"),
"authEntry.privacy.guideUnavailable":("The privacy protection guidelines are not available yet.","隐私保护指引暂不可用"),
"authEntry.privacy.manage":("Roam location withdrawal and marketing messages are managed in Settings › Privacy and location after signing in.","登录后可在“设置 › 隐私与定位”中撤回漫游定位同意或管理营销消息。"),
"authEntry.privacy.consentStatus":("Agreement status on this device","本机同意状态"),
"authEntry.privacy.consentGranted":("Agreed to the current versions","已同意当前版本"),
"authEntry.privacy.consentMissing":("Not agreed","尚未同意"),
"authEntry.expiry.title":("Session expired","登录已过期"),
"authEntry.expiry.message":("Your session has expired. Sign in again, or keep browsing as a guest.","登录已过期，请重新进入。你可以重新登录，或先以游客身份继续浏览。"),
"authEntry.expiry.signIn":("Sign in again","重新登录"),
"authEntry.expiry.browse":("Browse first","先逛一逛"),
"authEntry.deregister.wechatUnavailable":("This account has no bound phone number, so deletion needs WeChat re-confirmation, which the app cannot do. Bind a phone number first, or apply in the Questify mini program.","此账号未绑定手机号，注销需要通过微信重新确认本人，App 内暂不支持微信确认。请先绑定手机号，或在城瘾小程序中申请注销。"),
"authEntry.deregister.verificationUnavailable":("Identity verification is unavailable. Please check the deletion conditions again.","身份验证暂不可用，请重新核验注销条件。"),
"authEntry.deregister.recheck":("Check again","重新核验"),
"authEntry.deregister.executeAfter":("Scheduled execution","预计执行时间"),
"authEntry.deregister.beijingTime":("Beijing time","北京时间"),
"authEntry.deregister.timePending":("Execution time to be confirmed","执行时间待确认"),
"authEntry.deregister.serverDecides":("The cooling-off deadline is Beijing time and is decided by the server.","冷静期截止按北京时间计算，以服务端为准。"),
}
out={"sourceLanguage":"en","strings":{k:{"localizations":{"en":{"stringUnit":{"state":"translated","value":en}},"zh-Hans":{"stringUnit":{"state":"translated","value":zh}}}} for k,(en,zh) in sorted(S.items())},"version":"1.0"}
open(sys.argv[1] if len(sys.argv)>1 else pathlib.Path(__file__).resolve().parents[1]/'Resources/AuthEntry.xcstrings','w').write(json.dumps(out,ensure_ascii=False,indent=2)+"\n")
