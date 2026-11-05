import AppKit
import PitchsideCore
import SwiftUI

/// "Columns" button: tick any stat, attribute, hidden attribute or personality trait to show it as a
/// column in this table. Each table keeps its own choice.
struct ColumnsMenu: View {
    let table: String
    @Environment(Store.self) private var store

    var body: some View {
        let groups = StatColumns.catalog(meta: store.meta, includeHidden: !store.hideHidden)
        let count = store.columns(for: table).count
        Menu {
            if let general = groups.first {
                SwiftUI.Section(general.0) {
                    ForEach(general.1) { c in toggle(c) }
                }
            }
            ForEach(Array(groups.dropFirst().enumerated()), id: \.offset) { item in
                Menu(item.element.0) {
                    ForEach(item.element.1) { c in toggle(c) }
                }
            }
            Divider()
            Button("Reset to default columns") { store.resetColumns(table) }
            Button("Reset widths & order") { store.layoutResets[table, default: 0] += 1 }
        } label: {
            Label(count > 0 ? "Columns (\(count))" : "Columns", systemImage: "tablecells")
        }
        .fixedSize()
        .help("Add or remove columns: stats, attributes, hidden attributes and personality")
    }

    private func toggle(_ c: StatColumn) -> some View {
        Toggle(c.title, isOn: Binding(get: { store.hasColumn(c, in: table) },
                                      set: { _ in store.toggleColumn(c, in: table) }))
    }
}

/// One cell of a user-added column.
/// Gets the store passed in rather than from the environment: table cells and menus can be built
/// outside the normal view tree, where the environment is empty.
struct StatCell: View {
    let column: StatColumn
    let row: PlayerRow
    let store: Store
    /// When set (your squad), meta is coloured against your starters' average instead of the 1–20 bands.
    var metaScale: ScoreScale? = nil

    var body: some View {
        if column.isAttribute {
            AttrBox(value: Int(store.statValue(column, row) ?? 0)).help(column.title)
        } else {
            general.help(column.title)
        }
    }

    @ViewBuilder private var general: some View {
        let p = row.person
        switch column.key {
        case "interest":
            InterestBadge(a: store.interest(for: row))
        case "value":
            money(p.val)
        case "ask":
            money(p.ask.flatMap { $0 > 0 ? $0 : nil })
        case "wage":
            money(p.wage)
        case "pricePerCA":
            money(row.value >= 0 && row.ca > 0 ? Int(row.pricePerCA) : nil)
        case "contract":
            Text(row.expires.isEmpty ? "—" : DateText.monthYear(row.expires))
                .monospacedDigit().foregroundStyle(.secondary)
        case "growth":
            Text(row.growth == PlayerRow.noGrowth ? "—" : (row.growth > 0 ? "+\(row.growth)" : "\(row.growth)"))
                .monospacedDigit()
                .foregroundStyle(row.growth == PlayerRow.noGrowth ? Color.secondary
                                 : row.growth > 0 ? Theme.good : row.growth < 0 ? Theme.bad : Color.secondary)
        case "meta":
            score(row.meta)
                .help("Meta \(String(format: "%.1f", row.meta)): overall quality from the attributes that win matches in FM, keepers on the same scale. Better than \(row.metaRating)% of players in your division, \(row.metaRatingAll)% of everyone scanned.")
        case "bestRole":
            HStack(spacing: 4) {
                Text(Roles.role(row.bestRole)?.short ?? row.bestRole).foregroundStyle(.secondary).lineLimit(1)
                score(row.bestRoleScore)
            }
        case "ca":
            AbilityText(value: row.ca)
        case "pa":
            AbilityText(value: row.pa)
        case "height":
            Text(p.ht.map { $0 > 0 ? "\($0) cm" : "—" } ?? "—").monospacedDigit()
        case "nation", "division":
            Text(StatReader.text(column, row).flatMap { $0.isEmpty ? nil : $0 } ?? "—").lineLimit(1)
        default:
            Text(store.statValue(column, row).map { "\(Int($0))" } ?? "—").monospacedDigit()
        }
    }

    private func money(_ gbp: Int?) -> some View {
        Text(gbp == nil ? "—" : store.money(gbp)).monospacedDigit().lineLimit(1)
    }

    private func score(_ v: Double) -> some View {
        Text(String(format: "%.1f", v)).monospacedDigit().foregroundStyle(RelColor.color(v, metaScale))
    }
}

