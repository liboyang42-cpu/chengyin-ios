#!/usr/bin/env python3
"""Merge only the media-destination catalog, preserving unrelated entries."""
import json
from pathlib import Path
root = Path(__file__).resolve().parents[1]
entries = {
'media.destination.poiGallery': ('Place photos', '据点相册'),
'media.destination.squareImages': ('Photos', '图片浏览'),
'media.destination.openImage': ('Open photo', '查看图片'),
'media.destination.image': ('Photo', '图片'),
'media.destination.empty': ('No photos', '暂无图片'),
'media.destination.previous': ('Previous', '上一张'),
'media.destination.next': ('Next', '下一张'),
'media.destination.unavailable': ('Photo loading is not enabled', '图片加载尚未启用'),
'media.destination.failed': ('Photo could not load', '图片加载失败'),
'media.destination.zoomHint': ('Pinch or double-tap to zoom; drag to pan', '双指或双击缩放，拖动查看细节'),
'media.poster.title': ('Scan the place poster', '扫描据点海报'),
'media.poster.purpose': ('Scan with the camera and use one fresh foreground location to verify this place. Scanning alone does not complete check-in.', '使用相机扫描，并获取一次当前前台位置核验据点。扫描本身不代表打卡完成。'),
'media.poster.disabled': ('Camera, location and check-in are not enabled for this deployment', '此环境尚未启用相机、定位与打卡提交'),
'media.poster.consent': ('Allow this scan and one location check', '同意本次扫描与一次定位核验'),
'media.poster.scan': ('Open scanner', '打开扫描相机'),
'media.poster.confirm': ('Confirm place verification', '确认提交据点核验'),
'media.poster.ready': ('Ready to scan', '准备扫描'),
'media.poster.unsupported': ('This place has no available poster-scan method', '此据点未配置可用的海报扫描核验方式'),
'media.poster.phase.ready': ('Ready to scan', '准备扫描'),
'media.poster.phase.locating': ('Checking your current location…', '正在获取本次位置…'),
'media.poster.phase.review': ('QR captured. Confirm to submit the code and this location.', '已识别二维码。确认后将二维码与本次位置提交核验。'),
'media.poster.phase.preflighting': ('Checking the current place status…', '正在核对据点当前状态…'),
'media.poster.phase.submitting': ('Awaiting the verification result…', '正在等待核验结果…'),
'media.poster.phase.unknown': ('The result is unknown and this attempt is locked. Do not scan again. Return to place details to check its status.', '结果待确认，本次操作已锁定。请勿重新扫码，请返回据点详情核对状态。'),
'media.poster.phase.completed': ('The server confirmed this check-in', '服务端已确认本次打卡'),
'media.poster.phase.needsRedemption': ('Merchant redemption is still required', '仍需商家核销，尚未完成领取'),
'media.poster.phase.unavailable': ('Verification is unavailable', '核验暂不可用'),
'media.poster.phase.failed': ('Verification was not completed. Check permissions and scan again.', '核验未完成，请检查权限后重新扫描。'),
'media.stamp.title': ('Stamp camera', '集邮相机'),
'media.stamp.purpose': ('Take a new photo and review its 4:5 center crop before uploading. Saving to the album is a separate confirmed step. No location is requested.', '拍摄新照片后，先预览 4:5 中心裁切，再确认上传。上传成功后另行确认入册。本流程不请求定位。'),
'media.stamp.disabled': ('Camera and photo upload are not enabled for this deployment', '此环境尚未启用相机和照片上传'),
'media.stamp.cameraIssue': ('Camera access is unavailable. Check camera permission in Settings, then return and try again.', '相机暂不可用，请在系统设置中检查相机权限后返回重试。'),
'media.stamp.consent': ('Use the camera for this stamp', '为本枚邮票使用相机'),
'media.stamp.capturedPreview': ('Your captured photo, cropped to 4:5', '实际拍摄并裁切为 4:5 的照片'),
'media.stamp.retake': ('Retake photo', '重新拍摄'),
'media.stamp.upload': ('Upload this photo', '上传这张照片'),
'media.stamp.create': ('Confirm saving to album', '确认入册'),
'media.stamp.capture': ('Take photo', '拍摄照片'),
'media.stamp.exactRetry': ('Confirmation reuses the same uploaded photo and request key. Do not upload or retake while the result is unresolved.', '再次确认仅使用原照片与原幂等键核对。结果确认前请勿重新上传或重拍。'),
'media.stamp.phase.ready': ('Ready to take a photo', '准备拍摄'),
'media.stamp.phase.review': ('Review the actual cropped photo before uploading', '请先确认实际裁切后的照片'),
'media.stamp.phase.uploading': ('Uploading the photo…', '正在上传照片…'),
'media.stamp.phase.awaitingCreate': ('Photo uploaded. It has not been saved to the album yet.', '照片已上传，尚未入册。'),
'media.stamp.phase.creating': ('Waiting for album confirmation…', '正在等待入册确认…'),
'media.stamp.phase.unknown': ('The previous result needs confirmation. A new capture is locked.', '上次结果待确认，暂不能重新拍摄。'),
'media.stamp.phase.created': ('The server confirmed the stamp was added. Moderation may still be pending.', '服务端已确认入册，图片审核可能仍在进行中。'),
'media.stamp.phase.unavailable': ('Safe recovery storage is unavailable. No upload or save can start.', '安全恢复存储不可用，暂不能上传或入册。'),
'media.stamp.phase.failed': ('The photo was not uploaded. Review it and try again.', '照片尚未上传，请确认后重试。'),
'withdrawal.support.title': ('Balance and withdrawal help', '余额与提现帮助'),
'withdrawal.support.balance': ('Current balance', '当前余额'),
'withdrawal.support.notReceived': ('Amounts not yet available', '未到账金额'),
'withdrawal.support.explanation': ('Review your balance and unsettled amounts. Support can help check the records. This screen does not confirm a transfer or an arrival date.', '请先核对余额与未到账金额。客服可协助核对记录；本页展示不代表已转账，也不承诺到账时间。'),
'withdrawal.support.contact': ('Contact platform support', '联系平台客服'),
'withdrawal.support.weChat': ('Support WeChat ID', '客服微信号'),
'withdrawal.support.manualContact': ('Select the ID to copy it and contact support yourself. No message or financial details are sent automatically.', '可选择并复制微信号后自行联系。不会自动发送消息或财务信息。'),
'withdrawal.support.unconfigured': ('No reviewed support contact is configured for this deployment', '此环境尚未配置经核验的客服联系方式'),
}
fragment = {'sourceLanguage': 'en', 'strings': {key: {'localizations': {language: {'stringUnit': {'state': 'translated', 'value': value}} for language, value in zip(['en', 'zh-Hans'], values)}} for key, values in entries.items()}, 'version': '1.0'}
(root / 'Resources/MediaDestinationsLocalizations.fragment.json').write_text(json.dumps(fragment, ensure_ascii=False, indent=2) + '\n')
path = root / 'Resources/Localizable.xcstrings'
data = json.loads(path.read_text()); data['strings'].update(fragment['strings'])
path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n')
print(f'PASS merged {len(entries)} media destination strings')
