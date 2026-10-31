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
                GeometryReader { geo in
                    ScrollView([.vertical, .horizontal]) {
                        VStack(spacing: 14) {
                            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                                DepthRowLayout(xs: row.map(\.x)) {
                                    ForEach(row) { d in DepthCard(d: d, starts: starts, scale: store.squadScale, picked: $picked) }
                                }
                            }
                        }
                        .padding(18)
                        .frame(width: max(geo.size.width - 24, DepthRowLayout.minWidth + 36))
                        .background(PitchBackground().opacity(0.55))
                        .padding(12)
                    }
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
    let scale: ScoreScale?
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
                            .foregroundStyle(RelColor.color(o.score, scale))
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

    /// Role codes, as on the My tactic pitch ("IF / W"); full names on hover.
    private var roleText: String {
        d.slot.oop.isEmpty ? d.slot.role : "\(d.slot.role) / \(d.slot.oop.dropFirst())"
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

/// Lays a line of position cards out across the pitch at each position's own left–right spot
/// (wingers and wing backs wide, centre players in the middle), nudging cards apart if they'd overlap.
struct DepthRowLayout: Layout {
    let xs: [Double]
    var spacing: CGFloat = 12
    static let minWidth: CGFloat = 5 * 200 + 4 * 12

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let h = subviews.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
        return CGSize(width: max(proposal.width ?? Self.minWidth, Self.minWidth), height: h)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        var lefts: [CGFloat] = []
        for (i, size) in sizes.enumerated() {
            let x = i < xs.count ? xs[i] : 0.5
            var left = bounds.minX + CGFloat(x) * bounds.width - size.width / 2
            left = max(left, bounds.minX)
            if i > 0 { left = max(left, lefts[i - 1] + sizes[i - 1].width + spacing) }
            lefts.append(left)
        }
        var limit = bounds.maxX
        for i in lefts.indices.reversed() {
            if lefts[i] + sizes[i].width > limit { lefts[i] = limit - sizes[i].width }
            limit = lefts[i] - spacing
        }
        for (i, view) in subviews.enumerated() {
            view.place(at: CGPoint(x: lefts[i], y: bounds.minY), anchor: .topLeading, proposal: ProposedViewSize(sizes[i]))
        }
    }
}
