import AppKit
import PitchsideCore
import SwiftUI

extension Store {
    func genderMatches(_ r: PlayerRow) -> Bool {
        switch genderFilter {
        case 1: return r.person.f != 1
        case 2: return r.person.f == 1
        default: return true
        }
    }
}

/// Shared side panel for any screen that lists players.
private struct ProfileInspector: ViewModifier {
    @Binding var selection: UInt32?
    @Environment(Store.self) private var store

    func body(content: Content) -> some View {
        content.inspector(isPresented: Binding(get: { selection != nil }, set: { if !$0 { selection = nil } })) {
            Group {
                if let id = selection, let row = store.playerRow(id) { PlayerDetail(row: row) { selection = nil } }
                else { Text("Select a player").foregroundStyle(.secondary) }
            }
            .inspectorColumnWidth(min: 360, ideal: 440, max: 720)
        }
    }
}

extension View {
    func profileInspector(_ selection: Binding<UInt32?>) -> some View { modifier(ProfileInspector(selection: selection)) }
}

// MARK: - Squad builder

struct SquadView: View {
    @Environment(Store.self) private var store
    /// Column order, visibility and widths; drag headers to reorder, right-click a header to hide.
    @SceneStorage("table.signings") private var columnLayout: TableColumnCustomization<SquadBuilder.Suggestion>
    @State private var clubQuery = ""
    @State private var picked: UInt32?
    @State private var showSave = false
    @State private var saveName = ""
    /// 0 My tactic, 6 Depth, 3 Suggested, 4 Set pieces & captain, 5 Team instructions, 1 My squad, 2 Timeline.
    @AppStorage("squadMode") private var mode = 0

    var body: some View {
        VStack(spacing: 0) {
            controls
            Divider()
            if store.squadReport != nil && mode == 6 {
                DepthView(picked: $picked)
            } else if store.squadReport != nil && mode == 1 {
                MySquadView(picked: $picked)
            } else if store.squadReport != nil && mode == 2 {
                SquadTimelineView(picked: $picked)
            } else if store.squadReport != nil && mode == 3 {
                FormationsPane(onUse: { mode = 0 })
            } else if store.squadReport != nil && mode == 4 {
                SetPiecesPane()
            } else if store.squadReport != nil && mode == 5 {
                InstructionsPane()
            } else if let report = store.squadReport {
                HSplitView {
                    ScrollView {
                        VStack(spacing: 10) {
                            pitchHeader
                            FormationPitch(report: report)
                                .frame(minWidth: 320, maxWidth: 560)
                            if let a = report.slots.first(where: { $0.slot.label == store.selectedSlot }) {
                                SlotCard(a: a)
                            }
                            ClubXICard()
                        }
                        .padding(12)
                    }
                    .frame(minWidth: 340, idealWidth: 460, maxWidth: 600)
                    suggestionsPane(report).frame(minWidth: 460)
                }
            } else {
                emptyState
            }
        }
        .background(Theme.bg)
        .profileInspector($picked)
        .onAppear { clubQuery = store.myClub }
        .onChange(of: store.transferBudget) { store.refreshSuggestions() }
        .onChange(of: store.wageBudget) { store.refreshSuggestions() }
        .onChange(of: store.signMinAge) { store.refreshSuggestions() }
        .onChange(of: store.signMaxAge) { store.refreshSuggestions() }
        .onChange(of: store.signForDepth) { store.refreshSuggestions() }
    }

    private var matches: [String] {
        let q = clubQuery.trimmingCharacters(in: .whitespaces).lowercased()
        guard q.count >= 2, clubQuery != store.myClub else { return [] }
        let starts = store.clubs.filter { $0.lowercased().hasPrefix(q) }
        let contains = store.clubs.filter { !$0.lowercased().hasPrefix(q) && $0.lowercased().contains(q) }
        return Array((starts + contains).prefix(8))
    }

