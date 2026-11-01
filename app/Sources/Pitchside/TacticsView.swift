import SwiftUI
import PitchsideCore

// MARK: - Formation & roles

/// The shapes that suit your squad best, each with the best IP/OOP role per player.
struct FormationsPane: View {
    @Environment(Store.self) private var store
    var onUse: () -> Void = {}

    var body: some View {
        HSplitView {
            list.frame(minWidth: 250, idealWidth: 280, maxWidth: 340)
            if let fit = store.tacticsFit {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        summary(fit)
                        TacticsPitch(fit: fit, scale: store.squadScale).frame(maxWidth: 560).frame(maxWidth: .infinity)
                        picksTable(fit)
                        bench(fit)
                    }
                    .padding(14)
                }
                .frame(minWidth: 520)
            }
        }
    }

    private var list: some View {
        let best = store.tacticsFits.first?.formation.name
        return List(selection: Binding(get: { store.tacticsFit?.formation.name },
                                       set: { store.tacticsChoice = $0 })) {
            SwiftUI.Section {
                ForEach(store.tacticsFits) { f in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(f.formation.name).font(.callout.weight(.semibold))
                            Text(detail(f)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(String(format: "%.1f", f.level)).bold().monospacedDigit()
                            .foregroundStyle(store.scoreColor(f.level))
                        Text("\(Int(TeamCompare.rating(f.level).rounded()))").monospacedDigit()
                            .foregroundStyle(.secondary).frame(minWidth: 24, alignment: .trailing)
                            .help("Rating (0–100)")
                        Image(systemName: "crown.fill").foregroundStyle(f.formation.name == best ? Theme.gold : .clear)
                            .help(f.formation.name == best ? "Best fit: highest level, fewest players out of position, then depth" : "")
                    }
                    .tag(f.formation.name)
                }
            } header: {
                HStack {
                    Text("Best shapes for your squad")
                    Spacer()
                    Text("Level").help("XI level (1–20): average position score of the best eleven")
                    Text("Rating").frame(minWidth: 24, alignment: .trailing).help("XI level on 0–100")
                    Image(systemName: "crown.fill").foregroundStyle(.clear)
                }
            }
        }
    }

    private func detail(_ f: TacticsAdvisor.FormationFit) -> String {
        var s = String(format: "depth %.1f", f.depth)
        if f.outOfPosition > 0 { s += " · \(f.outOfPosition) out of position" }
        return s
    }

    private func summary(_ fit: TacticsAdvisor.FormationFit) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Stat(title: "XI level", value: String(format: "%.1f", fit.level), color: AttrColor.color(Int(fit.level.rounded())))
                Stat(title: "Rating", value: "\(Int(TeamCompare.rating(fit.level).rounded()))", color: AttrColor.color(Int(fit.level.rounded())))
                    .help(TeamCompare.metric("rating")?.explanation ?? "")
                Stat(title: "Depth", value: String(format: "%.1f", fit.depth), color: AttrColor.color(Int(fit.depth.rounded())))
                Stat(title: "Out of position", value: "\(fit.outOfPosition)", color: fit.outOfPosition > 0 ? .orange : .green)
            }
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Button {
                    store.useFormation(fit.formation)
                    onUse()
                } label: {
                    Label("Use as my tactic", systemImage: "arrow.right.circle.fill")
                }
                .help("Copies this shape and these IP/OOP roles into My tactic, where you can change anything")
                Text("Roles are scored like FM27's role stars: key attributes, then preferable ones, a little for the rest. A position blends 60% IP and 40% OOP.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func picksTable(_ fit: TacticsAdvisor.FormationFit) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
            GridRow {
                Text("Pos"); Text("Player"); Text("In possession"); Text("Out of possession"); Text("Score"); Text("Also good")
            }
            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Divider().gridCellUnsizedAxes(.horizontal)
            ForEach(fit.picks) { p in
                GridRow {
                    Text(p.slot.label).font(.callout.weight(.semibold))
                    HStack(spacing: 4) {
                        Text(p.player?.name ?? "—").lineLimit(1)
                        if p.player != nil && p.familiarity < 15 {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                                .help("Not a natural \(p.slot.position) (familiarity \(p.familiarity))")
                        }
                    }
                    roleCell(p.slot.role, p.ipScore)
                    roleCell(p.slot.oop, p.oopScore)
                    Text(String(format: "%.1f", p.score)).bold().monospacedDigit()
                        .foregroundStyle(store.scoreColor(p.score))
                    Text(p.alternatives.map { "\(Roles.role($0.code)?.name ?? $0.code) \(String(format: "%.1f", $0.score))" }
                        .joined(separator: ", "))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                .font(.callout)
            }
        }
        .fmCard()
    }

    private func roleCell(_ code: String, _ score: Double) -> some View {
        HStack(spacing: 4) {
            Text(Roles.role(code)?.name ?? "—").lineLimit(1)
            Text(String(format: "%.1f", score)).monospacedDigit().foregroundStyle(store.scoreColor(score))
        }
    }

    private func bench(_ fit: TacticsAdvisor.FormationFit) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("BENCH (BEST OF THE REST)").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            FlowLayout(spacing: 6) {
                ForEach(fit.bench) { r in
                    HStack(spacing: 4) {
                        Text(r.name).lineLimit(1)
                        Text(r.positions.split(separator: ",").first.map(String.init) ?? "").foregroundStyle(.secondary)
                        Text(String(format: "%.1f", r.bestRoleScore)).monospacedDigit()
                            .foregroundStyle(store.scoreColor(r.bestRoleScore))
                    }
                    .font(.caption)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Theme.panelAlt, in: Capsule())
                }
            }
        }
        .fmCard()
    }
}

