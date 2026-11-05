import AppKit
import PitchsideCore
import SwiftUI

@main
struct PitchsideApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var store: Store

    init() {
        Migration.run()   // before Store reads its saved settings
        _store = State(initialValue: Store())
    }

    var body: some Scene {
        WindowGroup("Pitchside") {
            ContentView()
                .environment(store)
                .frame(minWidth: 980, minHeight: 620)
                .preferredColorScheme(.light)
                .tint(Theme.accent)
        }
        .defaultSize(width: 1500, height: 900)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Scan Game") { store.scan() }
                    .keyboardShortcut("r", modifiers: .command)
                Button("Open Data Folder") { store.revealFolder() }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
            }
        }
        Settings {
            SettingsView()
                .environment(store)
                .preferredColorScheme(.light)
        }
    }
}

/// Lets the app show a normal Dock icon and window when started from `swift run` as well.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

enum SidebarItem: String, CaseIterable, Identifiable {
    case players, shortlist, radar, squad, compare, staff, calibration
    var id: String { rawValue }
    var title: String {
        switch self {
        case .players: "Players"
        case .squad: "Tactics & squad"
        case .compare: "Compare teams"
        case .radar: "Growth & regens"
        case .staff: "Staff"
        case .shortlist: "Shortlist"
        case .calibration: "Calibration"
        }
    }
    var icon: String {
        switch self {
        case .players: "person.2"
        case .shortlist: "star"
        case .radar: "chart.line.uptrend.xyaxis"
        case .squad: "sportscourt"
        case .compare: "chart.bar"
        case .staff: "person.text.rectangle"
        case .calibration: "slider.horizontal.3"
        }
    }
    struct Group: Identifiable { let id: String; let items: [SidebarItem] }
    static let groups: [Group] = [
        Group(id: "Scouting", items: [.players, .shortlist, .radar]),
        Group(id: "Club", items: [.squad, .compare, .staff]),
        Group(id: "Tools", items: [.calibration]),
    ]
}

/// The Pitchside mark: a P drawn from pitch lines (touchline stem, centre-circle bowl) with the centre spot.
struct LogoMark: View {
    var size: CGFloat = 30
    var body: some View {
        Canvas { ctx, sz in
            let k = sz.width / 824        // drawn on the icon's 824-unit tile
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: (x - 100) * k, y: (y - 100) * k) }
            let tile = Path(roundedRect: CGRect(origin: .zero, size: sz), cornerRadius: 186 * k, style: .continuous)
            ctx.fill(tile, with: .linearGradient(Gradient(colors: [Color(hex: 0x2C4A73), Color(hex: 0x1B2638)]),
                                                startPoint: .zero, endPoint: CGPoint(x: 0, y: sz.height)))
            var line = Path(); line.move(to: p(196, 456)); line.addLine(to: p(828, 456))
            ctx.stroke(line, with: .color(Color(hex: 0xF6F4EE).opacity(0.12)), lineWidth: max(1, 10 * k))
            var letter = Path()
            letter.move(to: p(392, 726)); letter.addLine(to: p(392, 316)); letter.addLine(to: p(532, 316))
            letter.addArc(center: p(532, 456), radius: 140 * k, startAngle: .degrees(-90), endAngle: .degrees(90), clockwise: false)
            letter.addLine(to: p(392, 596))
            ctx.stroke(letter, with: .color(Color(hex: 0xF6F4EE)),
                       style: StrokeStyle(lineWidth: 84 * k, lineCap: .round, lineJoin: .round))
            let r = 36 * k
            ctx.fill(Path(ellipseIn: CGRect(x: p(532, 456).x - r, y: p(532, 456).y - r, width: 2 * r, height: 2 * r)),
                     with: .color(Color(hex: 0x5FA37C)))
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Pitchside")
    }
}

struct ContentView: View {
    @Environment(Store.self) private var store
    @State private var section: SidebarItem? = .players
    @State private var showFind = false

