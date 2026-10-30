import SwiftUI
import PitchsideCore

/// Compare clubs: your league as a table, two teams head to head, or one team against a group.
struct TeamsCompareView: View {
    @Environment(Store.self) private var store
    @AppStorage("teamsCompareMode") private var mode = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "chart.bar.xaxis").foregroundStyle(Theme.gold)
                Text("Compare teams").font(.title3.bold())
                Picker("", selection: $mode) {
                    Text("League").tag(0)
                    Text("Head to head").tag(1)
                    Text("One vs group").tag(2)
                }
                .pickerStyle(.segmented).fixedSize()
                Picker("Compare by", selection: Binding(get: { store.compareBasis }, set: { store.compareBasis = $0 })) {
                    ForEach(TeamCompare.Basis.allCases) { Text($0.title).tag($0.rawValue).help($0.help) }
                }
                .fixedSize()
                .help(store.basis.help)
                if store.compareBusy { ProgressView().controlSize(.small) }
                Spacer()
                Picker("Side", selection: Binding(get: { store.squadWomen }, set: { store.squadWomen = $0 })) {
                    Text("Men").tag(false)
                    Text("Women").tag(true)
                }
                .pickerStyle(.segmented).fixedSize()
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            Divider()
            if store.allPlayers.isEmpty {
                Text("Scan the game first.").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                switch mode {
                case 1: HeadToHeadPane()
                case 2: GroupPane()
                default: LeaguePane()
                }
            }
        }
        .background(Theme.bg)
        .onAppear { store.refreshLeague() }
    }
}

// MARK: - Shared bits

@MainActor
enum MetricText {
    static func format(_ m: TeamCompare.Metric, _ v: Double, store: Store) -> String {
        switch m.id {
        case "wages": return store.money(Int(v)) + "/wk"
        case "value": return store.money(Int(v))
        default: return String(format: "%.\(m.decimals)f", v)
        }
    }

    static func color(_ m: TeamCompare.Metric, _ v: Double) -> Color {
        m.attributeScale ? AttrColor.color(Int(v.rounded())) : .primary
    }

    /// Green for the top quarter of the league, red for the bottom quarter.
    static func rankColor(_ standing: Double?) -> Color {
        guard let s = standing else { return .primary }
        return s <= 0.25 ? .green : s >= 0.75 ? .red : .primary
    }

    /// Difference from the league average, signed (+ = more).
    static func diff(_ m: TeamCompare.Metric, _ v: Double, _ avg: Double, store: Store) -> String {
        let d = v - avg
        switch m.id {
        case "wages", "value": return (d >= 0 ? "+" : "−") + MetricText.format(m, abs(d), store: store)
        default: return String(format: "%+.\(m.decimals)f", d).replacingOccurrences(of: "-", with: "−")
        }
    }

    static func ordinal(_ n: Int) -> String {
        let suffix = (11...13).contains(n % 100) ? "th" : n % 10 == 1 ? "st" : n % 10 == 2 ? "nd" : n % 10 == 3 ? "rd" : "th"
        return "\(n)\(suffix)"
    }

    /// Green when `a` is clearly better than `b` on this metric, red when clearly worse.
    static func diffColor(_ m: TeamCompare.Metric, _ a: Double, _ b: Double) -> Color {
        let d = m.higherIsBetter ? a - b : b - a
        let threshold = m.attributeScale ? 0.3 : max(abs(b) * 0.05, 0.5)
        return d > threshold ? .green : d < -threshold ? .red : .secondary
    }
}

/// Type-to-search club picker.
struct ClubField: View {
    let placeholder: String
    @Binding var club: String
    @Environment(Store.self) private var store
    @State private var query = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            TextField(placeholder, text: $query)
                .textFieldStyle(.roundedBorder).frame(width: 230)
                .onSubmit { if let m = matches.first { pick(m) } }
            ForEach(matches, id: \.self) { c in Button(c) { pick(c) }.buttonStyle(.link) }
        }
        .onAppear { query = club }
        .onChange(of: club) { _, c in query = c }
    }

    private var matches: [String] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard q.count >= 2, query != club else { return [] }
        let starts = store.clubs.filter { $0.lowercased().hasPrefix(q) }
        let contains = store.clubs.filter { !$0.lowercased().hasPrefix(q) && $0.lowercased().contains(q) }
        return Array((starts + contains).prefix(6))
    }

    private func pick(_ c: String) { club = c; query = c }
}

