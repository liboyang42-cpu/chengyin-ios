#!/usr/bin/env python3
"""Focused source contracts only; no Swift compilation, execution or AX acceptance."""
import argparse
import json
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[1])
parser.add_argument('--base', type=Path, help='Read-only source root for paths omitted by a sparse review overlay')
args = parser.parse_args()
checks = []
def read(path):
    source = args.root / path
    if not source.exists() and args.base is not None:
        source = args.base / path
    return source.read_text()
def check(name, value):
    assert value, name
    checks.append(name)

source = read('App/QuestifyDensityMap.swift')
map_view, alternative = source.split('struct QuestifyMapAlternativeList: View {', 1)
core = read('Core/MapMarkerDensity.swift')
fixture = read('App/ReferenceMapCardFixtureView.swift').split('struct MapAlternativeListFixtureView: View {', 1)[1]
ui = read('Tests/AppUITests/SearchMapAlternativeListFlowTests.swift')
keys = json.loads(read('Resources/Localizable.xcstrings'))['strings']
check('Online map exposes list before map accessibility subtree', map_view.index('QuestifyMapAlternativeList(pins: pins, selectedID: selectedID') < map_view.index('GeometryReader'))
check('List has no viewport, projection or group dependency', not any(x in alternative for x in ['MapProxy', 'cameraRevision', 'expandedSnapshot', 'groups(', 'applyCameraFit']))
check('All supplied unambiguous identities are listed in caller order', 'Dictionary(grouping: pins, by: \\.id)' in alternative and 'return pins.filter { !$0.id.isEmpty && counts[$0.id]?.count == 1 }' in alternative)
check('Selection request validates raw supplied identities', 'gate.request(id: pin.id, suppliedIDs: pins.map(\\.id))' in alternative and 'suppliedIDs.filter({ $0 == id }).count == 1' in core)
check('Selection gates use one-shot revision and exact identity', 'public struct SelectionGate' in core and 'guard request.revision == revision else { return nil }\n            invalidate()\n            return request.id' in core)
check('Current input includes full pin snapshot, parent selection, scope and enabled state', all(x in alternative for x in ['let pins: [SearchMapPin]', 'let selectedID: String?', 'let interactionID: AnyHashable?', 'let selectionEnabled: Bool']))
check('Old render and closed list cannot invoke callback', 'guard isExpanded, renderedInput == currentInput, let request,' in alternative and 'let id = gate.consume(request)' in alternative)
check('Refresh and same-ID replacement invalidate requests', '.onChange(of: input)' in alternative and 'currentInput = value\n                gate.invalidate()' in alternative)
check('Close and disappearance invalidate requests', 'gate.invalidate()\n                isExpanded.toggle()' in alternative and 'toggleGate.disappear()\n                isExpanded = false\n                gate.invalidate()' in alternative)
check('Toggle consumes a captured current-lifetime request', 'let toggleRequest = renderedInput == currentInput ? toggleGate.request() : nil' in alternative and 'toggleGate.consume(toggleRequest) else { return }' in alternative)
check('Presentation gate starts hidden and cannot issue offscreen requests', 'private var isVisible = false' in core and 'guard isVisible else { return nil }' in core)
check('Presentation gate rejects stale and foreign lifecycle requests', 'guard isVisible, request.revision == revision else { return false }' in core)
check('Appearance enables a fresh toggle and disappearance retires it', '.onAppear {' in alternative and 'toggleGate.appear()' in alternative and 'toggleGate.disappear()' in alternative and '.disabled(toggleRequest == nil)' in alternative)
check('Authored lifecycle negative controls and return journey exist', all(x in read('Tests/CoreTests/MapMarkerDensityTests.swift') for x in ['testPresentationToggleRequiresAppearanceAndCannotIssueOffscreenRequests', 'testPresentationToggleRejectsOldLifetimeAfterReturnButFreshToggleWorks', 'XCTAssertFalse(gate.consume(departed))', 'XCTAssertTrue(gate.consume(returned))']) and 'mapList.fixture.depart' in ui and 'mapList.fixture.away' in ui and 'XCTAssertTrue(returnedToggle.isEnabled)' in ui)
check('Read-only preview has no pretend selection action', '.disabled(onSelect == nil)' in alternative and '.accessibilityHint(onSelect == nil ? Text("mapList.readOnly")' in alternative and 'onSelect: onSelect.map' in map_view)
check('Map singleton uses fresh one-shot action instead of an unguarded callback', 'let id = selectionGate.consume(request)' in map_view and 'guard renderedInput == currentFocusInput, let request' in map_view)
check('Existing explicit focus and cluster choice remain', all(x in map_view for x in ['focusGate.consume(request)', 'mapDensity.member.', 'mapCamera.focusSelected', 'renderedExpansionID == expansionID']))
check('List and map use same selected ID without local business selection state', 'pin.id == selectedID' in alternative and '@State private var selectedID' not in alternative and 'anchor.id == selectedID' in map_view)
check('Selected status is text and an AX trait', 'Text("mapList.selected")' in alternative and '.accessibilityAddTraits(pin.id == selectedID ? .isSelected : [])' in alternative)
check('Titles are verbatim, wrap vertically and have no line limit', 'Text(verbatim: pin.title).fixedSize(horizontal: false, vertical: true)' in alternative and '.lineLimit(' not in alternative and '.truncationMode(' not in alternative)
check('Rows keep full-width 44pt minimum targets', '.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)' in alternative and '.contentShape(Rectangle())' in alternative)
check('Rows speak complete titles and caller hints', '.accessibilityLabel(Text(verbatim: pin.title))' in alternative and 'pinHint(pin.id)' in alternative)
check('Empty snapshot is explicit', 'if currentPins.isEmpty' in alternative and 'mapList.empty' in alternative)
check('No animation is introduced', '.animation(' not in alternative and 'withAnimation' not in alternative)
check('No fetching, permission, location, geocoding or task path is introduced', not any(x in source for x in ['URLSession', 'CLLocationManager', 'requestWhenInUseAuthorization', 'requestAlwaysAuthorization', 'MKDirections(', 'CLGeocoder(', '.task {', '.task(']))
for key in ['show', 'hide', 'expanded', 'collapsed', 'title', 'scope', 'empty', 'selected', 'readOnly']:
    value = keys['mapList.' + key]['localizations']
    check('Bilingual localization mapList.' + key, set(value) == {'en', 'zh-Hans'} and all(value[k]['stringUnit']['value'] for k in value))
