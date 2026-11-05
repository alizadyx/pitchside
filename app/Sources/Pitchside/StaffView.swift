import PitchsideCore
import SwiftUI

struct StaffView: View {
    @Environment(Store.self) private var store
    /// Column order, visibility and widths; drag headers to reorder, right-click a header to hide.
    @State private var columnLayout: TableColumnCustomization<StaffRow> = ColumnLayouts.load("staff")
    @State private var selection: Set<UInt32> = []
    @AppStorage("showStaffFilters") private var showFilters = true

    var body: some View {
        @Bindable var store = store
        let keys = store.meta?.staffAttrKeys ?? AttributeGroups.staffCoaching
        let f = store.staffFilter
        let searchActive = !f.text.isEmpty || !f.job.isEmpty || !f.nation.isEmpty || f.freeAgentsOnly
        let activeCount = [searchActive, !f.area.isEmpty, f.minAge != 15 || f.maxAge != 90 || f.minCA > 0, !f.rules.isEmpty]
            .filter { $0 }.count
        let areaOn = !f.area.isEmpty
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button { withAnimation(.snappy) { showFilters.toggle() } } label: {
                    Label(activeCount > 0 ? "Filters (\(activeCount))" : "Filters", systemImage: "line.3.horizontal.decrease.circle")
                }
                .tint(activeCount > 0 ? Theme.accent : nil)
                .buttonStyle(.bordered)
                if activeCount > 0 {
                    Button("Clear") {
                        var n = StaffFilter(); n.gender = store.staffFilter.gender; store.staffFilter = n
                    }
                    .buttonStyle(.link)
                }
                Text("\(store.staff.count.formatted()) staff").foregroundStyle(.secondary)
                Spacer()
                if !areaOn {
                    Picker("Column", selection: $store.staffColumnKey) {
                        ForEach(keys, id: \.self) { Text(AttributeGroups.label($0)).tag($0) }
                    }
                    .frame(maxWidth: 240)
                    .help("Attribute shown in the extra column")
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            if !store.myClub.isEmpty {
                AreaStrip()
            }
            Divider()
            HStack(spacing: 0) {
                if showFilters {
                    filters(keys: keys)
                    Divider()
                }
                table
            }
        }
        .background(Theme.bg)
        .inspector(isPresented: Binding(get: { selection.count == 1 }, set: { if !$0 { selection = [] } })) {
            Group {
                if selection.count == 1, let id = selection.first, let row = store.staffRow(id) { StaffDetail(row: row) { selection = [] } }
                else { Text("Select someone").foregroundStyle(.secondary) }
            }
            .inspectorColumnWidth(min: 320, ideal: 380, max: 560)
        }
        .onAppear { store.refilterStaff() }
        .onChange(of: store.staffFilter.area) {
            if !store.staffFilter.area.isEmpty { store.staffSort = [KeyPathComparator(\StaffRow.areaScore, order: .reverse)] }
        }
        .onChange(of: store.staffFilter) { store.refilterStaff() }
        .onChange(of: store.staffColumnKey) { store.refilterStaff() }
        .onChange(of: store.staffSort) { store.resortStaff() }
        .onChange(of: store.myClub) { store.refilterStaff() }
        .onChange(of: store.wageBudget) { store.refilterStaff() }
    }

