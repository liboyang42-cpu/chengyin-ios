#!/usr/bin/env python3
"""Add the reviewed en/zh-Hans keys for roam passport private tools (时光胶囊 / 探索目标 / 导出探索记录).

Chinese copy follows the mini-program subpackageTools pages. Idempotent: existing keys must match exactly.
"""
import argparse
import json
from pathlib import Path

KEYS = {
    'roam.private.new': ('NEW', 'NEW'),
    'roam.private.loading': ('Reading…', '正在读取…'),
    'roam.private.readFailed': ("Couldn't read this yet. Try again.", '暂时没读到，请重试'),
    'roam.private.changedContext': ('Your sign-in changed. Reopen this page.', '登录状态已变化，请重新打开此页'),
    'roam.private.writesDisabled': ('Saving changes is not open yet. You can browse only.', '写入尚未开放，目前只能浏览'),
    'roam.private.outcomeUnknown': ('The result is not confirmed. Check the original request before retrying it.', '结果待确认：请先核对原请求，再决定是否用原内容重试'),
    'roam.private.rejected': ('Not applied.', '操作未应用'),
    'roam.private.invalidDraft': ('Check the content and dates, then try again.', '请检查内容和日期后再试'),
    'roam.private.pendingFirst': ('Resolve the earlier request first; other content cannot be submitted.', '请先恢复原操作，不能提交其他内容'),
    'roam.private.dismiss': ('Got it', '知道了'),
    'roam.private.notNow': ('Not now', '先不要'),
    'roam.private.ok': ('OK', '好'),
    # 时光胶囊
    'roam.capsule.title': ('Time capsule', '时光胶囊'),
    'roam.capsule.tile': ('A note for your future self', '写给以后的自己'),
    'roam.capsule.pending': ('The last seal has no receipt yet. Check it before deciding to retry.', '上次封存还没收到回执，先核对再决定是否重试。'),
    'roam.capsule.verify': ('Check last seal', '核对上次封存'),
    'roam.capsule.retryOriginal': ('Retry with original content', '用原内容重试'),
    'roam.capsule.openedMeta %@ %@': ('Opens %1$@ · sealed %2$@', '%1$@ 开启 · %2$@ 封存'),
    'roam.capsule.photo': ('Attached photo', '附带的照片'),
    'roam.capsule.keep': ('Put it away', '收好了'),
    'roam.capsule.delete': ('Delete', '删除'),
    'roam.capsule.deleted': ('Deleted', '已删除'),
    'roam.capsule.backToList': ('Back to list', '返回列表'),
    'roam.capsule.bodyLabel': ('Capsule text', '胶囊正文'),
    'roam.capsule.placeholder': ('To myself on that day…', '写给那一天的自己…'),
    'roam.capsule.count %lld': ('%lld / 4000', '%lld / 4000'),
    'roam.capsule.photoUnavailable': ('Attaching a photo is not available in the app yet', 'App 内暂不支持附照片'),
    'roam.capsule.unlockLabel': ('Opening date', '开启日期'),
    'roam.capsule.unlock.month': ('In 1 month', '1 个月后'),
    'roam.capsule.unlock.halfYear': ('In 6 months', '半年后'),
    'roam.capsule.unlock.year': ('In 1 year', '1 年后'),
    'roam.capsule.unlockCustom': ('Custom', '自定义'),
    'roam.capsule.seal': ('Seal capsule', '封存胶囊'),
    'roam.capsule.later': ('Not now', '先不写'),
    'roam.capsule.write': ('Write a capsule', '写一枚胶囊'),
    'roam.capsule.lockedTip': ('Not time to open it yet', '尚未到开启时间'),
    'roam.capsule.confirmTitle': ('Seal this capsule?', '封存这枚胶囊？'),
    'roam.capsule.confirmMessage %@': ('Its text stays hidden until %@. Only you can see it.', '%@ 开启前不会显示正文，仅本人可见。'),
    'roam.capsule.deleteTitle': ('Delete this capsule?', '删除这枚胶囊？'),
    'roam.capsule.deleteMessage': ('This cannot be undone.', '删除后无法恢复。'),
    'roam.capsule.openReady %@': ('Ready to open · sealed %@', '已到开启日 · %@ 封存'),
    'roam.capsule.openIt': ('Open it', '打开看看'),
    'roam.capsule.writtenOn %@': ('Written %@', '%@ 写下'),
    'roam.capsule.daysLeft %lld': ('%lld days', '%lld 天'),
    'roam.capsule.unlocksOn %@': ('Opens %@', '%@ 开启'),
    'roam.capsule.empty': ('No capsules yet', '还没有胶囊'),
    'roam.capsule.mine': ('My capsules', '我的胶囊'),
    'roam.capsule.count.items %lld': ('%lld', '%lld 枚'),
    # 探索目标
    'roam.goals.title': ('Exploration goals', '探索目标'),
    'roam.goals.tile': ('Set yourself a small goal', '给自己定个小目标'),
    'roam.goals.pending': ('The last goal has no confirmed result yet. Check it or retry the original request.', '上一个目标结果待确认，请核对或以原操作重试。'),
    'roam.goals.verify': ('Check original request', '核对原请求'),
    'roam.goals.retryOriginal': ('Retry original request', '以原操作重试'),
    'roam.goals.metric.routes': ('Distinct routes', '不同路线数'),
    'roam.goals.metric.days': ('Exploration days', '探索自然日数'),
    'roam.goals.metric': ('Goal measure', '目标口径'),
    'roam.goals.state.active': ('In progress', '进行中'),
    'roam.goals.state.scheduled': ('Not started', '尚未开始'),
    'roam.goals.state.achieved': ('Achieved', '已达成'),
    'roam.goals.state.ended': ('Ended', '已结束'),
    'roam.goals.state.cancelled': ('Cancelled', '已取消'),
    'roam.goals.unit.routes %lld': ('%lld distinct routes', '%lld 条不同路线'),
    'roam.goals.unit.days %lld': ('%lld exploration days', '%lld 个探索日'),
    'roam.goals.range %@ %@': ('%1$@ to %2$@ (exclusive)', '%1$@ 至 %2$@（不含）'),
    'roam.goals.collapse': ('Collapse', '收起'),
    'roam.goals.cancelThis': ('Cancel this goal', '取消此目标'),
    'roam.goals.cancelTitle': ('Cancel this goal?', '取消这个目标？'),
    'roam.goals.cancelMessage': ('Progress stops counting and the goal cannot be restored. This cannot be undone.', '取消后不再统计进度，也不能恢复。此操作不可撤销。'),
    'roam.goals.cancelGoal': ('Cancel goal', '取消目标'),
    'roam.goals.keep': ('Keep', '保留'),
    'roam.goals.period': ('Period', '时间段'),
    'roam.goals.period.week': ('This week', '本周'),
    'roam.goals.period.month': ('This month', '本月'),
    'roam.goals.period.thirty': ('30 days', '30 天'),
    'roam.goals.start': ('Start', '开始'),
    'roam.goals.end': ('End (exclusive)', '结束（不含）'),
    'roam.goals.create': ('Create goal', '创建目标'),
    'roam.goals.later': ('Not now', '先不定'),
    'roam.goals.confirmTitle': ('Create this goal?', '创建这个目标？'),
    'roam.goals.new': ('Set a new goal', '定一个新目标'),
    'roam.goals.mine': ('My goals', '我的目标'),
    'roam.goals.count %lld': ('%lld', '%lld 个'),
    'roam.goals.empty': ('No exploration goals yet', '还没有探索目标'),
    # 导出探索记录
    'roam.export.title': ('Export exploration records', '导出探索记录'),
    'roam.export.explain': ('Prepare a range, read every part, then save or share one complete file. Records are your own completed roams.', '准备范围、逐块读取，全部读完才可保存或分享。记录来自你本人的完成记录。'),
    'roam.export.range': ('Export range', '导出范围'),
    'roam.export.range.30': ('Last 30 days', '近 30 天'),
    'roam.export.range.year': ('This year', '今年'),
    'roam.export.range.365': ('Last year', '近一年'),
    'roam.export.start': ('Start', '开始'),
    'roam.export.end': ('End (exclusive)', '结束（不含）'),
    'roam.export.rangeLimit': ('A range covers 1 to 366 days. Shorten the dates.', '导出范围须为 1–366 天，请缩短日期范围'),
    'roam.export.prepare': ('Prepare export', '准备导出'),
    'roam.export.readCount %lld %lld': ('Read %1$lld / %2$lld', '已读取 %1$lld / %2$lld 条'),
    'roam.export.noRecords': ('No records in this range', '这个范围内没有记录'),
    'roam.export.rows %lld': ('%lld records', '%lld 条'),
    'roam.export.share': ('Share', '分享'),
    'roam.export.save': ('Save to Files', '保存到手机'),
    'roam.export.reading': ('Reading the next part…', '正在读取下一块…'),
    'roam.export.readNext': ('Read next part', '读取下一块'),
    'roam.export.startReading': ('Start reading', '开始读取'),
    'roam.export.restart': ('Choose another range', '重新选择范围'),
    'roam.export.sourceChanged': ('The source changed, so the parts read are incomplete. Prepare again.', '来源已变化，已有部分不完整，请重新准备'),
    'roam.export.expired': ('The file content has expired. Prepare again.', '文件内容已过期，请重新准备'),
    'roam.export.saved': ('File saved', '文件保存已完成'),
    'roam.export.cancelled': ('Cancelled; the file was not saved', '已取消，未完成文件操作'),
    'roam.export.saveFailed': ('The file could not be saved', '文件保存未完成'),
}

parser = argparse.ArgumentParser()
parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[1])
parser.add_argument('--check', action='store_true', help='Fail if any key is missing or differs; write nothing')
args = parser.parse_args()
path = args.root / 'Resources/Localizable.xcstrings'
catalog = json.loads(path.read_text())
strings = catalog['strings']
added = 0
for key, (en, zh) in KEYS.items():
    entry = {'extractionState': 'manual', 'localizations': {
        'en': {'stringUnit': {'state': 'translated', 'value': en}},
        'zh-Hans': {'stringUnit': {'state': 'translated', 'value': zh}}}}
    if key in strings:
        assert strings[key] == entry, 'Existing key differs: ' + key
        continue
    assert not args.check, 'Missing key: ' + key
    strings[key] = entry
    added += 1
if added:
    path.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + '\n')
print(f'PASS: {len(KEYS)} roam private tool keys ({added} added)')