    private var controls: some View {
        @Bindable var store = store
        return VStack(alignment: .leading, spacing: 8) {
            FlowLayout(spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    TextField("Your club (type to search)", text: $clubQuery)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 250)
                        .onSubmit { if let first = matches.first { choose(first) } }
                    ForEach(matches, id: \.self) { c in
                        Button(c) { choose(c) }.buttonStyle(.link)
                    }
                }
                Picker("View", selection: $mode) {
                    Text("My tactic").tag(0)
                    Text("Depth").tag(6)
                    Text("Suggested").tag(3)
                    Text("Set pieces").tag(4)
                    Text("Instructions").tag(5)
                    Text("My squad").tag(1)
                    Text("Timeline").tag(2)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .help("My tactic: your formation and roles, how your squad fits and who to sign. Depth: everyone who can play each position. Suggested: the shapes that suit your squad best. Set pieces & captain, team instructions, everyone at the club, and the next three seasons.")
                if store.clubTeams.count > 1 {
                    Picker("Squad", selection: $store.squadTeamRank) {
                        ForEach(store.clubTeams) { t in Text("\(t.label) (\(t.count))").tag(t.rank) }
                        Divider()
                        Text("All teams").tag(-1)
                    }
                    .fixedSize()
                    .help(store.teamsApproximate
                          ? "This scan has no team data, so the first team is your best 30 and youth teams go by age. Rescan with the new plugin to use FM's real teams."
                          : "First team, youth and reserve teams are told apart by their contracts")
                    if store.teamsApproximate {
                        Label("Estimated — rescan for real teams", systemImage: "info.circle")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }
                if store.genderFilter == 0 {
                    Picker("Team", selection: $store.squadWomen) {
                        Text("Men").tag(false)
                        Text("Women").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                    .help("A club's men's and women's sides share its name; pick which one to build. Follows the Men/Women switch at the top unless that's on Both.")
                }
                tacticControls
                if mode == 0 {
                    // Signing filters only matter where signings are listed.
                    HStack(spacing: 6) {
                        Text("Budget \(store.currency.symbol)")
                        NumberField(value: $store.transferBudget, width: 110, zeroIsAny: true)
                        Text("Wage/wk")
                        NumberField(value: $store.wageBudget, width: 84, zeroIsAny: true)
                    }
                    HStack(spacing: 6) {
                        Text("Age")
                        NumberField(value: $store.signMinAge, width: 40)
                        Text("–")
                        NumberField(value: $store.signMaxAge, width: 40)
                    }
                    Picker("Willing to join", selection: $store.minInterest) {
                        Text("Anyone").tag(0)
                        Text("Doubtful or better").tag(1)
                        Text("Persuadable or better").tag(2)
                        Text("Interested only").tag(3)
                    }
                    .fixedSize()
                    .help("Estimated from club and league size, the player's fame, ambition, loyalty, age, contract and transfer status. FM itself doesn't store this, so treat it as a guide.")
                    Toggle("Depth signing", isOn: $store.signForDepth)
                        .help("Compare with the backup instead of the starter")
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("Nationality")
                        SuggestionField(placeholder: "Any", text: $store.signNationality, options: store.nations)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 170)
                    }
                    .help("Only suggest players of this nationality. Several: separate with commas (England, Wales).")
                }
            }
            .font(.callout)
            if let r = store.squadReport {
                HStack(spacing: 16) {
                    Text(r.club).font(.headline)
                    Text("\(r.squad.count) players")
                    Text("avg age \(String(format: "%.1f", r.averageAge))")
                    Text("starter level \(String(format: "%.1f", r.level)) · rating \(Int(TeamCompare.rating(r.level).rounded()))")
                        .help(TeamCompare.metric("rating")?.explanation ?? "")
                    Text("reputation \(r.reputation)")
                    Text("Scores: green above your XI level, white about level, orange/red below")
                        .font(.caption).foregroundStyle(.tertiary)
                        .help("Scores are coloured against your starters' average (\(String(format: "%.1f", r.level))), so you can see who's above or below your level at a glance.")
                }
                .font(.callout).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func choose(_ club: String) {
        clubQuery = club
        store.selectClub(club)
    }

    private var tacticControls: some View {
        HStack(spacing: 6) {
            Picker("Tactic", selection: Binding(get: { store.formationName }, set: { store.loadFormation($0) })) {
                SwiftUI.Section("Common shapes") {
                    ForEach(Formations.all) { Text($0.name).tag($0.name) }
                }
                SwiftUI.Section("More shapes") {
                    ForEach(Formations.more) { Text($0.name).tag($0.name) }
                }
                Text("Blank pitch (build from scratch)").tag(Formations.blank.name)
                if !store.customFormations.isEmpty {
                    SwiftUI.Section("My tactics") {
                        ForEach(store.customFormations) { Text($0.name).tag($0.name) }
                    }
                }
            }
            .frame(width: 210)
            if store.formationEdited {
                Text("edited")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Theme.accentSoft, in: Capsule())
                    .foregroundStyle(Theme.accent)
            }
            Menu {
                Button("New tactic from a blank pitch") { store.newBlankTactic() }
                Button("Save as new tactic…") {
                    saveName = store.isCustomFormation ? store.formationName : ""
                    showSave = true
                }
                if store.isCustomFormation && store.formationEdited {
                    Button("Update “\(store.formationName)”") { store.saveFormation(as: store.formationName) }
                }
                Button("Undo changes") { store.resetFormation() }.disabled(!store.formationEdited)
                if store.isCustomFormation {
                    Divider()
                    Button("Delete “\(store.formationName)”", role: .destructive) { store.deleteFormation(store.formationName) }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .fixedSize()
        }
        .alert("Save tactic", isPresented: $showSave) {
            TextField("Name", text: $saveName)
            Button("Save") { store.saveFormation(as: saveName) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Saved tactics appear under “My tactics”. Preset names can’t be reused.")
        }
    }

    private func legendDot(_ c: Color, _ text: String) -> some View {
        HStack(spacing: 3) {
            Circle().fill(c).frame(width: 8, height: 8)
            Text(text)
        }
    }

    private var pitchHeader: some View {
        let n = store.workingFormation.slots.count
        return HStack(spacing: 8) {
            Text("\(n) positions")
                .font(.callout)
                .foregroundStyle(n == 11 ? Color.secondary : Color.orange)
                .help(n == 11 ? "" : "A starting XI has 11 positions")
            HStack(spacing: 8) {
                legendDot(.green, "fine")
                legendDot(.orange, "weak spot")
                legendDot(.red, "big gap")
            }
            .font(.caption).foregroundStyle(.secondary)
            .help("Circle colour: how far the starter is below your XI level (more than 1 point: weak spot; more than 2.5 or nobody: big gap)")
            Spacer()
            Text("Click a position to edit it, or right-click")
                .font(.caption).foregroundStyle(.secondary)
            Menu {
                ForEach(Formations.positions, id: \.self) { p in
                    Button("\(Formations.positionName(p)) (\(p))") { store.addSlot(p) }
                }
            } label: {
                Label("Add", systemImage: "plus")
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .fixedSize()
        }
        .frame(maxWidth: 560)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "sportscourt.fill").font(.system(size: 44)).foregroundStyle(Theme.accent)
            Text("Type your club above").font(.title3.bold())
            Text("Works for any club, including the unknown one that just hired you. The builder lines your squad up in the formation you pick, shows where it is thin, old or out of contract, and lists signings that would improve each position within your budget.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 480)
            if store.allPlayers.isEmpty { Text("Scan the game first.").foregroundStyle(.orange) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func suggestionsPane(_ report: SquadReport) -> some View {
        @Bindable var store = store
        let slot = report.slots.first { $0.slot.label == store.selectedSlot }
        let role = slot.flatMap { s in Roles.role(s.slot.role) }
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                if let slot, let role {
                    Text("Signings for \(slot.slot.label)").font(.headline)
                    Text(RoleText.pair(slot.slot))
                        .foregroundStyle(.secondary)
                    Text(String(format: "must beat %.1f", store.signForDepth ? slot.backupScore : slot.starterScore))
                        .font(.callout).padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Theme.panelAlt, in: Capsule())
                } else {
                    Text("Click a position on the pitch").foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(store.suggestions.count) found").foregroundStyle(.secondary)
                ColumnsMenu(table: "signings")
            }
            .padding(10)
            upgradesStrip
            Table(store.suggestions, selection: $picked, sortOrder: $store.signingSort, columnCustomization: $columnLayout) {
                TableColumn("★") { s in
                    Button { store.toggleShortlist(s.row.id) } label: {
                        Image(systemName: store.shortlist.contains(s.row.id) ? "star.fill" : "star")
                            .foregroundStyle(store.shortlist.contains(s.row.id) ? Theme.gold : Color.secondary.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                }
                .width(20).customizationID("star")
                TableColumn("Name", value: \.name) { s in Text(s.row.name).fontWeight(.medium).lineLimit(1) }.width(min: 130, ideal: 180).customizationID("name")
                TableColumn("Age", value: \.age) { s in Text("\(s.row.age)").monospacedDigit() }.width(min: 30, ideal: 34, max: 40).customizationID("age")
                TableColumn("Nat", value: \.nat) { s in Text(s.nat).lineLimit(1).foregroundStyle(.secondary).help(s.nat) }
                    .width(min: 50, ideal: 90, max: 140).customizationID("nat")
                TableColumn("Club", value: \.club) { s in
                    Text(s.row.club.isEmpty ? "Free agent" : s.row.club + (s.row.person.own.map { " (loan from \($0))" } ?? ""))
                        .lineLimit(1).foregroundStyle(.secondary)
                        .help(s.row.person.own.map { "On loan at \(s.row.club); you'd buy him from \($0)" } ?? s.row.club)
                }
                .width(min: 90, ideal: 140, max: 240).customizationID("club")
                TableColumn("Role", value: \.score) { s in
                    Text(String(format: "%.1f", s.score)).monospacedDigit().foregroundStyle(store.scoreColor(s.score))
                }
                .width(min: 36, ideal: 42, max: 50).customizationID("role")
                TableColumn("Gain", value: \.gain) { s in
                    Text(String(format: "+%.1f", s.gain)).monospacedDigit().fontWeight(.semibold).foregroundStyle(.green)
                }
                .width(min: 40, ideal: 46, max: 54).customizationID("gain")
                TableColumn("CA/PA", value: \.ca) { s in Text("\(s.row.ca)/\(s.row.pa)").monospacedDigit() }.width(min: 54, ideal: 60, max: 70).customizationID("ca-pa")
                TableColumn("Interest", value: \.interestRank) { s in
                    InterestBadge(a: s.interest)
                }
                .width(min: 70, ideal: 92, max: 110).customizationID("interest")
                TableColumn("Value · Wage", value: \.valueSort) { s in
                    Text((s.row.club.isEmpty ? "Free transfer"
                          : Money.format(s.row.person.val, symbol: store.currency.symbol, perGbp: store.rate) + " · "
                            + Money.format(s.row.person.wage, symbol: store.currency.symbol, perGbp: store.rate)))
                        .monospacedDigit().lineLimit(1)
                        .foregroundStyle(s.row.club.isEmpty ? Color.green : Color.primary)
                }
                .width(min: 90, ideal: 120, max: 170).customizationID("value-wage")
                TableColumnForEach(store.columns(for: "signings")) { c in
                    TableColumn(c.shortTitle, value: \SquadBuilder.Suggestion[extra: c.id]) { s in StatCell(column: c, row: s.row, store: store) }
                        .width(min: c.minWidth, ideal: c.idealWidth, max: c.maxWidth).customizationID(c.id)
                }
            }
            .tableStyle(.inset(alternatesRowBackgrounds: true))
            .scrollContentBackground(.hidden)
            .contextMenu(forSelectionType: UInt32.self) { ids in
                PlayerContextItems(ids: ids, store: store)
            }
        }
    }
}

extension SquadView {
    /// The single best signing for every position of your tactic, biggest gain first.
    var upgradesStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Biggest upgrades").font(.callout.weight(.semibold))
                Text("best signing per position, within your budget and willingness filters")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                if store.upgradesBusy { ProgressView().controlSize(.small) }
                Button(store.upgrades.isEmpty ? "Find" : "Refresh") { store.findUpgrades() }
                    .controlSize(.small).disabled(store.upgradesBusy)
            }
            if !store.upgrades.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(store.upgrades.prefix(11)) { u in
                            Button {
                                store.selectedSlot = u.slot.label
                                picked = u.suggestion.row.id
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 4) {
                                        Text(u.slot.label).font(.caption.weight(.bold))
                                        Text(String(format: "+%.1f", u.suggestion.gain)).font(.caption.bold()).foregroundStyle(.green)
                                    }
                                    Text(u.suggestion.row.name).font(.callout).lineLimit(1)
                                    Text(u.suggestion.row.club.isEmpty ? "Free agent" : u.suggestion.row.club)
                                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                }
                                .padding(.horizontal, 8).padding(.vertical, 5)
                                .frame(width: 150, alignment: .leading)
                                .background(Theme.panelAlt, in: RoundedRectangle(cornerRadius: 7))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 10).padding(.bottom, 8)
    }
}

/// Your tactic filled from the whole club (youth teams too) against the first team alone.
struct ClubXICard: View {
    @Environment(Store.self) private var store

    var body: some View {
        if let p = store.clubPromotions {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("BEST XI AT THE WHOLE CLUB").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: "%.1f vs first team %.1f (%+.1f)", p.club, p.first, p.club - p.first))
                        .font(.callout).monospacedDigit()
                        .foregroundStyle(p.club - p.first > 0.05 ? .green : .secondary)
                }
                if p.promotions.isEmpty {
                    Text("Nobody outside the first team would get into this XI.").font(.callout).foregroundStyle(.secondary)
                }
                ForEach(p.promotions) { pr in
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Image(systemName: "arrow.up.circle.fill").foregroundStyle(.green)
                        Text("\(pr.player.name) (\(team(pr.player))) would start at \(pr.slot): "
                             + String(format: "%.1f", pr.score)
                             + (pr.replaces.map { " vs \($0.person.lastName) " + String(format: "%.1f", pr.replacedScore) } ?? ""))
                            .font(.callout).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: 560, alignment: .leading)
            .fmCard()
        }
    }

    private func team(_ r: PlayerRow) -> String {
        store.clubTeams.first { $0.id == r.person.tm && !$0.approximate }?.label ?? "age \(r.age)"
    }
}

// MARK: - My squad

/// Everyone at your club in one sortable list, with where each player sits in the formation.
struct MySquadView: View {
    @Binding var picked: UInt32?
    @Environment(Store.self) private var store
    /// Column order, visibility and widths; drag headers to reorder, right-click a header to hide.
    @SceneStorage("table.squad") private var columnLayout: TableColumnCustomization<PlayerRow>

