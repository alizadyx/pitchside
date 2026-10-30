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
                if let id = selection, let row = store.playerRow(id) { PlayerDetail(row: row) }
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
    @State private var clubQuery = ""
    @State private var picked: UInt32?
    @State private var showSave = false
    @State private var saveName = ""
    @AppStorage("squadMode") private var mode = 0     // 0 plan on the pitch, 1 my squad list

    var body: some View {
        VStack(spacing: 0) {
            controls
            Divider()
            if store.squadReport != nil && mode == 1 {
                MySquadView(picked: $picked)
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
                    Text("Plan").tag(0)
                    Text("My squad").tag(1)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .help("Plan: formation, weak spots and signings. My squad: everyone at your club in a list.")
                Picker("Team", selection: $store.squadWomen) {
                    Text("Men").tag(false)
                    Text("Women").tag(true)
                }
                .pickerStyle(.segmented)
                .fixedSize()
                .help("A club's men's and women's sides share its name; pick which one to build")
                tacticControls
                HStack(spacing: 6) {
                    Text("Budget \(store.currency.symbol)")
                    NumberField(value: $store.transferBudget, width: 110)
                    Text("Wage/wk")
                    NumberField(value: $store.wageBudget, width: 84)
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
            }
            .font(.callout)
            if let r = store.squadReport {
                HStack(spacing: 16) {
                    Text(r.club).font(.headline)
                    Text("\(r.squad.count) players")
                    Text("avg age \(String(format: "%.1f", r.averageAge))")
                    Text("starter level \(String(format: "%.1f", r.level))")
                    Text("reputation \(r.reputation)")
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
                SwiftUI.Section("Presets") {
                    ForEach(Formations.all) { Text($0.name).tag($0.name) }
                }
                if !store.customFormations.isEmpty {
                    SwiftUI.Section("My tactics") {
                        ForEach(store.customFormations) { Text($0.name).tag($0.name) }
                    }
                }
            }
            .fixedSize()
            if store.formationEdited {
                Text("edited")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Theme.accentSoft, in: Capsule())
                    .foregroundStyle(Theme.accent)
            }
            Menu {
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

    private var pitchHeader: some View {
        let n = store.workingFormation.slots.count
        return HStack(spacing: 8) {
            Text("\(n) positions")
                .font(.callout)
                .foregroundStyle(n == 11 ? Color.secondary : Color.orange)
                .help(n == 11 ? "" : "A starting XI has 11 positions")
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
        let slot = report.slots.first { $0.slot.label == store.selectedSlot }
        let role = slot.flatMap { s in Roles.all.first { $0.code == s.slot.role } }
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                if let slot, let role {
                    Text("Signings for \(slot.slot.label)").font(.headline)
                    Text(role.name).foregroundStyle(.secondary)
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
            Table(store.suggestions, selection: $picked) {
                TableColumn("★") { s in
                    Button { store.toggleShortlist(s.row.id) } label: {
                        Image(systemName: store.shortlist.contains(s.row.id) ? "star.fill" : "star")
                            .foregroundStyle(store.shortlist.contains(s.row.id) ? Theme.gold : Color.secondary.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                }
                .width(20)
                TableColumn("Name") { s in Text(s.row.name).fontWeight(.medium).lineLimit(1) }.width(min: 130, ideal: 180)
                TableColumn("Age") { s in Text("\(s.row.age)").monospacedDigit() }.width(min: 30, ideal: 34, max: 40)
                TableColumn("Club") { s in
                    Text(s.row.club.isEmpty ? "Free agent" : s.row.club).lineLimit(1).foregroundStyle(.secondary)
                }
                .width(min: 90, ideal: 140, max: 240)
                TableColumn("Role") { s in
                    Text(String(format: "%.1f", s.score)).monospacedDigit().foregroundStyle(AttrColor.color(Int(s.score.rounded())))
                }
                .width(min: 36, ideal: 42, max: 50)
                TableColumn("Gain") { s in
                    Text(String(format: "+%.1f", s.gain)).monospacedDigit().fontWeight(.semibold).foregroundStyle(.green)
                }
                .width(min: 40, ideal: 46, max: 54)
                TableColumn("CA/PA") { s in Text("\(s.row.ca)/\(s.row.pa)").monospacedDigit() }.width(min: 54, ideal: 60, max: 70)
                TableColumn("Interest") { s in
                    InterestBadge(a: s.interest)
                }
                .width(min: 70, ideal: 92, max: 110)
                TableColumn("Value · Wage") { s in
                    Text(Money.format(s.row.person.val, symbol: store.currency.symbol, perGbp: store.rate) + " · "
                         + Money.format(s.row.person.wage, symbol: store.currency.symbol, perGbp: store.rate))
                        .monospacedDigit().lineLimit(1)
                }
                .width(min: 90, ideal: 120, max: 170)
                TableColumnForEach(store.columns(for: "signings")) { c in
                    TableColumn(c.shortTitle) { s in StatCell(column: c, row: s.row, store: store) }
                        .width(min: c.minWidth, ideal: c.idealWidth, max: c.maxWidth)
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

// MARK: - My squad

/// Everyone at your club in one sortable list, with where each player sits in the formation.
struct MySquadView: View {
    @Binding var picked: UInt32?
    @Environment(Store.self) private var store

    var body: some View {
        @Bindable var store = store
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("\(store.squadRows.count) players").font(.callout.weight(.medium)).foregroundStyle(.secondary)
                Text("XI = starting position in your formation").font(.caption).foregroundStyle(.tertiary)
                Spacer()
                ColumnsMenu(table: "squad")
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            Table(store.squadRows, selection: $picked, sortOrder: $store.squadSort) {
                TableColumn("★", value: \.shortlistKey) { r in
                    Button { store.toggleShortlist(r.id) } label: {
                        Image(systemName: store.shortlist.contains(r.id) ? "star.fill" : "star")
                            .foregroundStyle(store.shortlist.contains(r.id) ? Theme.gold : Color.secondary.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                }
                .width(20)
                TableColumn("Name", value: \.name) { r in Text(r.name).fontWeight(.medium).lineLimit(1) }
                    .width(min: 130, ideal: 190)
                TableColumn("XI", value: \PlayerRow[extra: "xi"]) { r in
                    let t = store.squadRoleText[r.id]
                    Text(t ?? "—").lineLimit(1)
                        .fontWeight(t != nil && !(t ?? "").contains("backup") ? .semibold : .regular)
                        .foregroundStyle(t == nil ? Color.secondary.opacity(0.6)
                                         : (t ?? "").contains("backup") ? Color.secondary : Theme.accent)
                }
                .width(min: 50, ideal: 86, max: 120)
                TableColumn("Age", value: \.age) { r in Text("\(r.age)").monospacedDigit() }
                    .width(min: 30, ideal: 34, max: 40)
                TableColumn("Position", value: \.positions) { r in
                    Text(r.positions).foregroundStyle(.secondary).lineLimit(1)
                }
                .width(min: 60, ideal: 110, max: 180)
                TableColumn("Best role", value: \.bestRoleScore) { r in
                    HStack(spacing: 4) {
                        Text(r.bestRole).foregroundStyle(.secondary).frame(minWidth: 26, alignment: .leading)
                        Text(String(format: "%.1f", r.bestRoleScore)).monospacedDigit()
                            .foregroundStyle(AttrColor.color(Int(r.bestRoleScore.rounded())))
                    }
                }
                .width(min: 60, ideal: 80, max: 100)
                TableColumn("CA", value: \.ca) { r in AbilityText(value: r.ca) }.width(min: 32, ideal: 38, max: 44)
                TableColumn("PA", value: \.pa) { r in AbilityText(value: r.pa) }.width(min: 32, ideal: 38, max: 44)
                TableColumn("Contract", value: \.expires) { r in
                    Text(r.expires.isEmpty ? "—" : String(r.expires.prefix(7))).monospacedDigit().foregroundStyle(.secondary)
                }
                .width(min: 54, ideal: 64, max: 80)
                TableColumnForEach(store.columns(for: "squad")) { c in
                    TableColumn(c.shortTitle, value: \PlayerRow[extra: c.id]) { r in StatCell(column: c, row: r, store: store) }
                        .width(min: c.minWidth, ideal: c.idealWidth, max: c.maxWidth)
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
                        SlotMarker(a: a, selected: store.selectedSlot == a.slot.label)
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
                Text(a.slot.role).font(.system(size: 9.5, weight: .semibold)).foregroundStyle(.white.opacity(0.7))
                Text(a.starter == nil ? "empty" : String(format: "%.1f", a.starterScore))
                    .font(.system(size: 10, weight: .bold)).monospacedDigit()
                    .foregroundStyle(a.starter == nil ? Color.red : AttrColor.color(Int(a.starterScore.rounded())))
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
            Menu("Role") {
                ForEach(Formations.roles(for: slot.position)) { r in
                    Button { store.setSlotRole(i, r.code) } label: {
                        if r.code == slot.role { Label(r.name, systemImage: "checkmark") } else { Text(r.name) }
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
                Text(Roles.all.first { $0.code == a.slot.role }?.name ?? a.slot.role).foregroundStyle(.secondary)
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
        }
        .fmCard()
    }

    private func editor(_ i: Int) -> some View {
        let slot = store.workingFormation.slots[i]
        let natural = Formations.roles(for: slot.position)
        let others = Roles.all.filter { r in !natural.contains { $0.code == r.code } }
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
                Text("Role").foregroundStyle(.secondary)
                Picker("Role", selection: Binding(get: { slot.role }, set: { store.setSlotRole(i, $0) })) {
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
                Text(String(format: "%.1f", score)).bold().monospacedDigit().foregroundStyle(AttrColor.color(Int(score.rounded())))
            }
        }
        .font(.callout)
    }
}

// MARK: - Growth & regens

struct RadarView: View {
    @Environment(Store.self) private var store
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
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 10)], spacing: 10) {
                Stat(title: "Compared with", value: store.referenceLabel.isEmpty ? "—" : String(store.referenceLabel.prefix(28)))
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
                Table(rows, selection: $picked) {
                    TableColumn("★") { r in
                        Button { store.toggleShortlist(r.id) } label: {
                            Image(systemName: store.shortlist.contains(r.id) ? "star.fill" : "star")
                                .foregroundStyle(store.shortlist.contains(r.id) ? Theme.gold : Color.secondary.opacity(0.6))
                        }
                        .buttonStyle(.plain)
                    }
                    .width(20)
                    TableColumn("Name") { r in Text(r.name).fontWeight(.medium).lineLimit(1) }.width(min: 140, ideal: 190)
                    TableColumn("Age") { r in Text("\(r.age)").monospacedDigit() }.width(min: 30, ideal: 34, max: 40)
                    TableColumn("Position") { r in Text(r.positions).foregroundStyle(.secondary).lineLimit(1) }
                        .width(min: 60, ideal: 100, max: 160)
                    TableColumn("Club") { r in Text(r.club.isEmpty ? "Free agent" : r.club).lineLimit(1) }
                        .width(min: 90, ideal: 150, max: 240)
                    TableColumn("CA") { r in AbilityText(value: r.ca) }.width(min: 32, ideal: 38, max: 44)
                    TableColumn("PA") { r in AbilityText(value: r.pa) }.width(min: 32, ideal: 38, max: 44)
                    TableColumn("Growth") { r in
                        Text(r.growth == PlayerRow.noGrowth ? "new" : (r.growth > 0 ? "+\(r.growth)" : "\(r.growth)"))
                            .monospacedDigit().fontWeight(.semibold)
                            .foregroundStyle(r.growth == PlayerRow.noGrowth ? Color.purple : r.growth > 0 ? Color.green : Color.secondary)
                    }
                    .width(min: 40, ideal: 50, max: 60)
                    TableColumn("Meta") { r in
                        Text(String(format: "%.1f", r.meta)).monospacedDigit().foregroundStyle(AttrColor.color(Int(r.meta.rounded())))
                    }
                    .width(min: 36, ideal: 42, max: 50)
                    TableColumnForEach(store.columns(for: "growth")) { c in
                        TableColumn(c.shortTitle) { r in StatCell(column: c, row: r, store: store) }
                            .width(min: c.minWidth, ideal: c.idealWidth, max: c.maxWidth)
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
