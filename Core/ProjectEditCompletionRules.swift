import Foundation

/// Theme-level mini publish contract, not the node advanced-game `bingo` segment.
/// Grid conditions are server-owned. Cells remain in physical position order on the wire.
public struct ProjectEditCompletionRules: Codable, Equatable {
    public struct Cell: Codable, Equatable {
        public var label = ""
        public var couponID = ""
        public var feedbackText = ""
        public init() {}
    }
    public static let displayOrder = [0, 1, 2, 5, 4, 3, 6, 7, 8]
    public var mode = "ALL"
    public var requiredCount = "1"
    public var bingoEnabled = false
    public var cells = Array(repeating: Cell(), count: 9)
    public private(set) var readOnly = false
    private var source: ProjectEditJSON?
    private var root: [String: ProjectEditJSON] = [:]

    public init(raw: ProjectEditJSON?) {
        source = raw
        guard let raw, raw != .null, raw != .string("") else { return }
        guard let text = raw.text, let data = text.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(ProjectEditJSON.self, from: data), let object = decoded.object else {
            readOnly = true; return
        }
        root = object
        if let value = root["nodeCompletion"] {
            guard let rule = value.object, let value = rule["mode"]?.text,
                  ["ALL", "AT_LEAST"].contains(value),
                  Set(rule.keys).isSubset(of: value == "ALL" ? ["mode"] : ["mode", "requiredCount"]) else { readOnly = true; return }
            mode = value
            if mode == "AT_LEAST" {
                guard let count = rule["requiredCount"]?.integer, count > 0 else { readOnly = true; return }
                requiredCount = String(count)
            }
        }
        if let value = root["bingo"] {
            guard let bingo = value.object, Set(bingo.keys).isSubset(of: ["enabled", "cells"]),
                  bingo["enabled"] == .bool(true) || bingo["enabled"] == .bool(false) else { readOnly = true; return }
            bingoEnabled = bingo["enabled"] == .bool(true)
            guard let rows = bingo["cells"]?.array, rows.count == 9 else { readOnly = true; return }
            for (index, value) in rows.enumerated() {
                guard let row = value.object, Set(row.keys).isSubset(of: ["label", "couponId", "feedbackText"]),
                      row["label"] == nil || row["label"]?.text != nil,
                      row["feedbackText"] == nil || row["feedbackText"]?.text != nil else { readOnly = true; return }
                cells[index].label = row["label"]?.text ?? ""
                cells[index].feedbackText = row["feedbackText"]?.text ?? ""
                if let coupon = row["couponId"] {
                    guard let id = coupon.integer, id >= 0 else { readOnly = true; return }
                    cells[index].couponID = id > 0 ? String(id) : ""
                }
            }
        }
    }

    public func forProduct(_ product: ProjectEditProduct) -> Self {
        var result = self
        if product == .freeExplore && !readOnly { result.mode = "ALL" }
        return result
    }

    public var issueKey: String? {
        if readOnly { return nil } // Unsupported source is retained exactly, never normalized.
        guard ["ALL", "AT_LEAST"].contains(mode), mode != "AT_LEAST" || (Int(requiredCount) ?? 0) > 0 else { return "projectEdit.completion.invalidCount" }
        guard !bingoEnabled || cells.count == 9 else { return "projectEdit.completion.invalidCells" }
        if bingoEnabled {
            var reward = false
            for cell in cells {
                guard trimmed(cell.label).utf16.count <= 24, trimmed(cell.feedbackText).utf16.count <= 120 else { return "projectEdit.completion.invalidLength" }
                let coupon = trimmed(cell.couponID)
                guard coupon.isEmpty || (Int(coupon) != nil && (Int(coupon) ?? -1) >= 0) else { return "projectEdit.completion.invalidCoupon" }
                reward = reward || (Int(coupon) ?? 0) > 0 || !trimmed(cell.feedbackText).isEmpty
            }
            if !reward { return "projectEdit.completion.rewardRequired" }
        }
        return nil
    }

    public func validationIssue(totalNodes: Int) -> String? {
        if readOnly { return nil }
        if let issueKey { return issueKey }
        if mode == "AT_LEAST", (Int(requiredCount) ?? 0) > totalNodes { return "projectEdit.completion.tooManyNodes" }
        if (try? serialized(matching: source)) == nil { return "projectEdit.completion.tooLarge" }
        return nil
    }

    /// Binds restored edits to the exact imported source. Existing coordinator owns CAS,
    /// immutable review, account epoch and dispatch; no new write route is introduced.
    public func serialized(matching original: ProjectEditJSON?) throws -> ProjectEditJSON? {
        guard source == original else { throw ProjectEditError.invalidDraft }
        if readOnly { return source }
        guard issueKey == nil else { throw ProjectEditError.invalidDraft }
        var result = root
        result["nodeCompletion"] = mode == "AT_LEAST"
            ? .object(["mode": .string(mode), "requiredCount": .number(Decimal(Int(requiredCount)!))])
            : .object(["mode": .string("ALL")])
        if bingoEnabled {
            result["bingo"] = .object(["enabled": .bool(true), "cells": .array(cells.map { cell in
                var row: [String: ProjectEditJSON] = ["label": .string(trimmed(cell.label))]
                if let id = Int(trimmed(cell.couponID)), id > 0 { row["couponId"] = .number(Decimal(id)) }
                let feedback = trimmed(cell.feedbackText)
                if !feedback.isEmpty { row["feedbackText"] = .string(feedback) }
                return .object(row)
            })])
        } else { result.removeValue(forKey: "bingo") }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(ProjectEditJSON.object(result))
        guard data.count <= 16 * 1024 else { throw ProjectEditError.invalidDraft }
        return .string(String(decoding: data, as: UTF8.self))
    }
    private func trimmed(_ value: String) -> String { value.trimmingCharacters(in: .whitespacesAndNewlines) }
}