    var body: some View {
        @Bindable var store = store
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("XI = starting position in your formation").font(.caption).foregroundStyle(.tertiary)
                if !store.loanedOut.isEmpty {
                    Label("\(store.loanedOut.count) out on loan", systemImage: "arrow.up.forward.circle")
                        .font(.caption).foregroundStyle(.orange)
                        .help(store.loanedOut.map { "\($0.name) (CA \($0.ca)) at \($0.club)" }.joined(separator: "\n"))
                }
                Spacer()
                ColumnsMenu(table: "squad")
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            Table(store.squadRows, selection: $picked, sortOrder: $store.squadSort, columnCustomization: $columnLayout) {
                TableColumn("★", value: \.shortlistKey) { r in
                    Button { store.toggleShortlist(r.id) } label: {
                        Image(systemName: store.shortlist.contains(r.id) ? "star.fill" : "star")
                            .foregroundStyle(store.shortlist.contains(r.id) ? Theme.gold : Color.secondary.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                }
                .width(20).customizationID("star")
                TableColumn("Name", value: \.name) { r in
                    HStack(spacing: 4) {
                        Text(r.name).fontWeight(.medium).lineLimit(1)
                        if let own = r.person.own {
                            Text("loan").font(.caption2.weight(.semibold)).foregroundStyle(.orange)
                                .help("On loan from \(own)")
                        }
                    }
                }
                    .width(min: 130, ideal: 190).customizationID("name")
                TableColumn("XI", value: \PlayerRow[extra: "xi"]) { r in
                    let t = store.squadRoleText[r.id]
                    Text(t ?? "—").lineLimit(1)
                        .fontWeight(t != nil && !(t ?? "").contains("backup") ? .semibold : .regular)
                        .foregroundStyle(t == nil ? Color.secondary.opacity(0.6)
                                         : (t ?? "").contains("backup") ? Color.secondary : Theme.accent)
                }
                .width(min: 50, ideal: 86, max: 120).customizationID("xi")
                TableColumn("Age", value: \.age) { r in Text("\(r.age)").monospacedDigit() }
                    .width(min: 30, ideal: 34, max: 40).customizationID("age")
                TableColumn("Position", value: \.positions) { r in
                    Text(r.positions).foregroundStyle(.secondary).lineLimit(1)
                }
                .width(min: 60, ideal: 110, max: 180).customizationID("position")
                TableColumn("Best role", value: \.bestRoleScore) { r in
                    HStack(spacing: 4) {
                        Text(Roles.role(r.bestRole)?.short ?? r.bestRole).foregroundStyle(.secondary).lineLimit(1)
                            .help(Roles.role(r.bestRole)?.name ?? r.bestRole)
                        Text(String(format: "%.1f", r.bestRoleScore)).monospacedDigit()
                            .foregroundStyle(store.scoreColor(r.bestRoleScore))
                    }
                }
                .width(min: 90, ideal: 170, max: 240).customizationID("best-role")
                TableColumn("CA", value: \.ca) { r in AbilityText(value: r.ca) }.width(min: 32, ideal: 38, max: 44).customizationID("ca")
                TableColumn("PA", value: \.pa) { r in AbilityText(value: r.pa) }.width(min: 32, ideal: 38, max: 44).customizationID("pa")
                TableColumn("Contract", value: \.expires) { r in
                    Text(r.expires.isEmpty ? "—" : DateText.monthYear(r.expires)).monospacedDigit().foregroundStyle(.secondary)
                }
                .width(min: 54, ideal: 64, max: 80).customizationID("contract")
                TableColumnForEach(store.columns(for: "squad")) { c in
                    TableColumn(c.shortTitle, value: \PlayerRow[extra: c.id]) { r in
                        StatCell(column: c, row: r, store: store, metaScale: store.squadMetaScale)
                    }
                        .width(min: c.minWidth, ideal: c.idealWidth, max: c.maxWidth).customizationID(c.id)
                }
            }
            .tableStyle(.inset(alternatesRowBackgrounds: true))
            .scrollContentBackground(.hidden)
            .contextMenu(forSelectionType: UInt32.self) { ids in
                PlayerContextItems(ids: ids, store: store)
            } primaryAction: { ids in
                if let id = ids.first { picked = id }
            }
        }
    }
}

/// The chosen formation on a pitch; each position shows its starter and how weak it is.
struct FormationPitch: View {
    let report: SquadReport
    @Environment(Store.self) private var store

