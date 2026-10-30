import AppKit
import PitchsideCore
import SwiftUI

// MARK: - Players screen

struct PlayersView: View {
    let shortlistOnly: Bool
    @Environment(Store.self) private var store
    @State private var selection: UInt32?
    @AppStorage("showFilters") private var showFilters = true

    var body: some View {
        @Bindable var store = store
        let chips = store.filter.chips(currency: store.currency.symbol, roleName: roleName)
        VStack(spacing: 0) {
            // Header: filters toggle, searches, count, last-column picker
            HStack(spacing: 10) {
                if !shortlistOnly {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { showFilters.toggle() }
                    } label: {
                        Label(chips.isEmpty ? "Filters" : "Filters (\(chips.count))", systemImage: "line.3.horizontal.decrease")
                    }
                    .buttonStyle(.bordered)
                    .tint(chips.isEmpty ? nil : Theme.accent)
                    .help("Show or hide the filter panel")
                    PresetsMenu()
                }
                Text("\(store.players.count.formatted()) players")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                ColumnsMenu(table: "players")
                if shortlistOnly {
                    Button("Copy as CSV") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(store.exportShortlistCSV(), forType: .string)
                    }
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)

            // Active filters as removable chips
            if !chips.isEmpty && !shortlistOnly {
                FlowLayout(spacing: 6) {
                    ForEach(chips) { c in
                        Chip(label: c.label) { store.filter.clear(c.id) }
                    }
                    Button("Clear all") { store.filter.clearAll() }
                        .buttonStyle(.link)
                        .font(.callout)
                        .padding(.vertical, 4)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()
            HStack(spacing: 0) {
                if showFilters && !shortlistOnly {
                    PlayerFilterPanel()
                        .frame(width: 290)
                        .transition(.move(edge: .leading))
                    Divider()
                }
                PlayersTable(selection: $selection)
            }
        }
        .background(Theme.bg)
        .inspector(isPresented: Binding(get: { selection != nil }, set: { if !$0 { selection = nil } })) {
            Group {
                if let id = selection, let row = store.playerRow(id) {
                    PlayerDetail(row: row) { selection = nil }
                } else {
                    Text("Select a player").foregroundStyle(.secondary)
                }
            }
            .inspectorColumnWidth(min: 360, ideal: 440, max: 720)
        }
        .onAppear {
            if store.filter.shortlistOnly != shortlistOnly { store.filter.shortlistOnly = shortlistOnly }
        }
        .onChange(of: store.filter) { store.refilter() }
        .onChange(of: store.filter.roleCode) { _, code in
            // Picking a role means "who's best at it", so rank by it.
            if !code.isEmpty { store.playerSort = [KeyPathComparator(\PlayerRow.selectedRoleScore, order: .reverse)] }
        }
        .onChange(of: store.playerSort) { store.resort() }
        .onChange(of: store.rate) { store.refilter() }
    }

    private func roleName(_ code: String) -> String { Roles.all.first { $0.code == code }?.name ?? code }
}

struct PlayersTable: View {
    @Binding var selection: UInt32?
    @Environment(Store.self) private var store
    /// Column order, visibility and widths; drag headers to reorder, right-click a header to hide.
    @SceneStorage("table.players") private var columnLayout: TableColumnCustomization<PlayerRow>

