import Foundation

// MARK: - export.json (written by the Pitchside plugin)

public struct ExportMeta: Codable, Sendable {
    public var scannedAt: String?
    public var gameDate: String?
    public var offsetsVersion: String?
    public var offsetsVerified: Bool?
    public var plugin: String?
    public var scanMs: Int?
    public var playerAttrKeys: [String]
    public var hiddenKeys: [String]
    public var personalityKeys: [String]
    public var positionKeys: [String]
    public var staffAttrKeys: [String]
    public var warnings: [String]?
}

/// One person as exported. Short JSON keys keep a 500k-player file manageable.
public struct Person: Codable, Sendable, Hashable, Identifiable {
    public var id: UInt32
    public var n: String
    public var sn: String?      // surname, when the display name is first + second name
    public var dob: String?
    public var nat: String?
    public var club: String?
    public var div: String?
    public var ca: Int
    public var pa: Int
    public var rep: Int?
    public var wrep: Int?
    public var f: Int?
    public var wage: Int?
    public var exp: String?
    public var p: [UInt8]?      // personality
    // players
    public var a: [UInt8]?      // attributes
    public var h: [UInt8]?      // hidden attributes
    public var pos: [UInt8]?    // position familiarity 1..20
    public var ht: Int?
    public var ft: String?
    public var val: Int?
    public var ask: Int?
    public var lst: Bool?
    public var nfs: Bool?
    public var rel: Bool?
    // staff
    public var s: [UInt8]?
    public var job: String?

    public init(id: UInt32, n: String, ca: Int, pa: Int) {
        self.id = id; self.n = n; self.ca = ca; self.pa = pa
    }
}

public struct ExportFile: Codable, Sendable {
    public var meta: ExportMeta
    public var players: [Person]
    public var staff: [Person]
}

// MARK: - status.json / request.json

public struct PluginStatus: Codable, Sendable, Equatable {
    public var state: String          // idle | scanning | done | error
    public var mode: String?
    public var id: String?
    public var progress: Double?
    public var message: String?
    public var players: Int?
    public var staff: Int?
    public var at: String?
    public var plugin: String?

    public init(state: String, mode: String? = nil, id: String? = nil, progress: Double? = nil,
                message: String? = nil, players: Int? = nil, staff: Int? = nil,
                at: String? = nil, plugin: String? = nil) {
        self.state = state; self.mode = mode; self.id = id; self.progress = progress
        self.message = message; self.players = players; self.staff = staff; self.at = at; self.plugin = plugin
    }
}

public struct CalibrationTarget: Codable, Sendable, Equatable, Identifiable {
    public var id = UUID()
    public var name: String = ""
    public var kind: String = "player"            // player | staff
    public var attributes: [String: Int] = [:]
    public var birthDate: String?                  // yyyy-MM-dd
    public var heightCm: Int = 0

    enum CodingKeys: String, CodingKey { case name, kind, attributes, birthDate, heightCm }

    public init() {}
}

public struct PluginRequest: Codable, Sendable {
    public var mode: String
    public var id: String
    public var at: Int64
    public var database: String
    public var targets: [CalibrationTarget]

    public init(mode: String, database: String, targets: [CalibrationTarget] = []) {
        self.mode = mode
        self.id = UUID().uuidString
        self.at = Int64(Date().timeIntervalSince1970 * 1000)
        self.database = database
        self.targets = targets
    }
}

// MARK: - Files shared with the plugin

public enum ScoutFiles {
    public static var dir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Pitchside", isDirectory: true)
    }
    public static var export: URL { dir.appendingPathComponent("export.json") }
    public static var status: URL { dir.appendingPathComponent("status.json") }
    public static var request: URL { dir.appendingPathComponent("request.json") }
    public static var offsets: URL { dir.appendingPathComponent("offsets.json") }
    public static var suggestedOffsets: URL { dir.appendingPathComponent("offsets.suggested.json") }
    public static var discoveryReport: URL { dir.appendingPathComponent("discovery-report.txt") }
    public static var diagnostics: URL { dir.appendingPathComponent("diagnostics.txt") }
    public static var pluginLog: URL { dir.appendingPathComponent("plugin.log") }

    public static func send(_ request: PluginRequest) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(request)
        try data.write(to: Self.request, options: .atomic)
    }

    public static func readStatus() -> PluginStatus? {
        guard let d = try? Data(contentsOf: status) else { return nil }
        return try? JSONDecoder().decode(PluginStatus.self, from: d)
    }

    public static func loadExport() throws -> ExportFile {
        let d = try Data(contentsOf: export, options: .mappedIfSafe)
        return try JSONDecoder().decode(ExportFile.self, from: d)
    }

    /// Replace offsets.json with the suggestion from Calibration, keeping a dated backup.
    public static func applySuggestedOffsets() throws -> URL? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: suggestedOffsets.path) else { return nil }
        var backup: URL?
        if fm.fileExists(atPath: offsets.path) {
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            let b = dir.appendingPathComponent("offsets.backup-\(stamp).json")
            try fm.copyItem(at: offsets, to: b)
            try fm.removeItem(at: offsets)
            backup = b
        }
        try fm.copyItem(at: suggestedOffsets, to: offsets)
        return backup
    }
}