    var body: some View {
        let points = PitchLayout.points(for: report.slots.map(\.slot))
        GeometryReader { geo in
            ZStack {
                PitchBackground()
                ForEach(report.slots) { a in
                    if let pt = points[a.slot.label] {
                        SlotMarker(a: a, selected: store.selectedSlot == a.slot.label, scale: store.squadScale)
                            .position(x: pt.x * geo.size.width, y: pt.y * geo.size.height)
                            .onTapGesture { store.selectedSlot = a.slot.label }
                            .contextMenu { SlotMenu(label: a.slot.label, store: store) }
                    }
                }
            }
        }
        .aspectRatio(0.72, contentMode: .fit)
    }
}

struct SlotMarker: View {
    let a: SlotAnalysis
    let selected: Bool
    var scale: ScoreScale? = nil

    var body: some View {
        let colour: Color = a.weakness > 2.5 ? .red : a.weakness > 1 ? .orange : .green
        VStack(spacing: 2) {
            ZStack {
                Circle().fill(colour.opacity(0.9)).frame(width: 30, height: 30)
                Circle().stroke(selected ? Color.white : Color.black.opacity(0.4), lineWidth: selected ? 3 : 1).frame(width: 30, height: 30)
                Text(a.slot.label).font(.system(size: 9, weight: .heavy)).foregroundStyle(.black)
            }
            Text(a.starter.map { shortName($0.name) } ?? "—")
                .font(.system(size: 10.5, weight: .semibold))
                .lineLimit(1)
                .foregroundStyle(.white)
            HStack(spacing: 4) {
                Text(a.slot.oop.isEmpty ? a.slot.role : "\(a.slot.role)/\(a.slot.oop.dropFirst())")
                    .font(.system(size: 9.5, weight: .semibold)).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
                Text(a.starter == nil ? "empty" : String(format: "%.1f", a.starterScore))
                    .font(.system(size: 10, weight: .bold)).monospacedDigit()
                    .foregroundStyle(a.starter == nil ? Color.red : RelColor.color(a.starterScore, scale))
            }
        }
        .padding(.horizontal, 5).padding(.vertical, 3)
        .frame(width: 92)
        .background(Color.black.opacity(selected ? 0.55 : 0.35), in: RoundedRectangle(cornerRadius: 7))
        .contentShape(Rectangle())
    }

