import AppKit
import PitchsideCore
import Observation
import SwiftUI

/// What the configurable last column of the players table shows.
enum ExtraColumn: String, CaseIterable, Identifiable {
    case value, wage, contract, growth, pricePerCA, interest
    var id: String { rawValue }
    var title: String {
        switch self {
        case .value: "Value"
        case .wage: "Wage/wk"
        case .contract: "Contract"
        case .growth: "Growth"
        case .pricePerCA: "£ per CA"
        case .interest: "Interest"
        }
    }
}

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
    var meta: ExportMeta?
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
            refreshSquad()
        }
    }
    var extraColumn: ExtraColumn = ExtraColumn(rawValue: UserDefaults.standard.string(forKey: "extraColumn") ?? "") ?? .value {
        didSet { UserDefaults.standard.set(extraColumn.rawValue, forKey: "extraColumn"); refilter() }
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
    var squadWomen: Bool = UserDefaults.standard.bool(forKey: "squadWomen") {
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
    var squadReport: SquadReport?
    var selectedSlot: String? { didSet { refreshSuggestions() } }
    var suggestions: [SquadBuilder.Suggestion] = []
    var clubs: [String] = []
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
        return Calendar(identifier: .gregorian).component(.year, from: referenceDate)
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
            let s = RowBuilder.staff(file.staff, reference: ref)
            await MainActor.run {
                self.interestModel = nil
                self.allPlayers = p
                self.allStaff = s
                self.clubs = clubs
                self.refilter()
                self.refilterStaff()
                self.refreshSquad()
            }
        }
    }

    func refilter() {
        guard let meta else { players = []; return }
        filterTask?.cancel()
        let f = filter, rows = allPlayers, sort = playerSort, perUnit = 1 / max(rate, 0.0001), extra = extraColumn
        let roleIdx = Roles.all.firstIndex { $0.code == f.roleCode }
        if extra == .interest { ensureInterestModel() }
        let model = interestModel, club = myClub, women = squadWomen, season = season
        filterTask = Task.detached(priority: .userInitiated) {
            var out = Filtering.apply(f, to: rows, meta: meta, gbpPerUnit: perUnit)
            for i in out.indices {
                out[i].selectedRoleScore = roleIdx.map { out[i].roleScores[$0] } ?? out[i].bestRoleScore
                if extra == .interest {
                    let r = out[i]
                    out[i].extraSort = (r.person.f == 1) == women
                        ? (model?.assess(r, joining: club, season: season)?.score ?? -1) : -1
                } else {
                    out[i].extraSort = Store.extraSortValue(out[i], extra)
                }
            }
            out.sort(using: sort)
            if Task.isCancelled { return }
            let result = out
            await MainActor.run { self.players = result }
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
    func scan() { send(PluginRequest(mode: "dump", database: "both")) }

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

    // MARK: - Extra column

    nonisolated static func extraSortValue(_ r: PlayerRow, _ e: ExtraColumn) -> Double {
        switch e {
        case .value: return Double(r.value)
        case .wage: return Double(r.wage)
        case .contract: return Double(r.expires.replacingOccurrences(of: "-", with: "")) ?? 99_999_999
        case .growth: return Double(r.growth)
        case .pricePerCA: return r.pricePerCA
        case .interest: return -1   // filled in by refilter, which has the interest model
        }
    }

    func extraText(_ r: PlayerRow) -> String {
        switch extraColumn {
        case .value: return Money.format(r.person.val, symbol: currency.symbol, perGbp: rate)
        case .wage: return Money.format(r.person.wage, symbol: currency.symbol, perGbp: rate)
        case .contract: return r.expires.isEmpty ? "—" : String(r.expires.prefix(7))
        case .growth: return r.growth == PlayerRow.noGrowth ? "—" : (r.growth > 0 ? "+\(r.growth)" : "\(r.growth)")
        case .pricePerCA: return r.value < 0 ? "—" : Money.format(Int(r.pricePerCA), symbol: currency.symbol, perGbp: rate)
        case .interest: return interest(for: r)?.level.name ?? "—"
        }
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
    var allFormations: [Formation] { Formations.all + customFormations }
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
        return (Formations.all + custom).first { $0.name == name } ?? Formations.all[0]
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
        guard !name.isEmpty, !Formations.all.contains(where: { $0.name == name }) else { return }
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
        guard let meta, !myClub.isEmpty, !allPlayers.isEmpty else { squadReport = nil; suggestions = []; return }
        ensureInterestModel()
        squadReport = SquadBuilder.analyse(club: myClub, formation: formation, rows: teamRows, meta: meta, season: season)
        if extraColumn == .interest { refilter() }
        if selectedSlot == nil || !(squadReport?.slots.contains { $0.slot.label == selectedSlot } ?? false) {
            selectedSlot = squadReport?.slots.max { $0.weakness < $1.weakness }?.slot.label
        } else {
            refreshSuggestions()
        }
    }

    func refreshSuggestions() {
        guard let meta, let report = squadReport,
              let slot = report.slots.first(where: { $0.slot.label == selectedSlot }) else { suggestions = []; return }
        var c = SigningCriteria()
        c.maxValueGbp = transferBudget > 0 ? Int(Double(transferBudget) / max(rate, 0.0001)) : 0
        c.maxWageGbp = wageBudget > 0 ? Int(Double(wageBudget) / max(rate, 0.0001)) : 0
        c.minAge = signMinAge
        c.maxAge = signMaxAge
        c.minInterest = minInterest > 0 ? InterestLevel(rawValue: minInterest) : nil
        c.forDepth = signForDepth
        suggestions = SquadBuilder.suggestions(for: slot, report: report, rows: teamRows, meta: meta, criteria: c,
                                               interest: interestModel, season: season)
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
