import AppKit
import PitchsideCore
import Observation
import SwiftUI

enum Currency: String, CaseIterable, Identifiable {
    case gbp, eur, usd
    var id: String { rawValue }
    var symbol: String { switch self { case .gbp: "£"; case .eur: "€"; case .usd: "$" } }
    var defaultRate: Double { switch self { case .gbp: 1; case .eur: 1.17; case .usd: 1.30 } }
}

@MainActor
@Observable
final class Store {
    // Data
    var meta: ExportMeta? { didSet { readerCache = nil } }
    @ObservationIgnored private var readerCache: StatReader?
    /// Reads attribute and stat columns; rebuilt when a new scan arrives.
    var reader: StatReader? {
        if readerCache == nil, let meta { readerCache = StatReader(meta: meta) }
        return readerCache
    }
    private(set) var allPlayers: [PlayerRow] = []
    private(set) var allStaff: [StaffRow] = []
    var players: [PlayerRow] = []
    var staff: [StaffRow] = []
    var loading = false
    var loadError: String?
    private var exportStamp: Date?

    // Filters and sorting
    var filter = PlayerFilter()
    var staffFilter = StaffFilter()
    var staffColumnKey = "Attacking"  // any FM27 staff attribute key
    var playerSort: [KeyPathComparator<PlayerRow>] = [KeyPathComparator(\PlayerRow.ca, order: .reverse)]
    var staffSort: [KeyPathComparator<StaffRow>] = [KeyPathComparator(\StaffRow.ca, order: .reverse)]

    // Plugin communication
    var status: PluginStatus?
    var hint: String?
    private var pendingRequestAt: Date?
    private var timer: Timer?

    // Calibration
    var targets: [CalibrationTarget] = [] { didSet { saveTargets() } }
    var reportText = ""

    // Shortlist & settings (persisted)
    private(set) var shortlist: Set<UInt32> = []
    /// 0 = both, 1 = men, 2 = women — an instant filter on every list.
    var genderFilter: Int = UserDefaults.standard.object(forKey: "genderFilter") as? Int ?? 1 {
        didSet {
            UserDefaults.standard.set(genderFilter, forKey: "genderFilter")
            filter.gender = genderFilter
            staffFilter.gender = genderFilter
            // Tactics and Compare teams follow the Men/Women switch; with Both they keep their own.
            if genderFilter == 1, squadWomen { squadWomen = false }
            if genderFilter == 2, !squadWomen { squadWomen = true }
            refreshSquad()
        }
    }
    /// User-added columns per table ("players", "squad", "signings", "growth"), as StatColumn ids.
    var columnSets: [String: [String]] = Store.loadJSON("columnSets") ?? StatColumns.defaults {
        didSet { Store.saveJSON(columnSets, "columnSets") }
    }

    // Comparison (up to 3 players)
    var compareIds: [UInt32] = []
    var showCompare = false

    // Saved searches
    var savedPresets: [NamedFilter] = [] {
        didSet { if let d = try? JSONEncoder().encode(savedPresets) { UserDefaults.standard.set(d, forKey: "savedPresets") } }
    }

    // Scan history (growth & new regens)
    var snapshots: [SnapshotInfo] = []
    /// Snapshot id used as the growth reference; "" = the scan before the current one.
    var referenceSnapshot = "" { didSet { recomputeHistory() } }
    var referenceLabel = ""
    private var growthMap: [UInt32: Int] = [:]
    private var previousIds: Set<UInt32>?
    var newCount = 0

    // Squad builder
    var myClub: String = UserDefaults.standard.string(forKey: "myClub") ?? "" {
        didSet { UserDefaults.standard.set(myClub, forKey: "myClub"); refreshSquad() }
    }
    /// Name of the preset or saved tactic last loaded (the working copy may have been edited since).
    var formationName: String = UserDefaults.standard.string(forKey: "formation") ?? "4-3-3" {
        didSet { UserDefaults.standard.set(formationName, forKey: "formation") }
    }
    /// The formation the squad builder uses; every position and role can be changed.
    var workingFormation: Formation = Store.initialFormation() {
        didSet { Store.saveJSON(workingFormation, "workingFormation"); refreshSquad() }
    }
    var formationEdited: Bool = UserDefaults.standard.bool(forKey: "formationEdited") {
        didSet { UserDefaults.standard.set(formationEdited, forKey: "formationEdited") }
    }
    var customFormations: [Formation] = Store.loadJSON("customFormations") ?? [] {
        didSet { Store.saveJSON(customFormations, "customFormations") }
    }
    /// Men's and women's sides share the club name, so the builder always looks at one of them.
    var squadWomen: Bool = {
        // Starts on the side the Men/Women switch shows (its own choice only when that's on Both).
        switch UserDefaults.standard.object(forKey: "genderFilter") as? Int ?? 1 {
        case 1: return false
        case 2: return true
        default: return UserDefaults.standard.bool(forKey: "squadWomen")
        }
    }() {
        didSet { UserDefaults.standard.set(squadWomen, forKey: "squadWomen"); refreshSquad() }
    }
    var transferBudget = 0       // display currency; 0 = no limit
    var wageBudget = 0           // display currency per week; 0 = no limit
    var signMinAge = 16
    var signMaxAge = 33
    /// Minimum estimated interest in joining your club: 0 any, 1 doubtful, 2 persuadable, 3 interested.
    var minInterest: Int = UserDefaults.standard.object(forKey: "minInterest") as? Int ?? 2 {
        didSet { UserDefaults.standard.set(minInterest, forKey: "minInterest"); refreshSuggestions() }
    }
    /// Estimates how keen players are to join your club; rebuilt per scan and per men's/women's side.
    private(set) var interestModel: InterestModel?
    private var interestModelWomen: Bool?
    var signForDepth = false
    /// Only sign players of these nationalities ("England" or "England, Wales"); empty = any.
    var signNationality: String = UserDefaults.standard.string(forKey: "signNationality") ?? "" {
        didSet { UserDefaults.standard.set(signNationality, forKey: "signNationality"); refreshSuggestions() }
    }
    /// The signings table's sort; empty keeps the default order (biggest gain, then younger and cheaper).
    var signingSort: [KeyPathComparator<SquadBuilder.Suggestion>] = [] {
        didSet { if !signingSort.isEmpty { suggestions.sort(using: signingSort) } }
    }