    private func shortName(_ n: String) -> String {
        let parts = n.split(separator: " ")
        return parts.count > 1 ? "\(parts[0].prefix(1)). \(parts.dropFirst().joined(separator: " "))" : n
    }
}

/// Right-click menu on a pitch position: move it, change its role or remove it.
struct SlotMenu: View {
    let label: String
    let store: Store

    var body: some View {
        if let i = store.slotIndex(label) {
            let slot = store.workingFormation.slots[i]
            Menu("Position") {
                ForEach(Formations.positions, id: \.self) { p in
                    Button { store.setSlotPosition(i, p) } label: {
                        if p == slot.position { Label("\(Formations.positionName(p)) (\(p))", systemImage: "checkmark") }
                        else { Text("\(Formations.positionName(p)) (\(p))") }
                    }
                }
            }
            Menu("In possession role") {
                ForEach(Formations.roles(for: slot.position)) { r in
                    Button { store.setSlotRole(i, r.code) } label: {
                        if r.code == slot.role { Label(r.name, systemImage: "checkmark") } else { Text(r.name) }
                    }
                }
            }
            Menu("Out of possession role") {
                ForEach(Formations.oopRoles(for: slot.position)) { r in
                    Button { store.setSlotOOP(i, r.code) } label: {
                        if r.code == slot.oop { Label(r.name, systemImage: "checkmark") } else { Text(r.name) }
                    }
                }
            }
            Divider()
            Button("Remove \(label)", role: .destructive) { store.removeSlot(i) }
                .disabled(store.workingFormation.slots.count <= 1)
        }
    }
}

struct SlotCard: View {
    let a: SlotAnalysis
    @Environment(Store.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(a.slot.label).font(.headline)
                Text(Roles.role(a.slot.role)?.name ?? a.slot.role).foregroundStyle(.secondary)
                if let o = Roles.role(a.slot.oop) {
                    Text(o.name == Roles.role(a.slot.role)?.name ? "· in and out of possession" : "· \(o.name) (OOP)")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            if let i = store.slotIndex(a.slot.label) { editor(i) }
            Divider()
            line("1st choice", a.starter, a.starterScore)
            line("Backup", a.backup, a.backupScore)
            ForEach(a.issues, id: \.self) { i in
                Label(i, systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundStyle(.orange)
            }
            if a.issues.isEmpty {
                Label("Covered", systemImage: "checkmark.circle.fill").font(.callout).foregroundStyle(.green)
            }
            if let r = a.starter, let i = store.slotIndex(a.slot.label) { roleCheck(r, i) }
            if let report = store.squadReport, let meta = store.meta {
                let opts = SquadBuilder.options(for: a.slot, squad: report.squad, meta: meta)
                if !opts.isEmpty {
                    Divider()
                    Text("WHO CAN PLAY HERE").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(opts) { o in
                        HStack(spacing: 6) {
                            Text(o.row.name).lineLimit(1)
                            Text("\(o.row.age)").foregroundStyle(.secondary)
                            if o.familiarity < 15 {
                                Text("accomplished").font(.caption2).foregroundStyle(.orange)
                                    .help("Can play here but isn't a natural (familiarity \(o.familiarity))")
                            }
                            Spacer()
                            Text(String(format: "%.1f", o.score)).monospacedDigit()
                                .foregroundStyle(store.scoreColor(o.score))
                        }
                        .font(.callout)
                    }
                }
            }
        }
        .fmCard()
    }

    /// Points out when the starter would be clearly better in another role here, with a one-click switch.
    @ViewBuilder private func roleCheck(_ r: PlayerRow, _ i: Int) -> some View {
        let better = SquadBuilder.betterRoles(for: r, at: a.slot)
        if let ip = better.ip, let role = Roles.role(ip.code) {
            suggestion(r, "In possession", role.name, ip.score, current: a.slot.role) { store.setSlotRole(i, ip.code) }
        }
        if let oop = better.oop, let role = Roles.role(oop.code) {
            suggestion(r, "Out of possession", role.name, oop.score, current: a.slot.oop) { store.setSlotOOP(i, oop.code) }
        }
    }

    private func suggestion(_ r: PlayerRow, _ phase: String, _ name: String, _ score: Double, current: String,
                            apply: @escaping () -> Void) -> some View {
        let now = Roles.index(current).map { r.roleScores[$0] } ?? 0
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "lightbulb.fill").foregroundStyle(Theme.gold)
            Text("\(r.person.lastName) scores \(String(format: "%.1f", score)) as \(name) (\(phase.lowercased())), \(String(format: "%.1f", now)) now.")
                .font(.callout).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button("Switch", action: apply).controlSize(.small)
        }
    }

