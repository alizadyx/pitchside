import Foundation
import PitchsideCore

let args = CommandLine.arguments
if args.count == 4, args[1] == "shortlist" {
    do { print(try Audit.shortlist(exportPath: args[2], tokensPath: args[3])) } catch { print("failed: \(error)") }
    exit(0)
}
if args.count == 6, args[1] == "rotation" {
    do { print(try Audit.rotation(exportPath: args[2], club: args[3], formation: args[4], matches: Int(args[5]) ?? 3)) }
    catch { print("failed: \(error)") }
    exit(0)
}
guard args.count >= 3 else {
    print("usage: PitchsideAudit <export.json> <out.json> [\"Club name\"]"); exit(1)
}
do {
    let n = try Audit.dump(exportPath: args[1], club: args.count > 3 ? args[3] : "Manchester United", outPath: args[2])
    print("Wrote \(args[2]) (\(n) players)")
} catch {
    print("Audit failed: \(error.localizedDescription)"); exit(1)
}