/// Radar of several teams on the 1–20 metrics, with a legend.
struct TeamRadar: View {
    let series: [(String, [String: Double])]

    var body: some View {
        let ids = TeamCompare.radarIDs
        VStack(alignment: .leading, spacing: 6) {
            RadarChart(axes: ids.map { id in
                (TeamCompare.metric(id)?.title ?? id).components(separatedBy: " (").first ?? id },
                       series: series.map { s in ids.map { s.1[$0] ?? 0 } })
                .frame(minWidth: 280, minHeight: 280)
                .aspectRatio(1, contentMode: .fit)
            HStack(spacing: 12) {
                ForEach(Array(series.enumerated()), id: \.offset) { i, s in
                    HStack(spacing: 4) {
                        Circle().fill(Theme.series[i % Theme.series.count]).frame(width: 9, height: 9)
                        Text(s.0).font(.caption).lineLimit(1)
                    }
                }
            }
        }
    }
}

// MARK: - League

private struct LeaguePane: View {
    @Environment(Store.self) private var store
    @State private var country = ""
    @State private var league = ""
    @State private var sortID = "rating"
    @State private var selected = ""
    @AppStorage("leagueVsAverage") private var vsAverage = false
    static let columns = ["rating", "level", "depth", "ca", "gk", "def", "mid", "att", "technique", "pace", "work", "aerial",
                          "setpieces", "age", "wages"]

