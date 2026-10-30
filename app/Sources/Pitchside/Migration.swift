import Foundation
import PitchsideCore

/// One-time move of data from the app's earlier name (FM Scout / FMScoutMac), so nobody loses
/// their shortlist, saved searches, tactics, scan history or calibration after updating.
enum Migration {
    static let oldFolder = "FMScoutMac"
    static let oldBundleId = "com.fmscoutmac.viewer"

    static func run() {
        let fm = FileManager.default
        let old = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/\(oldFolder)", isDirectory: true)
        let new = ScoutFiles.dir
        if fm.fileExists(atPath: old.path) && !fm.fileExists(atPath: new.path) {
            try? fm.moveItem(at: old, to: new)
        }

        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: "migratedFromOldName") else { return }
        if let newId = Bundle.main.bundleIdentifier, newId != oldBundleId,
           let oldDomain = defaults.persistentDomain(forName: oldBundleId) {
            for (key, value) in oldDomain where defaults.object(forKey: key) == nil {
                defaults.set(value, forKey: key)
            }
        }
        defaults.set(true, forKey: "migratedFromOldName")
    }
}
