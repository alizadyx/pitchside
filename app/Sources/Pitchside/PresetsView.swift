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
                        if let style = FMPresets.style(pf.preset.style) { instructions(style) }
                    }
                    .padding(14)
                }
                .frame(minWidth: 540)
            }
        }
    }

    private var shown: [TacticsAdvisor.PresetFit] {
        store.presetFits.filter { store.presetStyle.isEmpty || $0.preset.style == store.presetStyle }
    }

    private var list: some View {
        @Bindable var store = store
        let best = store.presetFits.first?.id
        return VStack(spacing: 0) {
            Picker("Style", selection: $store.presetStyle) {
                Text("All styles").tag("")
                Divider()
                ForEach(FMPresets.styleNames, id: \.self) { Text($0).tag($0) }
            }
            .padding(8)
            List(selection: Binding(get: { store.presetFit?.id }, set: { store.presetChoice = $0 })) {
                SwiftUI.Section {
                    ForEach(shown) { f in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(f.preset.name).font(.callout.weight(.semibold)).lineLimit(1)
                                Text(detail(f)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            Text(String(format: "%.1f", f.fit.level)).bold().monospacedDigit()
                                .foregroundStyle(store.scoreColor(f.fit.level))
                            Text("\(Int(TeamCompare.rating(f.fit.level).rounded()))").monospacedDigit()
                                .foregroundStyle(.secondary).frame(minWidth: 24, alignment: .trailing)
                                .help("Rating (0–100)")
                            Image(systemName: "crown.fill").foregroundStyle(f.id == best ? Theme.gold : .clear)
                                .help(f.id == best ? "Best preset for your squad" : "")
                        }
                        .tag(f.id)
                    }
                } header: {
                    HStack {
                        Text("FM27 presets for your squad")
                        Spacer()
                        Text("Level").help("XI level (1–20): average score of the best eleven in this preset's roles")
                        Text("Rating").frame(minWidth: 24, alignment: .trailing).help("XI level on 0–100")
                        Image(systemName: "crown.fill").foregroundStyle(.clear)
                    }
                }
            }
        }
    }

    private func detail(_ f: TacticsAdvisor.PresetFit) -> String {
        var s = store.presetStyle.isEmpty ? f.preset.style : String(format: "depth %.1f", f.fit.depth)
        if f.fit.outOfPosition > 0 { s += " · \(f.fit.outOfPosition) out of position" }
        return s
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
                .help("Copies the In Possession shape, both roles per position, the style and mentality into My tactic")
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