    func signingCriteria() -> SigningCriteria {
        var c = SigningCriteria()
        c.maxValueGbp = transferBudget > 0 ? Int(Double(transferBudget) / max(rate, 0.0001)) : 0
        c.maxWageGbp = wageBudget > 0 ? Int(Double(wageBudget) / max(rate, 0.0001)) : 0
        c.minAge = signMinAge
        c.maxAge = signMaxAge
        c.minInterest = minInterest > 0 ? InterestLevel(rawValue: minInterest) : nil
        c.forDepth = signForDepth
        c.nationalities = SigningCriteria.nationalities(from: signNationality)
        return c
    }
    var squadReport: SquadReport?
    /// The club's teams (first team, U21, U18…) found in contracts; empty with older scans.
    private(set) var clubTeams: [ClubTeam] = []
    /// Colours squad scores against your XI level, and meta against your starters' average.
    var squadScale: ScoreScale? { squadReport.map { ScoreScale(reference: $0.level) } }
    var squadMetaScale: ScoreScale? {
        guard let r = squadReport else { return nil }
        let xi = r.slots.compactMap(\.starter)
        guard !xi.isEmpty else { return nil }
        return ScoreScale(reference: xi.map(\.meta).reduce(0, +) / Double(xi.count))
    }
    func scoreColor(_ v: Double) -> Color { RelColor.color(v, squadScale) }

    /// Your players out on loan at other clubs.
    private(set) var loanedOut: [PlayerRow] = []
    /// True when the scan has no team data and the teams shown are estimated from ability and age.
    var teamsApproximate: Bool { clubTeams.first?.approximate ?? false }
    /// Which team the builder looks at: 0 = first team, n = n-th team by reputation, -1 = all teams.
    var squadTeamRank: Int = UserDefaults.standard.object(forKey: "squadTeamRank") as? Int ?? 0 {
        didSet { UserDefaults.standard.set(squadTeamRank, forKey: "squadTeamRank"); refreshSquad() }
    }
    /// The squad over the next three seasons, for the Timeline view.
    private(set) var squadTimeline: [SquadBuilder.SeasonPlan] = []
    /// Staff upgrades for your club, weakest area first.
    private(set) var staffAdvice: [StaffAdvisor.Advice] = []
    /// Everyone at your club (the chosen side), for the My squad list; sorted by `squadSort`.
    private(set) var squadRows: [PlayerRow] = []
    /// Where each squad player sits in the formation: "ST", "LB · backup".
    private(set) var squadRoleText: [UInt32: String] = [:]
    var squadSort: [KeyPathComparator<PlayerRow>] = [KeyPathComparator(\PlayerRow[extra: "xi"])] {
        didSet { squadRows.sort(using: squadSort) }
    }
    var selectedSlot: String? { didSet { refreshSuggestions() } }

