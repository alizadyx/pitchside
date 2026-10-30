import SwiftUI
import PitchsideCore

/// The formation as a depth chart: every position lists the players in your squad who can play
/// there, best first, scored for that position's IP and OOP roles.
struct DepthView: View {
    @Binding var picked: UInt32?
    @Environment(Store.self) private var store
    @AppStorage("depthNaturalOnly") private var naturalOnly = false
    @AppStorage("depthLimit") private var limit = 5

    var body: some View {
        if let report = store.squadReport, let meta = store.meta {
            let rows = SquadBuilder.depthChart(report, meta: meta, naturalOnly: naturalOnly, limit: limit)
            let starts = Dictionary(report.slots.compactMap { a in a.starter.map { ($0.id, a.slot.label) } },
                                    uniquingKeysWith: { first, _ in first })
            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    Toggle("Naturals only", isOn: $naturalOnly)
                        .help("On: only players who are natural in the position. Off: accomplished players too (marked ◐).")
                    Picker("Show", selection: $limit) {
                        Text("Top 3").tag(3)
                        Text("Top 5").tag(5)
                        Text("Top 8").tag(8)
                        Text("Everyone").tag(30)
                    }
                    .fixedSize()
                    Text("Bold: starts there · grey: starts somewhere else in your XI · ◐ not a natural. Click a name for the profile.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                Divider()
                ScrollView([.vertical, .horizontal]) {
                    VStack(spacing: 14) {
                        ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                            HStack(alignment: .top, spacing: 12) {
                                ForEach(row) { d in DepthCard(d: d, starts: starts, picked: $picked) }
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(18)
                    .background(PitchBackground().opacity(0.55))
                    .padding(12)
                }
            }
        } else {
            Text("Pick your club first").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct DepthCard: View {
    let d: SquadBuilder.DepthSlot
    let starts: [UInt32: String]
    @Binding var picked: UInt32?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(d.slot.label).font(.caption.weight(.heavy))
                Text(roleText).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 2)
                Text("\(d.options.count)").font(.caption2).foregroundStyle(.secondary)
            }
            .help(roleHelp)
            Divider()
            if d.options.isEmpty {
                Text("Nobody in the squad").font(.caption).foregroundStyle(.red)
            }
            ForEach(d.options) { o in
                let here = starts[o.row.id] == d.slot.label
                let elsewhere = starts[o.row.id].flatMap { $0 == d.slot.label ? nil : $0 }
                Button { picked = o.row.id } label: {
                    HStack(spacing: 4) {
                        Text(o.row.name)
                            .fontWeight(here ? .bold : .regular)
                            .foregroundStyle(elsewhere != nil ? HierarchicalShapeStyle.secondary : .primary)
                            .lineLimit(1)
                        if o.familiarity < SquadBuilder.naturalFamiliarity {
                            Text("◐").font(.caption2).foregroundStyle(.orange)
                        }
                        Spacer(minLength: 4)
                        Text(String(format: "%.1f", o.score)).monospacedDigit().fontWeight(.semibold)
                            .foregroundStyle(AttrColor.color(Int(o.score.rounded())))
                    }
                    .font(.callout)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(help(o, elsewhere: elsewhere))
            }
        }
        .padding(8)
        .frame(width: 200, alignment: .topLeading)
        .background(Color.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
    }

    private var roleText: String {
        let ip = Roles.role(d.slot.role)?.short ?? d.slot.role
        guard let oop = Roles.role(d.slot.oop) else { return ip }
        return "\(ip) / \(oop.short)"
    }

    private var roleHelp: String {
        let ip = Roles.role(d.slot.role)?.name ?? d.slot.role
        let oop = Roles.role(d.slot.oop).map { "\n\($0.name) (out of possession)" } ?? ""
        return "\(d.slot.label): \(ip) (in possession)\(oop)"
    }

    private func help(_ o: SquadBuilder.Option, elsewhere: String?) -> String {
        var parts = ["\(o.row.name), \(o.row.age) · score here \(String(format: "%.1f", o.score)) · CA \(o.row.ca)"]
        parts.append(o.familiarity >= SquadBuilder.naturalFamiliarity
                     ? "Natural in this position"
                     : "Accomplished, not a natural (familiarity \(o.familiarity))")
        if let e = elsewhere { parts.append("Starts at \(e) in your XI") }
        return parts.joined(separator: "\n")
    }
}
