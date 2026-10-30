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
                .preferredColorScheme(.dark)
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
                .preferredColorScheme(.dark)
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
    case players, squad, compare, radar, staff, shortlist, calibration
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
        case .players: "person.3.fill"
        case .squad: "sportscourt.fill"
        case .compare: "chart.bar.xaxis"
        case .radar: "chart.line.uptrend.xyaxis"
        case .staff: "person.crop.rectangle.stack.fill"
        case .shortlist: "star.fill"
        case .calibration: "scope"
        }
    }
}

struct ContentView: View {
    @Environment(Store.self) private var store
    @State private var section: SidebarItem? = .players

    var body: some View {
        @Bindable var store = store
        NavigationSplitView {
            List(selection: $section) {
                ForEach(SidebarItem.allCases) { s in
                    Label(s.title, systemImage: s.icon)
                        .badge(badge(for: s))
                        .tag(s)
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 215, max: 280)
        } detail: {
            VStack(spacing: 0) {
                if let hint = store.hint {
                    Banner(text: hint, style: .orange) { store.hint = nil }
                }
                if let err = store.loadError {
                    Banner(text: err, style: .red) { store.loadError = nil }
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
        .sheet(isPresented: $store.showCompare) {
            CompareView().environment(store).preferredColorScheme(.dark)
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

/// Bottom bar: scan status, counts, warnings. Keeps the toolbar uncluttered at any width.
struct StatusBar: View {
    @Environment(Store.self) private var store
    @State private var showWarnings = false

    var body: some View {
        HStack(spacing: 10) {
            statusIcon
            Text(store.status?.message ?? "Ready").lineLimit(1).truncationMode(.tail)
            if let p = store.status?.progress, store.isBusy {
                ProgressView(value: p).frame(width: 120)
            }
            Spacer(minLength: 8)
            if let m = store.meta {
                Text("\(store.allPlayers.count.formatted()) players · \(store.allStaff.count.formatted()) staff")
                    .lineLimit(1)
                if let g = m.gameDate, let d = Ages.date(g) {
                    Text("· in-game \(d.formatted(.dateTime.day().month(.abbreviated).year()))").lineLimit(1)
                        .help("Read from the game; ages and contract dates use it")
                }
                if let s = m.scannedAt {
                    Text("· scanned \(s.replacingOccurrences(of: "T", with: " ").prefix(16))").lineLimit(1)
                }
                if let w = m.warnings, !w.isEmpty {
                    Button { showWarnings.toggle() } label: {
                        Label("\(w.count)", systemImage: "exclamationmark.triangle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.yellow)
                    .help("Scan notes")
                    .popover(isPresented: $showWarnings, arrowEdge: .top) {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(w, id: \.self) { Text("• " + $0).fixedSize(horizontal: false, vertical: true) }
                        }
                        .padding(14)
                        .frame(width: 380)
                    }
                }
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .frame(height: 28)
        .background(Theme.panel)
        .overlay(alignment: .top) { Divider() }
    }

    @ViewBuilder private var statusIcon: some View {
        switch store.status?.state ?? "" {
        case "scanning": ProgressView().controlSize(.small)
        case "error": Image(systemName: "exclamationmark.octagon.fill").foregroundStyle(.red)
        case "done": Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        default: Image(systemName: "circle.fill").font(.system(size: 7))
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
        .background(style.opacity(0.22))
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