    var body: some View {
        @Bindable var store = store
        let roleTitle = store.filter.roleCode.isEmpty ? "Best role" : store.filter.roleCode
        Table(store.players, selection: $selection, sortOrder: $store.playerSort, columnCustomization: $columnLayout) {
            TableColumn("★", value: \.shortlistKey) { r in
                Button { store.toggleShortlist(r.id) } label: {
                    Image(systemName: r.shortlisted ? "star.fill" : "star")
                        .foregroundStyle(r.shortlisted ? Theme.gold : Color.secondary.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
            .width(20).customizationID("star")
            TableColumn("Name", value: \.name) { r in
                HStack(spacing: 5) {
                    Text(r.name).fontWeight(.medium).lineLimit(1)
                    if r.isNew {
                        Text("NEW").font(.system(size: 9, weight: .heavy)).foregroundStyle(.black)
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(Color.purple.opacity(0.85), in: RoundedRectangle(cornerRadius: 3))
                    }
                    if store.compareIds.contains(r.id) {
                        Image(systemName: "rectangle.split.3x1.fill").font(.caption2).foregroundStyle(Theme.accent)
                    }
                }
            }
            .width(min: 140, ideal: 200).customizationID("name")
            TableColumn("Age", value: \.age) { r in Text("\(r.age)").monospacedDigit() }
                .width(min: 30, ideal: 34, max: 40).customizationID("age")
            TableColumn("Position", value: \.positions) { r in
                Text(r.positions).foregroundStyle(.secondary).lineLimit(1)
            }
            .width(min: 60, ideal: 110, max: 180).customizationID("position")
            TableColumn("Club", value: \.club) { r in
                Text(r.club.isEmpty ? "Free agent" : r.club).lineLimit(1)
                    .foregroundStyle(r.club.isEmpty ? Color.secondary : Color.primary)
            }
            .width(min: 90, ideal: 160, max: 260).customizationID("club")
            TableColumn("CA", value: \.ca) { r in AbilityText(value: r.ca) }
                .width(min: 32, ideal: 38, max: 44).customizationID("ca")
            TableColumn("PA", value: \.pa) { r in AbilityText(value: r.pa) }
                .width(min: 32, ideal: 38, max: 44).customizationID("pa")
            TableColumn("Meta", value: \.meta) { r in
                Text(String(format: "%.1f", r.meta)).monospacedDigit().fontWeight(.semibold)
                    .foregroundStyle(AttrColor.color(Int(r.meta.rounded())))
            }
            .width(min: 36, ideal: 42, max: 50).customizationID("meta")
            TableColumn(roleTitle, value: \.selectedRoleScore) { r in
                HStack(spacing: 4) {
                    if store.filter.roleCode.isEmpty {
                        Text(r.bestRole).foregroundStyle(.secondary).frame(minWidth: 26, alignment: .leading)
                    }
                    Text(String(format: "%.1f", r.selectedRoleScore)).monospacedDigit()
                        .foregroundStyle(AttrColor.color(Int(r.selectedRoleScore.rounded())))
                }
            }
            .width(min: 56, ideal: 76, max: 100).customizationID("role")
            TableColumnForEach(store.columns(for: "players")) { c in
                TableColumn(c.shortTitle, value: \PlayerRow[extra: c.id]) { r in StatCell(column: c, row: r, store: store) }
                    .width(min: c.minWidth, ideal: c.idealWidth, max: c.maxWidth).customizationID(c.id)
            }
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
        .scrollContentBackground(.hidden)
        .background(Theme.bg)
        .contextMenu(forSelectionType: UInt32.self) { ids in
            PlayerContextItems(ids: ids, store: store)
        } primaryAction: { ids in
            if let id = ids.first { selection = id }
        }
    }
}

struct AbilityText: View {
    let value: Int
    var body: some View {
        Text(value > 0 ? "\(value)" : "—")
            .monospacedDigit()
            .fontWeight(value >= 150 ? .bold : .medium)
            .foregroundStyle(value >= 170 ? Theme.gold : value >= 140 ? Color(red: 0.4, green: 0.9, blue: 0.5)
                             : value >= 110 ? Color.primary : Color.secondary)
    }
}

// MARK: - Filter panel

struct PlayerFilterPanel: View {
    @Environment(Store.self) private var store

    var body: some View {
        @Bindable var store = store
        let active = store.filter.activeGroups
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                FilterGroup(title: "Search", active: active.contains("search")) {
                    VStack(spacing: 6) {
                        SuggestionField(placeholder: "Name or club", text: $store.filter.text, options: store.clubs)
                        SuggestionField(placeholder: "Nationality", text: $store.filter.nation, options: store.nations)
                        SuggestionField(placeholder: "Division", text: $store.filter.division, options: store.divisions)
                    }
                    .textFieldStyle(.roundedBorder)
                }

                FilterGroup(title: "Ability & age", active: active.contains("ability")) {
                    Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
                        GridRow {
                            Text("Age")
                            HStack(spacing: 4) {
                                NumberField(value: $store.filter.minAge, width: 44)
                                Text("–")
                                NumberField(value: $store.filter.maxAge, width: 44)
                            }
                        }
                        GridRow {
                            Text("Min CA")
                            HStack(spacing: 4) {
                                NumberField(value: $store.filter.minCA, width: 44)
                                Text("PA")
                                NumberField(value: $store.filter.minPA, width: 44)
                            }
                        }
                    }
                }

                FilterGroup(title: "Positions", active: active.contains("positions")) {
                    PositionPicker(selected: $store.filter.positions, keys: store.meta?.positionKeys ?? [])
                        .frame(height: 230)
                }

                FilterGroup(title: "Role", active: active.contains("role")) {
                    VStack(alignment: .leading, spacing: 6) {
                        Picker("Role", selection: $store.filter.roleCode) {
                            Text("Best role (any)").tag("")
                            ForEach(Roles.all) { r in Text("\(r.name) (\(r.code))").tag(r.code) }
                        }
                        .labelsHidden()
                        if !store.filter.roleCode.isEmpty {
                            HStack {
                                Text("Min")
                                Slider(value: $store.filter.minRoleScore, in: 0...20, step: 0.5)
                                Text(String(format: "%.1f", store.filter.minRoleScore)).monospacedDigit().frame(width: 32)
                            }
                            Toggle("Include players who don't play there", isOn: $store.filter.roleAnyPosition)
                                .font(.callout)
                                .help("Off: only players who are natural in one of this role's positions (or the positions you picked)")
                        }
                    }
                }

                FilterGroup(title: "Meta & development", active: active.contains("meta")) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Min meta")
                            Slider(value: $store.filter.minMeta, in: 0...20, step: 0.5)
                            Text(String(format: "%.1f", store.filter.minMeta)).monospacedDigit().frame(width: 32)
                        }
                        HStack {
                            Text("Min CA growth")
                            NumberField(value: $store.filter.minGrowth, width: 44)
                        }
                        Toggle("New regens only", isOn: $store.filter.onlyNew)
                        Toggle("Free agents only", isOn: $store.filter.freeAgentsOnly)
                    }
                }

                FilterGroup(title: "Contract & money (\(store.currency.symbol))", active: active.contains("money")) {
                    VStack(alignment: .leading, spacing: 6) {
                        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
                            GridRow { Text("Max value"); NumberField(value: $store.filter.maxValue, width: 120) }
                            GridRow { Text("Max wage/wk"); NumberField(value: $store.filter.maxWage, width: 120) }
                            GridRow { Text("Expires by"); NumberField(value: $store.filter.expiringBy, width: 120, grouping: false) }
                        }
                        Toggle("Transfer listed only", isOn: $store.filter.listedOnly)
                        Toggle("Hide not for sale", isOn: $store.filter.hideNotForSale)
                    }
                }

