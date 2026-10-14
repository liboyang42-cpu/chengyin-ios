import Foundation

/// Author-only virtual inputs. No sensor stream, completion proof or payload is exposed.
public struct TemplateSensorRehearsal: Equatable {
    public enum Feedback: String { case ready, aligned, turn, inaccurate, loud, quiet, matched }
    public let game: TemplateAdvancedGame
    public let title: String
    public private(set) var feedback: Feedback = .ready
    private var compass: PlayKitCompassRun
    private var shout: PlayKitShoutRun
    private var tick = 0
    public var targetBearing: Double { compass.target }
    public var tolerance: Double { compass.tolerance }
    public var duration: Double { game == .compass ? compass.holdSeconds : shout.targetSeconds }
    public var heldSeconds: Double { game == .compass ? compass.heldSeconds : shout.heldSeconds }
    public var loudThreshold: Double { shout.loudThreshold }
    public var finished: Bool { feedback == .matched }

    public init?(_ draft: TemplateAdvancedDraft, game: TemplateAdvancedGame) {
        guard game == .compass || game == .shout, draft.enabled(game.section),
              draft.miniGameIssues(game).isEmpty, let segment = try? draft.miniPreviewSegment(game) else { return nil }
        self.game = game; title = segment["kicker"].text ?? ""
        compass = .init(target: segment["bearing"].double ?? 0,
                        tolerance: segment["tolerance"].double ?? 15, holdSeconds: segment["holdSeconds"].double ?? 3)
        shout = .init(seconds: segment["seconds"].double ?? 5)
        reset()
    }
    public mutating func reset() {
        tick = 0; feedback = .ready
        if game == .compass { compass.begin() }
        else {
            // Fixed virtual quiet baseline is visibly identified by the author UI.
            shout.calibrate()
            for value in 0...25 { shout.ingest(peak: 0.1, timestamp: Double(value) / 10) }
            tick = 26; shout.beginAfterAcknowledgement()
        }
    }
    /// One explicit author click advances one virtual second, never real elapsed time.
    @discardableResult public mutating func advance(bearing: Double, accuracy: Double, peak: Double) -> Bool {
        guard !finished, bearing.isFinite, (0..<360).contains(bearing), accuracy.isFinite,
              (0...180).contains(accuracy), peak.isFinite, (0...1).contains(peak) else { return false }
        for _ in 0..<10 {
            tick += 1
            if game == .compass { compass.ingest(bearing: bearing, accuracy: accuracy, timestamp: Double(tick) / 10) }
            else { shout.ingest(peak: peak, timestamp: Double(tick) / 10) }
        }
        if game == .compass {
            feedback = compass.phase == .measured ? .matched : compass.lowAccuracy ? .inaccurate : compass.aligned ? .aligned : .turn
        } else { feedback = shout.phase == .measured ? .matched : shout.loud ? .loud : .quiet }
        return true
    }
}