    private func editor(_ i: Int) -> some View {
        let slot = store.workingFormation.slots[i]
        let natural = Formations.roles(for: slot.position)
        let others = Roles.inPossession.filter { r in !natural.contains { $0.code == r.code } }
        let naturalOOP = Formations.oopRoles(for: slot.position)
        let othersOOP = Roles.outOfPossession.filter { r in !naturalOOP.contains { $0.code == r.code } }
        return Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
            GridRow {
                Text("Position").foregroundStyle(.secondary)
                Picker("Position", selection: Binding(get: { slot.position }, set: { store.setSlotPosition(i, $0) })) {
                    ForEach(Formations.positions, id: \.self) { p in
                        Text("\(Formations.positionName(p)) (\(p))").tag(p)
                    }
                }
                .labelsHidden()
            }
            GridRow {
                Text("In possession").foregroundStyle(.secondary)
                Picker("In possession", selection: Binding(get: { slot.role }, set: { store.setSlotRole(i, $0) })) {
                    SwiftUI.Section("Suits \(Formations.positionName(slot.position).lowercased())") {
                        ForEach(natural) { Text($0.name).tag($0.code) }
                    }
                    SwiftUI.Section("Other roles") {
                        ForEach(others) { Text($0.name).tag($0.code) }
                    }
                }
                .labelsHidden()
            }
            GridRow {
                Text("Out of possession").foregroundStyle(.secondary)
                Picker("Out of possession", selection: Binding(get: { slot.oop }, set: { store.setSlotOOP(i, $0) })) {
                    Text("None (judge on IP only)").tag("")
                    SwiftUI.Section("Suits \(Formations.positionName(slot.position).lowercased())") {
                        ForEach(naturalOOP) { Text($0.name).tag($0.code) }
                    }
                    SwiftUI.Section("Other roles") {
                        ForEach(othersOOP) { Text($0.name).tag($0.code) }
                    }
                }
                .labelsHidden()
            }
            GridRow {
                Color.clear.frame(width: 1, height: 1)
                Button(role: .destructive) { store.removeSlot(i) } label: {
                    Label("Remove position", systemImage: "minus.circle")
                }
                .buttonStyle(.link)
                .disabled(store.workingFormation.slots.count <= 1)
            }
        }
        .font(.callout)
    }

    private func line(_ title: String, _ r: PlayerRow?, _ score: Double) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary).frame(width: 74, alignment: .leading)
            Text(r?.name ?? "—").lineLimit(1)
            if let r { Text("\(r.age)").foregroundStyle(.secondary) }
            Spacer()
            if r != nil {
                Text(String(format: "%.1f", score)).bold().monospacedDigit().foregroundStyle(store.scoreColor(score))
            }
        }
        .font(.callout)
    }
}

// MARK: - Growth & regens

struct RadarView: View {
    @Environment(Store.self) private var store
    /// Column order, visibility and widths; drag headers to reorder, right-click a header to hide.
    @SceneStorage("table.growth") private var columnLayout: TableColumnCustomization<PlayerRow>
    @State private var mode = 0
    @State private var picked: UInt32?

    var body: some View {
        @Bindable var store = store
        let risers = store.allPlayers.filter { $0.growth != PlayerRow.noGrowth && $0.growth > 0 && store.genderMatches($0) }
            .sorted { $0.growth != $1.growth ? $0.growth > $1.growth : $0.pa > $1.pa }
        let regens = store.allPlayers.filter { $0.isNew && store.genderMatches($0) }
            .sorted { $0.pa != $1.pa ? $0.pa > $1.pa : $0.ca > $1.ca }
        let rows = Array((mode == 0 ? risers : regens).prefix(500))
        VStack(spacing: 0) {
            // Equal-width tiles across the whole width (an adaptive grid left half of it empty).
            HStack(spacing: 10) {
                Stat(title: "Compared with", value: store.referenceLabel.isEmpty ? "—" : store.referenceLabel)
                    .help(store.referenceLabel)
                Stat(title: "Players who improved", value: risers.count.formatted(), color: .green)
                Stat(title: "Biggest rise", value: risers.first.map { "+\($0.growth) \($0.name)" } ?? "—")
                Stat(title: "New since last scan", value: regens.count.formatted(), color: .purple)
                Stat(title: "Best new potential", value: regens.first.map { "\($0.pa) \($0.name)" } ?? "—", color: Theme.gold)
            }
            .padding(12)
            HStack(spacing: 14) {
                Picker("", selection: $mode) {
                    Text("Biggest risers").tag(0)
                    Text("New regens").tag(1)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Picker("Compare with", selection: $store.referenceSnapshot) {
                    Text("Previous scan").tag("")
                    ForEach(store.snapshots.reversed()) { s in Text(s.label).tag(s.id) }
                }
                .frame(maxWidth: 380)
                Spacer()
                ColumnsMenu(table: "growth")
            }
            .padding(.horizontal, 12).padding(.bottom, 8)
            if rows.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "chart.line.uptrend.xyaxis").font(.system(size: 38)).foregroundStyle(Theme.accent)
                    Text(store.snapshots.count < 2 ? "Scan again later in your save to see growth and new regens."
                                                   : "Nothing to show for this comparison.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(rows, selection: $picked, columnCustomization: $columnLayout) {
                    TableColumn("★") { r in
                        Button { store.toggleShortlist(r.id) } label: {
                            Image(systemName: store.shortlist.contains(r.id) ? "star.fill" : "star")
                                .foregroundStyle(store.shortlist.contains(r.id) ? Theme.gold : Color.secondary.opacity(0.6))
                        }
                        .buttonStyle(.plain)
                    }
                    .width(20).customizationID("star")
                    TableColumn("Name") { r in Text(r.name).fontWeight(.medium).lineLimit(1) }.width(min: 140, ideal: 190).customizationID("name")
                    TableColumn("Age") { r in Text("\(r.age)").monospacedDigit() }.width(min: 30, ideal: 34, max: 40).customizationID("age")
                    TableColumn("Position") { r in Text(r.positions).foregroundStyle(.secondary).lineLimit(1) }
                        .width(min: 60, ideal: 100, max: 160).customizationID("position")
                    TableColumn("Club") { r in Text(r.club.isEmpty ? "Free agent" : r.club).lineLimit(1) }
                        .width(min: 90, ideal: 150, max: 240).customizationID("club")
                    TableColumn("CA") { r in AbilityText(value: r.ca) }.width(min: 32, ideal: 38, max: 44).customizationID("ca")
                    TableColumn("PA") { r in AbilityText(value: r.pa) }.width(min: 32, ideal: 38, max: 44).customizationID("pa")
                    TableColumn("Growth") { r in
                        Text(r.growth == PlayerRow.noGrowth ? "new" : (r.growth > 0 ? "+\(r.growth)" : "\(r.growth)"))
                            .monospacedDigit().fontWeight(.semibold)
                            .foregroundStyle(r.growth == PlayerRow.noGrowth ? Color.purple : r.growth > 0 ? Color.green : Color.secondary)
                    }
                    .width(min: 40, ideal: 50, max: 60).customizationID("growth")
                    TableColumn("Meta") { r in
                        Text(String(format: "%.1f", r.meta)).monospacedDigit().foregroundStyle(AttrColor.color(Int(r.meta.rounded())))
                    }
                    .width(min: 36, ideal: 42, max: 50).customizationID("meta")
                    TableColumnForEach(store.columns(for: "growth")) { c in
                        TableColumn(c.shortTitle) { r in StatCell(column: c, row: r, store: store) }
                            .width(min: c.minWidth, ideal: c.idealWidth, max: c.maxWidth).customizationID(c.id)
                    }
                }
                .tableStyle(.inset(alternatesRowBackgrounds: true))
                .scrollContentBackground(.hidden)
                .contextMenu(forSelectionType: UInt32.self) { ids in
                    PlayerContextItems(ids: ids, store: store)
                }
            }
        }
        .background(Theme.bg)
        .profileInspector($picked)
    }
}