/// The suggested XI on a pitch.
struct TacticsPitch: View {
    let fit: TacticsAdvisor.FormationFit
    var scale: ScoreScale? = nil

    var body: some View {
        let points = PitchLayout.points(for: fit.picks.map(\.slot))
        GeometryReader { geo in
            ZStack {
                PitchBackground()
                ForEach(fit.picks) { p in
                    if let pt = points[p.slot.label] {
                        marker(p).position(x: pt.x * geo.size.width, y: pt.y * geo.size.height)
                    }
                }
            }
        }
        .aspectRatio(0.72, contentMode: .fit)
    }

    private func marker(_ p: TacticsAdvisor.Pick) -> some View {
        VStack(spacing: 1) {
            Text(p.player.map { short($0.name) } ?? "—")
                .font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
            Text(Roles.role(p.slot.role)?.name ?? p.slot.role)
                .font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.gold).lineLimit(1).minimumScaleFactor(0.7)
            Text(Roles.role(p.slot.oop)?.name ?? "")
                .font(.system(size: 8.5)).foregroundStyle(.white.opacity(0.7)).lineLimit(1).minimumScaleFactor(0.7)
            Text(p.player == nil ? "empty" : String(format: "%.1f", p.score))
                .font(.system(size: 10, weight: .bold)).monospacedDigit()
                .foregroundStyle(p.player == nil ? Color.red : RelColor.color(p.score, scale))
        }
        .padding(.horizontal, 5).padding(.vertical, 3)
        .frame(width: 104)
        .background(Color.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(p.familiarity < 15 && p.player != nil ? Color.orange : .clear))
    }

    private func short(_ n: String) -> String {
        let parts = n.split(separator: " ")
        return parts.count > 1 ? "\(parts[0].prefix(1)). \(parts.dropFirst().joined(separator: " "))" : n
    }
}

// MARK: - Set pieces & captain

struct SetPiecesPane: View {
    @Environment(Store.self) private var store