    var body: some View {
        let clubs = league.isEmpty ? [] : store.clubs(inLeague: league)
        let profiles = clubs.compactMap { store.profile($0) }
        let avg = TeamCompare.average(profiles)
        HSplitView {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Picker("Country", selection: $country) {
                        ForEach(store.leagueMap.countries, id: \.self) { Text($0).tag($0) }
                    }
                    .frame(maxWidth: 230)
                    Picker("League", selection: $league) {
                        ForEach(store.leagueMap.leagues(in: country), id: \.self) { Text($0).tag($0) }
                    }
                    .frame(maxWidth: 300)
                    Text("\(profiles.count) of \(clubs.count) clubs").foregroundStyle(.secondary)
                    Spacer()
                    Picker("", selection: $vsAverage) {
                        Text("Values").tag(false)
                        Text("vs league average").tag(true)
                    }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                    .help("Show each club's numbers, or how far above (+) or below (−) the league average they are")
                }
                Text("Green: top quarter of this league · red: bottom quarter. Hover a column name or a number for what it means. On the 1–20 scale one point is a big gap (about 15–20 CA).")
                    .font(.caption).foregroundStyle(.secondary)
                table(profiles, avg: avg)
            }
            .padding(12)
            .frame(minWidth: 700)
            detail(profiles, avg: avg).frame(minWidth: 330, idealWidth: 380, maxWidth: 460)
        }
        .onAppear {
            pickDefaults()
            if selected.isEmpty { selected = store.myClub }
            store.ensureProfiles(store.clubs(inLeague: league))
        }
        .onChange(of: country) { _, c in
            let ls = store.leagueMap.leagues(in: c)
            if !ls.contains(league) { league = (store.myCountry == c ? store.myLeague : nil) ?? ls.first ?? "" }
        }
        .onChange(of: league) { _, l in store.ensureProfiles(store.clubs(inLeague: l)) }
        .onChange(of: store.compareBasis) { store.ensureProfiles(store.clubs(inLeague: league)) }
        .onChange(of: store.clubLeague.count) {
            pickDefaults()
            store.ensureProfiles(store.clubs(inLeague: league))
        }
    }

    private func pickDefaults() {
        let map = store.leagueMap
        if country.isEmpty || !map.countries.contains(country) {
            country = store.myCountry ?? map.countries.first ?? ""
        }
        if league.isEmpty || map.country[league] != country {
            league = (store.myCountry == country ? store.myLeague : nil) ?? map.leagues(in: country).first ?? ""
        }
    }

    private func sorted(_ ps: [TeamCompare.TeamProfile]) -> [TeamCompare.TeamProfile] {
        guard let m = TeamCompare.metric(sortID) else { return ps }
        return ps.sorted { m.higherIsBetter ? $0[m.id] > $1[m.id] : $0[m.id] < $1[m.id] }
    }

    private func cellText(_ m: TeamCompare.Metric, _ p: TeamCompare.TeamProfile, avg: [String: Double]) -> String {
        vsAverage ? MetricText.diff(m, p[m.id], avg[m.id] ?? 0, store: store) : MetricText.format(m, p[m.id], store: store)
    }

    private func cellHelp(_ m: TeamCompare.Metric, _ p: TeamCompare.TeamProfile, profiles: [TeamCompare.TeamProfile],
                          avg: [String: Double]) -> String {
        let better = profiles.filter { m.higherIsBetter ? $0[m.id] > p[m.id] : $0[m.id] < p[m.id] }.count
        return "\(p.club) · \(m.title): \(MetricText.format(m, p[m.id], store: store)) — "
            + "\(MetricText.ordinal(better + 1)) of \(profiles.count), league average \(MetricText.format(m, avg[m.id] ?? 0, store: store))\n\n"
            + m.explanation
    }

    private func table(_ profiles: [TeamCompare.TeamProfile], avg: [String: Double]) -> some View {
        let metrics = Self.columns.compactMap { TeamCompare.metric($0) }
        return ScrollView([.vertical, .horizontal]) {
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
                GridRow {
                    Text("#").foregroundStyle(.secondary)
                    Text("Club").font(.caption.weight(.semibold))
                    Text("Shape").font(.caption.weight(.semibold))
                        .help("The formation that gets the most out of this squad")
                    ForEach(metrics) { m in
                        Button { sortID = m.id } label: {
                            Text(m.short + (sortID == m.id ? " ▾" : "")).font(.caption.weight(.semibold))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(m.explanation + "\n\nClick to sort.")
                    }
                }
                Divider().gridCellUnsizedAxes(.horizontal)
                ForEach(Array(sorted(profiles).enumerated()), id: \.element.club) { i, p in
                    GridRow {
                        Text("\(i + 1)").foregroundStyle(.secondary).monospacedDigit()
                        Button { selected = p.club } label: {
                            Text(p.club).fontWeight(p.club == store.myClub ? .bold : .regular).lineLimit(1)
                                .foregroundStyle(p.club == selected ? Theme.gold : .primary)
                        }
                        .buttonStyle(.plain)
                        .frame(minWidth: 150, alignment: .leading)
                        .help(p.club)
                        Text(p.formation).foregroundStyle(.secondary).font(.caption).help(p.formation)
                        ForEach(metrics) { m in
                            Text(cellText(m, p, avg: avg)).monospacedDigit()
                                .foregroundStyle(MetricText.rankColor(TeamCompare.standing(p[m.id], metric: m, in: profiles)))
                                .help(cellHelp(m, p, profiles: profiles, avg: avg))
                        }
                    }
                    .padding(.vertical, 1)
                    .background(p.club == store.myClub ? Theme.accentSoft : .clear)
                }
                Divider().gridCellUnsizedAxes(.horizontal)
                GridRow {
                    Text("")
                    Text("League average").italic()
                    Text("")
                    ForEach(metrics) { m in
                        Text(MetricText.format(m, avg[m.id] ?? 0, store: store)).monospacedDigit().foregroundStyle(.secondary)
                            .help("League average \(m.title): \(MetricText.format(m, avg[m.id] ?? 0, store: store))")
                    }
                }
            }
            .font(.callout)
            .padding(.bottom, 8)
        }
    }

    private func detail(_ profiles: [TeamCompare.TeamProfile], avg: [String: Double]) -> some View {
        ScrollView {
            if let me = profiles.first(where: { $0.club == selected }) ?? profiles.first(where: { $0.club == store.myClub }) {
                let top = profiles.max { $0["level"] < $1["level"] }
                VStack(alignment: .leading, spacing: 10) {
                    Text(me.club).font(.headline)
                    Text("Best in \(me.formation) · \(store.basis.title)").font(.caption).foregroundStyle(.secondary)
                    TeamRadar(series: radarSeries(me, top: top, avg: avg))
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(TeamCompare.notes(for: me.club, in: profiles), id: \.self) { n in
                            Label(n, systemImage: "circle.fill").labelStyle(BulletLabel()).font(.callout)
                        }
                    }
                }
                .padding(12)
            } else {
                Text(store.compareBusy ? "Working out the league…" : "Pick a club in the table")
                    .foregroundStyle(.secondary).padding(20)
            }
        }
    }
}