/// Width for a user-added column: attributes are narrow number boxes; never narrower than the header.
extension StatColumn {
    var minWidth: CGFloat { isAttribute ? 30 : 36 }
    var idealWidth: CGFloat {
        let content: CGFloat
        if isAttribute { content = 36 } else {
            switch key {
            case "interest", "nation": content = 92
            case "bestRole": content = 150
            case "division": content = 140
            case "value", "ask", "wage", "pricePerCA": content = 64
            case "contract", "height": content = 62
            default: content = 44
            }
        }
        return max(content, ColumnFit.header(shortTitle))
    }
    var maxWidth: CGFloat { isAttribute ? 60 : 220 }
}

/// Right-click items shared by every player list.
/// Right-click menu for one or more selected players (every player table uses it).
struct PlayerContextItems: View {
    let ids: Set<UInt32>
    let store: Store
    var onOpen: ((UInt32) -> Void)? = nil

    var body: some View {
        let n = ids.count
        let starred = !ids.isEmpty && ids.allSatisfy { store.shortlist.contains($0) }
        let comparing = !ids.isEmpty && ids.allSatisfy { store.compareIds.contains($0) }
        if n == 1, let id = ids.first, let onOpen {
            Button("Show Profile") { onOpen(id) }
            Divider()
        }
        Button(starred ? (n > 1 ? "Remove \(n) from Shortlist" : "Remove from Shortlist")
                       : (n > 1 ? "Add \(n) to Shortlist" : "Add to Shortlist")) {
            store.setShortlisted(ids, !starred)
        }
        if store.filter.shortlistOnly, store.shortlistFromFM, ids.contains(where: { store.fmShortlist.contains($0) }) {
            Button(n > 1 ? "Remove \(n) from FM Shortlist" : "Remove from FM Shortlist") { store.removeFromFMShortlist(ids) }
        }
        Divider()
        if (2...3).contains(n) {
            Button("Compare These \(n)") {
                store.compareIds = Array(ids)
                store.showCompare = true
            }
        }
        Button(comparing ? "Remove from Comparison" : "Add to Comparison") {
            for id in ids where store.compareIds.contains(id) == comparing { store.toggleCompare(id) }
        }
        Divider()
        Button(n > 1 ? "Copy \(n) Names" : "Copy Name") { store.copyName(ids) }
        Button("Copy as CSV") { store.copyCSV(ids) }
    }
}

/// A text field that offers matching values underneath as you type (clubs, nations, divisions).
struct SuggestionField: View {
    let placeholder: String
    @Binding var text: String
    let options: [String]
    var limit = 6

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            TextField(placeholder, text: $text)
                .onSubmit { if let first = matches.first { text = first } }
            ForEach(matches, id: \.self) { m in
                Button(m) { text = m }
                    .buttonStyle(.link)
                    .lineLimit(1)
                    .padding(.leading, 6)
            }
        }
    }

    private var matches: [String] {
        let q = text.trimmingCharacters(in: .whitespaces).lowercased()
        guard q.count >= 2, !options.contains(text) else { return [] }
        var starts: [String] = [], contains: [String] = []
        for o in options {
            let l = o.lowercased()
            if l.hasPrefix(q) { starts.append(o) } else if l.contains(q) { contains.append(o) }
            if starts.count >= limit { break }
        }
        return Array((starts + contains).prefix(limit))
    }
}

/// Table column order, visibility and widths, kept in the app's settings so they survive quitting.
/// (SwiftUI's window storage is dropped whenever macOS doesn't restore windows.)
enum ColumnLayouts {
    private static func key(_ table: String) -> String { "columnLayout." + table }

    static func load<Row: Identifiable>(_ table: String) -> TableColumnCustomization<Row> {
        guard let d = UserDefaults.standard.data(forKey: key(table)),
              let c = try? JSONDecoder().decode(TableColumnCustomization<Row>.self, from: d) else { return .init() }
        return c
    }

    static func save<Row: Identifiable>(_ c: TableColumnCustomization<Row>, _ table: String) {
        if let d = try? JSONEncoder().encode(c) { UserDefaults.standard.set(d, forKey: key(table)) }
    }
}

extension View {
    /// Saves a table's column layout whenever it changes, and clears it when "Reset widths & order" is picked.
    func persistsColumns<Row: Identifiable>(_ layout: Binding<TableColumnCustomization<Row>>, table: String, store: Store) -> some View {
        self.onChange(of: layout.wrappedValue) { ColumnLayouts.save(layout.wrappedValue, table) }
            .onChange(of: store.layoutResets[table] ?? 0) {
                layout.wrappedValue = TableColumnCustomization<Row>()
                ColumnLayouts.save(layout.wrappedValue, table)
            }
    }
}