    var body: some View {
        ScrollView {
            if let sp = store.tacticsSetPieces {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        SourcePicker()
                        Text("Penalties also look at the bench. Set these in FM under Tactics → Set Pieces.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 330), spacing: 12, alignment: .top)], spacing: 12) {
                        card("Captain", "person.badge.shield.checkmark.fill", sp.captains, ["Captain", "Vice-captain", "Third"])
                        card("Penalties", "target", sp.penalties, ["1st", "2nd", "3rd", "4th", "5th"])
                        card("Corners — left side", "arrow.turn.up.right", sp.leftCorners, ["Taker", "Alt", "Alt"],
                             subtitle: "Inswingers from the left need a right-footed taker")
                        card("Corners — right side", "arrow.turn.up.left", sp.rightCorners, ["Taker", "Alt", "Alt"],
                             subtitle: "Inswingers from the right need a left-footed taker")
                        card("Free kicks — shots", "scope", sp.directFreeKicks, ["Taker", "Alt", "Alt"])
                        card("Free kicks — crosses", "arrow.up.forward", sp.crossedFreeKicks, ["Taker", "Alt", "Alt"])
                        card("Attack the ball", "arrow.up.circle.fill", sp.aerialTargets, ["Target", "Target", "Target", "Alt"])
                        card("Stay back on corners", "shield.lefthalf.filled", sp.stayBack, ["Stays back", "Stays back"])
                        if !sp.longThrows.isEmpty {
                            card("Long throws", "hand.raised.fill", sp.longThrows, ["Taker", "Alt"])
                        }
                    }
                }
                .padding(14)
            }
        }
    }

    private func card(_ title: String, _ icon: String, _ takers: [TacticsAdvisor.Taker], _ labels: [String],
                      subtitle: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon).font(.headline)
            if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
            ForEach(Array(takers.enumerated()), id: \.element.id) { i, t in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(i < labels.count ? labels[i] : "").font(.caption).foregroundStyle(.secondary)
                        .frame(width: 70, alignment: .leading)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(t.player.name).font(.callout.weight(i == 0 ? .semibold : .regular)).lineLimit(1)
                        Text(t.note).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Text(String(format: "%.1f", t.score)).bold().monospacedDigit()
                        .foregroundStyle(AttrColor.color(Int(t.score.rounded())))
                }
            }
            if takers.isEmpty { Text("Nobody suitable").foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fmCard()
    }
}

// MARK: - Team instructions

/// Which XI set pieces and instructions are worked out for: your tactic, or the suggested shape.
struct SourcePicker: View {
    @Environment(Store.self) private var store
    var body: some View {
        Picker("Based on", selection: Binding(get: { store.tacticsSource }, set: { store.tacticsSource = $0 })) {
            Text("My tactic (\(store.workingFormation.name))").tag(0)
            Text("Suggested (\(store.tacticsFit?.formation.name ?? "best"))").tag(1)
        }
        .fixedSize()
    }
}

struct InstructionsPane: View {
    @Environment(Store.self) private var store
    static let phases = ["In possession", "Out of possession", "Goalkeeper", "Set pieces"]

    /// The FM preset style being compared: your pick, else your tactic's style, else the best-fitting preset's.
    private var presetStyle: FMStyle? {
        let names = FMPresets.styleNames
        if names.contains(store.instructionsPresetStyle) { return FMPresets.style(store.instructionsPresetStyle) }
        if let s = store.workingFormation.style, names.contains(s) { return FMPresets.style(s) }
        return store.presetFits.first.flatMap { FMPresets.style($0.preset.style) }
    }

    var body: some View {
        @Bindable var store = store
        ScrollView {
            if let ins = store.tacticsInstructions {
                let preset = presetStyle
                let presetIns = preset?.catalogueInstructions() ?? [:]
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        Picker("FM preset", selection: $store.instructionsPresetStyle) {
                            Text("Auto\(preset.map { " (\($0.name))" } ?? "")").tag("")
                            Divider()
                            ForEach(FMPresets.styleNames, id: \.self) { Text($0).tag($0) }
                        }
                        .fixedSize()
                        .help("The FM preset style to compare with. Auto: your tactic's style, else the preset that suits your squad best")
                        SourcePicker()
                        Picker("Going into games", selection: $store.tacticsStance) {
                            Text(autoLabel).tag(-1)
                            Divider()
                            ForEach(TacticsAdvisor.Stance.allCases) { Text($0.title).tag($0.rawValue) }
                        }
                        .fixedSize()
                        .help("Auto works it out from where your XI ranks in your league (Compare teams)")
                        if store.compareBusy { ProgressView().controlSize(.small) }
                        Spacer()
                        Menu {
                            Button("FM preset's instructions") { if let preset { store.applyPresetInstructions(preset) } }
                            Button("Pitchside's suggestions") { store.applySuggestedInstructions() }
                        } label: { Label("Use in my tactic", systemImage: "arrow.right.circle") }
                        .fixedSize()
                        .help("Copies one column, with its mentality and style, into your tactic")
                    }
                    HStack(spacing: 14) {
                        legend(.green, "agrees with the preset")
                        legend(.orange, "Pitchside would change it")
                        legend(.blue, "Pitchside would add it")
                        legend(.secondary.opacity(0.5), "no reason to change the preset")
                    }
                    .font(.caption).foregroundStyle(.secondary)
                    HStack(alignment: .top, spacing: 12) {
                        mentalityCard(ins, preset)
                        styles(ins.styles)
                    }
                    ForEach(Self.phases, id: \.self) { phase in section(phase, ins, presetIns, preset?.name ?? "preset") }
                    Text("Pitchside only suggests a setting where your squad gives a clear reason, so where it says nothing, the preset's choice is fine for your players. Names follow FM27's tactic screens; the wording in-game may differ slightly.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(14)
            }
        }
    }