                FilterGroup(title: "Attributes", active: active.contains("attributes")) {
                    AttributeRulesEditor(rules: $store.filter.rules, keys: attributeKeys(store.meta))
                }

                Button("Reset all filters") { store.filter.clearAll() }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .padding(10)
        }
        .background(Theme.bg)
    }

    private func attributeKeys(_ meta: ExportMeta?) -> [String] {
        guard let meta else { return [] }
        let visible = meta.playerAttrKeys.filter { $0 != "LeftFoot" && $0 != "RightFoot" }.sorted()
        return store.hideHidden ? visible : visible + meta.hiddenKeys + meta.personalityKeys
    }
}

/// Position toggles laid out on a pitch; selected positions light up.
struct PositionPicker: View {
    @Binding var selected: Set<String>
    let keys: [String]

    var body: some View {
        GeometryReader { geo in
            ZStack {
                PitchBackground()
                ForEach(keys, id: \.self) { k in
                    if let pt = PitchLayout.point(k) {
                        let on = selected.contains(k)
                        Button {
                            if on { selected.remove(k) } else { selected.insert(k) }
                        } label: {
                            Text(k)
                                .font(.system(size: 10.5, weight: .bold))
                                .foregroundStyle(on ? Color.white : Color.white.opacity(0.85))
                                .frame(width: 40, height: 22)
                                .background(on ? Theme.accent : Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 5))
                                .overlay(RoundedRectangle(cornerRadius: 5).stroke(on ? Color.white : Color.white.opacity(0.25),
                                                                                 lineWidth: on ? 1.5 : 1))
                        }
                        .buttonStyle(.plain)
                        .position(x: pt.x * geo.size.width, y: pt.y * geo.size.height)
                    }
                }
            }
        }
    }
}

