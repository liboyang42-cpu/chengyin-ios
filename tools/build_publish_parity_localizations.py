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
}
fragment = {'sourceLanguage': 'en', 'strings': {key: {'localizations': {language: {'stringUnit': {'state': 'translated', 'value': value}} for language, value in zip(['en', 'zh-Hans'], values)}} for key, values in entries.items()}, 'version': '1.0'}
(root / 'Resources/PublishParityLocalizations.fragment.json').write_text(json.dumps(fragment, ensure_ascii=False, indent=2) + '\n')
path = root / 'Resources/Localizable.xcstrings'
data = json.loads(path.read_text()); data['strings'].update(fragment['strings'])
path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n')
print(f'PASS merged {len(entries)} publish parity strings')
