"""Public saved-route replay source contracts. No private Mini/MASTER input.

These checks do not execute Swift, timers, Canvas or accessibility on a device.
Exact historical projections are proof only; forward predicates read raw sources.
"""
from pathlib import Path
import hashlib
import json
import re
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
SOURCE_INVERSES = {'App/RoamHistoryViews.swift': {'before': '01690f38f74de0698dee84c8d28a8a2413b75d603444c59c6ffdc22d9c9b52b8', 'after': '2a4d67bbb003df0646599c911ae8c2ac6e20b99e2af7ae81f89be384af608172', 'spans': [(b'    @State private var showShare = false\n    @State private var loaded = false\n    @State private var error: Error?\n    @State private var loadedOwner: ReadKey?\n    private struct ReadKey: Hashable {\n        let owner: RoamHistoryLiveOwner\n        let timestamp: Int64\n    }\n    private var readKey: ReadKey { .init(owner: .init(reader: reader), timestamp: timestamp) }\n    private var currentRecord: RoamHistoryRecord? { loadedOwner == readKey ? record : nil }\n    private var currentError: Error? { loadedOwner == readKey ? error : nil }\n    private var currentLoaded: Bool { loadedOwner == readKey && loaded }\n    var body: some View {\n        ScrollView {\n            VStack(alignment: .leading, spacing: 20) {\n                RoamExperienceNotice(offline: reader.isOfflineExample)\n                if let error = currentError { RoamExperienceIssue(error: error, retry: load) }\n                else if let record = currentRecord {\n                    RoamExperienceCard {\n                        VStack(alignment: .leading, spacing: 18) {\n                            Label("roam.experience.savedRecord", systemImage: "book.closed").font(.caption).foregroundStyle(.secondary)\n                            if let zone = record.meaningfulZone { Text(verbatim: zone).font(.title2).bold() }\n                            else { Text("roam.experience.cityWalk").font(.title2).bold() }\n                            if let date = record.recordedAt { Text(date, style: .date) }\n                            RoamSavedRouteReplayView(reader: reader, record: record)\n                            RoamRecordedStats(record: record)\n                        }\n                    }\n', b'    @State private var showShare = false\n    @State private var loaded = false\n    @State private var error: Error?\n    var body: some View {\n        ScrollView {\n            VStack(alignment: .leading, spacing: 20) {\n                RoamExperienceNotice(offline: reader.isOfflineExample)\n                if let error { RoamExperienceIssue(error: error, retry: load) }\n                else if let record {\n                    RoamExperienceCard {\n                        VStack(alignment: .leading, spacing: 18) {\n                            Label("roam.experience.savedRecord", systemImage: "book.closed").font(.caption).foregroundStyle(.secondary)\n                            if let zone = record.meaningfulZone { Text(verbatim: zone).font(.title2).bold() }\n                            else { Text("roam.experience.cityWalk").font(.title2).bold() }\n                            if let date = record.recordedAt { Text(date, style: .date) }\n                            RoamRouteSketchView(record: record)\n                            RoamRecordedStats(record: record)\n                        }\n                    }\n'), (b'                    Button("roam.share.title", systemImage: "square.and.arrow.up") { showShare = true }\n                        .accessibilityIdentifier("roam.share.open")\n                    Text("roam.experience.historyPrivacy").font(.caption).foregroundStyle(.secondary)\n                } else if currentLoaded {\n                    ContentUnavailableView("roam.experience.recordMissing", systemImage: "questionmark.folder", description: Text("roam.experience.recordMissingHint"))\n                        .accessibilityIdentifier("roam.experience.history.missing")\n                } else { ProgressView("roam.loading") }\n            }.padding()\n        }.navigationTitle("roam.experience.session")\n            .task(id: readKey) { showShare = false; load() }\n            .onChange(of: readKey) { _, _ in showShare = false }\n            .sheet(isPresented: $showShare) { if let record = currentRecord { NavigationStack { RoamHistoryShareView(record: record) } } }\n            .accessibilityIdentifier("roam.experience.session")\n    }\n    private func load() {\n        record = nil; error = nil; loaded = false; loadedOwner = nil\n        let captured = readKey\n        do {\n            let value = try reader.history().first { $0.ts == timestamp }\n            guard captured == readKey else { return }\n            record = value; loaded = true; loadedOwner = captured\n        } catch {\n            guard captured == readKey else { return }\n            self.error = error; loadedOwner = captured\n        }\n    }\n}\n', b'                    Button("roam.share.title", systemImage: "square.and.arrow.up") { showShare = true }\n                        .accessibilityIdentifier("roam.share.open")\n                    Text("roam.experience.historyPrivacy").font(.caption).foregroundStyle(.secondary)\n                } else if loaded {\n                    ContentUnavailableView("roam.experience.recordMissing", systemImage: "questionmark.folder", description: Text("roam.experience.recordMissingHint"))\n                        .accessibilityIdentifier("roam.experience.history.missing")\n                } else { ProgressView("roam.loading") }\n            }.padding()\n        }.navigationTitle("roam.experience.session")\n            .task(id: reader.identity) { showShare = false; load() }\n            .sheet(isPresented: $showShare) { if let record { NavigationStack { RoamHistoryShareView(record: record) } } }\n            .accessibilityIdentifier("roam.experience.session")\n    }\n    private func load() {\n        record = nil; error = nil; loaded = false\n        do { record = try reader.history().first { $0.ts == timestamp }; loaded = true } catch { self.error = error }\n    }\n}\n')]}, 'App/RoamExperienceComponents.swift': {'before': '5d07efdb738c201f6f9b6502b1211330db63d6873ed4be5d33e1eb054115b453', 'after': '02188caf2ccd48dae34f6775828d2e722ce4f8239f9925af8d972d9148e772fb', 'spans': [(b'}\nstruct RoamRouteSketchView: View {\n    let record: RoamHistoryRecord\n    var visibleSegments: Int? = nil\n    var body: some View {\n        let sketch = RoamRouteSketch(track: record.track, places: record.pois.map(\\.point))\n        ZStack {\n', b'}\nstruct RoamRouteSketchView: View {\n    let record: RoamHistoryRecord\n    var body: some View {\n        let sketch = RoamRouteSketch(track: record.track, places: record.pois.map(\\.point))\n        ZStack {\n'), (b'            } else {\n                Canvas { context, size in\n                    var path = Path()\n                    let segmentCount = max(0, sketch.track.count - 1)\n                    let pointCount = visibleSegments.map { min(segmentCount, max(0, $0)) + 1 } ?? sketch.track.count\n                    for (index, point) in sketch.track.prefix(pointCount).enumerated() {\n                        let position = CGPoint(x: point.x * size.width, y: point.y * size.height)\n                        if index == 0 { path.move(to: position) } else { path.addLine(to: position) }\n                    }\n', b'            } else {\n                Canvas { context, size in\n                    var path = Path()\n                    for (index, point) in sketch.track.enumerated() {\n                        let position = CGPoint(x: point.x * size.width, y: point.y * size.height)\n                        if index == 0 { path.move(to: position) } else { path.addLine(to: position) }\n                    }\n'), (b'        }.font(.subheadline).monospacedDigit()\n    }\n}\n\n/// Replays only the stored sketch. This view has no location, network or write capability.\n@MainActor struct RoamSavedRouteReplayView: View {\n    let reader: any RoamExperienceReading\n    let record: RoamHistoryRecord\n    @Environment(\\.scenePhase) private var scenePhase\n    @Environment(\\.accessibilityReduceMotion) private var reduceMotion\n    @State private var replay = RoamRouteReplayState()\n    @State private var visible = false\n    @State private var request: Request?\n    private struct Request {\n        let id = UUID()\n        let context: RoamRouteReplayState.Context\n        let counts: [Int]\n    }\n    private var owner: RoamRouteReplayState.Owner { .init(reader: reader, record: record) }\n    var body: some View {\n        let current = owner\n        let context = replay.context(for: current)\n        VStack(alignment: .leading, spacing: 12) {\n            // Always normalize the complete record; revealing a prefix never rescales it.\n            RoamRouteSketchView(record: record, visibleSegments: context == nil ? nil : replay.visibleSegments)\n            if let context {\n                if replay.phase == .playing {\n                    Button("roamRouteReplay.skip", systemImage: "forward.end") {\n                        synchronize()\n                        guard replay.accepts(context, current: owner) else { return }\n                        replay.skip(in: context, current: owner); request = nil\n                    }.frame(minHeight: 44).accessibilityIdentifier("roamRouteReplay.skip")\n                } else {\n                    Button(LocalizedStringKey(replay.phase == .completed ? "roamRouteReplay.again" : "roamRouteReplay.start"), systemImage: "play") {\n                        synchronize()\n                        guard replay.accepts(context, current: owner) else { return }\n                        if let ticket = replay.start(in: context, current: owner) {\n                            request = Request(context: ticket, counts: replay.plan.counts)\n                        }\n                    }.frame(minHeight: 44).accessibilityIdentifier("roamRouteReplay.start")\n                }\n                ProgressView(value: replay.progress, total: 1)\n                    .accessibilityLabel(Text("roamRouteReplay.progress"))\n                    .accessibilityValue(Text(replay.progress, format: .percent.precision(.fractionLength(0))))\n                    .accessibilityIdentifier("roamRouteReplay.progress")\n                Text(LocalizedStringKey(replay.phase == .playing ? "roamRouteReplay.playing" : (replay.phase == .completed ? "roamRouteReplay.completed" : "roamRouteReplay.ready")))\n                    .font(.caption).foregroundStyle(.secondary)\n            }\n        }\n        .onAppear { visible = true; synchronize() }\n        .onDisappear { visible = false; synchronize() }\n        .onChange(of: owner) { _, _ in synchronize() }\n        .onChange(of: scenePhase) { _, _ in synchronize() }\n        .onChange(of: reduceMotion) { _, _ in synchronize() }\n        .task(id: request?.id) {\n            guard let captured = request else { return }\n            for (index, count) in captured.counts.enumerated() {\n                if index > 0 {\n                    do { try await Task.sleep(nanoseconds: RoamRouteReplayPlan.intervalNanoseconds) }\n                    catch { return }\n                }\n                if reduceMotion { synchronize(); return }\n                guard !Task.isCancelled, visible, scenePhase == .active,\n                      replay.accepts(captured.context, current: owner) else { return }\n                replay.advance(to: count, in: captured.context, current: owner)\n            }\n            // No old-task cleanup can clear a later request.\n        }\n        .accessibilityElement(children: .contain)\n        .accessibilityIdentifier("roamRouteReplay.saved")\n    }\n    private func synchronize() {\n        replay.update(owner: owner, active: visible && scenePhase == .active, reduceMotion: reduceMotion)\n        if let captured = request, !replay.accepts(captured.context, current: owner) { request = nil }\n    }\n}\n', b'        }.font(.subheadline).monospacedDigit()\n    }\n}\n')]}, 'Core/RoamExperienceMath.swift': {'before': '38d408d0608a12124ea22621c98e7b7608a441f8991b671e3283e5ee249ba959', 'after': '02acd81d49d370748da8c780447b771bc7913e8813a9c537e04509b233e266f1', 'spans': [(b'        self.track = Array(normalized.prefix(track.count)); self.places = Array(normalized.dropFirst(track.count))\n    }\n}\n\n/// A bounded local display schedule; it never reads, changes or saves a route.\npublic struct RoamRouteReplayPlan: Equatable {\n    public static let intervalNanoseconds: UInt64 = 120_000_000\n    public static let maximumFrames = 24\n    public let counts: [Int]\n    public init(segmentCount: Int) {\n        let total = max(0, segmentCount)\n        guard total > 0 else { counts = []; return }\n        let frames = min(total, Self.maximumFrames)\n        let step = total / frames + (total % frames == 0 ? 0 : 1)\n        var result: [Int] = [], count = 0\n        while count < total {\n            count = total - count <= step ? total : count + step\n            result.append(count)\n        }\n        counts = result\n    }\n}\n\n/// Value-only replay authority. Timers live in the SwiftUI detail presentation.\n/// A context belongs to an exact reader/scope, complete record value and visible lifetime.\npublic struct RoamRouteReplayState {\n    public struct Owner: Equatable {\n        public let readerID: ObjectIdentifier\n        public let identity: RoamExperienceIdentity?\n        public let storageKey: String?\n        public let configured: Bool\n        public let record: RoamHistoryRecord\n        @MainActor public init(reader: any RoamExperienceReading, record: RoamHistoryRecord) {\n            readerID = ObjectIdentifier(reader); identity = reader.identity\n            storageKey = identity?.scope.storageKey\n            configured = reader.isConfigured; self.record = record\n        }\n    }\n    public struct Context: Equatable {\n        fileprivate let owner: Owner\n        fileprivate let generation: UUID\n    }\n    public enum Phase: Equatable { case ready, playing, completed }\n    public private(set) var phase: Phase = .ready\n    public private(set) var totalSegments = 0\n    /// nil means the unchanged full static sketch, including non-replay callers.\n    public private(set) var visibleSegments: Int?\n    private var owner: Owner?\n    private var active = false\n    private var reduceMotion = false\n    private var generation = UUID()\n    public init() {}\n    public var progress: Double {\n        guard totalSegments > 0 else { return 0 }\n        return Double(visibleSegments ?? totalSegments) / Double(totalSegments)\n    }\n    public var plan: RoamRouteReplayPlan { .init(segmentCount: totalSegments) }\n    public mutating func update(owner: Owner, active: Bool, reduceMotion: Bool) {\n        if self.owner != owner || self.active != active {\n            generation = UUID(); phase = .ready; visibleSegments = nil\n            let points = RoamRouteSketch(track: owner.record.track, places: owner.record.pois.map(\\.point)).track\n            let hasLine = zip(points, points.dropFirst()).contains { pair in pair.0 != pair.1 }\n            totalSegments = hasLine ? max(0, points.count - 1) : 0\n        }\n        self.owner = owner; self.active = active; self.reduceMotion = reduceMotion\n        if reduceMotion && phase == .playing { complete() }\n    }\n    public func context(for current: Owner) -> Context? {\n        guard active, owner == current, totalSegments > 0 else { return nil }\n        return Context(owner: current, generation: generation)\n    }\n    public func accepts(_ context: Context, current: Owner) -> Bool {\n        self.context(for: current) == context\n    }\n    @discardableResult public mutating func start(in context: Context, current: Owner) -> Context? {\n        guard accepts(context, current: current), phase != .playing else { return nil }\n        generation = UUID()\n        if reduceMotion { phase = .completed; visibleSegments = nil; return nil }\n        phase = .playing; visibleSegments = 0\n        return self.context(for: current)\n    }\n    public mutating func advance(to count: Int, in context: Context, current: Owner) {\n        guard accepts(context, current: current), phase == .playing else { return }\n        let bounded = min(totalSegments, max(0, count))\n        guard bounded >= (visibleSegments ?? 0) else { return }\n        visibleSegments = bounded\n        if bounded == totalSegments { complete() }\n    }\n    public mutating func skip(in context: Context, current: Owner) {\n        guard accepts(context, current: current), phase == .playing else { return }\n        complete()\n    }\n    private mutating func complete() {\n        generation = UUID(); phase = .completed; visibleSegments = nil\n    }\n}\n', b'        self.track = Array(normalized.prefix(track.count)); self.places = Array(normalized.dropFirst(track.count))\n    }\n}\n')]}, 'Resources/Localizable.xcstrings': {'after': '31e752ef2c28332983b7b8f813dcfc466a24c9053954ce49c0ea06a6ae13c2c1', 'before': '3cde2e666bef443b0998df2b3dca07f108764e1621d1598f58546a881408519c', 'spans': [(b'    },\n    "roamRouteReplay.start": {\n      "extractionState": "manual",\n      "localizations": {\n        "en": {\n          "stringUnit": {\n            "state": "translated",\n            "value": "Replay saved route"\n          }\n        },\n        "zh-Hans": {\n          "stringUnit": {\n            "state": "translated",\n            "value": "\xe5\x9b\x9e\xe6\x94\xbe\xe5\xb7\xb2\xe4\xbf\x9d\xe5\xad\x98\xe8\xb7\xaf\xe7\xba\xbf"\n          }\n        }\n      }\n    },\n    "roamRouteReplay.again": {\n      "extractionState": "manual",\n      "localizations": {\n        "en": {\n          "stringUnit": {\n            "state": "translated",\n            "value": "Replay again"\n          }\n        },\n        "zh-Hans": {\n          "stringUnit": {\n            "state": "translated",\n            "value": "\xe9\x87\x8d\xe6\x96\xb0\xe5\x9b\x9e\xe6\x94\xbe"\n          }\n        }\n      }\n    },\n    "roamRouteReplay.skip": {\n      "extractionState": "manual",\n      "localizations": {\n        "en": {\n          "stringUnit": {\n            "state": "translated",\n            "value": "Show complete route"\n          }\n        },\n        "zh-Hans": {\n          "stringUnit": {\n            "state": "translated",\n            "value": "\xe8\xb7\xb3\xe5\x88\xb0\xe5\xae\x8c\xe6\x95\xb4\xe8\xb7\xaf\xe7\xba\xbf"\n          }\n        }\n      }\n    },\n    "roamRouteReplay.progress": {\n      "extractionState": "manual",\n      "localizations": {\n        "en": {\n          "stringUnit": {\n            "state": "translated",\n            "value": "Saved route replay progress"\n          }\n        },\n        "zh-Hans": {\n          "stringUnit": {\n            "state": "translated",\n            "value": "\xe5\xb7\xb2\xe4\xbf\x9d\xe5\xad\x98\xe8\xb7\xaf\xe7\xba\xbf\xe5\x9b\x9e\xe6\x94\xbe\xe8\xbf\x9b\xe5\xba\xa6"\n          }\n        }\n      }\n    },\n    "roamRouteReplay.playing": {\n      "extractionState": "manual",\n      "localizations": {\n        "en": {\n          "stringUnit": {\n            "state": "translated",\n            "value": "Replaying this saved route"\n          }\n        },\n        "zh-Hans": {\n          "stringUnit": {\n            "state": "translated",\n            "value": "\xe6\xad\xa3\xe5\x9c\xa8\xe5\x9b\x9e\xe6\x94\xbe\xe6\x9c\xac\xe6\xac\xa1\xe5\xb7\xb2\xe4\xbf\x9d\xe5\xad\x98\xe8\xb7\xaf\xe7\xba\xbf"\n          }\n        }\n      }\n    },\n    "roamRouteReplay.completed": {\n      "extractionState": "manual",\n      "localizations": {\n        "en": {\n          "stringUnit": {\n            "state": "translated",\n            "value": "Route replay complete"\n          }\n        },\n        "zh-Hans": {\n          "stringUnit": {\n            "state": "translated",\n            "value": "\xe8\xb7\xaf\xe7\xba\xbf\xe5\x9b\x9e\xe6\x94\xbe\xe5\xae\x8c\xe6\x88\x90"\n          }\n        }\n      }\n    },\n    "roamRouteReplay.ready": {\n      "extractionState": "manual",\n      "localizations": {\n        "en": {\n          "stringUnit": {\n            "state": "translated",\n            "value": "Complete saved route. Replay when you choose."\n          }\n        },\n        "zh-Hans": {\n          "stringUnit": {\n            "state": "translated",\n            "value": "\xe5\xb7\xb2\xe6\x98\xbe\xe7\xa4\xba\xe5\xae\x8c\xe6\x95\xb4\xe4\xbf\x9d\xe5\xad\x98\xe8\xb7\xaf\xe7\xba\xbf\xef\xbc\x8c\xe5\x8f\xaf\xe9\x9a\x8f\xe6\x97\xb6\xe9\x80\x89\xe6\x8b\xa9\xe5\x9b\x9e\xe6\x94\xbe\xe3\x80\x82"\n          }\n        }\n      }\n    },\n    "templateVenue.scenicArea": {\n', b'    },\n    "templateVenue.scenicArea": {\n')]}}
LIVE_ENTRY_PREFIX_SHA256 = '7851b3627a7933e6ce1100603f0734f50952116a37e176ee6d5f61dca4a02415'
PROTECTED_SHA256 = {'App/RoamHistoryShareView.swift': '252495326401471cf28212a22ee814ffcd41d1739b4fbb48fcfba14c675afa02', 'Core/RoamHistoryStore.swift': '95cbbd6e95b9e2d3bcbd981a6ba29d5daec5cecd59cf462b8053a9320fc965a3', 'Core/RoamExperienceReading.swift': '8d09824483e88d777805f1993564e40524a481462f9038f94c06df56700e7e88', 'Questify.xcodeproj/project.pbxproj': '47564244c59ed3ba8274eebbd2802de774399fab45701cf3991a8bf12f386867', 'Package.swift': '89fefe8ae302c55a9b8853a792f2426d6331eeaa2c1c1b905a77ef6efeac5e2d'}
SWIFT_TEST_SHA256 = 'bee4110b199342c675def44f367f9da180da699124b9cf5f9222e7ad06441e0a'