    // MARK: Tactics advisor state
    /// Every formation fitted to your squad, best first.
    private(set) var tacticsFits: [TacticsAdvisor.FormationFit] = []
    /// The formation being looked at in Tactics (nil = the best one).
    var tacticsChoice: String? { didSet { refreshTacticsDetail() } }
    /// -1 = work it out from where your XI ranks in your league.
    var tacticsStance: Int = UserDefaults.standard.object(forKey: "tacticsStance2") as? Int ?? -1 {
        didSet { UserDefaults.standard.set(tacticsStance, forKey: "tacticsStance2"); refreshTacticsDetail() }
    }
    private(set) var tacticsSetPieces: TacticsAdvisor.SetPieces?
    private(set) var tacticsInstructions: TacticsAdvisor.Instructions?
    var tacticsFit: TacticsAdvisor.FormationFit? {
        tacticsFits.first { $0.formation.name == tacticsChoice } ?? tacticsFits.first
    }
    /// Your own tactic fitted to the squad, keeping the roles you chose.
    private(set) var myTacticFit: TacticsAdvisor.FormationFit?
    /// Set pieces and instructions follow: 0 = my tactic, 1 = the suggested shape picked in Suggested.
    var tacticsSource: Int = UserDefaults.standard.object(forKey: "tacticsSource") as? Int ?? 0 {
        didSet { UserDefaults.standard.set(tacticsSource, forKey: "tacticsSource"); refreshTacticsDetail() }
    }
    var detailFit: TacticsAdvisor.FormationFit? { tacticsSource == 0 ? (myTacticFit ?? tacticsFit) : tacticsFit }
    /// Your tactic filled from the whole club vs the first team (when a team is chosen).
    private(set) var clubPromotions: (first: Double, club: Double, promotions: [TeamCompare.Promotion])?
    /// Best signing per position of your tactic (computed on request).
    private(set) var upgrades: [SquadBuilder.Upgrade] = []
    private(set) var upgradesBusy = false
    var suggestions: [SquadBuilder.Suggestion] = []
    var clubs: [String] = []
    var nations: [String] = []
    var divisions: [String] = []
    var seasonOverride: Int = UserDefaults.standard.integer(forKey: "seasonOverride") {
        didSet { UserDefaults.standard.set(seasonOverride, forKey: "seasonOverride"); rebuildRows() }
    }
    var currency: Currency = Currency(rawValue: UserDefaults.standard.string(forKey: "currency") ?? "gbp") ?? .gbp {
        didSet { UserDefaults.standard.set(currency.rawValue, forKey: "currency"); rate = currency.defaultRate }
    }
    var rate: Double = UserDefaults.standard.object(forKey: "rate") as? Double ?? 1 {
        didSet { UserDefaults.standard.set(rate, forKey: "rate") }
    }
    var hideHidden: Bool = UserDefaults.standard.bool(forKey: "hideHidden") {
        didSet { UserDefaults.standard.set(hideHidden, forKey: "hideHidden") }
    }

    private var filterTask: Task<Void, Never>?

    init() {
        let saved = UserDefaults.standard.array(forKey: "shortlist") as? [Int] ?? []
        shortlist = Set(saved.map { UInt32($0) })
        if let d = UserDefaults.standard.data(forKey: "targets"),
           let t = try? JSONDecoder().decode([CalibrationTarget].self, from: d), !t.isEmpty {
            targets = t
        } else {
            var a = CalibrationTarget(); a.kind = "player"
            var b = CalibrationTarget(); b.kind = "player"
            var c = CalibrationTarget(); c.kind = "staff"
            targets = [a, b, c]
        }
        if let d = UserDefaults.standard.data(forKey: "savedPresets"),
           let p = try? JSONDecoder().decode([NamedFilter].self, from: d) { savedPresets = p }
        filter.gender = genderFilter
        staffFilter.gender = genderFilter
        loadReport()
        startPolling()
        reload()
    }

    var season: Int {
        if seasonOverride > 1900 { return seasonOverride }
        // FM seasons start in summer: January–June 2027 is still the 2026/27 season.
        let c = Calendar(identifier: .gregorian).dateComponents([.year, .month], from: referenceDate)
        return (c.year ?? 2026) - ((c.month ?? 7) < 7 ? 1 : 0)
    }

    // MARK: - Loading

    var referenceDate: Date {
        if seasonOverride > 1900, let d = Ages.date("\(seasonOverride)-08-01") { return d }
        return Ages.date(meta?.gameDate) ?? Date()
    }

    func reload() {
        guard FileManager.default.fileExists(atPath: ScoutFiles.export.path) else { return }
        loading = true
        loadError = nil
        let stamp = (try? FileManager.default.attributesOfItem(atPath: ScoutFiles.export.path)[.modificationDate]) as? Date
        Task.detached(priority: .userInitiated) {
            do {
                let file = try ScoutFiles.loadExport()
                _ = try? History.save(Snapshot(export: file))
                let chosen = await MainActor.run { self.referenceSnapshot }
                let h = Store.history(for: file, chosen: chosen)
                await MainActor.run {
                    self.meta = file.meta
                    self.exportStamp = stamp
                    self.applyHistory(h, file: file)
                    self.buildRows(file)
                    self.loading = false
                }
            } catch {
                await MainActor.run {
                    self.loading = false
                    self.loadError = "Could not read export.json: \(error.localizedDescription)"
                }
            }
        }
    }

    private var lastFile: ExportFile?

    private func buildRows(_ file: ExportFile) {
        lastFile = file
        rebuildRows()
    }

    private func rebuildRows() {
        guard let file = lastFile else { return }
        let ref = referenceDate
        let shortlist = self.shortlist
        let growth = growthMap, prev = previousIds
        Task.detached(priority: .userInitiated) {
            let p = RowBuilder.players(file.players, meta: file.meta, reference: ref, shortlist: shortlist,
                                       growth: growth, previousIds: prev)
            let clubs = SquadBuilder.clubs(p)
            let nations = Array(Set(p.compactMap { $0.person.nat }.filter { !$0.isEmpty })).sorted()
            let divisions = Array(Set(p.compactMap { $0.person.div }.filter { !$0.isEmpty })).sorted()
            let s = RowBuilder.staff(file.staff, reference: ref)
            await MainActor.run {
                self.interestModel = nil
                self.allPlayers = p
                self.allStaff = s
                self.clubs = clubs
                self.nations = nations
                self.divisions = divisions
                self.refilter()
                self.refilterStaff()
                self.refreshSquad()
            }
        }
    }