check('Search and Roam retain their shared renderer', 'QuestifyDensityMap(area: area, pins: pins, selectedID: selectedID' in read('App/SearchMapCanvas.swift') and 'QuestifyDensityMap(area: area, pins: pins, selectedID: selectedID' in read('App/RoamMapView.swift'))
check('New synthetic host mounts actual list without a map/provider', 'QuestifyMapAlternativeList(pins: pins' in fixture and not any(x in fixture for x in ['QuestifyDensityMap(', 'Map(', 'SearchMapCanvas(', 'https://', 'URLSession']))
check('Authored UI uses maximum bilingual text and honest point witness', '--uitesting-max-text' in ui and 'for chinese in [false, true]' in ui and 'mapList.fixture.pointSecond' in ui)
check('Authored UI covers removal, duplicates, refresh, close/reopen, empty and readonly', all('mapList.fixture.'+x in ui for x in ['removed', 'duplicates', 'refreshed', 'empty', 'readOnly']) and 'testAlternativeListCloseReopenAndEmptySnapshotNeverRetainOldRows' in ui)
print('PASS: ' + str(len(checks)) + ' map alternative-list source contracts')
for name in checks:
    print(' - ' + name)
print('NOT_RUN: Swift tests, Apple compilation, XCUITest, real MapKit, VoiceOver, device and visual acceptance.')