def project_saved_route_source(path, raw):
    row = SOURCE_INVERSES[path]
    if hashlib.sha256(raw).hexdigest() != row['after']:
        raise AssertionError('Unknown saved-route postimage: ' + path)
    restored = raw
    for after, before in reversed(row['spans']):
        if restored.count(after) != 1:
            raise AssertionError('Missing or repeated saved-route span')
        restored = restored.replace(after, before, 1)
    if hashlib.sha256(restored).hexdigest() != row['before']:
        raise AssertionError('Original saved-route source not restored exactly')
    return restored


def section(source, start, end=None):
    if source.count(start) != 1:
        return ''
    result = source.split(start, 1)[1]
    if end:
        if result.count(end) != 1:
            return ''
        result = result.split(end, 1)[0]
    return result


CORE_MARKERS = {
    'frame_budget': 'public static let maximumFrames = 24',
    'interval': 'public static let intervalNanoseconds: UInt64 = 120_000_000',
    'nonnegative_total': 'let total = max(0, segmentCount)',
    'empty_plan': 'guard total > 0 else { counts = []; return }',
    'frame_count': 'let frames = min(total, Self.maximumFrames)',
    'bounded_step': 'let step = total / frames + (total % frames == 0 ? 0 : 1)',
    'overflow_safe': 'count = total - count <= step ? total : count + step',
    'reader_object': 'readerID = ObjectIdentifier(reader)',
    'session': 'identity = reader.identity',
    'scope_bytes': 'storageKey = identity?.scope.storageKey',
    'config_observation': 'configured = reader.isConfigured',
    'record_identity': 'configured = reader.isConfigured; self.record = record',
    'lifetime_change': 'if self.owner != owner || self.active != active {',
    'retire_to_static': 'generation = UUID(); phase = .ready; visibleSegments = nil',
    'no_degenerate': 'let hasLine = zip(points, points.dropFirst()).contains { pair in pair.0 != pair.1 }',
    'complete_geometry': r'RoamRouteSketch(track: owner.record.track, places: owner.record.pois.map(\.point)).track',
    'degenerate_zero': 'totalSegments = hasLine ? max(0, points.count - 1) : 0',
    'reduced_motion_change': 'if reduceMotion && phase == .playing { complete() }',
    'context_guard': 'guard active, owner == current, totalSegments > 0 else { return nil }',
    'generation_context': 'return Context(owner: current, generation: generation)',
    'acceptance': 'self.context(for: current) == context',
    'single_flight': 'guard accepts(context, current: current), phase != .playing else { return nil }',
    'reduced_motion_start': 'if reduceMotion { phase = .completed; visibleSegments = nil; return nil }',
    'start_zero': 'phase = .playing; visibleSegments = 0',
    'bound_progress': 'let bounded = min(totalSegments, max(0, count))',
    'monotonic': 'guard bounded >= (visibleSegments ?? 0) else { return }',
    'complete_last': 'if bounded == totalSegments { complete() }',
    'retire_terminal': 'generation = UUID(); phase = .completed; visibleSegments = nil',
}
VIEW_MARKERS = {
    'local_record': 'RoamRouteSketchView(record: record, visibleSegments: context == nil ? nil : replay.visibleSegments)',
    'live_owner': 'private var owner: RoamRouteReplayState.Owner { .init(reader: reader, record: record) }',
    'captured_context': 'let context = replay.context(for: current)',
    'single_start': 'if let ticket = replay.start(in: context, current: owner) {',
    'request_capture': 'request = Request(context: ticket, counts: replay.plan.counts)',
    'request_identity': 'let id = UUID()',
    'skip_cancel': 'replay.skip(in: context, current: owner); request = nil',
    'appear': '.onAppear { visible = true; synchronize() }',
    'disappear': '.onDisappear { visible = false; synchronize() }',
    'owner_observer': '.onChange(of: owner) { _, _ in synchronize() }',
    'scene_observer': '.onChange(of: scenePhase) { _, _ in synchronize() }',
    'motion_observer': '.onChange(of: reduceMotion) { _, _ in synchronize() }',
    'one_task': '.task(id: request?.id)',
    'captured_task': 'guard let captured = request else { return }',
    'bounded_frames': 'for (index, count) in captured.counts.enumerated()',
    'first_frame_now': 'if index > 0 {',
    'interval': 'try await Task.sleep(nanoseconds: RoamRouteReplayPlan.intervalNanoseconds)',
    'cancel_exit': 'catch { return }',
    'motion_tick': 'if reduceMotion { synchronize(); return }',
    'active_tick': 'guard !Task.isCancelled, visible, scenePhase == .active,',
    'current_tick': 'replay.accepts(captured.context, current: owner) else { return }',
    'advance_capture': 'replay.advance(to: count, in: captured.context, current: owner)',
    'active_sync': 'replay.update(owner: owner, active: visible && scenePhase == .active, reduceMotion: reduceMotion)',
    'retire_task': 'if let captured = request, !replay.accepts(captured.context, current: owner) { request = nil }',
    'progress': 'ProgressView(value: replay.progress, total: 1)',
    'progress_label': '.accessibilityLabel(Text("roamRouteReplay.progress"))',
    'progress_value': '.accessibilityValue(Text(replay.progress, format: .percent.precision(.fractionLength(0))))',
    'localized_button': 'Button(LocalizedStringKey(replay.phase == .completed ? "roamRouteReplay.again" : "roamRouteReplay.start")',
}
DETAIL_MARKERS = {
    'owner_read': 'private var readKey: ReadKey { .init(owner: .init(reader: reader), timestamp: timestamp) }',
    'mask_record': 'private var currentRecord: RoamHistoryRecord? { loadedOwner == readKey ? record : nil }',
    'mask_error': 'private var currentError: Error? { loadedOwner == readKey ? error : nil }',
    'mask_loaded': 'private var currentLoaded: Bool { loadedOwner == readKey && loaded }',
    'replay_detail_only': 'RoamSavedRouteReplayView(reader: reader, record: record)',
    'full_read_key': '.task(id: readKey) { showShare = false; load() }',
    'retire_share': '.onChange(of: readKey) { _, _ in showShare = false }',
    'share_current': '.sheet(isPresented: $showShare) { if let record = currentRecord {',
    'read_capture': 'let captured = readKey',
    'read_local': 'let value = try reader.history().first { $0.ts == timestamp }',
    'read_assign': 'record = value; loaded = true; loadedOwner = captured',
}