extension LeaguePane {
    func radarSeries(_ me: TeamCompare.TeamProfile, top: TeamCompare.TeamProfile?, avg: [String: Double])
        -> [(String, [String: Double])] {
        var series: [(String, [String: Double])] = [(me.club, me.values), ("League average", avg)]
        if let top, top.club != me.club { series.append((top.club, top.values)) }
        return series
    }
}

struct BulletLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("•").foregroundStyle(Theme.gold)
            configuration.title
        }
    }
}

// MARK: - Head to head

private struct HeadToHeadPane: View {
    @Environment(Store.self) private var store
    @AppStorage("h2hA") private var a = ""
    @AppStorage("h2hB") private var b = ""

    var body: some View {
        let pa = store.profile(a)
        let pb = store.profile(b)
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 16) {
                    ClubField(placeholder: "Team A", club: $a)
                    Text("vs").font(.headline).padding(.top, 4)
                    ClubField(placeholder: "Team B (any league)", club: $b)
                    Spacer()
                }
                if let pa, let pb {
                    Text(TeamCompare.summary(pa, vs: pb)).font(.callout.weight(.medium))
                    HStack(alignment: .top, spacing: 16) {
                        TeamRadar(series: [(pa.club, pa.values), (pb.club, pb.values)]).frame(maxWidth: 420)
                        VStack(alignment: .leading, spacing: 12) {
                            linesCard(pa, pb)
                            CompareTable(columns: [(pa.club, pa.values), (pb.club, pb.values)])
                        }
                    }
                } else if !a.isEmpty && !b.isEmpty {
                    ProgressView("Working out both teams…")
                } else {
                    Text("Pick two clubs from any leagues.").foregroundStyle(.secondary)
                }
            }
            .padding(14)
        }
        .onAppear { if a.isEmpty { a = store.myClub }; store.ensureProfiles([a, b]) }
        .onChange(of: a) { store.ensureProfiles([a, b]) }
        .onChange(of: b) { store.ensureProfiles([a, b]) }
        .onChange(of: store.compareBasis) { store.ensureProfiles([a, b]) }
    }

    private func linesCard(_ pa: TeamCompare.TeamProfile, _ pb: TeamCompare.TeamProfile) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("LINE BY LINE").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(TeamCompare.lines(pa, pb)) { l in
                HStack {
                    Text(l.line).frame(width: 100, alignment: .leading)
                    Text(String(format: "%.1f", l.mine)).monospacedDigit().foregroundStyle(AttrColor.color(Int(l.mine.rounded())))
                    Text("vs").foregroundStyle(.secondary)
                    Text(String(format: "%.1f", l.theirs)).monospacedDigit().foregroundStyle(AttrColor.color(Int(l.theirs.rounded())))
                    let d = l.mine - l.theirs
                    Text(String(format: "%+.1f", d)).monospacedDigit().fontWeight(.semibold)
                        .foregroundStyle(d > 0.3 ? .green : d < -0.3 ? .red : .secondary)
                }
                .font(.callout)
            }
        }
        .fmCard()
    }
}