    var body: some View {
        @Bindable var store = store
        NavigationSplitView {
            List(selection: $section) {
                ForEach(SidebarItem.groups) { group in
                    SwiftUI.Section(group.id) {
                        ForEach(group.items) { s in
                            Label {
                                Text(s.title)
                            } icon: {
                                Image(systemName: s.icon).frame(width: 22, alignment: .center)
                            }
                            .badge(badge(for: s))
                            .tag(s)
                        }
                    }
                }
                SavedSearchesSection(section: $section)
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                HStack(spacing: 10) {
                    LogoMark(size: 30)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Pitchside").font(.headline).foregroundStyle(Theme.ink)
                        Text("Scouting workspace").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 14).padding(.top, 6).padding(.bottom, 10)
            }
            .navigationSplitViewColumnWidth(min: 210, ideal: 225, max: 290)
        } detail: {
            VStack(spacing: 0) {
                if let hint = store.hint {
                    Banner(text: hint, style: Theme.warn) { store.hint = nil }
                }
                if let err = store.loadError {
                    Banner(text: err, style: Theme.bad) { store.loadError = nil }
                }
                Group {
                    switch section ?? .players {
                    case .players: PlayersView(shortlistOnly: false)
                    case .squad: SquadView()
                    case .compare: TeamsCompareView()
                    case .radar: RadarView()
                    case .shortlist: PlayersView(shortlistOnly: true)
                    case .staff: StaffView()
                    case .calibration: CalibrationView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                StatusBar()
            }
            .background(Theme.bg)
        }
        .sheet(isPresented: $showFind) {
            FindPlayerSheet().environment(store).preferredColorScheme(.light)
        }
        .sheet(isPresented: $store.showCompare) {
            CompareView().environment(store).preferredColorScheme(.light)
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Show", selection: $store.genderFilter) {
                    Text("Men").tag(1)
                    Text("Women").tag(2)
                    Text("Both").tag(0)
                }
                .pickerStyle(.segmented)
                .fixedSize()
                .help("Show men's or women's football (filters instantly)")
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    showFind = true
                } label: {
                    Label("Find player", systemImage: "magnifyingglass")
                }
                .keyboardShortcut("f", modifiers: .command)
                .help("Find any scanned player by name, ignoring every filter (⌘F)")
                Button {
                    store.showCompare = true
                } label: {
                    Label("Compare", systemImage: "rectangle.split.3x1")
                }
                .badge(store.compareIds.count)
                .disabled(store.compareIds.isEmpty)
                .help("Compare up to 3 players side by side")
                Button {
                    store.scan()
                } label: {
                    Label("Scan", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(store.isBusy)
                .help("Read the loaded save from FM (⌘R)")
            }
        }
    }

    private func badge(for s: SidebarItem) -> Int {
        switch s {
        case .shortlist: return store.shortlist.count
        case .radar: return store.newCount
        default: return 0
        }
    }
}

/// Saved player searches, one click away: applies the filters and opens Players.
struct SavedSearchesSection: View {
    @Binding var section: SidebarItem?
    @Environment(Store.self) private var store
    @State private var renaming: NamedFilter?
    @State private var newName = ""
    @State private var naming = false

    var body: some View {
        SwiftUI.Section("Saved searches") {
            ForEach(store.savedPresets) { p in
                Button {
                    store.applyPreset(p)
                    section = .players
                } label: {
                    Label {
                        Text(p.name).lineLimit(1)
                    } icon: {
                        Image(systemName: store.filter.sameSearch(as: p.filter) ? "bookmark.fill" : "bookmark")
                            .frame(width: 22, alignment: .center)
                    }
                }
                .buttonStyle(.plain)
                .help(p.filter.chips(currency: store.currency.symbol, roleName: { Roles.role($0)?.label ?? $0 })
                        .map(\.label).joined(separator: " · "))
                .contextMenu {
                    Button("Update with current filters") { store.updatePreset(p) }
                    Button("Rename…") { newName = p.name; renaming = p }
                    Divider()
                    Button("Delete", role: .destructive) { store.deletePreset(p) }
                }
            }
            Button {
                newName = ""; naming = true
            } label: {
                Label { Text("Save current search…") } icon: { Image(systemName: "plus").frame(width: 22, alignment: .center) }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .disabled(store.filter.chips(currency: "", roleName: { $0 }).isEmpty)
            .help("Save the Players filters you have on now")
        }
        .alert("Save search", isPresented: $naming) {
            TextField("Name", text: $newName)
            Button("Save") { store.saveCurrentFilter(as: newName) }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Saves all current Players filters under this name.") }
        .alert("Rename search", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newName)
            Button("Rename") { if let r = renaming { store.renamePreset(r, to: newName) } }
            Button("Cancel", role: .cancel) {}
        }
    }
}

/// Bottom bar: scan status, what's loaded, how fresh it is. Keeps the toolbar uncluttered at any width.
struct StatusBar: View {
    @Environment(Store.self) private var store
    @State private var showWarnings = false