def core_contract(source):
    code = section(source, 'public struct RoamRouteReplayPlan:')
    errors = [name for name, marker in CORE_MARKERS.items() if code.count(marker) != 1]
    if code.count('guard accepts(context, current: current), phase == .playing else { return }') != 2:
        errors.append('advance_and_skip_authority')
    if code.count('generation = UUID()') != 4:
        errors.append('generation_retirement')
    for token in ['Task', 'Timer(', 'Timer.', 'reader.history(', 'URLSession', 'CLLocation', 'write(', 'save(', 'startSession', 'resumeSession']:
        if token in code:
            errors.append('pure_display_only')
    return errors


def replay_contract(source):
    code = section(source, '@MainActor struct RoamSavedRouteReplayView:')
    errors = [name for name, marker in VIEW_MARKERS.items() if code.count(marker) != 1]
    if code.count('guard replay.accepts(context, current: owner) else { return }') != 2:
        errors.append('both_captured_button_guards')
    if code.count('.frame(minHeight: 44)') != 2:
        errors.append('button_targets')
    task = section(code, '.task(id: request?.id)', '        .accessibilityElement(children: .contain)')
    if not task or 'request = nil' in task or 'defer {' in task:
        errors.append('old_finish_cannot_clear_new')
    for token in ['reader.history(', 'reader.sessionFact(', 'URLSession', 'CLLocation', 'MKDirections', 'ShareLink(', 'UserDefaults', 'write(', 'save(', 'startSession', 'resumeSession', 'UIAccessibility.post']:
        if token in code:
            errors.append('no_external_effect')
    return errors


