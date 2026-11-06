import SwiftUI
import PitchsideCore

/// Rotation: two or three XIs for your tactic that share out the starts in a busy run of fixtures.
struct RotationView: View {
    @Environment(Store.self) private var store
    @Binding var picked: UInt32?

    var body: some View {
        @Bindable var store = store
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Picker("Plan for", selection: $store.rotationMatches) {
                    Text("2 matches").tag(2)
                    Text("3 matches").tag(3)
                }
                .pickerStyle(.segmented)
                .fixedSize()
                Toggle("Include reserves & youth", isOn: $store.rotationYouth)
                    .help("Let players from your other teams into the rotation")
                Spacer()
                Text(ruleText).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            Divider()
            if let plan = store.rotationPlan {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(alignment: .top, spacing: 12) {
                            ForEach(plan.xis) { xi in
                                RotationXICard(xi: xi, bestLevel: plan.bestLevel, picked: $picked)
                            }
                        }
                        RotationLoadList(plan: plan, picked: $picked)
                    }
                    .padding(14)
                }
            } else {
                ContentUnavailableView("No squad", systemImage: "arrow.triangle.2.circlepath",
                                       description: Text("Pick your club and tactic first."))
            }
        }
        .background(Theme.bg)
    }

    private var ruleText: String {
        let cap = max(1, store.rotationMatches - 1)
        return "Outfield players start at most \(cap) of \(store.rotationMatches). Your keeper and locked players start every match.\n"
            + "Same tactic as My tactic. XIs are balanced, so any can face any opponent."
    }
}

/// One planned XI as a team sheet: keeper first, defence to attack.
struct RotationXICard: View {
    let xi: Rotation.XI
    let bestLevel: Double
    @Binding var picked: UInt32?
    @Environment(Store.self) private var store

    var body: some View {
        let delta: Double = xi.level - bestLevel
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("XI \(xi.id + 1)").font(.headline).foregroundStyle(Theme.ink)
                Spacer()
                Text(String(format: "%.1f", xi.level)).font(.headline).monospacedDigit()
                    .foregroundStyle(store.scoreColor(xi.level))
                Text(String(format: "%+.1f", delta)).font(.caption).monospacedDigit()
                    .foregroundStyle(delta < -0.5 ? Theme.warn : Color.secondary)
                    .help(String(format: "Your best XI with no rotation is %.1f", bestLevel))
            }
            Divider()
            ForEach(xi.picks) { p in
                RotationPickRow(pick: p, picked: $picked)
            }
            if xi.cover > 0 || xi.empty > 0 {
                Divider()
                Text(footer).font(.caption).foregroundStyle(xi.empty > 0 ? Theme.bad : Theme.warn)
            }
        }
        .fmCard()
        .frame(minWidth: 240, maxWidth: .infinity, alignment: .topLeading)
    }

    private var footer: String {
        var parts: [String] = []
        if xi.cover > 0 { parts.append("\(xi.cover) playing out of position") }
        if xi.empty > 0 { parts.append("\(xi.empty) position\(xi.empty == 1 ? "" : "s") nobody can fill") }
        return parts.joined(separator: " · ")
    }
}

struct RotationPickRow: View {
    let pick: Rotation.Pick
    @Binding var picked: UInt32?
    @Environment(Store.self) private var store

    var body: some View {
        HStack(spacing: 6) {
            Text(pick.slot.label).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                .frame(width: 34, alignment: .leading)
            if let r = pick.player {
                Button { picked = r.id } label: {
                    Text(r.name).lineLimit(1).foregroundStyle(Theme.ink)
                }
                .buttonStyle(.plain)
                if !pick.natural {
                    Image(systemName: "circle.lefthalf.filled").font(.caption2).foregroundStyle(Theme.warn)
                        .help("Accomplished here, not natural: covering to keep the rotation going")
                }
                if pick.overCap {
                    Image(systemName: "exclamationmark.triangle.fill").font(.caption2).foregroundStyle(Theme.warn)
                        .help("Starts more matches than the rotation allows: nobody else can play here")
                }
                Spacer(minLength: 4)
                Text(String(format: "%.1f", pick.score)).monospacedDigit().foregroundStyle(store.scoreColor(pick.score))
            } else {
                Text("Nobody available").foregroundStyle(Theme.bad)
                Spacer()
            }
        }
        .font(.callout)
    }
}

/// Who starts how often, with switches to lock a player in or mark him unavailable.
struct RotationLoadList: View {
    let plan: Rotation.Plan
    @Binding var picked: UInt32?
    @Environment(Store.self) private var store

    var body: some View {
        let matches: Int = plan.xis.count
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("STARTS").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Text("Lock: always starts · Out: injured, suspended or needs a rest")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 5) {
                ForEach(plan.loads) { l in
                    GridRow {
                        Button { picked = l.row.id } label: {
                            Text(l.row.name).lineLimit(1).foregroundStyle(l.unavailable ? Color.secondary : Theme.ink)
                        }
                        .buttonStyle(.plain)
                        Text(l.row.positions).foregroundStyle(.secondary).lineLimit(1)
                        StartDots(inXIs: l.inXIs, matches: matches)
                        Text(l.unavailable ? "out" : "\(l.starts)").monospacedDigit()
                            .foregroundStyle(l.overCap ? Theme.warn : Color.secondary)
                        Toggle("Lock", isOn: lockBinding(l.row.id)).toggleStyle(.checkbox)
                            .help("Always starts, in every XI")
                        Toggle("Out", isOn: outBinding(l.row.id)).toggleStyle(.checkbox)
                            .help("Leave him out of every XI")
                    }
                    .font(.callout)
                }
            }
        }
        .fmCard()
    }

    private func lockBinding(_ id: UInt32) -> Binding<Bool> {
        Binding(get: { store.rotationLocked.contains(id) }, set: { on in
            if on { store.rotationUnavailable.remove(id); store.rotationLocked.insert(id) }
            else { store.rotationLocked.remove(id) }
        })
    }

    private func outBinding(_ id: UInt32) -> Binding<Bool> {
        Binding(get: { store.rotationUnavailable.contains(id) }, set: { on in
            if on { store.rotationLocked.remove(id); store.rotationUnavailable.insert(id) }
            else { store.rotationUnavailable.remove(id) }
        })
    }
}

/// One dot per planned XI, filled where he starts.
struct StartDots: View {
    let inXIs: [Int]
    let matches: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<matches, id: \.self) { k in
                Circle()
                    .fill(inXIs.contains(k) ? Theme.accent : Theme.panelAlt)
                    .frame(width: 9, height: 9)
                    .help("XI \(k + 1)")
            }
        }
    }
}
