#!/usr/bin/env python3
"""Supplementary source assertions; not Swift compiler or runtime evidence."""
from pathlib import Path
import sys
root=Path(sys.argv[1]); checks=0
def check(value, message):
 global checks
 assert value, message
 checks+=1
read=lambda p:(root/p).read_text()
node=read('Core/PlayContracts.swift'); brief=read('Core/PlayNPCBrief.swift')
app=read('App/AppSession.swift'); host=read('App/ShopNPCSessionHost.swift')
view=read('App/ShopNPCView.swift'); play=read('App/PlayExperienceView.swift'); entry=read('App/SessionPlayRuntimeView.swift')
http=read('Core/ShopNPCAuthenticatedTransport.swift'); core=read('Core/ShopNPCCoordinator.swift')
for token in ['public let npc: PlayNPCBrief?', 'npc = try? c.decode(PlayNPCBrief.self, forKey: .npc)']:
 check(token in node, 'node '+token)
for token in ['decode(String.self, forKey: .name)', 'trimmingCharacters(in: .whitespacesAndNewlines).isEmpty', 'decodeIfPresent(String.self, forKey: .greeting)']:
 check(token in brief, 'NPC brief '+token)
for token in ['runtime.hasCurrentMediaSnapshot', 'snapshot.availability == .active', '!snapshot.isLocked(node), node.npc == npc', 'ShopNPCNodeID(nodeID)', 'roleID: account.effectiveRole', 'accessRevision: shopNPCSessionOwner.accessRevision', 'runtimeDependencyFactory?.accepted != nil ? runtimeDependencies.shopNPCGrants : ShopNPCGrants()', 'runtimeDependencyFactory?.accepted?.shopNPCWrites == true', 'if current() != captured { coordinator.invalidate() }', 'account?.effectiveRole != newValue?.effectiveRole { invalidateShopNPCConversations(); merchantNPCSessionOwner.invalidate() }', 'if token != newValue { invalidateShopNPCConversations(); platformConsumers.invalidate() }']:
 check(token in app, 'AppSession '+token)
shop_block=app[app.index('// Shop NPC remains'):app.index('private let playService:')]
check('merchantID' not in shop_block and 'merchantId' not in shop_block and 'bizId' not in shop_block,'No merchant identity bridge')
check('capture:' not in shop_block, 'No capture factory')
for token in ['@Observable final class ShopNPCSessionOwner','accessRevision &+= 1','conversations.forEach { $0.value?.invalidate() }','@State private var coordinator:', 'if coordinator == nil { coordinator = makeCoordinator() }']:
 check(token in host, 'owner '+token)
for token in ['@Bindable var coordinator:', '.onChange(of: coordinator.active)', '.onChange(of: coordinator.scope)', '.onChange(of: coordinator.grants)', 'draft = ""', 'ShopNPCOwnedDestination(makeCoordinator: makeCoordinator']:
 check(token in view,'view '+token)
check('@MainActor @Observable public final class ShopNPCCoordinator' in core,'observable coordinator')
for token in ['shopNPCModel?(id)', 'ShopNPCNodeEntrance(', '.id(shopNPC.identity)', '.onChange(of: model.snapshot)', '.onChange(of: model.hasCurrentMediaSnapshot)']:
 check(token in play, 'Play '+token)
for token in ['deviceModel:', 'advancedModel:', 'motionModel:', 'preferenceModel:', 'summaryModel:', 'playerModel:', 'circleModel:', 'prefabModel:', 'journeyModel:', 'ambientModel:', 'makeAudio:', 'makeExternalMaps:', 'shopNPCModel:', 'invalidateShopNPC:']:
 check(token in entry,'Existing/new factory preserved '+token)
for token in ['productionWritesEnabled: Bool = false', 'currentGrants: @escaping () -> ShopNPCGrants = { .init() }','captured.scope == input.scope', 'currentSession() == captured, currentGrants() == grants', 'request.setValue(captured.token, forHTTPHeaderField: "Authorization")', 'transport.send(request)', 'catch { throw ShopNPCFailure.unknownOutcome }', 'onUnauthorized(captured); throw ShopNPCFailure.unknownOutcome']:
 check(token in http,'adapter '+token)
post=http[http.index('transport.send(request)'):]
check('throw ShopNPCFailure.stale' not in post, 'Post-dispatch uncertainty never reported as preflight stale')
check('URLSession.shared' not in http and 'URLSession(' not in http, 'No bare unauthenticated network fallback')
check(read('Tests/CoreTests/ShopNPCHostTests.swift').count('func test')==10,'Ten host tests authored')
print(f'PASS: {checks} host source assertions. Swift typecheck/tests and Apple runtime NOT_RUN.')
