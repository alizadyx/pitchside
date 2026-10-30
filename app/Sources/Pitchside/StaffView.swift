import PitchsideCore
import SwiftUI

struct StaffView: View {
    @Environment(Store.self) private var store
    /// Column order, visibility and widths; drag headers to reorder, right-click a header to hide.
    @SceneStorage("table.staff") private var columnLayout: TableColumnCustomization<StaffRow>
    @State private var selection: UInt32?
    @AppStorage("showStaffFilters") private var showFilters = true
    @AppStorage("staffMode") private var mode = 0     // 0 search, 1 recommendations for my club

    var body: some View {
        @Bindable var store = store
        let keys = store.meta?.staffAttrKeys ?? AttributeGroups.staffCoaching
        let f = store.staffFilter
        let activeCount = [!f.text.isEmpty || !f.job.isEmpty, f.minAge != 15 || f.maxAge != 90 || f.minCA > 0, !f.rules.isEmpty]
            .filter { $0 }.count
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Picker("Mode", selection: $mode) {
                    Text("Search").tag(0)
                    Text("For my club").tag(1)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                if mode == 0 {
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
                    Picker("Column", selection: $store.staffColumnKey) {
                        ForEach(keys, id: \.self) { Text(AttributeGroups.label($0)).tag($0) }
                    }
                    .frame(maxWidth: 240)
                } else {
                    Text(store.myClub.isEmpty ? "Pick your club in Tactics & squad first" : "Upgrades for \(store.myClub), weakest area first")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            Divider()
            if mode == 1 {
                StaffAdviceView(selection: $selection)
            } else {
                HStack(spacing: 0) {
                    if showFilters {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 10) {
                                FilterGroup(title: "Search", active: !f.text.isEmpty || !f.job.isEmpty) {
                                    TextField("Name or club", text: $store.staffFilter.text)
                                    TextField("Job (Coach, Scout, Physio…)", text: $store.staffFilter.job)
                                }
                                .textFieldStyle(.roundedBorder)
                                FilterGroup(title: "Ability & age", active: f.minAge != 15 || f.maxAge != 90 || f.minCA > 0) {
                                    Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
                                        GridRow {
                                            Text("Age")
                                            NumberField(value: $store.staffFilter.minAge)
                                            Text("–")
                                            NumberField(value: $store.staffFilter.maxAge)
                                        }
                                        GridRow { Text("Min CA"); NumberField(value: $store.staffFilter.minCA) }
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
                        Divider()
                    }
                    Table(store.staff, selection: $selection, sortOrder: $store.staffSort, columnCustomization: $columnLayout) {
                        TableColumn("Name", value: \.name) { r in Text(r.name).fontWeight(.medium).lineLimit(1) }
                            .width(min: 130, ideal: 190).customizationID("name")
                        TableColumn("Age", value: \.age) { r in Text("\(r.age)").monospacedDigit() }.width(min: 30, ideal: 34, max: 42).customizationID("age")
                        TableColumn("Job", value: \.job) { r in Text(r.job).lineLimit(1) }.width(min: 80, ideal: 140, max: 220).customizationID("job")
                        TableColumn("Club", value: \.club) { r in Text(r.club).lineLimit(1).foregroundStyle(.secondary) }
                            .width(min: 90, ideal: 150, max: 260).customizationID("club")
                        TableColumn("CA", value: \.ca) { r in AbilityText(value: r.ca) }.width(min: 32, ideal: 38, max: 44).customizationID("ca")
                        TableColumn("PA", value: \.pa) { r in AbilityText(value: r.pa) }.width(min: 32, ideal: 38, max: 44).customizationID("pa")
                        TableColumn(AttributeGroups.label(store.staffColumnKey), value: \.selectedAttr) { r in
                            HStack(spacing: 6) {
                                AttrBox(value: r.selectedAttr).help(AttributeGroups.label(store.staffColumnKey))
                                Text(r.selectedAttr > 0 ? AttributeGroups.staffWord(r.selectedAttr) : "")
                                    .foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        .width(min: 80, ideal: 120, max: 160).customizationID("attr")
                        TableColumn("Contract", value: \.expires) { r in
                            Text(r.expires.isEmpty ? "—" : String(r.expires.prefix(7))).foregroundStyle(.secondary)
                        }
                        .width(min: 54, ideal: 64, max: 80).customizationID("contract")
                    }
                    .tableStyle(.inset(alternatesRowBackgrounds: true))
                    .scrollContentBackground(.hidden)
                    .contextMenu(forSelectionType: UInt32.self) { ids in
                        Button(ids.count > 1 ? "Copy Names" : "Copy Name") { store.copyStaffName(ids) }
                    }
                }
            }
        }
        .background(Theme.bg)
        .inspector(isPresented: Binding(get: { selection != nil }, set: { if !$0 { selection = nil } })) {
            Group {
                if let id = selection, let row = store.staffRow(id) { StaffDetail(row: row) { selection = nil } }
                else { Text("Select someone").foregroundStyle(.secondary) }
            }
            .inspectorColumnWidth(min: 320, ideal: 380, max: 560)
        }
        .onChange(of: store.staffFilter) { store.refilterStaff() }
        .onChange(of: store.staffColumnKey) { store.refilterStaff() }
        .onChange(of: store.staffSort) { store.resortStaff() }
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
                    Stat(title: "Contract", value: p.exp ?? "—")
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
struct StaffAdviceView: View {
    @Binding var selection: UInt32?
    @Environment(Store.self) private var store

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if store.myClub.isEmpty {
                    Text("Type your club in Tactics & squad, then come back here.").foregroundStyle(.secondary)
                } else if store.staffAdvice.isEmpty {
                    Text("No staff data yet. Scan the game first.").foregroundStyle(.secondary)
                } else {
                    HStack {
                        Toggle("Only staff likely to join", isOn: Binding(get: { store.staffRealistic },
                                                                           set: { store.staffRealistic = $0 }))
                            .help("Leaves out staff at clearly bigger clubs and big names who wouldn't move to your club")
                        Spacer()
                        Text("Only people whose job fits each area; board members and unpaid roles are left out.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if store.wageBudget > 0 {
                        Text("Only staff within your wage budget of \(store.currency.symbol)\(store.wageBudget.formatted())/wk (set in Tactics & squad).")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 380), spacing: 10, alignment: .top)], spacing: 10) {
                        ForEach(store.staffAdvice) { a in card(a) }
                    }
                }
            }
            .padding(12)
        }
        .onAppear { store.refreshStaffAdvice() }
        .onChange(of: store.myClub) { store.refreshStaffAdvice() }
        .onChange(of: store.wageBudget) { store.refreshStaffAdvice() }
        .onChange(of: store.allStaff.count) { store.refreshStaffAdvice() }
    }

    private func card(_ a: StaffAdvisor.Advice) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(a.area.title).font(.headline)
                Spacer()
                if a.best != nil {
                    Text(String(format: "yours: %.0f", a.bestScore)).monospacedDigit()
                        .foregroundStyle(AttrColor.color(Int(a.bestScore.rounded())))
                } else {
                    Text("nobody").foregroundStyle(.red)
                }
            }
            if let b = a.best {
                Text("\(b.name) · \(b.job)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Divider()
            if a.candidates.isEmpty {
                Text("No clear upgrade available").font(.callout).foregroundStyle(.secondary)
            }
            ForEach(a.candidates) { c in
                Button { selection = c.row.id } label: {
                    HStack(spacing: 8) {
                        AttrBox(value: Int(c.score.rounded()))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(c.row.name).lineLimit(1)
                            Text([c.row.job, c.row.club.isEmpty ? "Free agent" : c.row.club, "\(c.row.age)"]
                                    .filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            if let d = c.doubt {
                                Text("Unlikely: \(d)").font(.caption2).foregroundStyle(.orange)
                            }
                        }
                        Spacer(minLength: 4)
                        Text(c.row.wage >= 0 ? store.money(c.row.wage) + "/wk" : "—")
                            .font(.callout).monospacedDigit().foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .fmCard()
    }
}
