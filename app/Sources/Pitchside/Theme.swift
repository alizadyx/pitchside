import PitchsideCore
import SwiftUI

/// FM-style dark palette and the small building blocks shared by every screen.
enum Theme {
    static let bg = Color(red: 0.075, green: 0.082, blue: 0.11)
    static let panel = Color(red: 0.11, green: 0.12, blue: 0.16)
    static let panelAlt = Color(red: 0.15, green: 0.16, blue: 0.21)
    static let stroke = Color.white.opacity(0.08)
    static let accent = Color(red: 0.36, green: 0.55, blue: 1.0)
    static let accentSoft = Color(red: 0.36, green: 0.55, blue: 1.0).opacity(0.22)
    static let pitch = Color(red: 0.13, green: 0.36, blue: 0.22)
    static let pitchDark = Color(red: 0.10, green: 0.30, blue: 0.18)
    static let gold = Color(red: 1.0, green: 0.78, blue: 0.25)
    /// Colours for up to three compared players.
    static let series: [Color] = [Color(red: 0.36, green: 0.62, blue: 1.0), Color(red: 1.0, green: 0.6, blue: 0.2),
                                  Color(red: 0.92, green: 0.35, blue: 0.75)]
}

enum AttrColor {
    /// FM-like bands: weak red, ordinary amber, good green, elite bright green.
    static func color(_ v: Int) -> Color {
        switch v {
        case ..<1: return .secondary
        case 1...5: return Color(red: 0.93, green: 0.36, blue: 0.33)
        case 6...10: return Color(red: 0.95, green: 0.68, blue: 0.27)
        case 11...15: return Color(red: 0.62, green: 0.84, blue: 0.32)
        default: return Color(red: 0.25, green: 0.9, blue: 0.5)
        }
    }
}

extension View {
    /// Rounded dark card.
    func fmCard(padding: CGFloat = 12) -> some View {
        self.padding(padding)
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.stroke))
    }
}

/// Attribute value in a small coloured box, like FM's profile screen.
struct AttrBox: View {
    let value: Int
    var width: CGFloat = 28
    var body: some View {
        Text(value > 0 ? "\(value)" : "–")
            .font(.system(size: 12.5, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(value > 0 ? Color.black.opacity(0.85) : Color.secondary)
            .frame(width: width, height: 19)
            .background(value > 0 ? AttrColor.color(value) : Theme.panelAlt, in: RoundedRectangle(cornerRadius: 4))
    }
}

/// 0.5–5 stars.
struct StarsView: View {
    let value: Double
    var size: CGFloat = 12
    var color: Color = Theme.gold
    var body: some View {
        HStack(spacing: 1) {
            ForEach(0..<5, id: \.self) { i in
                let filled = value - Double(i)
                Image(systemName: filled >= 1 ? "star.fill" : filled >= 0.5 ? "star.leadinghalf.filled" : "star")
                    .font(.system(size: size))
                    .foregroundStyle(filled > 0 ? color : Color.secondary.opacity(0.5))
            }
        }
    }
}

/// Removable filter chip.
struct Chip: View {
    let label: String
    var onRemove: (() -> Void)?
    var body: some View {
        HStack(spacing: 5) {
            Text(label).font(.callout).lineLimit(1)
            if let onRemove {
                Button(action: onRemove) { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)) }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 9).padding(.vertical, 4)
        .background(Theme.accentSoft, in: Capsule())
        .overlay(Capsule().stroke(Theme.accent.opacity(0.6)))
    }
}

/// Wrapping row layout (chips, tags).
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0 && x + s.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += s.width + spacing
            maxX = max(maxX, x)
            rowHeight = max(rowHeight, s.height)
        }
        return CGSize(width: min(maxX, width), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX && x + s.width > bounds.maxX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowHeight = max(rowHeight, s.height)
        }
    }
}

/// Filter-panel group; gets an accent edge and dot when it holds an active filter.
struct FilterGroup<Content: View>: View {
    let title: String
    let active: Bool
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(title.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(active ? Theme.accent : .secondary)
                if active { Circle().fill(Theme.accent).frame(width: 6, height: 6) }
            }
            content
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(active ? Theme.accentSoft.opacity(0.45) : Theme.panel, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(active ? Theme.accent.opacity(0.7) : Theme.stroke))
    }
}

