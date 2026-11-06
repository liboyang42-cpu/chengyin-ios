#!/usr/bin/env python3
"""Source checks only. Requires an explicit root; never implies Swift or App execution."""
import argparse, hashlib, json
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--root',type=Path,required=True);a=p.parse_args();root=a.root.resolve()
s=(root/'App/AppSession.swift').read_text();f=s.split('    func playPlayer(scope: PlaySessionScope)',1)[1].split('    func playCircle(',1)[0]
checks={
 'valid_activity_only':'case .activity(let id) = scope, id > 0' in f,
 'reject_committing_session':'!committingAuthenticatedSession' in f,
 'recognized_actual_role':'PlayRecoveryAccountRole(rawValue: account.effectiveRole)' in f,
 'captured_real_owner':'namespace: storageScope.service, token: token, role: role.rawValue' in f,
 'captured_viewer':'let viewer = compositionViewerRevision' in f,
 'viewer_qualified_cache':'suffix: "player:\\(viewer)"' in f,
 'one_retained_coordinator':'if let retained = retainedPlayPlayers[key] { return retained }' in f,
 'existing_journal_composition':'PlayGameSessionJournalFactory.makeCoordinator(scope: scope, service: api' in f,
 'explicit_captured_session':'session: captured, regionalConfiguration: regional, storageScope: storageScope' in f,
 'permanent_old_viewer_fence':'matchesContinuationSession(captured, viewerRevision: viewer)' in f,
 'existing_secure_storage':'composition.storage.playRecovery.make(session: session, scope: scope' in f,
 'no_direct_nil_journal_constructor':'PlayPlayerGameCoordinator(activityID:' not in f,
 'no_default_player_callback':'currentPlayRuntimeSession' not in f,
 'dormant_service_unchanged':'let api = dormantPlayRuntimeService()' in f,
 'no_capability_expansion':not any(x in f for x in ['enabled:', '.playerCommands', 'RuntimeDependencyConfiguration(', 'EndpointAllowlist(']),
 'no_memory_fallback':'PlayMemoryGameCommandJournal' not in f,
 'failed_construction_returns_nil':'}) else { return nil }' in f,
 'retain_only_constructed_model':'retainedPlayPlayers[key] = model; return model' in f,
}
print(json.dumps({'root':str(root),'AppSession_sha256':hashlib.sha256(s.encode()).hexdigest(),'checks':checks,'pass':sum(checks.values()),'fail':sum(not x for x in checks.values()),'Swift_App':'NOT_RUN'},indent=2))
raise SystemExit(0 if all(checks.values()) else 1)