// MARK: - Comparison

struct CompareView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let rows = store.compareRows
        VStack(spacing: 0) {
            HStack {
                Text("Comparison").font(.title2.bold())
                Spacer()
                Button("Clear") { store.compareIds = []; dismiss() }
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding()
            Divider()
            if rows.isEmpty {
                Text("Right-click players and choose “Add/Remove from Comparison” (up to 3).")
                    .foregroundStyle(.secondary).padding(40)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        legend(rows)
                        if let meta = store.meta {
                            let gk = rows.allSatisfy { $0.isGoalkeeper }
                            let axes = gk ? RadarAxes.goalkeeper : RadarAxes.outfield
                            RadarChart(axes: axes.map { $0.0 },
                                       series: rows.map { RadarAxes.values($0.person, meta: meta, axes: axes) })
                                .frame(height: 320)
                                .fmCard()
                        }
                        summary(rows).fmCard()
                        ForEach(groups(rows), id: \.0) { g in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(g.0.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                ForEach(g.1, id: \.self) { key in
                                    BarRow(title: AttributeGroups.label(key), values: rows.map { attr($0, key) })
                                }
                            }
                            .fmCard()
                        }
                    }
                    .padding()
                }
            }
        }
        .frame(minWidth: 720, idealWidth: 860, minHeight: 700, idealHeight: 900)
        .background(Theme.bg)
    }

    private func legend(_ rows: [PlayerRow]) -> some View {
        HStack(spacing: 12) {
            ForEach(Array(rows.enumerated()), id: \.offset) { i, r in
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 3).fill(Theme.series[i]).frame(width: 6)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(r.name).font(.headline).lineLimit(1)
                        Text("\(r.age) · \(r.club.isEmpty ? "Free agent" : r.club)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        Text(r.positions).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .fmCard(padding: 8)
            }
        }
    }

    private func summary(_ rows: [PlayerRow]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            BarRow(title: "Current ability", values: rows.map { Double($0.ca) }, scale: 200)
            BarRow(title: "Potential", values: rows.map { Double($0.pa) }, scale: 200)
            BarRow(title: "Meta score", values: rows.map { $0.meta }, decimals: 1)
            BarRow(title: "Best role", values: rows.map { $0.bestRoleScore }, decimals: 1)
            BarRow(title: "Age", values: rows.map { Double($0.age) }, scale: 40, lowerIsBetter: true)
            BarRow(title: "Value (£M)", values: rows.map { $0.value >= 0 ? Double($0.value) / 1_000_000 : nil },
                   scale: max(1, rows.map { Double(max($0.value, 0)) / 1_000_000 }.max() ?? 1), decimals: 1, lowerIsBetter: true)
        }
    }

    private func groups(_ rows: [PlayerRow]) -> [(String, [String])] {
        var g: [(String, [String])] = []
        if rows.contains(where: { $0.isGoalkeeper }) { g.append(("Goalkeeping", AttributeGroups.goalkeeping)) }
        g.append(("Technical", AttributeGroups.technical))
        g.append(("Mental", AttributeGroups.mental))
        g.append(("Physical", AttributeGroups.physical))
        if !store.hideHidden, let m = store.meta {
            g.append(("Hidden", m.hiddenKeys))
            g.append(("Personality", m.personalityKeys))
        }
        return g
    }

    private func attr(_ r: PlayerRow, _ key: String) -> Double? {
        guard let m = store.meta else { return nil }
        if let i = m.playerAttrKeys.firstIndex(of: key), let a = r.person.a, i < a.count { return Double(a[i]) }
        if let i = m.hiddenKeys.firstIndex(of: key), let h = r.person.h, i < h.count { return Double(h[i]) }
        if let i = m.personalityKeys.firstIndex(of: key), let p = r.person.p, i < p.count { return Double(p[i]) }
        return nil
    }
}

