import AppKit
import PitchsideCore
import SwiftUI
import UniformTypeIdentifiers
import Vision

/// Reads text from a screenshot with the Mac's built-in text recognition (the same engine as Live Text).
enum ScreenshotReader {
    static func tokens(_ url: URL) throws -> [ShortlistImport.Token] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        try VNImageRequestHandler(url: url, options: [:]).perform([request])
        return (request.results ?? []).compactMap { obs -> ShortlistImport.Token? in
            guard let c = obs.topCandidates(1).first else { return nil }
            let b = obs.boundingBox            // normalised, origin bottom left
            return ShortlistImport.Token(text: c.string, x: Double(b.minX), y: Double(1 - b.midY), h: Double(b.height))
        }
    }
}

/// Import FM's shortlist (or any FM player list) from screenshots of it.
struct ShortlistImportSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var picking = false
    @State private var busy = false
    @State private var shots = 0
    @State private var matches: [ShortlistImport.Match] = []
    @State private var error: String?

    /// Added to the FM shortlist: sure and likely matches. Unsure ones are only shown, for you to check.
    private var found: [ShortlistImport.Match] { matches.filter { $0.player != nil && $0.confidence != .unsure } }
    private var unsure: [ShortlistImport.Match] { matches.filter { $0.player != nil && $0.confidence == .unsure } }
    private var missing: [ShortlistImport.Match] { matches.filter { $0.player == nil } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Import FM shortlist from screenshots").font(.title3.bold())
            Text("In FM, open your shortlist (or the Player Database showing it) and take screenshots while you scroll (Cmd-Shift-4 for an area, or Cmd-Shift-3 for the whole screen), so every player is on at least one. Overlaps are fine. Then choose them here.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button { picking = true } label: { Label("Choose screenshots…", systemImage: "photo.on.rectangle") }
                if busy { ProgressView().controlSize(.small); Text("Reading \(shots) screenshot\(shots == 1 ? "" : "s")…").foregroundStyle(.secondary) }
            }
            if let error { Text(error).foregroundStyle(.red).font(.callout) }
            if !matches.isEmpty {
                Text("\(found.count) players found\(unsure.isEmpty ? "" : ", \(unsure.count) unsure")\(missing.isEmpty ? "" : ", \(missing.count) not in your scan")")
                    .font(.callout.weight(.semibold))
                List {
                    if !unsure.isEmpty {
                        Section("Not added — closest match, please check") { ForEach(unsure) { row($0) } }
                    }
                    if !missing.isEmpty {
                        Section("Not in your scan") {
                            ForEach(missing) { m in Text(m.line.name).foregroundStyle(.secondary) }
                        }
                    }
                    Section("Found") { ForEach(found) { row($0) } }
                }
                .frame(minHeight: 260)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Add to FM shortlist") { save(replace: false) }.disabled(found.isEmpty)
                Button("Replace FM shortlist") { save(replace: true) }.disabled(found.isEmpty).keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 560)
        .fileImporter(isPresented: $picking, allowedContentTypes: [.image], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): read(urls)
            case .failure(let e): error = e.localizedDescription
            }
        }
    }

    private func row(_ m: ShortlistImport.Match) -> some View {
        HStack {
            Text(m.line.name).frame(width: 180, alignment: .leading).lineLimit(1)
            Image(systemName: "arrow.right").foregroundStyle(.secondary)
            if let p = m.player {
                Text(p.name).lineLimit(1)
                Text("\(p.age) · \(p.person.nat ?? "") · \(p.club.isEmpty ? "free" : p.club)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
        }
        .font(.callout)
    }

    private func read(_ urls: [URL]) {
        busy = true; shots = urls.count; error = nil
        let rows = store.allPlayers
        Task.detached(priority: .userInitiated) {
            var tokens: [[ShortlistImport.Token]] = []
            var failed = 0
            for u in urls {
                let scoped = u.startAccessingSecurityScopedResource()
                defer { if scoped { u.stopAccessingSecurityScopedResource() } }
                if let t = try? ScreenshotReader.tokens(u) { tokens.append(t) } else { failed += 1 }
            }
            let lines = tokens.flatMap { ShortlistImport.lines($0) }
            let result = ShortlistImport.match(lines, index: .init(rows))
            let failedCount = failed, noRows = lines.isEmpty
            await MainActor.run {
                matches = result
                busy = false
                if failedCount > 0 { error = "\(failedCount) file\(failedCount == 1 ? "" : "s") couldn't be read." }
                else if noRows { error = "No player rows found. Are these screenshots of an FM player list?" }
            }
        }
    }

    private func save(replace: Bool) {
        store.setFMShortlist(Set(found.compactMap { $0.player?.id }), replace: replace)
        dismiss()
    }
}
