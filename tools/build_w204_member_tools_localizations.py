#!/usr/bin/env python3
"""Writes Resources/W204MemberToolsLocalizations.fragment.json (complaint, invite, template copy).

Chinese values follow the mini-program pages subpackageMember/complaint, myinvite and
mytemplate. Merge into the catalog with tools/merge_localization_fragments.py.
"""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'Resources/W204MemberToolsLocalizations.fragment.json'

STRINGS = {
    # Complaint page (subpackageMember/complaint)
    'profile.complaint.pageTitle': ('Complaints & feedback', '投诉与建议'),
    'profile.complaint.pageSubtitle': ('Only for activities you registered and paid for. The platform will step in.', '仅限已报名并支付的活动，平台会介入处理'),
    'profile.complaint.sourceEmpty': ('No activities to report', '暂无可投诉的活动'),
    'profile.complaint.sourceEmptyHint': ('Complaints must concern an activity you registered and paid for. After you do, you can start one here.', '投诉需针对你已报名并支付的活动；报名并支付后可在这里发起。'),
    'profile.complaintProgress.title': ('My case progress', '我的处理进展'),
    'profile.complaintProgress.refresh': ('Refresh progress', '刷新进展'),
    'profile.complaintProgress.unavailable': ('Progress unavailable', '处理进展不可查看'),
    'profile.complaintProgress.signIn': ('Sign in to see your case progress.', '请登录后查看处理进展'),
    'profile.complaintProgress.denied': ('This account cannot view case progress.', '当前账号无法查看处理进展'),
    'profile.complaintProgress.statusUnknown': ('Status to be confirmed', '状态待确认'),
    'profile.complaintProgress.handleNote %@': ('Handling note: %@', '处理说明：%@'),
}


def entry(en, zh):
    unit = lambda value: {'stringUnit': {'state': 'translated', 'value': value}}
    return {'localizations': {'en': unit(en), 'zh-Hans': unit(zh)}}


if __name__ == '__main__':
    OUT.write_text(json.dumps({'sourceLanguage': 'en', 'strings': {k: entry(*v) for k, v in STRINGS.items()}},
                              ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({'status': 'WRITTEN', 'keys': len(STRINGS)}))
