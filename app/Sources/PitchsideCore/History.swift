import Foundation

/// A compact record of one scan: who existed and their CA. Kept so later scans can show
/// growth ("+8 CA since the summer") and spot newly generated players.
public struct Snapshot: Codable, Sendable {
    public var scannedAt: String
    public var gameDate: String?
    public var ids: [UInt32]
    public var ca: [UInt8]

    public init(scannedAt: String, gameDate: String?, ids: [UInt32], ca: [UInt8]) {
        self.scannedAt = scannedAt; self.gameDate = gameDate; self.ids = ids; self.ca = ca
    }

    public init(export: ExportFile) {
        scannedAt = export.meta.scannedAt ?? Ages.string(Date())
        gameDate = export.meta.gameDate
        ids = export.players.map(\.id)
        ca = export.players.map { UInt8(clamping: $0.ca) }
    }

    public var caById: [UInt32: Int] {
        var d = [UInt32: Int](minimumCapacity: ids.count)
        for (i, id) in ids.enumerated() where i < ca.count { d[id] = Int(ca[i]) }
        return d
    }

    /// Label for pickers: in-game date when known, otherwise when the scan ran.
    public var label: String {
        let when = scannedAt.replacingOccurrences(of: "T", with: " ").prefix(16)
        if let g = gameDate { return "Game date \(g)  (scanned \(when))" }
        return "Scanned \(when)"
    }
}

public struct SnapshotInfo: Sendable, Hashable, Identifiable {
    public var id: String { file.lastPathComponent }
    public let file: URL
    public let label: String
}

public enum History {
    public static let keep = 80

    public static var dir: URL { ScoutFiles.dir.appendingPathComponent("history", isDirectory: true) }

    public static func fileName(for scannedAt: String) -> String {
        "scan-" + scannedAt.replacingOccurrences(of: ":", with: "-") + ".json"
    }

    /// Saves the snapshot unless one for this scan already exists. Returns true if written.
    @discardableResult
    public static func save(_ s: Snapshot, in directory: URL = History.dir) throws -> Bool {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(fileName(for: s.scannedAt))
        if fm.fileExists(atPath: url.path) { return false }
        try JSONEncoder().encode(s).write(to: url, options: .atomic)
        // Prune the oldest beyond `keep`.
        let all = list(in: directory)
        if all.count > keep { for old in all.prefix(all.count - keep) { try? fm.removeItem(at: old.file) } }
        return true
    }

    /// Oldest first.
    public static func list(in directory: URL = History.dir) -> [SnapshotInfo] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.lastPathComponent.hasPrefix("scan-") && $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { url in
                let stamp = url.deletingPathExtension().lastPathComponent.dropFirst(5)
                return SnapshotInfo(file: url, label: "Scanned " + stamp.replacingOccurrences(of: "T", with: " ").prefix(16))
            }
    }

    public static func load(_ info: SnapshotInfo) -> Snapshot? {
        guard let d = try? Data(contentsOf: info.file) else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: d)
    }

    /// CA change per player between `reference` and the current export.
    public static func growth(current: [Person], reference: Snapshot) -> [UInt32: Int] {
        let old = reference.caById
        var out = [UInt32: Int](minimumCapacity: current.count)
        for p in current { if let c = old[p.id] { out[p.id] = p.ca - c } }
        return out
    }
}
