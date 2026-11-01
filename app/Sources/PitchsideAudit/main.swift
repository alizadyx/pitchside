import Foundation
import PitchsideCore

let args = CommandLine.arguments
guard args.count >= 3 else {
    print("usage: PitchsideAudit <export.json> <out.json> [\"Club name\"]"); exit(1)
}
do {
    let n = try Audit.dump(exportPath: args[1], club: args.count > 3 ? args[3] : "Manchester United", outPath: args[2])
    print("Wrote \(args[2]) (\(n) players)")
} catch {
    print("Audit failed: \(error.localizedDescription)"); exit(1)
}