struct NumberField: View {
    @Binding var value: Int
    var width: CGFloat = 52
    var grouping = true
    var body: some View {
        TextField("", value: $value, format: grouping ? .number : .number.grouping(.never))
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.trailing)
            .frame(width: width)
    }
}

struct AttributeRulesEditor: View {
    @Binding var rules: [AttributeRule]
    let keys: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach($rules) { $rule in
                HStack(spacing: 6) {
                    Picker("", selection: $rule.key) {
                        ForEach(keys, id: \.self) { Text(AttributeGroups.label($0)).tag($0) }
                    }
                    .labelsHidden()
                    Text("≥")
                    Stepper(value: $rule.min, in: 1...20) { AttrBox(value: rule.min) }
                    Button { rules.removeAll { $0.id == rule.id } } label: { Image(systemName: "minus.circle.fill") }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
            }
            Button {
                rules.append(AttributeRule(key: keys.first(where: { $0 == "Pace" }) ?? keys.first ?? "Pace", min: 15))
            } label: {
                Label("Add attribute rule", systemImage: "plus.circle")
            }
            .disabled(keys.isEmpty)
        }
    }
}

// MARK: - Player profile

struct PlayerDetail: View {
    let row: PlayerRow
    var onClose: (() -> Void)? = nil
    @Environment(Store.self) private var store