    func refilter() {
        guard let meta else { players = []; return }
        filterTask?.cancel()
        let f = filter, rows = allPlayers, sort = playerSort, perUnit = 1 / max(rate, 0.0001)
        let roleIdx = Roles.all.firstIndex { $0.code == f.roleCode }
        let cols = columns(for: "players")
        if cols.contains(where: { $0.id == "gen.interest" }) { ensureInterestModel() }
        let reader = self.reader, score = interestScorer()
        filterTask = Task.detached(priority: .userInitiated) {
            var out = Filtering.apply(f, to: rows, meta: meta, gbpPerUnit: perUnit)
            for i in out.indices {
                out[i].selectedRoleScore = roleIdx.map { out[i].roleScores[$0] } ?? out[i].bestRoleScore
            }
            reader?.fill(&out, cols, interest: score)
            out.sort(using: sort)
            if Task.isCancelled { return }
            let result = out
            await MainActor.run {
                // The sort may have changed while filtering (picking a role re-sorts by it).
                var rows = result
                if self.playerSort != sort { rows.sort(using: self.playerSort) }
                self.players = rows
            }
        }
    }

    func resort() { players.sort(using: playerSort) }

    func refilterStaff() {
        guard let meta else { staff = []; return }
        let idx = meta.staffAttrKeys.firstIndex(of: staffColumnKey)
        var out = Filtering.apply(staffFilter, to: allStaff, meta: meta)
        for i in out.indices {
            out[i].selectedAttr = idx.flatMap { j in out[i].person.s.flatMap { j < $0.count ? Int($0[j]) : nil } } ?? 0
        }
        out.sort(using: staffSort)
        staff = out
    }

    func resortStaff() { staff.sort(using: staffSort) }

    func playerRow(_ id: UInt32) -> PlayerRow? { players.first { $0.id == id } ?? allPlayers.first { $0.id == id } }
    func staffRow(_ id: UInt32) -> StaffRow? { staff.first { $0.id == id } ?? allStaff.first { $0.id == id } }

    // MARK: - Shortlist

    func toggleShortlist(_ id: UInt32) {
        if shortlist.contains(id) { shortlist.remove(id) } else { shortlist.insert(id) }
        UserDefaults.standard.set(shortlist.map { Int($0) }, forKey: "shortlist")
        let on = shortlist.contains(id)
        if let i = allPlayers.firstIndex(where: { $0.id == id }) { allPlayers[i].shortlisted = on }
        if let i = players.firstIndex(where: { $0.id == id }) { players[i].shortlisted = on }
        if filter.shortlistOnly { refilter() }
    }