    private func filters(keys: [String]) -> some View {
        @Bindable var store = store
        let f = store.staffFilter
        let bests = store.staffBests
        return ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                FilterGroup(title: "Search", active: !f.text.isEmpty || !f.job.isEmpty || !f.nation.isEmpty || f.freeAgentsOnly) {
                    TextField("Name or club", text: $store.staffFilter.text)
                    TextField("Job (Coach, Scout, Physio…)", text: $store.staffFilter.job)
                    TextField("Country", text: $store.staffFilter.nation)
                    Toggle("Free agents only", isOn: $store.staffFilter.freeAgentsOnly)
                }
                .textFieldStyle(.roundedBorder)
                FilterGroup(title: "For my club", active: !f.area.isEmpty) {
                    if store.myClub.isEmpty {
                        Text("Pick your club in Tactics & squad to search for upgrades.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    Picker("Area", selection: $store.staffFilter.area) {
                        Text("Any job").tag("")
                        ForEach(StaffAdvisor.areas) { a in
                            Text(bests[a.title].map { "\(a.title) · yours \(Int($0.score.rounded()))" } ?? a.title).tag(a.title)
                        }
                    }
                    .help("Ranks people for this job by its attributes; only people who can do the job are shown")
                    Toggle("Clear upgrades only", isOn: $store.staffFilter.upgradesOnly)
                        .help("At least 2 points better than your best in this area; your own staff are left out")
                        .disabled(f.area.isEmpty || store.myClub.isEmpty)
                    Toggle("Likely to join only", isOn: $store.staffFilter.likelyOnly)
                        .help("Leaves out people far more famous than your club, free agents included, and staff at clearly bigger clubs")
                        .disabled(f.area.isEmpty || store.myClub.isEmpty)
                    if !f.area.isEmpty, store.wageBudget > 0 {
                        Text("Within your wage budget of \(store.currency.symbol)\(store.wageBudget.formatted())/wk (set in Tactics & squad).")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                FilterGroup(title: "Ability & age", active: f.minAge != 15 || f.maxAge != 90 || f.minCA > 0) {
                    Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
                        GridRow {
                            Text("Age")
                            NumberField(value: $store.staffFilter.minAge)
                            Text("–")
                            NumberField(value: $store.staffFilter.maxAge)
                        }
                        GridRow { Text("Min CA"); NumberField(value: $store.staffFilter.minCA, zeroIsAny: true) }
                    }
                }
                FilterGroup(title: "Attributes", active: !f.rules.isEmpty) {
                    AttributeRulesEditor(rules: $store.staffFilter.rules, keys: keys)
                }
            }
            .padding(10)
        }
        .frame(width: 290)
        .background(Theme.panelAlt.opacity(0.4))
        .transition(.move(edge: .leading).combined(with: .opacity))
    }

    private var table: some View {
        @Bindable var store = store
        let areaOn = !store.staffFilter.area.isEmpty
        let attrTitle = areaOn ? store.staffFilter.area : AttributeGroups.label(store.staffColumnKey)
        let sample = Array(store.staff.prefix(600))
        let nameW: CGFloat = ColumnFit.width(sample.map(\.name), header: "Name", max: 300, medium: true)
        let jobW: CGFloat = ColumnFit.width(sample.map(\.job), header: "Job", max: 220)
        let clubW: CGFloat = ColumnFit.width(sample.map { $0.club.isEmpty ? "Free agent" : $0.club }, header: "Club", max: 260)
        let nationW: CGFloat = ColumnFit.width(sample.map(\.nation), header: "Country", max: 160)
        let attrW: CGFloat = max(110, ColumnFit.header(attrTitle))
        return Table(store.staff, selection: $selection, sortOrder: $store.staffSort, columnCustomization: $columnLayout) {
            TableColumn("Name", value: \.name) { r in Text(r.name).fontWeight(.medium).lineLimit(1) }
                .width(min: 80, ideal: nameW)
                .customizationID("name").disabledCustomizationBehavior([.reorder, .visibility])
            TableColumn("Age", value: \.age) { r in Text("\(r.age)").monospacedDigit() }.width(min: 30, ideal: 34, max: 42).customizationID("age")
            TableColumn("Job", value: \.job) { r in Text(r.job).lineLimit(1) }
                .width(min: 50, ideal: jobW, max: 300).customizationID("job")
            TableColumn("Club", value: \.club) { r in
                Text(r.club.isEmpty ? "Free agent" : r.club).lineLimit(1).foregroundStyle(r.club.isEmpty ? Theme.green : Color.secondary)
            }
            .width(min: 60, ideal: clubW, max: 320)
            .customizationID("club")
            TableColumn("Country", value: \.nation) { r in Text(r.nation).lineLimit(1).foregroundStyle(.secondary) }
                .width(min: 40, ideal: nationW, max: 220).customizationID("nation")
            TableColumn("CA", value: \.ca) { r in AbilityText(value: r.ca) }.width(min: 32, ideal: 38, max: 44).customizationID("ca")
            TableColumn("PA", value: \.pa) { r in AbilityText(value: r.pa) }.width(min: 32, ideal: 38, max: 44).customizationID("pa")
            // A table block takes at most 10 columns; Group lifts the limit.
            Group {
                TableColumn(attrTitle, value: \.areaSortValue) { r in
                    StaffScoreCell(row: r, area: store.staffFilter.area, attrTitle: attrTitle)
                }
                .width(min: 60, ideal: attrW, max: 220).customizationID("attr")
                TableColumn("Interest", value: \.interestRank) { r in
                    StaffInterestCell(row: r, myClub: store.myClub)
                }
                .width(min: 56, ideal: 72, max: 100).customizationID("interest")
                TableColumn("Wage/wk", value: \.wageSort) { r in
                    Text(r.wage >= 0 ? store.money(r.wage) : "—").monospacedDigit().foregroundStyle(.secondary)
                }
                .width(min: 50, ideal: 70, max: 110).customizationID("wage")
                TableColumn("Contract", value: \.expires) { r in
                    Text(r.expires.isEmpty ? "—" : DateText.monthYear(r.expires)).foregroundStyle(.secondary)
                }
                .width(min: 54, ideal: 64, max: 80).customizationID("contract")
            }
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
        .persistsColumns($columnLayout, table: "staff", store: store)
        .scrollContentBackground(.hidden)
        .contextMenu(forSelectionType: UInt32.self) { ids in
            if ids.count == 1, let id = ids.first {
                Button("Show Profile") { selection = [id] }
                Divider()
            }
            Button(ids.count > 1 ? "Copy \(ids.count) Names" : "Copy Name") { store.copyStaffName(ids) }
        } primaryAction: { ids in
            if let id = ids.first { selection = [id] }
        }
        .onCopyCommand {
            store.copyStaffName(selection)
            return []
        }
    }
}

/// The extra column: score in the searched area, or the chosen attribute with its word.
struct StaffScoreCell: View {
    let row: StaffRow
    let area: String
    let attrTitle: String
    @Environment(Store.self) private var store