    var body: some View {
        let p = row.person
        let meta = store.meta
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header(p)
                abilityTiles(p)
                if let a = store.interest(for: row) { interestCard(a) }
                if let meta { insightsCard(meta) }
                if let meta { positionsAndRoles(p, meta) }
                if let attrs = p.a, let meta { attributeCards(attrs, meta) }
                if !store.hideHidden, let meta { hiddenCards(p, meta) }
            }
            .padding(12)
        }
        .background(Theme.bg)
        // Actions live in the panel's part of the window toolbar: buttons placed at the top of the
        // panel's scrolling content were hit-tested a toolbar-height off (clicking ✕ hit Compare).
        .toolbar {
            ToolbarItemGroup {
                Button { store.copyText([p.n]) } label: { Label("Copy Name", systemImage: "doc.on.doc") }
                    .help("Copy the name for FM's search")
                Button { store.toggleCompare(row.id) } label: {
                    Label("Compare", systemImage: store.compareIds.contains(row.id) ? "rectangle.split.3x1.fill" : "rectangle.split.3x1")
                }
                .help("Add to or remove from the comparison")
                Button { store.toggleShortlist(row.id) } label: {
                    Label("Shortlist", systemImage: store.shortlist.contains(row.id) ? "star.fill" : "star")
                }
                .help("Add to or remove from your shortlist")
                if let onClose {
                    Button(action: onClose) { Label("Close", systemImage: "xmark") }
                        .keyboardShortcut(.cancelAction)
                        .help("Close (Esc)")
                }
            }
        }
    }

    /// Red and green flags, plus how much of his potential a young player is likely to reach.
    @ViewBuilder private func insightsCard(_ meta: ExportMeta) -> some View {
        let flags = Flags.of(row.person, meta: meta, includeHidden: !store.hideHidden)
        let dev = Development.outlook(row, meta: meta)
        if !flags.isEmpty || dev != nil {
            VStack(alignment: .leading, spacing: 8) {
                if let dev {
                    HStack(spacing: 8) {
                        Text("Development outlook").font(.callout).foregroundStyle(.secondary)
                        Spacer(minLength: 4)
                        Text(dev.label)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(devColor(dev).opacity(0.18), in: Capsule())
                            .foregroundStyle(devColor(dev))
                    }
                    Text("Likely to reach about **\(dev.likelyPeak)** ability (potential \(row.pa), now \(row.ca))")
                        .font(.callout)
                    if !dev.reasons.isEmpty {
                        Text(dev.reasons.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                    }
                }
                if !flags.isEmpty {
                    if dev != nil { Divider() }
                    FlowLayout(spacing: 6) {
                        ForEach(flags) { f in FlagChip(flag: f) }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .fmCard()
        }
    }

    private func devColor(_ d: DevelopmentOutlook) -> Color {
        d.realisation >= 0.75 ? .green : d.realisation >= 0.55 ? Color(red: 0.75, green: 0.85, blue: 0.3)
            : d.realisation >= 0.4 ? .orange : .red
    }

    private func interestCard(_ a: InterestAssessment) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("Interest in joining \(store.myClub)").font(.callout).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 4)
                InterestBadge(a: a)
            }
            if !a.reasons.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(a.reasons, id: \.self) { Chip(label: $0) }
                }
            }
            Text("Estimate. FM works this out live and doesn't store it.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .fmCard()
    }

    // Name, club, age, nationality and actions
    private func header(_ p: Person) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(p.n).font(.title2.bold()).lineLimit(2).minimumScaleFactor(0.7)
                        .contextMenu {
                            Button("Copy Name") { store.copyText([p.n]) }
                        }
                        .help("Right-click to copy the name for FM's search")
                    if row.isNew { Tag(text: "NEW", color: .purple) }
                }
                Text(p.club ?? "Free agent").font(.headline)
                if let d = p.div { Text(d).font(.callout).foregroundStyle(.secondary) }
                Text(subtitle(p)).font(.callout).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
        }
        .fmCard()
    }

    private func abilityTiles(_ p: Person) -> some View {
        let sym = store.currency.symbol, rate = store.rate
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 8)], spacing: 8) {
            StarTile(title: "Current ability", value: p.ca)
            StarTile(title: "Potential", value: p.pa)
            Stat(title: "Meta score", value: String(format: "%.1f", row.meta), color: AttrColor.color(Int(row.meta.rounded())))
            if row.growth != PlayerRow.noGrowth {
                Stat(title: "CA growth", value: row.growth > 0 ? "+\(row.growth)" : "\(row.growth)",
                     color: row.growth > 0 ? .green : row.growth < 0 ? .red : .secondary)
            }
            Stat(title: "Value", value: Money.format(p.val, symbol: sym, perGbp: rate))
            Stat(title: "Wage / week", value: Money.format(p.wage, symbol: sym, perGbp: rate))
            Stat(title: "Contract", value: p.exp.map { String($0.prefix(7)) } ?? "—")
            if p.lst == true { Stat(title: "Status", value: "Listed", color: .orange) }
            if p.nfs == true { Stat(title: "Status", value: "Not for sale", color: .red) }
        }
    }

    private func positionsAndRoles(_ p: Person, _ meta: ExportMeta) -> some View {
        let top = Roles.all.indices.sorted { row.roleScores[$0] > row.roleScores[$1] }.prefix(7)
        let pitch = PositionPitch(familiarity: p.pos ?? [], keys: meta.positionKeys).frame(width: 118)
        let roles = VStack(alignment: .leading, spacing: 5) {
            Text("ROLES").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(Array(top), id: \.self) { i in
                let r = Roles.all[i]
                let natural = !row.positionSet.isDisjoint(with: Set(r.positions.compactMap { meta.positionKeys.firstIndex(of: $0) }))
                HStack(spacing: 6) {
                    Text(r.name).font(.callout).lineLimit(1).minimumScaleFactor(0.8)
                        .foregroundStyle(natural ? Color.primary : Color.secondary)
                    Spacer(minLength: 4)
                    ProgressView(value: min(row.roleScores[i], 20), total: 20)
                        .tint(AttrColor.color(Int(row.roleScores[i].rounded())))
                        .frame(width: 60)
                    Text(String(format: "%.1f", row.roleScores[i])).font(.callout.bold()).monospacedDigit()
                        .frame(width: 32, alignment: .trailing)
                }
            }
        }
        return ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 14) { pitch; roles.frame(minWidth: 220) }
            VStack(alignment: .leading, spacing: 12) { pitch; roles }
        }
        .fmCard()
    }

    private func attributeCards(_ attrs: [UInt8], _ meta: ExportMeta) -> some View {
        let values = zipValues(meta.playerAttrKeys, attrs)
        var groups: [(String, [String])] = []
        if row.isGoalkeeper { groups.append(("Goalkeeping", AttributeGroups.goalkeeping)) }
        groups.append(("Technical", AttributeGroups.technical))
        groups.append(("Mental", AttributeGroups.mental))
        groups.append(("Physical", AttributeGroups.physical))
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 10, alignment: .top)], alignment: .leading, spacing: 10) {
            ForEach(groups, id: \.0) { g in
                AttrGroupCard(title: g.0, keys: g.1, values: values)
            }
        }
    }

    private func hiddenCards(_ p: Person, _ meta: ExportMeta) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 10, alignment: .top)], alignment: .leading, spacing: 10) {
            AttrGroupCard(title: "Hidden", keys: meta.hiddenKeys, values: zipValues(meta.hiddenKeys, p.h))
            AttrGroupCard(title: "Personality", keys: meta.personalityKeys, values: zipValues(meta.personalityKeys, p.p))
        }
    }

    private func subtitle(_ p: Person) -> String {
        var parts = ["\(row.age) years", p.nat ?? "—"]
        if let h = p.ht { parts.append("\(h) cm") }
        switch p.ft {
        case "L": parts.append("left foot")
        case "R": parts.append("right foot")
        case "B": parts.append("both feet")
        default: break
        }
        if !row.positions.isEmpty { parts.append(row.positions) }
        return parts.joined(separator: " · ")
    }

    private func zipValues(_ keys: [String], _ vals: [UInt8]?) -> [String: Int] {
        guard let vals else { return [:] }
        var d: [String: Int] = [:]
        for (i, k) in keys.enumerated() where i < vals.count { d[k] = Int(vals[i]) }
        return d
    }
}

