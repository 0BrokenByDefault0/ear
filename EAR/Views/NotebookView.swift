import SwiftUI
import EARKit

struct NotebookView: View {
    private enum Order: String, CaseIterable, Identifiable { case newest = "Newest", title = "Title", tempo = "Tempo", loudness = "Loudness"; var id: String { rawValue } }

    @Environment(EarStore.self) private var store
    @Binding var importing: Bool
    @State private var search = ""
    @State private var deletion: Study?
    @State private var renaming: Study?
    @AppStorage("ear.notebook.order") private var orderName = Order.newest.rawValue

    private var order: Order { Order(rawValue: orderName) ?? .newest }

    private var filtered: [Study] {
        let matches = store.studies.filter {
            search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.notes.localizedCaseInsensitiveContains(search)
                || ($0.metrics.key?.name.localizedCaseInsensitiveContains(search) ?? false)
        }
        switch order {
        case .newest: return matches.sorted { $0.created > $1.created }
        case .title: return matches.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .tempo: return matches.sorted { ($0.tempo ?? 0) < ($1.tempo ?? 0) }
        case .loudness: return matches.sorted { ($0.metrics.integratedLoudness ?? -100) > ($1.metrics.integratedLoudness ?? -100) }
        }
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your listening\nnotebook.").font(Ink.display(40))
                    Text(summary).font(.subheadline).foregroundStyle(Ink.secondary)
                }
                .padding(.vertical, 8)
                .listRowBackground(Color.clear).listRowSeparator(.hidden)
            }
            if filtered.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label(search.isEmpty ? "A place for discoveries" : "No matching studies", systemImage: "waveform")
                    } description: {
                        Text(search.isEmpty ? "Import a song or try Afterglow to start your first study." : "Try a different title, key or note.")
                    } actions: {
                        if search.isEmpty {
                            Button("Study a song") { importing = true }.buttonStyle(.glassProminent).disabled(!store.canStartStudy)
                        }
                    }
                    .listRowBackground(Color.clear)
                }
            } else {
                Section {
                    ForEach(filtered) { study in
                        Button { store.open(study) } label: { NotebookRow(study: study) }
                            .buttonStyle(.plain)
                            .disabled(!store.canStartStudy)
                            .listRowBackground(Ink.surface)
                            .listRowSeparatorTint(Ink.line)
                            .swipeActions(edge: .trailing) {
                                Button("Delete", systemImage: "trash", role: .destructive) { deletion = study }
                            }
                            .swipeActions(edge: .leading) {
                                Button("Rename", systemImage: "pencil") { renaming = study }.tint(Ink.glow)
                            }
                            .contextMenu {
                                Button("Rename", systemImage: "pencil") { renaming = study }
                                ShareLink(item: study.shareText) { Label("Share report", systemImage: "square.and.arrow.up") }
                                if !study.metrics.isCurrent {
                                    Button("Re-measure", systemImage: "arrow.triangle.2.circlepath") { store.remeasure(study) }
                                }
                                Divider()
                                Button("Delete study", systemImage: "trash", role: .destructive) { deletion = study }
                            }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Ink.background)
        .foregroundStyle(Ink.primary)
        .navigationTitle("Notebook").navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, prompt: "Titles, keys and notes")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Picker("Sort by", selection: $orderName) { ForEach(Order.allCases) { Text($0.rawValue).tag($0.rawValue) } }
                } label: { Label("Sort", systemImage: "arrow.up.arrow.down") }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Import audio", systemImage: "plus") { importing = true }.disabled(!store.canStartStudy)
            }
        }
        .confirmationDialog("Delete this study and its imported audio copy?",
                            isPresented: Binding(get: { deletion != nil }, set: { if !$0 { deletion = nil } }), titleVisibility: .visible) {
            Button("Delete study", role: .destructive) { if let deletion { store.delete(deletion) }; deletion = nil }
        } message: { Text("Your original file is not affected.") }
        .sheet(item: $renaming) { study in
            NavigationStack { RenameView(study: study) }.environment(store).presentationDetents([.medium]).presentationBackground(Ink.background)
        }
    }

    private var summary: String {
        let count = store.studies.count
        guard count > 0 else { return "Keep the sounds. Remember the discoveries." }
        let tried = store.studies.reduce(0) { $0 + $1.completed.count }
        return "\(count) \(count == 1 ? "study" : "studies") · \(tried) \(tried == 1 ? "experiment" : "experiments") tried"
    }
}

struct NotebookRow: View {
    let study: Study
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(study.title).font(Ink.display(26, relativeTo: .title2)).foregroundStyle(Ink.primary).lineLimit(2)
                Spacer()
                if !study.metrics.isCurrent {
                    Image(systemName: "arrow.triangle.2.circlepath").font(.caption).foregroundStyle(Ink.warm)
                        .accessibilityLabel("Can be re-measured")
                }
            }
            Waveform(values: study.metrics.waveform, barWidth: 1.5).frame(height: 28)
            HStack(spacing: 6) {
                ForEach(study.chips, id: \.self) { Chip(text: $0) }
                Spacer(minLength: 0)
            }
            HStack {
                Text(study.created, style: .date)
                Spacer()
                Text("\(study.completed.count) tried")
            }
            .font(.system(.caption2, design: .monospaced)).foregroundStyle(Ink.secondary)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

struct RenameView: View {
    @Environment(EarStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let study: Study
    @State private var title = ""
    @FocusState private var focused: Bool

    var body: some View {
        Form {
            Section("Title") {
                TextField("Study title", text: $title).focused($focused).submitLabel(.done).onSubmit(save)
                    .accessibilityIdentifier("renameField")
            }
        }
        .scrollContentBackground(.hidden).background(Ink.background)
        .navigationTitle("Rename study").navigationBarTitleDisplayMode(.inline)
        .onAppear { title = study.title; focused = true }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).disabled(title.trimmingCharacters(in: .whitespaces).isEmpty) }
        }
    }

    private func save() {
        store.rename(study, to: title)
        dismiss()
    }
}
