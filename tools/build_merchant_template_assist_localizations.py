#!/usr/bin/env python3
"""Merge only merchant template-assist keys into the existing bilingual catalog."""
import json
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
ROWS = {
    'title': ('AI template assist', 'AI 帮写模板'),
    'generatedNote': ('AI-generated suggestions', 'AI 生成建议'),
    'boundary': ('Review suggestions before applying them to this local draft. Applying does not save or publish.', '请先检查建议，再填入当前本地草稿。填入不会保存或发布。'),
    'request': ('Describe the template', '描述模板玩法'),
    'shopName': ('Shop or template name', '店名或模板名称'),
    'prompt': ('Describe the activity or riddle you want', '描述想生成的玩法或谜题'),
    'disabled': ('AI generation is not enabled for this account and deployment. You can keep editing the template manually.', '当前账号和环境尚未启用 AI 生成，你仍可手动编辑模板。'),
    'working': ('Preparing suggestions…', '正在准备建议…'),
    'generate': ('Generate suggestions', '生成建议'),
    'retry': ('Try again', '重试'),
    'review': ('Review suggested fields', '检查建议内容'),
    'unsupported': ('Returned fields this editor cannot apply', '当前编辑器无法填入的返回字段'),
    'unsupportedHint': ('These fields are shown in full for review but are not saved by this form. A story may supply only the first 30 characters as a description when no description was returned.', '这些字段完整展示供检查，但不会由此表单保存。未返回描述时，仅将故事的前 30 个字符用作描述。'),
    'applyHint': ('Only untouched, empty fields will be filled. Your existing values and any changes made since generation began are preserved. Save separately after reviewing the template.', '只填入未编辑过的空字段，保留已有内容及开始生成后所作的修改。请检查模板后另行保存。'),
    'noChanges': ('There are no applicable empty fields. Your draft will stay as it is.', '没有可以填入的空字段，草稿将保持原样。'),
    'apply': ('Apply to this draft', '填入当前草稿'),
    'permissionNextStep': ('Check your merchant access and active identity in Settings, or sign in again. Repeating this request will not change your permissions.', '请在设置中检查商家权限和当前身份，或重新登录。反复重试不会改变权限。'),
    'error.shopNameRequired': ('Enter a shop or template name first.', '请先填写店名或模板名称。'),
    'error.promptRequired': ('Describe the activity you want before generating.', '请先描述想生成的玩法。'),
    'error.permission': ('Your sign-in or current identity does not permit AI creation.', '当前登录状态或身份不允许 AI 创作。'),
    'error.provider': ('The service is temporarily unavailable. You can retry or continue editing manually.', '服务暂时不可用，可重试或继续手动编辑。'),
    'error.malformed': ('The service returned an unreadable result. Nothing was applied.', '服务返回的内容无法解析，尚未填入任何内容。'),
    'error.empty': ('No usable content was generated. Try another description or continue manually.', '没有生成可用内容，请换种描述重试或继续手动编辑。'),
    'error.disabled': ('AI generation is not enabled. No request was sent.', '尚未启用 AI 生成，未发送请求。'),
    'error.unknown': ('The request outcome is unknown. Do not repeat it; it may have used provider quota. Your draft was not changed.', '请求结果未知，请勿重复提交，可能已消耗服务额度。草稿未被修改。'),
    'error.cancelled': ('Stopped waiting. Your draft was not changed; a request already sent may still complete.', '已停止等待。草稿未被修改，已发送的请求仍可能完成。'),
    'error.stale': ('The account, access, or source draft changed. Close this sheet and reopen it from the current draft.', '账号、权限或源草稿已变化，请关闭后从当前草稿重新打开。'),
    'field.title': ('Title', '标题'), 'field.description': ('Description', '描述'),
    'field.questionName': ('Question', '题目'), 'field.questionAnswer': ('Secret answer', '口令答案'),
    'field.optionA': ('Option A', '选项 A'), 'field.optionB': ('Option B', '选项 B'),
    'field.optionC': ('Option C', '选项 C'), 'field.optionD': ('Option D', '选项 D'),
    'field.correctAnswer': ('Correct answer', '正确选项'), 'field.feedbackText': ('Completion feedback', '完成反馈'),
    'field.validationMethod': ('Validation method', '验证方式'),
}
def main():
    fragment = {}
    for key, (en, zh) in ROWS.items():
        fragment['merchant.assist.' + key] = {'extractionState': 'manual', 'localizations': {locale: {'stringUnit': {'state': 'translated', 'value': value}} for locale, value in [('en', en), ('zh-Hans', zh)]}}
    path = ROOT / 'Resources/Localizable.xcstrings'
    catalog = json.loads(path.read_text()); catalog['strings'].update(fragment)
    path.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + '\n')
    (ROOT / 'Resources/MerchantTemplateAssistLocalizations.fragment.json').write_text(json.dumps(fragment, ensure_ascii=False, indent=2) + '\n')
    print(f'Merged {len(fragment)} bilingual template-assist keys')
if __name__ == '__main__': main()
