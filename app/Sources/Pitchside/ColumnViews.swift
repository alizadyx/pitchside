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
            Button("Reset to default") { store.resetColumns(table) }
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

    var body: some View {
        if column.isAttribute {
            AttrBox(value: Int(store.statValue(column, row) ?? 0))
        } else {
            general
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
            Text(row.expires.isEmpty ? "—" : String(row.expires.prefix(7)))
                .monospacedDigit().foregroundStyle(.secondary)
        case "growth":
            Text(row.growth == PlayerRow.noGrowth ? "—" : (row.growth > 0 ? "+\(row.growth)" : "\(row.growth)"))
                .monospacedDigit()
                .foregroundStyle(row.growth == PlayerRow.noGrowth ? Color.secondary
                                 : row.growth > 0 ? Color.green : row.growth < 0 ? Color.red : Color.secondary)
        case "meta":
            score(row.meta)
        case "bestRole":
            HStack(spacing: 4) {
                Text(row.bestRole).foregroundStyle(.secondary)
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
        Text(String(format: "%.1f", v)).monospacedDigit().foregroundStyle(AttrColor.color(Int(v.rounded())))
    }
}

/// Width for a user-added column: attributes are narrow number boxes.
extension StatColumn {
    var minWidth: CGFloat { isAttribute ? 32 : 50 }
    var idealWidth: CGFloat {
        if isAttribute { return 40 }
        switch key {
        case "interest", "bestRole", "nation": return 92
        case "division": return 140
        default: return 70
        }
    }
    var maxWidth: CGFloat { isAttribute ? 60 : 220 }
}

/// Right-click items shared by every player list.
struct PlayerContextItems: View {
    let ids: Set<UInt32>
    let store: Store

    var body: some View {
        Button(ids.count > 1 ? "Copy Names" : "Copy Name") { store.copyName(ids) }
        Divider()
        Button("Add/Remove Shortlist") { ids.forEach { store.toggleShortlist($0) } }
        Button("Add/Remove from Comparison") { ids.forEach { store.toggleCompare($0) } }
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