struct AttrGroupCard: View {
    let title: String
    let keys: [String]
    let values: [String: Int]

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.bottom, 3)
            ForEach(keys, id: \.self) { k in
                HStack(spacing: 6) {
                    Text(AttributeGroups.label(k)).font(.callout).lineLimit(1).minimumScaleFactor(0.75)
                    Spacer(minLength: 4)
                    AttrBox(value: values[k] ?? 0)
                }
            }
        }
        .fmCard(padding: 10)
    }
}

struct StarTile: View {
    let title: String
    let value: Int
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            HStack(spacing: 6) {
                Text(value > 0 ? "\(value)" : "—").font(.title3.bold()).monospacedDigit()
                StarsView(value: Stars.value(value), size: 10)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.stroke))
    }
}

struct Stat: View {
    let title: String
    let value: String
    var color: Color = .primary
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Text(value).font(.title3.bold()).monospacedDigit().foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.stroke))
    }
}

struct Tag: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text).font(.caption.bold()).padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.3), in: Capsule())
    }
}

// MARK: - Searches menu

struct PresetsMenu: View {
    @Environment(Store.self) private var store
    @State private var naming = false
    @State private var newName = ""

    var body: some View {
        Menu {
            SwiftUI.Section("Ready-made") {
                ForEach(store.builtInPresets) { p in
                    Button(p.name) { store.applyPreset(p) }
                }
            }
            if !store.savedPresets.isEmpty {
                SwiftUI.Section("Saved") {
                    ForEach(store.savedPresets) { p in
                        Button(p.name) { store.applyPreset(p) }
                    }
                }
                Menu("Delete saved search") {
                    ForEach(store.savedPresets) { p in
                        Button(p.name, role: .destructive) { store.deletePreset(p) }
                    }
                }
            }
            Divider()
            Button("Save current filters…") { newName = ""; naming = true }
        } label: {
            Label("Searches", systemImage: "bookmark")
        }
        .fixedSize()
        .alert("Save search", isPresented: $naming) {
            TextField("Name", text: $newName)
            Button("Save") { store.saveCurrentFilter(as: newName) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Saves all current filters under this name.")
        }
    }
}

/// A green or red flag with the attribute behind it as a tooltip.
struct FlagChip: View {
    let flag: PlayerFlag
    var body: some View {
        Label(flag.text, systemImage: flag.good ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
            .font(.callout)
            .lineLimit(1)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background((flag.good ? Color.green : Color.red).opacity(0.15), in: Capsule())
            .foregroundStyle(flag.good ? Color.green : Color(red: 1, green: 0.45, blue: 0.4))
            .help(flag.detail)
    }
}