    var body: some View {
        if area.isEmpty {
            HStack(spacing: 6) {
                AttrBox(value: row.selectedAttr).help(attrTitle)
                Text(row.selectedAttr > 0 ? AttributeGroups.staffWord(row.selectedAttr) : "")
                    .foregroundStyle(.secondary).lineLimit(1)
            }
        } else {
            let score: Double = row.areaScore
            let rounded: Int = Int(score.rounded())
            let label: String = String(format: "%.1f", score)
            HStack(spacing: 6) {
                AttrBox(value: rounded)
                Text(label).monospacedDigit().foregroundStyle(.secondary)
            }
            .help(tip(score))
        }
    }

    private func tip(_ score: Double) -> String {
        let mine = String(format: "%.1f in %@", score, area)
        guard let best = store.staffBests[area] else { return mine }
        return mine + String(format: "; your best is %@ at %.1f", best.row.name, best.score)
    }
}

/// Interest column: Yours, Possible or Unlikely (with the reason on hover).
struct StaffInterestCell: View {
    let row: StaffRow
    let myClub: String

    var body: some View {
        if !row.interestKnown {
            Text("—").foregroundStyle(.tertiary)
        } else if row.club == myClub {
            Text("Yours").foregroundStyle(.secondary)
        } else if let d = row.doubt {
            Text("Unlikely").foregroundStyle(Theme.warn).help("Unlikely: " + d)
        } else {
            Text("Possible").foregroundStyle(Theme.good)
                .help("Reputation within reach of your club. An estimate: FM decides when you approach him.")
        }
    }
}

/// Your staff areas, weakest first: your best score in each. Click one to search for upgrades there.
struct AreaStrip: View {
    @Environment(Store.self) private var store

