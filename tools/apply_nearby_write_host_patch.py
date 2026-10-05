#!/usr/bin/env python3
"""Apply only the existing nearby coordinator factory, after the parent grants shared ownership."""
import argparse
from pathlib import Path
parser=argparse.ArgumentParser(); parser.add_argument('--root',type=Path,required=True); args=parser.parse_args()
p=args.root/'App/AppSession.swift'; text=p.read_text()
start=text.index('    func makeNearbyTeamCoordinator(readApproval:')
end=text.index('    func makeTeamCoordinator(readApproval:',start)
old=text[start:end]
assert 'writeApproval:' not in old, 'Already patched; do not repeat'
assert 'return NearbyTeamCoordinator(service: service, session: nearbyTeamSession)' in old
new='''    func makeNearbyTeamCoordinator(readApproval: OperationEndpointApproval? = nil,
                                   writeApproval: OperationEndpointApproval? = nil,
                                   writeEvidence: ((NearbyTeamReview) async throws -> NearbyTeamWriteEvidence)? = nil,
                                   transport: any HTTPTransport = URLSessionTransport()) -> NearbyTeamCoordinator {
        // No default caller supplies an operation grant or evidence loader; writes remain off.
        let writer: NearbyTeamHTTPWriteAdapter?
        if let writeApproval, let writeEvidence, let configuration = regionalConfiguration?.apiConfiguration {
            writer = NearbyTeamHTTPWriteAdapter(configuration: configuration, transport: transport, approval: writeApproval,
                journal: NearbyTeamDefaultsDispatchJournal(defaults: .standard),
                currentSession: { [weak self] in self?.nearbyTeamSession },
                token: { [weak self] captured in guard let self, self.nearbyTeamSession == captured else { return nil }; return self.token },
                freshEvidence: writeEvidence)
        } else { writer = nil }
        let service: NearbyTeamService
        if let readApproval, let configuration = regionalConfiguration?.apiConfiguration {
            let reader = NearbyTeamHTTPReadTransport(configuration: configuration, transport: transport, approval: readApproval,
                currentSession: { [weak self] in self?.nearbyTeamSession },
                token: { [weak self] captured in guard let self, self.nearbyTeamSession == captured else { return nil }; return self.token })
            service = NearbyTeamService(readTransport: reader, liveReadGrant: true, writeAdapter: writer)
        } else { service = NearbyTeamService(writeAdapter: writer) }
        return NearbyTeamCoordinator(service: service, session: nearbyTeamSession)
    }
'''
p.write_text(text[:start]+new+text[end:])
print('Patched nearby factory only; default read/write approvals and evidence loader remain nil')
