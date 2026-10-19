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
    # Invitation history (subpackageMember/myinvite → scene-member-invite-history)
    'profile.inviteHistory.signIn': ('Sign in to see invitation history', '登录后查看邀请记录'),
    'profile.inviteHistory.signInHint': ('After signing in you can see your actual invitations.', '登录后可查看你的真实邀请关系'),
    'profile.inviteHistory.denied': ('This account cannot view invitation history', '当前账号无法查看邀请记录'),
    'profile.inviteHistory.deniedHint': ("Check this account's viewing permission.", '请确认当前账号的查看权限'),
    'profile.inviteHistory.failed': ('Invitation history did not load', '邀请记录没加载出来'),
    'profile.inviteHistory.failedHint': ('The network may be unstable. Your invitations are still there.', '网络可能不稳定，你的邀请关系还在'),
    'profile.inviteHistory.empty': ('No one has accepted your invitation yet', '还没有人接受你的邀请'),
    'profile.inviteHistory.emptyHint': ('Friends appear here by time after they join.', '好友加入后，会按时间出现在这里'),
    'profile.inviteHistory.nicknameUnknown': ('Nickname to be confirmed', '昵称待确认'),
    # My node plays (subpackageMember/mytemplate, utils/template-market.js)
    'templateOwnShelf.market.submit': ('Submit for marketplace review', '提交广场审核'),
    'templateOwnShelf.market.withdraw': ('Withdraw marketplace review', '撤回广场审核'),
    'templateOwnShelf.market.delist': ('Remove from marketplace', '从广场下架'),
    'templateOwnShelf.market.list': ('List in marketplace', '上架广场'),
    'templateOwnShelf.delete.title %@': ('Delete node play “%@”?', '删除节点玩法「%@」?'),
    'templateOwnShelf.delete.body': ('If you only want to stop others from using it, removing it from the play library is enough.', '只是不想让别人再用的话,从玩法库下架就够了。'),
    'templateOwnShelf.delete.keepsReferences': ('Nodes that already reference this play are unaffected and keep their configuration.', '已经引用了这个玩法的节点不受影响,继续按原配置跑'),
    'templateOwnShelf.delete.irreversible': ('This cannot be undone. The play configuration cannot be recovered.', '此操作不可撤销,玩法配置无法找回'),
    'templateOwnShelf.delete.confirm': ('Delete play', '删除玩法'),
}


def entry(en, zh):
    unit = lambda value: {'stringUnit': {'state': 'translated', 'value': value}}
    return {'localizations': {'en': unit(en), 'zh-Hans': unit(zh)}}


if __name__ == '__main__':
    OUT.write_text(json.dumps({'sourceLanguage': 'en', 'strings': {k: entry(*v) for k, v in STRINGS.items()}},
                              ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({'status': 'WRITTEN', 'keys': len(STRINGS)}))
