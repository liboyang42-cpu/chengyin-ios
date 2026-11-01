#!/usr/bin/env python3
"""Merge only the w2-13 publish / my-project parity catalog, preserving unrelated entries.

zh-Hans copy follows mini-program subpackageA/pages/myproject and pages/publish/*.
"""
import json
from pathlib import Path
root = Path(__file__).resolve().parents[1]
entries = {
'myProject.tab.topic': ('Topics', '主题'),
'myProject.tab.activity': ('Activities', '活动'),
'myProject.tab.template': ('Templates', '模板'),
'myProject.role.host': ('Host', '主办'),
'myProject.role.coHost': ('Co-host', '承办'),
'myProject.empty.topic': ('No topics yet', '还没有主题'),
'myProject.empty.topicDetail': ('Use Publish to create your first city route', '用发布按钮创建你的第一条城市路线'),
'myProject.empty.activity': ('No activities yet', '还没有活动'),
'myProject.empty.activityPublish': ('Publish your first single-session activity here', '在这里发布你的第一场单场活动'),
'myProject.empty.template': ('No node plays yet', '还没有节点玩法'),
'myProject.empty.templateDetail': ('Node interactions you build while publishing routes can be reused and managed here', '发布路线时可以沉淀自己的节点互动，之后在这里复用和管理'),
'myProject.cta.topic': ('Publish', '去发布'),
'myProject.cta.activity': ('Publish a single-session activity', '发布单场活动'),
'myProject.pendingVerify %lld': ('%lld to redeem', '待核销 %lld'),
'myProject.longPressHint': ('Long-press a card to list, unlist or delete', '长按卡片可上下架 / 删除'),
'myProject.op.viewApplies': ('Received applications', '收到的申请'),
'myProject.op.edit': ('Edit', '编辑'),
'myProject.op.toggleOn': ('List', '上架'),
'myProject.op.toggleOff': ('Unlist', '下架'),
'myProject.op.cancel': ('Cancel and refund', '取消并退款'),
'myProject.op.delete': ('Delete', '删除'),
'myProject.op.toggle': ('List / unlist', '上下架'),
'myProject.op.unavailable': ('These actions are not enabled in the app yet', '这些操作暂未在 App 中开放'),
'myProject.template.scope': ('Node plays come from your template shelf, not from project records', '节点玩法来自你的模板列表，不与主题 / 活动混排'),
'myProject.template.open': ('Open my node plays', '查看我的节点玩法'),
'myProject.template.unavailable': ('Node plays are not available from this entry', '此入口暂不提供节点玩法列表'),
'publishParity.crop.useOriginal': ('Use original', '使用原图'),
'publishParity.activity.title': ('Activity title', '活动标题'),
'publishParity.activity.description': ('Activity description', '活动说明'),
'publishParity.activity.type': ('Choose activity type', '请选择活动类型'),
'publishParity.ticket.name': ('Ticket name', '票单名称'),
'publishParity.ticket.price': ('Face price (enter 0 for free)', '票面价格（免费填 0）'),
'publishParity.ticket.stock': ('Ticket stock', '票单库存'),
'publishParity.crop.title': ('Crop', '裁剪'),
'publishParity.crop.cancel': ('Cancel', '取消'),
'publishParity.crop.confirm': ('Select', '选取'),
'publishParity.crop.ratio': ('Ratio', '比例'),
'publishParity.crop.failed': ('No image to crop. Go back and choose an image again.', '没有可裁剪的图片，请返回上一页重新选择图片后再裁剪。'),
'publishParity.crop.progress %lld %lld': ('Crop %lld/%lld', '裁剪 %lld/%lld'),
'publishParity.intro.lead': ('Turn a stretch you have played', '把你玩过的一段路'),
'publishParity.intro.tail': ('into a play others can follow', '做成别人也能走的玩法'),
}
# zh-Hans values of existing keys aligned to pages/publish/template-intro and templateadd.
# English values are untouched so existing English UI assertions keep their meaning.
overrides = {
'Resources/Localizable.xcstrings': {
    'creatorContent.truncated': '已达到200条加载上限，请筛选查找',
    'templateAuthor.begin': '开始创建',
    'templateAuthor.nameStep': '给节点玩法起一个名字',
    'templateAuthor.validation.title': '请输入模板名称',
},
'Resources/CreatorIntroExamples.xcstrings': {
    'creatorIntro.skip': '跳过',
    'creatorIntro.failed': '精选示例暂未加载',
    'creatorIntro.empty': '暂时没有精选示例，你仍可直接创建自己的节点玩法。',
},
}
mirrors = {
    'docs/template-authoring-localizations.json': 'Resources/Localizable.xcstrings',
    'docs/creator-content-localizations.json': 'Resources/Localizable.xcstrings',
}
fragment = {'sourceLanguage': 'en', 'strings': {key: {'localizations': {language: {'stringUnit': {'state': 'translated', 'value': value}} for language, value in zip(['en', 'zh-Hans'], values)}} for key, values in entries.items()}, 'version': '1.0'}
(root / 'Resources/PublishParityLocalizations.fragment.json').write_text(json.dumps(fragment, ensure_ascii=False, indent=2) + '\n')
path = root / 'Resources/Localizable.xcstrings'
data = json.loads(path.read_text()); data['strings'].update(fragment['strings'])
for key, value in overrides['Resources/Localizable.xcstrings'].items():
    data['strings'][key]['localizations']['zh-Hans']['stringUnit']['value'] = value
path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n')
intro = root / 'Resources/CreatorIntroExamples.xcstrings'
table = json.loads(intro.read_text())
for key, value in overrides['Resources/CreatorIntroExamples.xcstrings'].items():
    table['strings'][key]['localizations']['zh-Hans']['stringUnit']['value'] = value
intro.write_text(json.dumps(table, ensure_ascii=False, indent=2) + '\n')
for mirror, source in mirrors.items():
    doc = json.loads((root / mirror).read_text())
    for key, value in overrides[source].items():
        if key in doc: doc[key]['zh-Hans'] = value
    (root / mirror).write_text(json.dumps(doc, ensure_ascii=False, indent=2) + '\n')
print(f'PASS merged {len(entries)} publish parity strings')