/// Metric-by-metric table for two or more columns; the first column is compared with the second.
struct CompareTable: View {
    let columns: [(String, [String: Double])]
    @Environment(Store.self) private var store

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
            GridRow {
                Text("")
                ForEach(Array(columns.enumerated()), id: \.offset) { _, c in
                    Text(c.0).font(.caption.weight(.semibold)).lineLimit(1).frame(maxWidth: 140, alignment: .leading)
                }
            }
            Divider().gridCellUnsizedAxes(.horizontal)
            ForEach(TeamCompare.metrics) { m in
                GridRow {
                    Text(m.title).font(.callout).foregroundStyle(.secondary).help(m.explanation)
                    ForEach(Array(columns.enumerated()), id: \.offset) { i, c in
                        let v = c.1[m.id] ?? 0
                        Text(MetricText.format(m, v, store: store)).monospacedDigit()
                            .fontWeight(i == 0 ? .semibold : .regular)
                            .foregroundStyle(i == 0 && columns.count > 1
                                             ? MetricText.diffColor(m, v, columns[1].1[m.id] ?? 0)
                                             : MetricText.color(m, v))
                    }
                }
            }
        }
        .fmCard()
    }
}

// MARK: - One vs group

private struct GroupPane: View {
    @Environment(Store.self) private var store
    @AppStorage("groupMain") private var main = ""
    @AppStorage("groupOthers") private var othersRaw = ""
    @State private var adding = ""

    private var others: [String] { othersRaw.split(separator: "|").map(String.init).filter { !$0.isEmpty } }

    var body: some View {
        let pm = store.profile(main)
        let ps = others.compactMap { store.profile($0) }
        let avg = TeamCompare.average(ps)
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 16) {
                    ClubField(placeholder: "Your team", club: $main)
                    Text("vs the average of").padding(.top, 4)
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(others, id: \.self) { c in
                            HStack {
                                Text(c)
                                Button { remove(c) } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if others.count < 5 {
                            ClubField(placeholder: "Add a club (\(others.count)/5)", club: $adding)
                        }
                    }
                    Spacer()
                }
                if let pm, !ps.isEmpty {
                    let groupName = "Group average (\(ps.count))"
                    Text(TeamCompare.summary(pm, vs: groupProfile(pm, avg))).font(.callout.weight(.medium))
                    HStack(alignment: .top, spacing: 16) {
                        TeamRadar(series: [(pm.club, pm.values), (groupName, avg)]).frame(maxWidth: 420)
                        CompareTable(columns: [(pm.club, pm.values), (groupName, avg)] + ps.map { ($0.club, $0.values) })
                    }
                } else if !main.isEmpty && !others.isEmpty {
                    ProgressView("Working out the teams…")
                } else {
                    Text("Pick your team and up to five others from any leagues.").foregroundStyle(.secondary)
                }
            }
            .padding(14)
        }
        .onAppear { if main.isEmpty { main = store.myClub }; store.ensureProfiles([main] + others) }
        .onChange(of: main) { store.ensureProfiles([main] + others) }
        .onChange(of: othersRaw) { store.ensureProfiles([main] + others) }
        .onChange(of: store.compareBasis) { store.ensureProfiles([main] + others) }
        .onChange(of: adding) { _, c in
            guard !c.isEmpty, !others.contains(c), others.count < 5 else { return }
            othersRaw = (others + [c]).joined(separator: "|")
            adding = ""
        }
    }

    private func remove(_ c: String) { othersRaw = others.filter { $0 != c }.joined(separator: "|") }

    /// The group average as a profile, so the head-to-head summary can describe it.
    private func groupProfile(_ me: TeamCompare.TeamProfile, _ avg: [String: Double]) -> TeamCompare.TeamProfile {
        TeamCompare.TeamProfile(club: "the group", division: "", formation: "", values: avg, fit: me.fit,
                                players: [], tactical: me.tactical)
    }
}