    func exportShortlistCSV() -> String {
        var lines = ["Name,Age,Club,Positions,CA,PA,Value,Wage,Contract"]
        for r in allPlayers where r.shortlisted {
            let cells = [r.name, "\(r.age)", r.club, r.positions, "\(r.ca)", "\(r.pa)",
                         r.value >= 0 ? "\(r.value)" : "", r.wage >= 0 ? "\(r.wage)" : "", r.expires]
            lines.append(cells.map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"" }.joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Plugin requests

    var isBusy: Bool { status?.state == "scanning" }

    // Always scan both databases; the Men/Women switch filters instantly.
    func scan() {
        var r = PluginRequest(mode: "dump", database: "both")
        if !myClub.isEmpty { r.club = myClub }
        send(r)
    }

    func calibrate() {
        let valid = targets.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !valid.isEmpty else { hint = "Enter at least one name to calibrate."; return }
        send(PluginRequest(mode: "discover", database: "both", targets: valid))
    }

    private func send(_ r: PluginRequest) {
        do {
            try ScoutFiles.send(r)
            pendingRequestAt = Date()
            hint = nil
            status = PluginStatus(state: "scanning", mode: r.mode, id: r.id, progress: 0,
                                  message: "Waiting for the plugin…")
        } catch {
            hint = "Could not write the request: \(error.localizedDescription)"
        }
    }

    private func startPolling() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func tick() {
        let fm = FileManager.default
        if let s = ScoutFiles.readStatus(), s != status {
            let finishedDiscovery = s.state == "done" && s.mode == "discover" && status?.state == "scanning"
            status = s
            if finishedDiscovery { loadReport() }
        }
        // Request still lying there after a few seconds → plugin isn't running.
        if let t = pendingRequestAt {
            if !fm.fileExists(atPath: ScoutFiles.request.path) {
                pendingRequestAt = nil
            } else if Date().timeIntervalSince(t) > 5 {
                hint = "The plugin hasn't picked up the request. Is FM running through the modded launcher, with a save loaded?"
            }
        }
        // New export on disk → load it.
        if let stamp = (try? fm.attributesOfItem(atPath: ScoutFiles.export.path)[.modificationDate]) as? Date,
           stamp != exportStamp, !loading, status?.state != "scanning" {
            reload()
        }
    }

    // MARK: - Columns

    func columns(for table: String) -> [StatColumn] {
        (columnSets[table] ?? StatColumns.defaults[table] ?? []).compactMap(StatColumn.init(id:))
    }

    func hasColumn(_ c: StatColumn, in table: String) -> Bool { columns(for: table).contains(c) }

    func toggleColumn(_ c: StatColumn, in table: String) {
        var ids = columns(for: table).map(\.id)
        if let i = ids.firstIndex(of: c.id) { ids.remove(at: i) } else { ids.append(c.id) }
        columnSets[table] = ids
        columnsChanged(table)
    }

    func resetColumns(_ table: String) {
        columnSets[table] = StatColumns.defaults[table] ?? []
        columnsChanged(table)
    }

    private func columnsChanged(_ table: String) {
        switch table {
        case "players": refilter()
        case "squad": refreshSquad()
        default: break
        }
    }

    /// Interest score for sorting, as a value-type closure safe to use off the main thread.
    func interestScorer() -> @Sendable (PlayerRow) -> Double? {
        let model = interestModel, club = myClub, women = squadWomen, season = season
        return { r in
            guard !club.isEmpty, (r.person.f == 1) == women else { return nil }
            return model?.assess(r, joining: club, season: season)?.score
        }
    }

    /// Display value for a user-added column (nil = no data).
    func statValue(_ c: StatColumn, _ r: PlayerRow) -> Double? { reader?.value(c, r) }

    func money(_ gbp: Int?) -> String { Money.format(gbp, symbol: currency.symbol, perGbp: rate) }

    /// Puts a player's full name or surname on the clipboard, ready to paste into FM's search.
    func copyName(_ ids: Set<UInt32>) {
        copyText(ids.compactMap { playerRow($0) }.map(\.name))
    }

    func copyStaffName(_ ids: Set<UInt32>) {
        copyText(ids.compactMap { staffRow($0) }.map(\.name))
    }

    func copyText(_ lines: [String]) {
        guard !lines.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
    }

    func ensureInterestModel() {
        guard let meta, !allPlayers.isEmpty else { interestModel = nil; return }
        if interestModel == nil || interestModelWomen != squadWomen {
            interestModel = InterestModel(rows: SquadBuilder.team(allPlayers, women: squadWomen), meta: meta)
            interestModelWomen = squadWomen
        }
    }

    /// Estimated interest in joining your club (nil without a club, or for the other side's players).
    func interest(for r: PlayerRow) -> InterestAssessment? {
        guard !myClub.isEmpty, (r.person.f == 1) == squadWomen, let m = interestModel else { return nil }
        return m.assess(r, joining: myClub, season: season)
    }

    // MARK: - Presets

    var builtInPresets: [NamedFilter] { Presets.builtIn(season: season, perUnit: rate) }

    func applyPreset(_ p: NamedFilter) {
        var f = p.filter
        f.gender = genderFilter
        f.shortlistOnly = filter.shortlistOnly
        filter = f
    }

    func saveCurrentFilter(as name: String) {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        savedPresets.removeAll { $0.name == n }
        savedPresets.append(NamedFilter(name: n, filter: filter))
    }

    func deletePreset(_ p: NamedFilter) { savedPresets.removeAll { $0.id == p.id } }

    // MARK: - Comparison

    func toggleCompare(_ id: UInt32) {
        if let i = compareIds.firstIndex(of: id) { compareIds.remove(at: i); return }
        if compareIds.count >= 3 { compareIds.removeFirst() }
        compareIds.append(id)
    }

    var compareRows: [PlayerRow] { compareIds.compactMap { playerRow($0) } }

    // MARK: - History

    struct HistoryResult: Sendable {
        let list: [SnapshotInfo]
        let label: String
        let growth: [UInt32: Int]
        let previousIds: Set<UInt32>?
    }

    /// Picks the reference scan (chosen one, or the one before `file`) and computes growth.
    nonisolated static func history(for file: ExportFile, chosen: String) -> HistoryResult {
        let list = History.list()
        let current = History.fileName(for: file.meta.scannedAt ?? "")
        let older = list.filter { $0.id < current }
        let previous = older.last
        let reference = list.first { $0.id == chosen && $0.id != current } ?? previous
        let refSnap = reference.flatMap { History.load($0) }
        let prevSnap = previous.flatMap { History.load($0) }
        return HistoryResult(list: list,
                             label: refSnap?.label ?? "",
                             growth: refSnap.map { History.growth(current: file.players, reference: $0) } ?? [:],
                             previousIds: prevSnap.map { Set($0.ids) })
    }

    private func applyHistory(_ h: HistoryResult, file: ExportFile) {
        snapshots = h.list
        referenceLabel = h.label
        growthMap = h.growth
        previousIds = h.previousIds
        if let prev = h.previousIds {
            newCount = file.players.reduce(0) { $0 + (prev.contains($1.id) ? 0 : 1) }
        } else { newCount = 0 }
    }

    private func recomputeHistory() {
        guard let file = lastFile else { return }
        let chosen = referenceSnapshot
        Task.detached(priority: .userInitiated) {
            let h = Store.history(for: file, chosen: chosen)
            await MainActor.run {
                self.applyHistory(h, file: file)
                self.rebuildRows()
            }
        }
    }

    // MARK: - Squad builder

    var formation: Formation { workingFormation }
    var allFormations: [Formation] { Formations.presets + [Formations.blank] + customFormations }
    var isCustomFormation: Bool { customFormations.contains { $0.name == formationName } }

    private var teamRows: [PlayerRow] { SquadBuilder.team(allPlayers, women: squadWomen) }

    static func loadJSON<T: Decodable>(_ key: String) -> T? {
        guard let d = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: d)
    }

    static func saveJSON<T: Encodable>(_ value: T, _ key: String) {
        if let d = try? JSONEncoder().encode(value) { UserDefaults.standard.set(d, forKey: key) }
    }

    static func initialFormation() -> Formation {
        if let f: Formation = loadJSON("workingFormation"), !f.slots.isEmpty { return f }
        let name = UserDefaults.standard.string(forKey: "formation") ?? "4-3-3"
        let custom: [Formation] = loadJSON("customFormations") ?? []
        return (Formations.presets + custom).first { $0.name == name } ?? Formations.all[0]
    }

    /// Picks a club and switches to its men's or women's side when it only has one.
    func selectClub(_ club: String) {
        let c = SquadBuilder.genderCounts(club: club, rows: allPlayers)
        if c.men == 0 && c.women > 0 { squadWomen = true }
        else if c.women == 0 && c.men > 0 { squadWomen = false }
        myClub = club
    }

    func loadFormation(_ name: String) {
        guard let f = allFormations.first(where: { $0.name == name }) else { return }
        formationName = name
        formationEdited = false
        workingFormation = f
    }

    func resetFormation() { loadFormation(formationName) }

    private func edit(_ f: Formation, select index: Int?) {
        formationEdited = true
        workingFormation = f
        if let index, f.slots.indices.contains(index) { selectedSlot = f.slots[index].label }
    }

    func slotIndex(_ label: String?) -> Int? { workingFormation.slots.firstIndex { $0.label == label } }

    func setSlotPosition(_ index: Int, _ position: String) {
        edit(Formations.moving(index, to: position, in: workingFormation), select: index)
    }

    func setSlotRole(_ index: Int, _ role: String) {
        var f = workingFormation
        guard f.slots.indices.contains(index) else { return }
        f.slots[index].role = role
        edit(f, select: index)
    }

    func setSlotOOP(_ index: Int, _ role: String) {
        var f = workingFormation
        guard f.slots.indices.contains(index) else { return }
        f.slots[index].oop = role
        edit(f, select: index)
    }

    /// Takes a formation (with its roles) from the tactics advisor into the squad builder.
    func useFormation(_ f: Formation) {
        var f = f
        if f.mentality == nil && f.style == nil && (f.instructions ?? [:]).isEmpty {   // keep your settings
            f.mentality = workingFormation.mentality; f.style = workingFormation.style
            f.instructions = workingFormation.instructions
        }
        formationName = f.name
        formationEdited = true
        workingFormation = f
    }

    func newBlankTactic() {
        formationName = Formations.blank.name
        formationEdited = true
        workingFormation = Formations.blank
    }

    func setInstruction(_ name: String, _ value: String?) {
        var f = workingFormation
        var ins = f.instructions ?? [:]
        ins[name] = value
        f.instructions = ins
        formationEdited = true
        workingFormation = f
    }

    func setMentality(_ m: String?) { var f = workingFormation; f.mentality = m; formationEdited = true; workingFormation = f }
    func setStyle(_ st: String?) { var f = workingFormation; f.style = st; formationEdited = true; workingFormation = f }

    /// Copies every suggested instruction (and the mentality and best-fitting style) into your tactic.
    func applySuggestedInstructions() {
        guard let ins = tacticsInstructions else { return }
        var f = workingFormation
        var d = f.instructions ?? [:]
        for i in ins.items { d[i.name] = i.setting }
        f.instructions = d
        f.mentality = ins.mentality
        f.style = ins.styles.first?.name
        formationEdited = true
        workingFormation = f
    }

    func findUpgrades() {
        guard let meta, let report = squadReport, !upgradesBusy else { return }
        let c = signingCriteria()
        let rows = teamRows, model = interestModel, season = season
        upgradesBusy = true
        Task.detached(priority: .userInitiated) {
            let u = SquadBuilder.biggestUpgrades(report: report, rows: rows, meta: meta, criteria: c,
                                                 interest: model, season: season)
            await MainActor.run { self.upgrades = u; self.upgradesBusy = false }
        }
    }

    func addSlot(_ position: String) {
        let (f, i) = Formations.adding(position, to: workingFormation)
        edit(f, select: i)
    }

    func removeSlot(_ index: Int) {
        var f = workingFormation
        guard f.slots.indices.contains(index), f.slots.count > 1 else { return }
        f.slots.remove(at: index)
        f.slots = Formations.relabel(f.slots)
        edit(f, select: nil)
    }

    func saveFormation(as name: String) {
        let name = name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !Formations.presets.contains(where: { $0.name == name }), name != Formations.blank.name else { return }
        var f = workingFormation
        f.name = name
        customFormations.removeAll { $0.name == name }
        customFormations.append(f)
        formationName = name
        formationEdited = false
    }

    func deleteFormation(_ name: String) {
        customFormations.removeAll { $0.name == name }
        if formationName == name { loadFormation(Formations.all[0].name) }
    }

    func refreshSquad() {
        guard let meta, !myClub.isEmpty, !allPlayers.isEmpty else {
            squadReport = nil; suggestions = []; clubTeams = []; squadTimeline = []
            tacticsFits = []; tacticsSetPieces = nil; tacticsInstructions = nil; myTacticFit = nil; return
        }
        ensureInterestModel()
        let side = teamRows
        clubTeams = SquadBuilder.teams(club: myClub, rows: side)
        loanedOut = SquadBuilder.loanedOut(club: myClub, rows: side)
        var rows = side
        if !clubTeams.isEmpty && squadTeamRank >= 0 {
            let chosen = clubTeams[min(squadTeamRank, clubTeams.count - 1)]
            rows = side.filter { $0.person.club != myClub } + SquadBuilder.members(of: chosen, club: myClub, rows: side)
        }
        squadReport = SquadBuilder.analyse(club: myClub, formation: formation, rows: rows, meta: meta, season: season)
        squadTimeline = SquadBuilder.timeline(club: myClub, formation: formation, squad: squadReport?.squad ?? [],
                                              meta: meta, season: season)
        buildSquadRows()
        refreshTactics()
        refreshLeague()
        if columns(for: "players").contains(where: { $0.id == "gen.interest" }) { refilter() }
        if selectedSlot == nil || !(squadReport?.slots.contains { $0.slot.label == selectedSlot } ?? false) {
            selectedSlot = squadReport?.slots.max { $0.weakness < $1.weakness }?.slot.label
        } else {
            refreshSuggestions()
        }
    }

    func refreshTactics() {
        guard let meta, let report = squadReport else {
            tacticsFits = []; tacticsSetPieces = nil; tacticsInstructions = nil; return
        }
        let shapes = Formations.presets + customFormations.filter { c in !Formations.presets.contains { $0.name == c.name } }
        tacticsFits = TacticsAdvisor.rankFormations(shapes, squad: report.squad, meta: meta)
        myTacticFit = TacticsAdvisor.fit(workingFormation, squad: report.squad, meta: meta, keepRoles: true)
        if clubTeams.count > 1 && squadTeamRank >= 0 {
            let whole = teamRows.filter { $0.person.club == myClub }
            clubPromotions = TeamCompare.promotions(formation: workingFormation, firstTeam: report.squad,
                                                    wholeClub: whole, meta: meta)
        } else {
            clubPromotions = nil
        }
        upgrades = []
        refreshTacticsDetail()
    }

    private func refreshTacticsDetail() {
        guard let meta, let fit = detailFit else { tacticsSetPieces = nil; tacticsInstructions = nil; return }
        tacticsSetPieces = TacticsAdvisor.setPieces(xi: fit.picks.compactMap(\.player), bench: fit.bench, meta: meta)
        tacticsInstructions = TacticsAdvisor.instructions(fit, meta: meta, stance: resolvedStance,
                                                          league: TeamCompare.averageTactical(leagueProfiles))
    }

    var resolvedStance: TacticsAdvisor.Stance {
        if tacticsStance >= 0 { return TacticsAdvisor.Stance(rawValue: tacticsStance) ?? .even }
        return autoStance?.0 ?? .even
    }
    var autoStance: (TacticsAdvisor.Stance, rank: Int, of: Int)? { TeamCompare.stance(for: myClub, in: leagueProfiles) }

    // MARK: - Comparisons

    /// Which players clubs are judged on: 0 first-team XI, 1 best XI at the club, 2 top 18.
    var compareBasis: Int = UserDefaults.standard.object(forKey: "compareBasis") as? Int ?? 0 {
        didSet { UserDefaults.standard.set(compareBasis, forKey: "compareBasis"); refreshLeague() }
    }
    var basis: TeamCompare.Basis { TeamCompare.Basis(rawValue: compareBasis) ?? .firstTeam }
    /// Where every club plays, each league's country and strength (current men's/women's side).
    private(set) var leagueMap = TeamCompare.LeagueMap()
    private var clubLeagueKey = ""
    var clubLeague: [String: String] { leagueMap.clubLeague }
    var leagues: [String] { Array(Set(clubLeague.values)).sorted() }
    var myLeague: String? { clubLeague[myClub] }
    var myCountry: String? { myLeague.flatMap { leagueMap.country[$0] } }
    private(set) var profileCache: [String: TeamCompare.TeamProfile] = [:]
    private(set) var compareJobs = 0
    var compareBusy: Bool { compareJobs > 0 }
    /// Every club in your league, for league averages and the auto "going into games" setting.
    private(set) var leagueProfiles: [TeamCompare.TeamProfile] = []

    private func cacheKey(_ club: String) -> String { "\(compareBasis)|\(squadWomen)|\(club)" }
    func profile(_ club: String) -> TeamCompare.TeamProfile? { profileCache[cacheKey(club)] }
    func clubs(inLeague league: String) -> [String] { leagueMap.clubs(in: league) }

    /// Works out profiles for `clubs` in the background (cached per basis and side).
    func ensureProfiles(_ clubs: [String]) {
        guard let meta else { return }
        let missing = Array(Set(clubs.filter { !$0.isEmpty && profileCache[cacheKey($0)] == nil }))
        guard !missing.isEmpty else { return }
        let wanted = Set(missing)
        let rows = teamRows, basis = basis, season = season
        let keys = Dictionary(uniqueKeysWithValues: missing.map { ($0, cacheKey($0)) })
        compareJobs += 1
        Task.detached(priority: .userInitiated) {
            let byClub = Dictionary(grouping: rows.filter { $0.person.club.map(wanted.contains) ?? false },
                                    by: { $0.person.club ?? "" })
            var out: [String: TeamCompare.TeamProfile] = [:]
            for c in missing {
                if let p = TeamCompare.profile(club: c, rows: byClub[c] ?? [], meta: meta, basis: basis, season: season) {
                    out[keys[c]!] = p
                }
            }
            let result = out
            await MainActor.run {
                self.profileCache.merge(result) { $1 }
                self.compareJobs -= 1
                self.updateLeagueProfiles()
            }
        }
    }

    /// Recomputes which league each club plays in (once per scan and side), then your league's profiles.
    func refreshLeague() {
        let key = "\(allPlayers.count)|\(squadWomen)"
        if key != clubLeagueKey {
            clubLeagueKey = key
            profileCache = [:]
            let rows = teamRows
            Task.detached(priority: .utility) {
                let map = TeamCompare.leagueMap(rows)
                await MainActor.run { self.leagueMap = map; self.refreshLeague() }
            }
            return
        }
        updateLeagueProfiles()
        if let l = myLeague { ensureProfiles(clubs(inLeague: l)) }
    }

    private func updateLeagueProfiles() {
        guard let l = myLeague else { leagueProfiles = []; return }
        let ps = clubs(inLeague: l).compactMap { profile($0) }
        let changed = ps.map(\.club) != leagueProfiles.map(\.club) || ps.first?.values != leagueProfiles.first?.values
        leagueProfiles = ps
        if changed { refreshTacticsDetail() }
    }

    private func buildSquadRows() {
        guard let report = squadReport else { squadRows = []; squadRoleText = [:]; return }
        var order: [UInt32: Double] = [:], text: [UInt32: String] = [:]
        for (i, a) in report.slots.enumerated() {
            if let s = a.starter { order[s.id] = Double(i); text[s.id] = a.slot.label }
            if let b = a.backup, order[b.id] == nil { order[b.id] = 100 + Double(i); text[b.id] = "\(a.slot.label) · backup" }
        }
        var rows = report.squad
        for i in rows.indices { rows[i].extras["xi"] = order[rows[i].id] ?? 1000 }
        reader?.fill(&rows, columns(for: "squad"), interest: interestScorer())
        rows.sort(using: squadSort)
        squadRows = rows
        squadRoleText = text
    }

    func refreshStaffAdvice() {
        guard let meta, !myClub.isEmpty else { staffAdvice = []; return }
        let cap = wageBudget > 0 ? Int(Double(wageBudget) / max(rate, 0.0001)) : 0
        let rep = clubTeams.first { $0.rank == 0 }?.reputation
            ?? squadReport?.squad.compactMap(\.person.trep).max()
        staffAdvice = StaffAdvisor.advise(club: myClub, staff: allStaff, meta: meta, maxWageGbp: cap,
                                          clubRep: rep, realistic: staffRealistic)
    }

    /// Only suggest staff who would plausibly join (not from clearly bigger clubs).
    var staffRealistic: Bool = UserDefaults.standard.object(forKey: "staffRealistic") as? Bool ?? true {
        didSet { UserDefaults.standard.set(staffRealistic, forKey: "staffRealistic"); refreshStaffAdvice() }
    }

    func refreshSuggestions() {
        guard let meta, let report = squadReport,
              let slot = report.slots.first(where: { $0.slot.label == selectedSlot }) else { suggestions = []; return }
        // Up to 200 so sorting by another column still has plenty to choose from.
        var list = SquadBuilder.suggestions(for: slot, report: report, rows: teamRows, meta: meta,
                                            criteria: signingCriteria(), interest: interestModel, season: season, limit: 200)
        let cols = columns(for: "signings")
        if !cols.isEmpty, let reader {
            var rows = list.map(\.row)
            reader.fill(&rows, cols, interest: interestScorer())
            for i in list.indices { list[i].row = rows[i] }
        }
        if !signingSort.isEmpty { list.sort(using: signingSort) }
        suggestions = list
    }

    // MARK: - Calibration files

    func loadReport() {
        reportText = (try? String(contentsOf: ScoutFiles.discoveryReport, encoding: .utf8)) ?? ""
    }

    var hasSuggestion: Bool { FileManager.default.fileExists(atPath: ScoutFiles.suggestedOffsets.path) }

    func applySuggestion() {
        do {
            let backup = try ScoutFiles.applySuggestedOffsets()
            hint = "Suggested offsets applied" + (backup != nil ? " (old file backed up)." : ".") + " Press Scan to try them."
        } catch {
            hint = "Could not apply offsets: \(error.localizedDescription)"
        }
    }

    func revealFolder() {
        try? FileManager.default.createDirectory(at: ScoutFiles.dir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(ScoutFiles.dir)
    }

    private func saveTargets() {
        if let d = try? JSONEncoder().encode(targets) { UserDefaults.standard.set(d, forKey: "targets") }
    }
}
