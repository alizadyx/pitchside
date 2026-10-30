import AppKit
import PitchsideCore
import SwiftUI

/// Teaches the plugin where FM keeps each field, using people you can see in game.
struct CalibrationView: View {
    @Environment(Store.self) private var store
    @State private var tab = 0

    var body: some View {
        @Bindable var store = store
        HSplitView {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Calibration").font(.title2.bold())
                    Text("""
                    FM27 keeps players in memory in a layout nobody has mapped yet. Give the plugin \
                    2 of your own players and 1 of your own staff (exact attributes are visible for them), \
                    and it will find where every field lives.

                    1. Load your save in FM and keep it on any screen.
                    2. For each person: type the name exactly as FM shows it, their date of birth and height \
                    if you can see them, and as many attributes as you can read (at least 8).
                    3. Press Run calibration. It takes about a minute. Then press Apply suggested offsets and Scan.
                    """)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                    Picker("", selection: $tab) {
                        ForEach(store.targets.indices, id: \.self) { i in
                            Text(store.targets[i].name.isEmpty ? "Person \(i + 1)" : store.targets[i].name).tag(i)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    if store.targets.indices.contains(tab) {
                        TargetEditor(target: $store.targets[tab])
                    }

                    HStack {
                        Button {
                            store.calibrate()
                        } label: {
                            Label("Run calibration", systemImage: "scope")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(store.isBusy)
                        Button("Apply suggested offsets") { store.applySuggestion() }
                            .disabled(!store.hasSuggestion || store.isBusy)
                        Spacer()
                        Button("Open data folder") { store.revealFolder() }
                    }
                }
                .padding(16)
            }
            .frame(minWidth: 460, idealWidth: 520)

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Report").font(.headline)
                    Spacer()
                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(store.reportText, forType: .string)
                    }
                    .disabled(store.reportText.isEmpty)
                    Button("Reload") { store.loadReport() }
                }
                .padding(10)
                if store.reportText.isEmpty {
                    Text("No calibration report yet.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ReportTextView(text: store.reportText)
                }
            }
            .frame(minWidth: 420)
        }
    }
}

struct TargetEditor: View {
    @Binding var target: CalibrationTarget

    private var keys: [String] {
        target.kind == "staff"
            ? AttributeGroups.staffCoaching + AttributeGroups.staffMental + AttributeGroups.staffKnowledge
            : AttributeGroups.visibleOutfield + AttributeGroups.goalkeeping
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                GridRow {
                    Text("Name")
                    TextField("e.g. Bukayo Saka", text: $target.name).textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("Type")
                    Picker("", selection: $target.kind) {
                        Text("Player").tag("player")
                        Text("Staff").tag("staff")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 180)
                }
                GridRow {
                    Text("Born")
                    TextField("yyyy-mm-dd", text: Binding(
                        get: { target.birthDate ?? "" },
                        set: { target.birthDate = $0.isEmpty ? nil : $0 }))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                }
                if target.kind == "player" {
                    GridRow {
                        Text("Height cm")
                        TextField("", value: $target.heightCm, format: .number.grouping(.never))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 70)
                    }
                }
            }

            Text("Attributes (leave blank if unknown)").font(.headline).padding(.top, 4)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], alignment: .leading, spacing: 6) {
                ForEach(keys, id: \.self) { k in
                    HStack {
                        Text(AttributeGroups.label(k)).font(.callout)
                        Spacer(minLength: 4)
                        TextField("", text: Binding(
                            get: { target.attributes[k].map(String.init) ?? "" },
                            set: { s in
                                if let v = Int(s.trimmingCharacters(in: .whitespaces)), (1...20).contains(v) {
                                    target.attributes[k] = v
                                } else {
                                    target.attributes[k] = nil
                                }
                            }))
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.center)
                            .frame(width: 38)
                    }
                }
            }
            Text("\(target.attributes.count) attributes entered")
                .font(.caption).foregroundStyle(target.attributes.count >= 8 ? Color.green : Color.secondary)
        }
    }
}

/// NSTextView: the report can be large, and SwiftUI Text is slow with big monospaced text.
struct ReportTextView: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        if let tv = scroll.documentView as? NSTextView {
            tv.isEditable = false
            tv.isSelectable = true
            tv.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
            tv.textContainerInset = NSSize(width: 8, height: 8)
        }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? NSTextView, tv.string != text else { return }
        tv.string = text
    }
}