    var body: some View {
        let bests = store.staffBests
        let areas = StaffAdvisor.areas.sorted { (bests[$0.title]?.score ?? 0) < (bests[$1.title]?.score ?? 0) }
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Text("\(store.myClub) staff, weakest first").font(.caption).foregroundStyle(.secondary).padding(.trailing, 4)
                ForEach(areas) { a in
                    let b = bests[a.title]
                    let on = store.staffFilter.area == a.title
                    Button {
                        store.staffFilter.area = on ? "" : a.title
                    } label: {
                        HStack(spacing: 5) {
                            Text(a.title).lineLimit(1)
                            Text(b.map { "\(Int($0.score.rounded()))" } ?? "none")
                                .fontWeight(.semibold).monospacedDigit()
                                .foregroundStyle(b.map { AttrColor.color(Int($0.score.rounded())) } ?? Theme.bad)
                        }
                        .font(.callout)
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(on ? Theme.accentSoft : Theme.panel, in: Capsule())
                        .overlay(Capsule().stroke(on ? Theme.accent : Theme.stroke))
                    }
                    .buttonStyle(.plain)
                    .help(b.map { "Your best: \($0.row.name) (\($0.row.job)), \(String(format: "%.1f", $0.score)). Click to find upgrades." }
                          ?? "Nobody at your club does this job. Click to find someone.")
                }
            }
            .padding(.horizontal, 12).padding(.bottom, 8)
        }
    }
}

struct StaffDetail: View {
    let row: StaffRow
    var onClose: (() -> Void)? = nil
    @Environment(Store.self) private var store

    var body: some View {
        let p = row.person
        let values = staffValues(p)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(p.n).font(.title2.bold())
                        .contextMenu { Button("Copy Name") { store.copyText([p.n]) } }
                    Text([p.job, p.club].compactMap { $0 }.joined(separator: " · ")).foregroundStyle(.secondary)
                    Text("\(row.age) years · \(p.nat ?? "—")").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .fmCard()
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], spacing: 8) {
                    Stat(title: "CA", value: "\(p.ca)")
                    Stat(title: "PA", value: p.pa > 0 ? "\(p.pa)" : "—")
                    Stat(title: "Wage/wk", value: Money.format(p.wage, symbol: store.currency.symbol, perGbp: store.rate))
                    Stat(title: "Contract", value: p.exp.map { DateText.monthYear($0) } ?? "—")
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 10, alignment: .top)], spacing: 10) {
                    StaffAttrList(title: "Coaching", keys: AttributeGroups.staffCoaching, values: values)
                    StaffAttrList(title: "Mental", keys: AttributeGroups.staffMental, values: values)
                    StaffAttrList(title: "Knowledge & medical", keys: AttributeGroups.staffKnowledge, values: values)
                }
            }
            .padding(14)
        }
        .toolbar {
            ToolbarItemGroup {
                Button { store.copyText([p.n]) } label: { Label("Copy Name", systemImage: "doc.on.doc") }
                if let onClose {
                    Button(action: onClose) { Label("Close", systemImage: "xmark") }
                        .keyboardShortcut(.cancelAction)
                        .help("Close (Esc)")
                }
            }
        }
    }

    /// Staff attributes, plus Adaptability, which FM shows from the person's personality.
    private func staffValues(_ p: Person) -> [String: Int] {
        var values = attributeValues(keys: store.meta?.staffAttrKeys ?? [], vals: p.s)
        if let i = store.meta?.personalityKeys.firstIndex(of: "Adaptability"), let pv = p.p, i < pv.count, pv[i] > 0 {
            values["Adaptability"] = Int(pv[i])
        }
        return values
    }

    private func attributeValues(keys: [String], vals: [UInt8]?) -> [String: Int] {
        guard let vals else { return [:] }
        var d: [String: Int] = [:]
        for (i, k) in keys.enumerated() where i < vals.count { d[k] = Int(vals[i]) }
        return d
    }
}

/// Staff attributes with the FM27 word next to the number ("Good · 13").
struct StaffAttrList: View {
    let title: String
    let keys: [String]
    let values: [String: Int]
    var body: some View {
        let shown = keys.filter { values[$0] != nil }
        if !shown.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text(title.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.bottom, 2)
                ForEach(shown, id: \.self) { k in
                    let v = values[k] ?? 0
                    HStack {
                        Text(AttributeGroups.label(k)).font(.callout)
                        Spacer(minLength: 6)
                        Text(AttributeGroups.staffWord(v)).font(.callout).foregroundStyle(.secondary)
                        AttrBox(value: v)
                    }
                }
            }
            .fmCard(padding: 10)
        }
    }
}

/// For each staff area, your best person and clear upgrades from elsewhere (weakest area first).
