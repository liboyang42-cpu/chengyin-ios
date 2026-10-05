import SwiftUI

extension PlayKitScreen {
    @ViewBuilder var coinFace: some View {
        let side = (raw["side"].text ?? "").uppercased()
        let key = ["HEADS", "H", "正面"].contains(side) ? "heads" : ["TAILS", "T", "反面"].contains(side) ? "tails" : ""
        Image(systemName: key.isEmpty ? "circle.dashed" : "circle.inset.filled").font(.system(size: 100)).frame(maxWidth: .infinity).accessibilityHidden(true)
        if !key.isEmpty {
            Text(verbatim: raw[key]["label"].text ?? side).font(.largeTitle.bold()).frame(maxWidth: .infinity)
            if let action = raw[key]["action"].text, !action.isEmpty { Text(verbatim: action) }
        } else { Text("playkit.coin.waiting") }
        HStack(alignment: .top) {
            ForEach(["heads", "tails"], id: \.self) { face in
                VStack(alignment: .leading) {
                    Text(verbatim: raw[face]["label"].text ?? "").font(.headline)
                    if let action = raw[face]["action"].text { Text(verbatim: action) }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        Button("playkit.coin.flip") { prepare("FLIP_COIN") }.buttonStyle(.borderedProminent).disabled(!enabled)
    }
    @ViewBuilder var diceFaces: some View {
        let values = (raw["pips"].array ?? []).compactMap(\.integer)
        let d20 = raw["mode"].text == "d20"
        HStack {
            ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                if !d20 && (1...6).contains(value) { Image(systemName: "die.face.\(value).fill").font(.system(size: 72)).accessibilityLabel(Text(verbatim: String(value))) }
                else { Text(verbatim: String(value)).font(.system(.largeTitle, design: .rounded).bold()).padding().background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16)) }
            }
        }.frame(maxWidth: .infinity)
        if values.isEmpty { Text("playkit.dice.waiting") }
        if let action = raw["action"].text, !action.isEmpty { Text(verbatim: action) }
        if let total = projection.diceTotal { LabeledContent("playkit.dice.total") { Text(verbatim: String(total)).accessibilityIdentifier("playkit.dice.total") } }
        if let kept = raw["kept"].integer { LabeledContent("playkit.dice.kept") { Text(verbatim: String(kept)) } }
        if d20, let dc = raw["dc"].integer { LabeledContent("playkit.dice.target") { Text(verbatim: String(dc)) } }
        if d20, projection.complete, let success = raw["success"].bool { Text(success ? "playkit.result.passed" : "playkit.result.notPassed") }
        if !d20, values.count == 1, let pip = values.first, let faces = raw["faces"].array, faces.indices.contains(pip - 1), let task = faces[pip - 1].text { Text(verbatim: task) }
        Button("playkit.dice.roll") { prepare("ROLL_DICE") }.buttonStyle(.borderedProminent).disabled(!enabled)
    }
    @ViewBuilder var randomDeck: some View {
        if let name = raw["deckName"].text { Text(verbatim: name).font(.title2.bold()) }
        let drawn = raw["drawn"].array ?? [], count = raw["drawCount"].integer ?? 0
        ForEach(Array(drawn.enumerated()), id: \.offset) { index, card in
            VStack(alignment: .leading, spacing: 12) {
                Text(verbatim: "\(index + 1)").font(.caption)
                if let label = card["label"].text { Text(verbatim: label).font(.title2.bold()) }
                if let content = card["content"].text { Text(verbatim: content) }
            }.padding().frame(maxWidth: .infinity, alignment: .leading).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
        }
        if count > drawn.count {
            Image(systemName: "rectangle.stack").font(.system(size: 80)).frame(maxWidth: .infinity).accessibilityHidden(true)
            LabeledContent("playkit.random.remaining") { Text(verbatim: String(count - drawn.count)) }
        }
        Button("playkit.random.draw") { prepare("DRAW") }.buttonStyle(.borderedProminent).disabled(!enabled || count <= drawn.count)
    }
    @ViewBuilder var dailySignForm: some View {
        if let address = raw["address"].text { Text(verbatim: address).font(.headline) }
        ForEach(Array((raw["lines"].array ?? []).enumerated()), id: \.offset) { _, line in
            if let value = line.text { Text(verbatim: value).font(.title2) }
        }
        if let signer = raw["signer"].text, !signer.isEmpty { Text(verbatim: signer).foregroundStyle(.secondary) }
        if let date = raw["leftAt"].text, !date.isEmpty { Text(verbatim: date).font(.caption) }
        artwork(raw["photoUrl"].text)
        let limit = max(1, raw["textMax"].integer ?? 40)
        TextField("playkit.daily.message", text: textBinding(limit: limit), axis: .vertical).textFieldStyle(.roundedBorder).disabled(!enabled)
        Text("playkit.daily.audience").font(.footnote)
        submitButton("CLAIM_DAILY_SIGN", payload: ["text": .string(text), "photoUrl": .string(avatarURL)], valid: !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
    @ViewBuilder var walkProgress: some View {
        if let steps = raw["todaySteps"].integer, steps >= 0 {
            LabeledContent("playkit.walk.steps") { Text(verbatim: steps.formatted()).font(.largeTitle.monospacedDigit()) }
            if let goal = raw["goal"].integer, goal > 0 {
                ProgressView(value: Double(min(steps, goal)), total: Double(goal)).accessibilityLabel(Text("playkit.walk.progress"))
                LabeledContent("playkit.walk.remaining") { Text(verbatim: max(0, goal - steps).formatted()) }
            }
        } else { Text("playkit.walk.noReading") }
        if let goal = raw["goal"].integer, goal > 0 { LabeledContent("playkit.walk.goal") { Text(verbatim: goal.formatted()) } }
        Text("playkit.walk.goalLocked").font(.footnote)
        Label("playkit.walk.providerGate", systemImage: "lock.shield")
        // No native pedometer value substitutes for the service's WeChat encrypted proof.
        Button("playkit.walk.sync") {}.disabled(true)
    }
    @ViewBuilder var bingoBoard: some View {
        let board = PlayKitBingoBoard(raw)
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .top), count: 3), spacing: 12) {
            ForEach(0..<9, id: \.self) { index in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(verbatim: String(index + 1)).font(.caption)
                        Spacer()
                        Image(systemName: board.filled.contains(index) ? "checkmark.circle.fill" : "circle")
                    }
                    Text(verbatim: board.title(at: index)).font(.headline).fixedSize(horizontal: false, vertical: true)
                    Text(verbatim: board.instruction(at: index)).font(.caption).fixedSize(horizontal: false, vertical: true)
                    if board.linePositions.contains(index) { Text("playkit.bingo.inLine").font(.caption) }
                }.padding(10).frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
                    .background(board.filled.contains(index) ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityElement(children: .combine)
                    .accessibilityValue(Text(board.filled.contains(index) ? "playkit.bingo.filled" : "playkit.bingo.empty"))
            }
        }
        LabeledContent("playkit.bingo.lines") { Text(verbatim: String(board.completedLines.count)) }
        if let line = raw["lineReward"].text, !line.isEmpty { LabeledContent("playkit.bingo.lineReward") { Text(verbatim: line) } }
        if let full = raw["fullReward"].text, !full.isEmpty { LabeledContent("playkit.bingo.fullReward") { Text(verbatim: full) } }
        Text("playkit.bingo.authority").font(.footnote)
    }
}
