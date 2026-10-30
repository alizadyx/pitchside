import SwiftUI
import PitchsideCore

/// Smart tactics for your club: best formation and FM27 roles, set pieces & captain, team instructions.
struct TacticsView: View {
    @Environment(Store.self) private var store
    @AppStorage("tacticsTab") private var tab = 0

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if store.myClub.isEmpty || store.tacticsFits.isEmpty {
                empty
            } else {
                switch tab {
                case 1: SetPiecesPane()
                case 2: InstructionsPane()
                default: FormationsPane()
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "wand.and.stars").foregroundStyle(Theme.gold)
            Text(store.myClub.isEmpty ? "Tactics" : store.myClub).font(.title3.bold())
            if let fit = store.tacticsFit {
                Text(fit.formation.name).foregroundStyle(.secondary)
            }
            Spacer()
            Picker("", selection: $tab) {
                Text("Formation & roles").tag(0)
                Text("Set pieces & captain").tag(1)
                Text("Team instructions").tag(2)
            }
            .pickerStyle(.segmented)
            .frame(width: 470)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private var empty: some View {
        VStack(spacing: 10) {
            Image(systemName: "sportscourt").font(.system(size: 40)).foregroundStyle(.secondary)
            Text("Pick your club in the Squad builder first").font(.headline)
            Text("Tactics uses the same club and team (first team, U21…) as the Squad builder.")
                .foregroundStyle(.secondary)
            if store.allPlayers.isEmpty { Text("Scan the game first.").foregroundStyle(.orange) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Formation & roles

private struct FormationsPane: View {
    @Environment(Store.self) private var store

    var body: some View {
        HSplitView {
            list.frame(minWidth: 250, idealWidth: 280, maxWidth: 340)
            if let fit = store.tacticsFit {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        summary(fit)
                        TacticsPitch(fit: fit).frame(maxWidth: 560)
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
        let best = store.tacticsFits.first?.rating ?? 0
        return List(selection: Binding(get: { store.tacticsFit?.formation.name },
                                       set: { store.tacticsChoice = $0 })) {
            SwiftUI.Section("Best shapes for your squad") {
                ForEach(store.tacticsFits) { f in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(f.formation.name).font(.callout.weight(.semibold))
                            Text(detail(f)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(String(format: "%.1f", f.level)).bold().monospacedDigit()
                            .foregroundStyle(AttrColor.color(Int(f.level.rounded())))
                        if f.rating >= best - 0.05 {
                            Image(systemName: "crown.fill").foregroundStyle(Theme.gold).help("Best fit")
                        }
                    }
                    .tag(f.formation.name)
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
        HStack(alignment: .top, spacing: 10) {
            Stat(title: "XI level", value: String(format: "%.1f", fit.level), color: AttrColor.color(Int(fit.level.rounded())))
            Stat(title: "Depth", value: String(format: "%.1f", fit.depth), color: AttrColor.color(Int(fit.depth.rounded())))
            Stat(title: "Out of position", value: "\(fit.outOfPosition)", color: fit.outOfPosition > 0 ? .orange : .green)
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    store.useFormation(fit.formation)
                } label: {
                    Label("Use in Squad builder", systemImage: "arrow.right.circle.fill")
                }
                .help("Loads this shape with these IP/OOP roles into the Squad builder")
                Text("Roles are scored like FM27's role stars: key attributes, then preferable ones. A slot blends 60% IP and 40% OOP.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 260, alignment: .leading)
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
                        .foregroundStyle(AttrColor.color(Int(p.score.rounded())))
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
            Text(String(format: "%.1f", score)).monospacedDigit().foregroundStyle(AttrColor.color(Int(score.rounded())))
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
                            .foregroundStyle(AttrColor.color(Int(r.bestRoleScore.rounded())))
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
private struct TacticsPitch: View {
    let fit: TacticsAdvisor.FormationFit

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
                .foregroundStyle(p.player == nil ? Color.red : AttrColor.color(Int(p.score.rounded())))
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

private struct SetPiecesPane: View {
    @Environment(Store.self) private var store

    var body: some View {
        ScrollView {
            if let sp = store.tacticsSetPieces {
                VStack(alignment: .leading, spacing: 12) {
                    Text("From the \(store.tacticsFit?.formation.name ?? "") XI (penalties also look at the bench). Set these in FM under Tactics → Set Pieces.")
                        .font(.callout).foregroundStyle(.secondary)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 330), spacing: 12, alignment: .top)], spacing: 12) {
                        card("Captain", "person.badge.shield.checkmark.fill", sp.captains, ["Captain", "Vice-captain", "Third"])
                        card("Penalties", "target", sp.penalties, ["1st", "2nd", "3rd", "4th", "5th"])
                        card("Corners — left side", "arrow.turn.up.right", sp.leftCorners, ["Taker", "Alt", "Alt"])
                        card("Corners — right side", "arrow.turn.up.left", sp.rightCorners, ["Taker", "Alt", "Alt"])
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

    private func card(_ title: String, _ icon: String, _ takers: [TacticsAdvisor.Taker], _ labels: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon).font(.headline)
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

private struct InstructionsPane: View {
    @Environment(Store.self) private var store
    static let phases = ["In possession", "Out of possession", "Goalkeeper", "Set pieces"]

    var body: some View {
        @Bindable var store = store
        ScrollView {
            if let ins = store.tacticsInstructions {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        Picker("Going into games", selection: $store.tacticsStance) {
                            ForEach(TacticsAdvisor.Stance.allCases) { Text($0.title).tag($0.rawValue) }
                        }
                        .frame(width: 320)
                        Spacer()
                        Text("For the \(store.tacticsFit?.formation.name ?? "") XI").foregroundStyle(.secondary)
                    }
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("MENTALITY").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            Text(ins.mentality).font(.title2.bold()).foregroundStyle(Theme.gold)
                            Text(ins.mentalityReason).font(.callout).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(width: 230, alignment: .leading)
                        .fmCard()
                        styles(ins.styles)
                    }
                    ForEach(Self.phases, id: \.self) { phase in
                        let items = ins.items.filter { $0.phase == phase }
                        if !items.isEmpty { section(phase, items) }
                    }
                    Text("Only instructions with a clear reason in your squad are listed; leave the rest on FM's default. Names follow FM27's tactic screens; the exact wording in-game may differ slightly.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(14)
            }
        }
    }

    private func styles(_ s: [TacticsAdvisor.StyleFit]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("TACTICAL STYLE FIT").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(Array(s.prefix(5).enumerated()), id: \.element.id) { i, st in
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

    private func section(_ title: String, _ items: [TacticsAdvisor.Instruction]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(items) { it in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(it.name).font(.callout).frame(width: 200, alignment: .leading)
                    Text(it.setting).font(.callout.bold())
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background((it.strength > 0.6 ? Theme.gold : Color.accentColor).opacity(0.22), in: Capsule())
                        .frame(width: 210, alignment: .leading)
                    Text(it.reason).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fmCard()
    }
}