def detail_contract(source):
    code = section(source, '@MainActor struct RoamHistoryDetailView:')
    errors = [name for name, marker in DETAIL_MARKERS.items() if code.count(marker) != 1]
    if code.count('guard captured == readKey else { return }') != 2:
        errors.append('both_read_acceptance_guards')
    if code.count('reader.history()') != 1:
        errors.append('one_local_read')
    return errors


class RoamRouteReplaySourceContracts(unittest.TestCase):
    def test_raw_shipping_sources_satisfy_forward_contracts(self):
        for path, check in [('Core/RoamExperienceMath.swift', core_contract), ('App/RoamExperienceComponents.swift', replay_contract), ('App/RoamHistoryViews.swift', detail_contract)]:
            self.assertEqual(check((ROOT / path).read_text()), [])

    def test_actual_old_sources_do_not_satisfy_new_replay_contract(self):
        for path, check in [('Core/RoamExperienceMath.swift', core_contract), ('App/RoamExperienceComponents.swift', replay_contract), ('App/RoamHistoryViews.swift', detail_contract)]:
            prior = project_saved_route_source(path, (ROOT / path).read_bytes())
            self.assertTrue(check(prior.decode()))

    def test_each_core_owner_lifetime_budget_and_motion_guard_has_mutation(self):
        source = (ROOT / 'Core/RoamExperienceMath.swift').read_text()
        for name, marker in CORE_MARKERS.items():
            with self.subTest(guard=name):
                self.assertEqual(source.count(marker), 1)
                self.assertIn(name, core_contract(source.replace(marker, '', 1)))
        guard = 'guard accepts(context, current: current), phase == .playing else { return }'
        for offset in [source.index(guard), source.rindex(guard)]:
            self.assertIn('advance_and_skip_authority', core_contract(source[:offset] + source[offset:].replace(guard, '', 1)))

    def test_each_view_task_owner_capture_cancel_motion_and_accessibility_guard_has_mutation(self):
        source = (ROOT / 'App/RoamExperienceComponents.swift').read_text()
        for name, marker in VIEW_MARKERS.items():
            with self.subTest(guard=name):
                self.assertEqual(source.count(marker), 1)
                self.assertIn(name, replay_contract(source.replace(marker, '', 1)))
        guard = 'guard replay.accepts(context, current: owner) else { return }'
        for offset in [source.index(guard), source.rindex(guard)]:
            self.assertIn('both_captured_button_guards', replay_contract(source[:offset] + source[offset:].replace(guard, '', 1)))
        changed = source.replace('// No old-task cleanup can clear a later request.', 'request = nil')
        self.assertIn('old_finish_cannot_clear_new', replay_contract(changed))

    def test_detail_read_masks_and_task_key_have_mutation_controls(self):
        source = (ROOT / 'App/RoamHistoryViews.swift').read_text()
        for name, marker in DETAIL_MARKERS.items():
            with self.subTest(guard=name):
                self.assertEqual(source.count(marker), 1)
                self.assertIn(name, detail_contract(source.replace(marker, '', 1)))
        guard = 'guard captured == readKey else { return }'
        for offset in [source.index(guard), source.rindex(guard)]:
            self.assertIn('both_read_acceptance_guards', detail_contract(source[:offset] + source[offset:].replace(guard, '', 1)))

    def test_replay_side_effects_are_rejected(self):
        core = (ROOT / 'Core/RoamExperienceMath.swift').read_text()
        view = (ROOT / 'App/RoamExperienceComponents.swift').read_text()
        for token in ['reader.history()', 'URLSession.shared', 'CLLocationManager()', 'save()', 'startSession()', 'resumeSession()']:
            self.assertIn('pure_display_only', core_contract(core + token))
            self.assertIn('no_external_effect', replay_contract(view + token))
        self.assertIn('no_external_effect', replay_contract(view + 'UIAccessibility.post(notification: .announcement)'))

    def test_source_inverses_are_exact_and_fail_closed_for_drift_crlf_and_spans(self):
        for path, row in SOURCE_INVERSES.items():
            raw = (ROOT / path).read_bytes()
            old = project_saved_route_source(path, raw)
            self.assertEqual(hashlib.sha256(old).hexdigest(), row['before'])
            for bad in [old, raw + b'\n', raw[:-1], raw.replace(b'\n', b'\r\n')]:
                with self.assertRaises(AssertionError): project_saved_route_source(path, bad)
            # Every byte of the three Swift production files; catalog hunk bytes
            # plus first/middle/last byte probes, with a full-file hash on every call.
            positions = range(len(raw)) if path.endswith('.swift') else [0, len(raw)//2, len(raw)-1]
            for index in positions:
                changed = raw[:index] + bytes([raw[index] ^ 1]) + raw[index + 1:]
                with self.assertRaises(AssertionError): project_saved_route_source(path, changed)
            for after, before in row['spans']:
                self.assertEqual(raw.count(after), 1)
                for changed in [raw.replace(after, b'', 1), raw + after, raw.replace(after, before, 1)]:
                    with self.assertRaises(AssertionError): project_saved_route_source(path, changed)

    def test_inverse_table_missing_duplicate_and_wrong_old_bytes_are_rejected(self):
        for path, row in SOURCE_INVERSES.items():
            raw = (ROOT / path).read_bytes(); after, before = row['spans'][0]
            for spans in [row['spans'][1:], row['spans'] + [row['spans'][0]], [(after, before + b'x')] + row['spans'][1:]]:
                with patch.dict(SOURCE_INVERSES, {path: {**row, 'spans': spans}}):
                    with self.assertRaises(AssertionError): project_saved_route_source(path, raw)

    def test_history_live_entry_prefix_remains_byte_identical(self):
        raw = (ROOT / 'App/RoamHistoryViews.swift').read_bytes()
        prefix = raw.split(b'@MainActor struct RoamHistoryDetailView:', 1)[0]
        self.assertEqual(hashlib.sha256(prefix).hexdigest(), LIVE_ENTRY_PREFIX_SHA256)
        self.assertIn(b'RoamRouteSketchView(record: record)', prefix)
        self.assertIn(b'RoamHistoryDetailView(reader: reader, timestamp: record.ts)', prefix)

    def test_geometry_and_static_callers_keep_full_record_scale_and_default(self):
        source = (ROOT / 'App/RoamExperienceComponents.swift').read_text()
        sketch = section(source, 'struct RoamRouteSketchView:', 'struct RoamRecordedStats:')
        self.assertIn('var visibleSegments: Int? = nil', sketch)
        self.assertIn(r'let sketch = RoamRouteSketch(track: record.track, places: record.pois.map(\.point))', sketch)
        self.assertIn('sketch.track.prefix(pointCount).enumerated()', sketch)
        self.assertIn('for point in sketch.places', sketch)
        self.assertNotIn('RoamRouteSketch(track: record.track.prefix', sketch)
        core = (ROOT / 'Core/RoamExperienceMath.swift').read_bytes()
        prior = project_saved_route_source('Core/RoamExperienceMath.swift', core)
        self.assertEqual(core.split(b'\n/// A bounded local display schedule;', 1)[0],
                         prior.split(b'\n/// P128 local share projection only.', 1)[0])
        self.assertEqual(core.split(b'public enum RoamShareRoutePrivacy {', 1)[1],
                         prior.split(b'public enum RoamShareRoutePrivacy {', 1)[1])
        share = (ROOT / 'App/RoamHistoryShareView.swift').read_text()
        self.assertIn('if includeRoute { privateRoute }', share)
        self.assertIn('let sketch = RoamShareRoutePrivacy.sketch(for: record)', share)
        self.assertIn('@State private var includeRoute = false', share)
        self.assertNotIn('RoamRouteSketchView(record: record)', share)
        self.assertNotIn('RoamSavedRouteReplayView', share)

    def test_catalog_only_adds_seven_exclusive_bilingual_keys(self):
        path = 'Resources/Localizable.xcstrings'; raw = (ROOT / path).read_bytes()
        old = json.loads(project_saved_route_source(path, raw)); now = json.loads(raw)
        additions = set(now['strings']) - set(old['strings'])
        expected = {'roamRouteReplay.' + name for name in ['start', 'again', 'skip', 'progress', 'playing', 'completed', 'ready']}
        self.assertEqual(additions, expected)
        self.assertEqual({k:v for k,v in now['strings'].items() if k not in additions}, old['strings'])
        for key in additions:
            self.assertEqual(set(now['strings'][key]['localizations']), {'en', 'zh-Hans'})
            for language in ['en', 'zh-Hans']:
                self.assertTrue(now['strings'][key]['localizations'][language]['stringUnit']['value'])
        now['strings'] = {k:v for k,v in now['strings'].items() if k not in additions}
        self.assertEqual(now, old)

    def test_only_authored_controller_cases_not_runtime_claim(self):
        source = (ROOT / 'Tests/CoreTests/RoamRouteReplayTests.swift').read_bytes()
        self.assertEqual(hashlib.sha256(source).hexdigest(), SWIFT_TEST_SHA256)
        self.assertEqual(len(re.findall(rb'\bfunc test\w+\(', source)), 17)
        self.assertIn(b'Reader: RoamExperienceReading', source)
        self.assertIn(b'XCTAssertEqual(reader.historyReads, 0)', source)

    def test_underlying_history_store_reader_share_and_registration_unchanged(self):
        from Tests.ContractChecks.test_category_roam_registration import checked_current, CONTRACT_PATH
        checked_current((ROOT / CONTRACT_PATH).read_bytes(), ROOT)
        for path, expected in PROTECTED_SHA256.items():
            self.assertEqual(hashlib.sha256((ROOT / path).read_bytes()).hexdigest(), expected, path)
        project = (ROOT / 'Questify.xcodeproj/project.pbxproj').read_text()
        for path in ['App/RoamHistoryShareView.swift', 'Core/RoamExperienceMath.swift']:
            self.assertEqual(project.count('"path" = "' + path + '";'), 1)
        for path in ['Tests/ContractChecks/test_search_map_layer_retry.py', 'Tests/CoreTests/SearchMapLayerRetryTests.swift']:
            self.assertFalse((ROOT / path).exists())

    def test_public_discovery_requires_no_private_sources(self):
        runner = (ROOT / 'tools/run_static_checks.py').read_text()
        self.assertIn("'contracts': {'directory': 'Tests/ContractChecks', 'pattern': 'test_*.py'}", runner)
        self.assertTrue(Path(__file__).name.startswith('test_'))
        self.assertIn('path: "Tests/CoreTests"', (ROOT / 'Package.swift').read_text())


if __name__ == '__main__':
    unittest.main()
