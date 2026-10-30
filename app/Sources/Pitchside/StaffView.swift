import PitchsideCore
import SwiftUI

struct StaffView: View {
    @Environment(Store.self) private var store
    @State private var selection: UInt32?
    @AppStorage("showStaffFilters") private var showFilters = true

    var body: some View {
        @Bindable var store = store
        let keys = store.meta?.staffAttrKeys ?? AttributeGroups.staffCoaching
        let f = store.staffFilter
        let activeCount = [!f.text.isEmpty || !f.job.isEmpty, f.minAge != 15 || f.maxAge != 90 || f.minCA > 0, !f.rules.isEmpty]
            .filter { $0 }.count
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
                Picker("Column", selection: $store.staffColumnKey) {
                    ForEach(keys, id: \.self) { Text(AttributeGroups.label($0)).tag($0) }
                }
                .frame(maxWidth: 240)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            Divider()
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
                Table(store.staff, selection: $selection, sortOrder: $store.staffSort) {
                    TableColumn("Name", value: \.name) { r in Text(r.name).fontWeight(.medium).lineLimit(1) }
                        .width(min: 130, ideal: 190)
                    TableColumn("Age", value: \.age) { r in Text("\(r.age)").monospacedDigit() }.width(min: 30, ideal: 34, max: 42)
                    TableColumn("Job", value: \.job) { r in Text(r.job).lineLimit(1) }.width(min: 80, ideal: 140, max: 220)
                    TableColumn("Club", value: \.club) { r in Text(r.club).lineLimit(1).foregroundStyle(.secondary) }
                        .width(min: 90, ideal: 150, max: 260)
                    TableColumn("CA", value: \.ca) { r in AbilityText(value: r.ca) }.width(min: 32, ideal: 38, max: 44)
                    TableColumn("PA", value: \.pa) { r in AbilityText(value: r.pa) }.width(min: 32, ideal: 38, max: 44)
                    TableColumn(AttributeGroups.label(store.staffColumnKey), value: \.selectedAttr) { r in
                        HStack(spacing: 6) {
                            AttrBox(value: r.selectedAttr)
                            Text(r.selectedAttr > 0 ? AttributeGroups.staffWord(r.selectedAttr) : "")
                                .foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    .width(min: 80, ideal: 120, max: 160)
                    TableColumn("Contract", value: \.expires) { r in
                        Text(r.expires.isEmpty ? "—" : String(r.expires.prefix(7))).foregroundStyle(.secondary)
                    }
                    .width(min: 54, ideal: 64, max: 80)
                }
                .tableStyle(.inset(alternatesRowBackgrounds: true))
                .scrollContentBackground(.hidden)
            }
        }
        .background(Theme.bg)
        .inspector(isPresented: Binding(get: { selection != nil }, set: { if !$0 { selection = nil } })) {
            Group {
                if let id = selection, let row = store.staffRow(id) { StaffDetail(row: row) }
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
    @Environment(Store.self) private var store

    var body: some View {
        let p = row.person
        let values = attributeValues(keys: store.meta?.staffAttrKeys ?? [], vals: p.s)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(p.n).font(.title2.bold()).textSelection(.enabled)
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
