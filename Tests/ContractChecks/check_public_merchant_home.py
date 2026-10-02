#!/usr/bin/env python3
"""Source contract assertions only, not Swift execution or runtime proof."""
import json
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parents[2]
SOURCE = ROOT.parent / 'app-audit' / 'lib'
checks = 0

def require(condition, message):
    global checks
    checks += 1
    assert condition, message

def read(path):
    return (ROOT / path).read_text()

home = read('Core/PublicMerchantHome.swift')
reader = read('Core/PublicMerchantHomeReading.swift')
reviews = read('Core/PublicMerchantReviews.swift')
writes = read('Core/PublicMerchantReviewWrites.swift')
coordinator = read('Core/PublicMerchantReviewCoordinator.swift')
view = read('App/PublicMerchantHomeView.swift')
review_view = read('App/PublicMerchantReviewsView.swift')
editor = read('App/PublicMerchantReviewEditor.swift')
source_api = (SOURCE / 'data/api/merchant_api.dart').read_text()
source_reviews = (SOURCE / 'data/api/merchant_review_api.dart').read_text()
source_model = (SOURCE / 'data/models/merchant_review.dart').read_text()
source_home = (SOURCE / 'feature/merchant/merchant_public_home_page.dart').read_text()
for item in ['ownerMemberID(PublicMerchantOwnerID)', 'legacyMerchantRowID(PublicMerchantRowID)', '["memberId": id.rawValue]', '["id": id.rawValue]']:
    require(item in home, item)
require("{'id': id}" in source_api and "'memberId': memberId" in source_api, 'source ID bodies changed')
for item in ['api/merchant/public-home', 'request.httpMethod = "POST"', 'request.httpShouldHandleCookies = false', 'target.fields', '商家不存在或未开放']:
    require(item in reader, item)
require('Authorization' not in reader, 'home must not require login')
require('public-detail' not in reader, 'public-detail semantics must not be replaced')
for item in ['memberId', 'coverImage', 'businessStatus', 'gallery', 'sysCategoryList', 'capacity', 'suitActivityTypes', 'demand']:
    require(item in home and item in source_home, 'missing source field '+item)
require("message == '商家不存在或未开放'" in source_api, 'unavailable predicate source changed')
for item in ['api/merchant/reviews/public', 'merchantRowId', 'pageNum', 'pageSize']:
    require(item in reviews and item in source_reviews, item)
require('request.httpBody' not in reviews, 'public review read sends query only')
for item in ['mode == "public"', 'item.status == "VISIBLE"', 'hasMore == (loaded < total)', 'eligibility.canCreate == (eligibility.reasonCode == "ELIGIBLE")']:
    require(item in reviews, item)
for item in ['api/merchant/reviews/create', 'api/merchant/reviews/report', 'merchantRowId', 'registrationId', 'requestId', 'merchantMemberId', 'expectedVersion']:
    require(item in writes and item in source_reviews + source_model, item)
require('(2...1000).contains(text.utf16.count)' in writes and 'length < 2 || length > 1000' in source_model, 'create text length source mismatch')
require('(2...500).contains(text.utf16.count)' in writes and 'length < 2 || length > 500' in source_model, 'report text length source mismatch')
for item in ['PENDING_REVIEW', 'PENDING_PLATFORM_REVIEW', 'auditTaskId', 'replayed']:
    require(item in writes and item in source_model, item)
for item in ['MerchantBusinessIntentStore', 'journal.reserve(intent)', 'journal.complete(intent)', 'writer.session == review.session', 'try validate(review.command, evidence: evidence)', 'sameTarget(as: intent)']:
    require(item in coordinator, item)
require(coordinator.index('journal.reserve(intent)') < coordinator.index('writer.execute('), 'reserve before dispatch')
require('epoch: 0' in coordinator, 'durable unknown locks must survive session changes')
require('DisabledPublicMerchantHomeReader()' in view, 'default backend must be off')
require('var shopNpcChat = false' in view and 'var image:' in view, 'media/provider gate absent')
require('value.reviewTarget' in view and 'context.publicReviews' in view, 'typed reviews bridge absent')
require('value.canOfferNPCChat(shopNpcChat: context.shopNpcChat)' in view, 'NPC source gate absent')
require('snapshot.eligibility.canCreate' in review_view and 'item.canReport' in review_view, 'source permissions not surfaced')
require('state.confirmation' in editor and 'state.locked' in editor, 'review/unknown UI missing')
for filename in ROOT.glob('App/PublicMerchant*.swift'):
    text = filename.read_text()
    require('AsyncImage(' not in text and 'URLSession.' not in text, 'real media/network activated in '+str(filename))
catalog = {k:v for k,v in json.loads(read('Resources/Localizable.xcstrings'))['strings'].items() if k.startswith('merchant.publicHome.')}
keys = set()
for path in list(ROOT.glob('Core/PublicMerchant*.swift')) + list(ROOT.glob('App/PublicMerchant*.swift')):
    keys.update(re.findall(r'"(merchant\.publicHome\.[A-Za-z]+)"', path.read_text()))
# Identifiers that are not copy are intentionally absent from the translation catalog.
identifiers = {'ratingPicker','editorText','writeFailure','review','report'}
missing = [k for k in keys if k not in catalog and k.rsplit('.',1)[-1] not in identifiers]
require(not missing, 'missing labels: '+str(missing))
for key, value in catalog.items():
    require(all(language in value['localizations'] for language in ['en','zh-Hans']), 'missing translation '+key)
print(f'PASS {checks} source assertions; not Swift typechecking or runtime evidence')