/// Football pitch background, drawn vertically (own goal at the bottom).
struct PitchBackground: View {
    var body: some View {
        Canvas { ctx, size in
            let r = CGRect(origin: .zero, size: size)
            // Stripes
            let stripes = 8
            for i in 0..<stripes {
                let h = size.height / CGFloat(stripes)
                ctx.fill(Path(CGRect(x: 0, y: CGFloat(i) * h, width: size.width, height: h)),
                         with: .color(i % 2 == 0 ? Theme.pitch : Theme.pitchDark))
            }
            let line = GraphicsContext.Shading.color(.white.opacity(0.35))
            let inset = r.insetBy(dx: 6, dy: 6)
            ctx.stroke(Path(inset), with: line, lineWidth: 1.2)
            ctx.stroke(Path { p in p.move(to: CGPoint(x: inset.minX, y: inset.midY)); p.addLine(to: CGPoint(x: inset.maxX, y: inset.midY)) },
                       with: line, lineWidth: 1.2)
            let cr = min(size.width, size.height) * 0.11
            ctx.stroke(Path(ellipseIn: CGRect(x: inset.midX - cr, y: inset.midY - cr, width: cr * 2, height: cr * 2)), with: line, lineWidth: 1.2)
            let boxW = inset.width * 0.55, boxH = inset.height * 0.14
            ctx.stroke(Path(CGRect(x: inset.midX - boxW / 2, y: inset.minY, width: boxW, height: boxH)), with: line, lineWidth: 1.2)
            ctx.stroke(Path(CGRect(x: inset.midX - boxW / 2, y: inset.maxY - boxH, width: boxW, height: boxH)), with: line, lineWidth: 1.2)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

/// Small pitch showing how well a player knows each position.
struct PositionPitch: View {
    let familiarity: [UInt8]
    let keys: [String]

    var body: some View {
        GeometryReader { geo in
            ZStack {
                PitchBackground()
                ForEach(keys.indices, id: \.self) { i in
                    if let pt = PitchLayout.point(keys[i]) {
                        let v = i < familiarity.count ? Int(familiarity[i]) : 0
                        Circle()
                            .fill(dotColor(v))
                            .overlay(Circle().stroke(.white.opacity(v >= 15 ? 0.9 : 0.3), lineWidth: 1))
                            .frame(width: v >= 15 ? 15 : 11, height: v >= 15 ? 15 : 11)
                            .position(x: pt.x * geo.size.width, y: pt.y * geo.size.height)
                            .help("\(keys[i]): \(label(v))")
                    }
                }
            }
        }
        .aspectRatio(0.68, contentMode: .fit)
    }

    private func dotColor(_ v: Int) -> Color {
        switch v {
        case 18...: return Color(red: 0.25, green: 0.95, blue: 0.45)
        case 15...17: return Color(red: 0.7, green: 0.9, blue: 0.35)
        case 10...14: return Color(red: 0.95, green: 0.75, blue: 0.3)
        case 5...9: return Color.white.opacity(0.25)
        default: return Color.black.opacity(0.25)
        }
    }

    private func label(_ v: Int) -> String {
        switch v {
        case 18...: return "Natural"
        case 15...17: return "Accomplished"
        case 10...14: return "Competent"
        case 5...9: return "Unconvincing"
        default: return "Ineffectual"
        }
    }
}

/// Spider chart for up to three players.
struct RadarChart: View {
    let axes: [String]
    let series: [[Double]]     // 0–20 per axis

    var body: some View {
        Canvas { ctx, size in
            let n = axes.count
            guard n >= 3 else { return }
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2 - 34
            func pt(_ i: Int, _ v: Double) -> CGPoint {
                let a = -Double.pi / 2 + 2 * Double.pi * Double(i) / Double(n)
                let r = radius * CGFloat(v / 20)
                return CGPoint(x: c.x + r * CGFloat(cos(a)), y: c.y + r * CGFloat(sin(a)))
            }
            for ring in [5.0, 10, 15, 20] {
                var p = Path()
                for i in 0..<n { if i == 0 { p.move(to: pt(i, ring)) } else { p.addLine(to: pt(i, ring)) } }
                p.closeSubpath()
                ctx.stroke(p, with: .color(.white.opacity(ring == 20 ? 0.25 : 0.1)), lineWidth: 1)
            }
            for i in 0..<n {
                var p = Path(); p.move(to: c); p.addLine(to: pt(i, 20))
                ctx.stroke(p, with: .color(.white.opacity(0.1)), lineWidth: 1)
                let lp = pt(i, 23.5)
                ctx.draw(Text(axes[i]).font(.caption).foregroundStyle(.secondary), at: lp)
            }
            for (si, values) in series.enumerated() {
                var p = Path()
                for i in 0..<min(n, values.count) { if i == 0 { p.move(to: pt(i, values[i])) } else { p.addLine(to: pt(i, values[i])) } }
                p.closeSubpath()
                let col = Theme.series[si % Theme.series.count]
                ctx.fill(p, with: .color(col.opacity(0.22)))
                ctx.stroke(p, with: .color(col), lineWidth: 2)
            }
        }
    }
}