    private func legend(_ c: Color, _ t: String) -> some View {
        HStack(spacing: 4) { Circle().fill(c).frame(width: 7, height: 7); Text(t) }
    }

    private var autoLabel: String {
        guard let a = store.autoStance else { return "Auto (needs your league)" }
        return "Auto: \(a.0.title.lowercased()) (\(a.rank) of \(a.of))"
    }

    private func mentalityCard(_ ins: TacticsAdvisor.Instructions, _ preset: FMStyle?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("MENTALITY").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("FM preset").font(.caption).foregroundStyle(.secondary)
                    Text(preset?.mentality ?? "—").font(.title3.bold())
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Pitchside").font(.caption).foregroundStyle(.secondary)
                    Text(ins.mentality).font(.title3.bold()).foregroundStyle(Theme.gold)
                }
            }
            Text(ins.mentalityReason).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: 260, alignment: .leading)
        .fmCard()
    }

    private func styles(_ s: [TacticsAdvisor.StyleFit]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("TACTICAL STYLE FIT").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(Array(s.prefix(6).enumerated()), id: \.element.id) { i, st in
                HStack(spacing: 8) {
                    Text(st.name).font(.callout.weight(i == 0 ? .bold : .regular)).frame(width: 170, alignment: .leading)
                    ProgressView(value: st.fit, total: 100).tint(i == 0 ? Theme.gold : .accentColor).frame(width: 110)
                    Text("\(Int(st.fit))").monospacedDigit().frame(width: 28, alignment: .trailing)
                    Text(st.why).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fmCard()
    }

    private func section(_ title: String, _ ins: TacticsAdvisor.Instructions, _ presetIns: [String: String], _ presetName: String) -> some View {
        let specs = TacticsAdvisor.catalogue.filter { $0.phase == title }
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    .frame(width: 210, alignment: .leading)
                Text(presetName.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(.secondary).frame(width: 180, alignment: .leading)
                Text("PITCHSIDE").font(.caption2.weight(.semibold)).foregroundStyle(.secondary).frame(width: 180, alignment: .leading)
                Text("WHY").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            }
            ForEach(specs) { spec in
                let sug = ins.items.first { $0.name == spec.name }
                let pre = presetIns[spec.name]
                let (dot, why): (Color, String) = {
                    switch (pre, sug) {
                    case let (p?, s?) where p == s.setting: return (.green, s.reason)
                    case let (_?, s?): return (.orange, s.reason)
                    case let (nil, s?): return (.blue, s.reason)
                    case (_?, nil): return (.secondary.opacity(0.5), "Nothing in your squad argues against it.")
                    default: return (.clear, "")
                    }
                }()
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    HStack(spacing: 5) {
                        Circle().fill(dot).frame(width: 7, height: 7)
                        Text(spec.name).font(.callout)
                    }
                    .frame(width: 200, alignment: .leading)
                    Text(pre ?? "Default").font(.callout.weight(pre == nil ? .regular : .semibold))
                        .foregroundStyle(pre == nil ? .secondary : .primary)
                        .frame(width: 180, alignment: .leading)
                    Group {
                        if let sug {
                            Text(sug.setting).font(.callout.bold())
                                .padding(.horizontal, 8).padding(.vertical, 2)
                                .background((sug.strength > 0.6 ? Theme.gold : Color.accentColor).opacity(0.22), in: Capsule())
                                .help(sug.strength > 0.6 ? "Strong reason in your squad" : "Mild reason — worth trying")
                        } else {
                            Text("—").font(.callout).foregroundStyle(.secondary)
                                .help("No clear reason in your squad either way")
                        }
                    }
                    .frame(width: 180, alignment: .leading)
                    Text(why).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fmCard()
    }
}