/// One comparison row: a bar per player in their series colour, best value marked.
struct BarRow: View {
    let title: String
    let values: [Double?]
    var scale: Double = 20
    var decimals = 0
    var lowerIsBetter = false

    var body: some View {
        let present = values.compactMap { $0 }
        let best = lowerIsBetter ? present.min() : present.max()
        let distinct = Set(present).count > 1
        HStack(spacing: 10) {
            Text(title).font(.callout).foregroundStyle(.secondary).lineLimit(1).frame(width: 130, alignment: .leading)
            ForEach(values.indices, id: \.self) { i in
                let v = values[i]
                let isBest = distinct && v != nil && v == best
                HStack(spacing: 6) {
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.panelAlt)
                            Capsule().fill(Theme.series[i % Theme.series.count].opacity(isBest ? 1 : 0.55))
                                .frame(width: g.size.width * CGFloat(min(1, max(0, (v ?? 0) / scale))))
                        }
                    }
                    .frame(height: 8)
                    Text(v.map { decimals == 0 ? "\(Int($0))" : String(format: "%.\(decimals)f", $0) } ?? "—")
                        .font(.callout.weight(isBest ? .bold : .regular)).monospacedDigit()
                        .foregroundStyle(isBest ? Color.white : Color.secondary)
                        .frame(width: 40, alignment: .trailing)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 20)
    }
}

/// Coloured label for an estimated interest level; the tooltip lists the reasons behind it.
struct InterestBadge: View {
    let a: InterestAssessment?
    var body: some View {
        if let a {
            Text(a.level.name)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(a.level.color.opacity(0.18), in: Capsule())
                .foregroundStyle(a.level.color)
                .help(a.reasons.isEmpty ? "Similar-sized club" : a.reasons.joined(separator: "\n"))
        } else {
            Text("—").foregroundStyle(.secondary)
        }
    }
}

extension InterestLevel {
    var color: Color {
        switch self {
        case .interested: .green
        case .persuadable: Color(red: 0.75, green: 0.85, blue: 0.3)
        case .doubtful: .orange
        case .unlikely: .red
        }
    }
}

// MARK: - Timeline

/// The XI over the next three seasons: who is still under contract, a year older each season.
struct SquadTimelineView: View {
    @Binding var picked: UInt32?
    @Environment(Store.self) private var store

    var body: some View {
        let plans = store.squadTimeline
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Who fills each position as contracts run out and players age. Orange: 31 or older that season. Grey: only covered if you renew his contract. Red: nobody left who plays there.")
                    .font(.callout).foregroundStyle(.secondary)
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
                    GridRow {
                        Text("Position").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        ForEach(plans) { p in
                            Text(p.label).font(.headline).frame(minWidth: 200, maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    Divider().gridCellUnsizedAxes(.horizontal)
                    ForEach(store.workingFormation.slots) { slot in
                        GridRow {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(slot.label).font(.callout.weight(.semibold))
                                Text(slot.role).font(.caption2).foregroundStyle(.secondary)
                            }
                            .frame(width: 70, alignment: .leading)
                            ForEach(plans) { p in
                                cell(p.report.slots.first { $0.slot.label == slot.label },
                                     renewed: p.ifRenewed?.slots.first { $0.slot.label == slot.label })
                            }
                        }
                    }
                    Divider().gridCellUnsizedAxes(.horizontal)
                    GridRow(alignment: .top) {
                        Text("Leaving").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        ForEach(plans) { p in
                            VStack(alignment: .leading, spacing: 3) {
                                if p.leaving.isEmpty { Text("Nobody").foregroundStyle(.secondary) }
                                ForEach(p.leaving.prefix(12), id: \.id) { r in
                                    Button { picked = r.id } label: {
                                        Text("\(r.name) · \(r.age)").lineLimit(1)
                                    }
                                    .buttonStyle(.link)
                                }
                                if p.leaving.count > 12 { Text("+\(p.leaving.count - 12) more").foregroundStyle(.secondary) }
                            }
                            .font(.callout)
                            .frame(minWidth: 200, maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .fmCard()
            }
            .padding(12)
        }
    }

    @ViewBuilder private func cell(_ a: SlotAnalysis?, renewed: SlotAnalysis?) -> some View {
        if let a, let s = a.starter {
            let old = s.age >= 31
            Button { picked = s.id } label: {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2).fill(old ? Color.orange : Color.green).frame(width: 4, height: 26)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(s.name).lineLimit(1).foregroundStyle(.primary)
                        HStack(spacing: 6) {
                            Text("\(s.age)").foregroundStyle(old ? Color.orange : Color.secondary)
                            Text(String(format: "%.1f", a.starterScore))
                                .foregroundStyle(store.scoreColor(a.starterScore))
                            if let e = s.person.exp, !e.isEmpty { Text("to \(DateText.monthYear(e))").foregroundStyle(.tertiary) }
                        }
                        .font(.caption).monospacedDigit()
                    }
                }
                .frame(minWidth: 200, maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else if let r = renewed, let s = r.starter {
            Button { picked = s.id } label: {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2).fill(Color.gray).frame(width: 4, height: 26)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(s.name).lineLimit(1).foregroundStyle(.secondary)
                        Text("contract ends \(DateText.monthYear(s.person.exp ?? "")) — renew?")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }
                .frame(minWidth: 200, maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Nobody under contract plays here this season. Renewing \(s.name) would keep it covered (score \(String(format: "%.1f", r.starterScore))).")
        } else {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 2).fill(Color.red).frame(width: 4, height: 26)
                Text("Nobody").foregroundStyle(.red)
            }
            .frame(minWidth: 200, maxWidth: .infinity, alignment: .leading)
        }
    }
}