    var body: some View {
        HStack(spacing: 8) {
            statusIcon
            Text(store.status?.message ?? "Ready").lineLimit(1).truncationMode(.tail)
            if let p = store.status?.progress, store.isBusy {
                ProgressView(value: p).frame(width: 120).tint(Theme.accent)
            }
            if store.selectionCount > 1 {
                dot
                Text("\(store.selectionCount) selected").foregroundStyle(Theme.accent)
                    .help("Right-click for actions on all of them; Delete removes them from the shortlist on the Shortlist screen")
            }
            Spacer(minLength: 8)
            if let m = store.meta {
                Text("\(store.allPlayers.count.formatted()) players · \(store.allStaff.count.formatted()) staff")
                    .lineLimit(1)
                if let g = m.gameDate, let d = Ages.date(g) {
                    dot
                    Label(d.formatted(.dateTime.day().month(.abbreviated).year()), systemImage: "calendar")
                        .lineLimit(1)
                        .help("In-game date of the scan; ages and contract dates use it")
                }
                if let s = m.scannedAt, let when = Self.parse(s) {
                    dot
                    TimelineView(.periodic(from: .now, by: 60)) { ctx in
                        Text("Scanned \(Self.relative(when, now: ctx.date))").lineLimit(1)
                    }
                    .help("Scanned \(when.formatted(date: .abbreviated, time: .shortened)). Played on since? Scan again (⌘R).")
                }
                if let w = m.warnings, !w.isEmpty {
                    Button { showWarnings.toggle() } label: {
                        Label("\(w.count)", systemImage: "exclamationmark.triangle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.warn)
                    .help("Scan notes")
                    .popover(isPresented: $showWarnings, arrowEdge: .top) {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(w, id: \.self) { Text("• " + $0).fixedSize(horizontal: false, vertical: true) }
                        }
                        .padding(14)
                        .frame(width: 380)
                    }
                }
            } else if !store.isBusy {
                Text("No scan loaded: open your save in FM, then Scan (⌘R)")
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .frame(height: 28)
        .background(Theme.panel)
        .overlay(alignment: .top) { Divider() }
    }

    private var dot: some View { Text("·").foregroundStyle(.tertiary) }

    private static func parse(_ s: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return f.date(from: String(s.prefix(19)))
    }

    private static func relative(_ d: Date, now: Date) -> String {
        if now.timeIntervalSince(d) < 60 { return "just now" }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f.localizedString(for: d, relativeTo: now)
    }

    @ViewBuilder private var statusIcon: some View {
        switch store.status?.state ?? "" {
        case "scanning": ProgressView().controlSize(.small)
        case "error": Image(systemName: "exclamationmark.octagon.fill").foregroundStyle(Theme.bad)
        case "done": Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.good)
        default: Image(systemName: "circle.fill").font(.system(size: 7)).foregroundStyle(Theme.green)
        }
    }
}

struct Banner: View {
    let text: String
    let style: Color
    var onClose: (() -> Void)?
    var body: some View {
        HStack(alignment: .top) {
            Text(text).font(.callout).textSelection(.enabled)
            Spacer()
            if let onClose { Button(action: onClose) { Image(systemName: "xmark") }.buttonStyle(.plain) }
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(style.opacity(0.14))
    }
}

struct SettingsView: View {
    @Environment(Store.self) private var store
    var body: some View {
        @Bindable var store = store
        Form {
            Picker("Currency", selection: $store.currency) {
                ForEach(Currency.allCases) { Text("\($0.symbol)  \($0.rawValue.uppercased())").tag($0) }
            }
            TextField("Exchange rate (per £1)", value: $store.rate, format: .number)
            TextField("Season year for ages (0 = from game)", value: $store.seasonOverride, format: .number.grouping(.never))
            Toggle("Hide hidden attributes & personality", isOn: $store.hideHidden)
            LabeledContent("Data folder") {
                Button("Open in Finder") { store.revealFolder() }
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}


/// Find any player in the scan by name, regardless of filters, squad or the Men/Women switch.
struct FindPlayerSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var picked: UInt32?
    @FocusState private var focused: Bool

    private var results: [PlayerRow] {
        let words = ShortlistImport.normalise(query).split(separator: " ")
        guard !words.isEmpty, words.joined().count >= 2 else { return [] }
        return Array(store.allPlayers.lazy
            .filter { r in let n = ShortlistImport.normalise(r.name); return words.allSatisfy { n.contains($0) } }
            .prefix(300))
            .sorted { $0.ca > $1.ca }
    }

    private func team(_ r: PlayerRow) -> String {
        var parts: [String] = []
        if let t = r.person.tage { parts.append(t >= 100 ? "senior team" : "U\(t)") }
        if let own = r.person.own, own != r.person.club { parts.append("on loan from \(own)") }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        let found = results
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TextField("Player name (accents optional)", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .focused($focused)
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            Text(query.isEmpty ? "Searches all \(store.allPlayers.count.formatted()) scanned players, ignoring filters and the Men/Women switch."
                 : "\(found.count == 300 ? "300+" : "\(found.count)") found")
                .font(.caption).foregroundStyle(.secondary)
            HSplitView {
                List(found, selection: $picked) { r in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(r.name).fontWeight(.medium)
                            Spacer()
                            Text("CA \(r.ca)").monospacedDigit().foregroundStyle(.secondary)
                        }
                        Text([r.club.isEmpty ? "Free agent" : r.club, team(r), "\(r.age)", r.person.nat ?? "", r.positions]
                                .filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .tag(r.id)
                }
                .frame(minWidth: 320)
                Group {
                    if let id = picked, let row = store.playerRow(id) {
                        ScrollView { PlayerDetail(row: row) }
                    } else {
                        Text(found.isEmpty ? "" : "Pick a player to see his profile").foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(minWidth: 420)
            }
        }
        .padding(14)
        .frame(width: 980, height: 640)
        .onAppear { focused = true }
    }
}
