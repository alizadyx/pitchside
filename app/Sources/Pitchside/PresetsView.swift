import SwiftUI
import PitchsideCore

/// Every tactic preset FM27 offers (style + In / Out of Possession shapes), ranked for your squad.
struct PresetsPane: View {
    @Environment(Store.self) private var store
    var onUse: () -> Void = {}

    var body: some View {
        HSplitView {
            list.frame(minWidth: 290, idealWidth: 320, maxWidth: 380)
            if let pf = store.presetFit {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        summary(pf)
                        TacticsPitch(fit: pf.fit, scale: store.squadScale).frame(maxWidth: 560).frame(maxWidth: .infinity)
                        picksTable(pf)
                        if let r = pf.style { demands(pf.preset.style, r) }
                        if let style = FMPresets.style(pf.preset.style) { instructions(style) }
                    }
                    .padding(14)
                }
                .frame(minWidth: 540)
            }
        }
    }

    private var shown: [TacticsAdvisor.PresetFit] { store.presetsShown }

    /// The score the list is ranked by, as shown.
    private func shownScore(_ f: TacticsAdvisor.PresetFit) -> Double {
        switch store.presetSort { case 1: f.styleScore; case 2: f.combined; default: f.fit.level }
    }

    private var list: some View {
        @Bindable var store = store
        let shown = self.shown
        let best = shown.first
        return VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Picker("Style", selection: $store.presetStyle) {
                    Text("All styles").tag("")
                    Divider()
                    ForEach(FMPresets.styleNames, id: \.self) { Text($0).tag($0) }
                }
                Picker("Rank by", selection: $store.presetSort) {
                    Text("Roles").tag(0)
                    Text("Style fit").tag(1)
                    Text("Both").tag(2)
                }
                .pickerStyle(.segmented)
                .help("Roles: how well your best XI plays the preset's roles. Style fit: whether your players' strengths lean towards what the style asks. Both: roles level plus half the style lean.")
            }
            .padding(8)
            List(selection: Binding(get: { store.presetFit?.id }, set: { store.presetChoice = $0 })) {
                SwiftUI.Section {
                    ForEach(shown) { f in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(f.preset.name).font(.callout.weight(.semibold)).lineLimit(1)
                                Text(detail(f, best)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            Text(String(format: "%.1f", f.fit.level)).bold(store.presetSort != 1).monospacedDigit()
                                .foregroundStyle(store.scoreColor(f.fit.level))
                                .frame(minWidth: 30, alignment: .trailing)
                            Text(String(format: "%+.1f", f.styleScore)).bold(store.presetSort != 0).monospacedDigit()
                                .foregroundStyle(leanColor(f.styleScore))
                                .frame(minWidth: 30, alignment: .trailing)
                            Image(systemName: "crown.fill").foregroundStyle(f.id == best?.id ? Theme.gold : .clear)
                                .help(f.id == best?.id ? "Best preset for your squad by the chosen ranking" : "")
                        }
                        .tag(f.id)
                    }
                } header: {
                    HStack {
                        Text("FM27 presets for your squad")
                        Spacer()
                        Text("Roles").frame(minWidth: 30, alignment: .trailing)
                            .help("XI level (1–20): average score of the best eleven in this preset's roles")
                        Text("Style").frame(minWidth: 30, alignment: .trailing)
                            .help("Style fit: + this style leans on your players' strengths more than your average preset does, − less. 0 = average for your squad.")
                        Image(systemName: "crown.fill").foregroundStyle(.clear)
                    }
                }
            }
        }
    }

    private func detail(_ f: TacticsAdvisor.PresetFit, _ best: TacticsAdvisor.PresetFit?) -> String {
        var s = store.presetStyle.isEmpty ? f.preset.style : String(format: "depth %.1f", f.fit.depth)
        if let best, best.id != f.id {
            s += String(format: " · %+.1f", shownScore(f) - shownScore(best))
        }
        if f.fit.outOfPosition > 0 { s += " · \(f.fit.outOfPosition) out of position" }
        return s
    }

    /// Style lean: green when the squad leans towards what the style asks, red when away from it.
    private func leanColor(_ v: Double) -> Color {
        v >= 1 ? .green : v >= 0.3 ? Color(red: 0.6, green: 0.8, blue: 0.3) : v > -0.3 ? .secondary : v > -1 ? .orange : .red
    }

    private func summary(_ pf: TacticsAdvisor.PresetFit) -> some View {
        let fit = pf.fit
        let rank = (store.presetFits.firstIndex { $0.id == pf.id } ?? 0) + 1
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(pf.preset.style).font(.title3.bold())
                Text(pf.preset.name).font(.title3).foregroundStyle(.secondary)
                Spacer()
                Text("#\(rank) of \(store.presetFits.count)").font(.callout).foregroundStyle(.secondary)
            }
            HStack(alignment: .top, spacing: 10) {
                Stat(title: "XI level", value: String(format: "%.1f", fit.level), color: AttrColor.color(Int(fit.level.rounded())))
                Stat(title: "Rating", value: "\(Int(TeamCompare.rating(fit.level).rounded()))", color: AttrColor.color(Int(fit.level.rounded())))
                    .help(TeamCompare.metric("rating")?.explanation ?? "")
                Stat(title: "Depth", value: String(format: "%.1f", fit.depth), color: AttrColor.color(Int(fit.depth.rounded())))
                Stat(title: "Out of position", value: "\(fit.outOfPosition)", color: fit.outOfPosition > 0 ? .orange : .green)
                Stat(title: "Style fit", value: String(format: "%+.1f", pf.styleScore), color: leanColor(pf.styleScore))
                    .help("+ this style leans on your players' strengths more than your average preset does, − less. 0 = average for your squad. Quality is in the role scores.")
                if let m = FMPresets.style(pf.preset.style)?.mentality {
                    Stat(title: "Mentality", value: m, color: .secondary)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Button {
                    store.useFormation(pf.preset.formation)
                    onUse()
                } label: {
                    Label("Use as my tactic", systemImage: "arrow.right.circle.fill")
                }
                .help("Copies the In Possession shape, both roles per position, the style, mentality and team instructions into My tactic")
                Text("Each player is judged in the preset's roles: 60% his In Possession role at the IP position, 40% his Out of Possession role, with a cost when he isn't natural at either position.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func picksTable(_ pf: TacticsAdvisor.PresetFit) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
            GridRow {
                Text("Pos"); Text("Player"); Text("In possession"); Text("Out of possession"); Text("Score")
            }
            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Divider().gridCellUnsizedAxes(.horizontal)
            ForEach(Array(pf.fit.picks.enumerated()), id: \.offset) { i, p in
                let oopPos = pf.oopPositions[i]
                GridRow {
                    Text(p.slot.label).font(.callout.weight(.semibold))
                    HStack(spacing: 4) {
                        Text(p.player?.name ?? "—").lineLimit(1)
                        if p.player != nil && p.familiarity < 15 {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                                .help("Not a natural \(Formations.positionName(p.slot.position)) (familiarity \(p.familiarity))")
                        }
                    }
                    roleCell(p.slot.role, p.ipScore, nil)
                    HStack(spacing: 4) {
                        roleCell(p.slot.oop, p.oopScore, oopPos == p.slot.position ? nil : oopPos)
                        if p.player != nil && oopPos != p.slot.position && pf.oopFamiliarity[i] < 15 {
                            Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                                .help("Drops to \(Formations.positionName(oopPos)) without the ball, where he isn't natural (familiarity \(pf.oopFamiliarity[i]))")
                        }
                    }
                    Text(p.player == nil ? "—" : String(format: "%.1f", p.score)).bold().monospacedDigit()
                        .foregroundStyle(store.scoreColor(p.score))
                }
                .font(.callout)
            }
        }
        .fmCard()
    }

    private func roleCell(_ code: String, _ score: Double, _ movesTo: String?) -> some View {
        HStack(spacing: 4) {
            if let movesTo { Text("→ \(Formations.positionName(movesTo))").foregroundStyle(.secondary).lineLimit(1) }
            Text(Roles.role(code)?.name ?? code).lineLimit(1)
            Text(String(format: "%.1f", score)).monospacedDigit().foregroundStyle(store.scoreColor(score))
        }
    }

    private func demands(_ style: String, _ r: PresetStyle.Result) -> some View {
        let weakest = r.demands.min { $0.score < $1.score }?.id
        return VStack(alignment: .leading, spacing: 6) {
            Text("HOW YOUR XI SUITS \(style.uppercased())").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 5) {
                ForEach(r.demands) { d in
                    GridRow {
                        Text(d.label).lineLimit(1)
                        Text(d.group).foregroundStyle(.secondary).lineLimit(1)
                        Text(String(format: "%+.1f", d.score)).bold().monospacedDigit()
                            .foregroundStyle(leanColor(d.score))
                        HStack(spacing: 4) {
                            Text(d.attributes.map(AttributeGroups.label).joined(separator: ", "))
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            if d.id == weakest && r.demands.count > 1 {
                                Text("weakest").font(.caption2.weight(.semibold)).foregroundStyle(.orange)
                            }
                        }
                    }
                    .font(.callout)
                    .help("These attributes compared with each player's own average, across the \(d.group.lowercased()) in the XI")
                }
            }
            Text("Each instruction that isn't Standard asks something of some players. + means those attributes are above what the players are usually asked for in their position, − below; heavier instructions count more. The style fit at the top is this, compared with your average preset.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .fmCard()
    }

    private func instructions(_ style: FMStyle) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(style.name.uppercased()) TEAM INSTRUCTIONS").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 24) {
                column("In possession", style.highlights("IP"))
                column("Out of possession", style.highlights("OOP"))
            }
            Text("Only settings that differ from Standard / Balanced are listed. They are the same for every preset of this style.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .fmCard()
    }

    private func column(_ title: String, _ items: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.callout.weight(.semibold))
            ForEach(Array(items.enumerated()), id: \.offset) { _, it in
                HStack(spacing: 6) {
                    Text(it.0).foregroundStyle(.secondary)
                    Text(it.1)
                }
                .font(.callout)
            }
            if items.isEmpty { Text("All standard").font(.callout).foregroundStyle(.secondary) }
        }
    }
}
