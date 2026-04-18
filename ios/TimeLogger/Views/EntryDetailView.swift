import SwiftUI
import SwiftData

struct EntryDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var syncEngine: SyncEngine

    @Bindable var entry: TimeEntryLocal

    @State private var editName: String = ""
    @State private var editCategory: String = ""
    @State private var adjustMinutes: String = ""

    private var tint: Color { TL.categoryColor(entry.category) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: TL.Space.m) {
                    hero
                    editPanel
                    breaksPanel
                    adjustPanel
                    deleteButton
                }
                .padding(.horizontal, TL.Space.m)
                .padding(.top, TL.Space.s)
                .padding(.bottom, TL.Space.xl)
            }
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Entry").font(TL.TypeScale.headline)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        applyEdits()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                editName = entry.name
                editCategory = entry.category
            }
        }
    }

    // MARK: - Hero

    @ViewBuilder
    private var hero: some View {
        VStack(spacing: TL.Space.s) {
            RingProgress(progress: nil, tint: tint, lineWidth: 10, glow: false) {
                VStack(spacing: 2) {
                    CategoryChip(name: entry.category, compact: true)
                    Text(TL.clock(entry.activeSecs))
                        .font(TL.TypeScale.mono(32, weight: .semibold))
                        .foregroundStyle(.primary)
                }
            }
            .frame(height: 180)

            Text(entry.name)
                .font(TL.TypeScale.title3)
                .multilineTextAlignment(.center)
                .padding(.horizontal, TL.Space.m)

            HStack(spacing: TL.Space.l) {
                stat("STARTED", value: formatTimestamp(entry.startedAt))
                stat("ENDED", value: formatTimestamp(entry.endedAt))
            }

            if entry.breakSecs > 0 {
                Text("Break total: \(TL.clock(entry.breakSecs))")
                    .font(TL.TypeScale.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, TL.Space.s)
        .glassCard(tint: tint, cornerRadius: TL.Radius.xl, padding: TL.Space.m)
    }

    private func stat(_ label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(TL.TypeScale.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(TL.TypeScale.caption.weight(.semibold))
        }
    }

    // MARK: - Edit

    @ViewBuilder
    private var editPanel: some View {
        VStack(alignment: .leading, spacing: TL.Space.xs) {
            Text("EDIT")
                .font(TL.TypeScale.caption2)
                .foregroundStyle(.secondary)

            TextField("Name", text: $editName)
                .padding(10)
                .background { RoundedRectangle(cornerRadius: 12).fill(.ultraThinMaterial) }

            TextField("Category", text: $editCategory)
                .padding(10)
                .background { RoundedRectangle(cornerRadius: 12).fill(.ultraThinMaterial) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(tint: TL.Palette.sky, cornerRadius: TL.Radius.l, padding: TL.Space.m)
    }

    // MARK: - Breaks timeline

    @ViewBuilder
    private var breaksPanel: some View {
        if !entry.breaks.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("BREAKS · \(entry.breaks.count)")
                    .font(TL.TypeScale.caption2)
                    .foregroundStyle(.secondary)

                let total = max(entry.endedAt - entry.startedAt, 1)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(tint.opacity(0.25))
                            .frame(height: 10)
                        ForEach(Array(entry.breaks.enumerated()), id: \.offset) { _, brk in
                            let start = max(0, brk.startTs - entry.startedAt)
                            let end = brk.endTs == 0 ? entry.endedAt : brk.endTs
                            let width = max(0, end - max(brk.startTs, entry.startedAt))
                            let x = geo.size.width * Double(start) / Double(total)
                            let w = max(2, geo.size.width * Double(width) / Double(total))
                            Capsule()
                                .fill(TL.Palette.citrine.gradient)
                                .frame(width: w, height: 10)
                                .offset(x: x)
                        }
                    }
                }
                .frame(height: 10)

                ForEach(Array(entry.breaks.enumerated()), id: \.offset) { _, brk in
                    HStack(spacing: 8) {
                        Image(systemName: "pause.circle.fill")
                            .font(.caption)
                            .foregroundStyle(TL.Palette.citrine)
                        Text(formatTimestamp(brk.startTs))
                            .font(TL.TypeScale.caption2)
                        Spacer()
                        let d = (brk.endTs == 0 ? entry.endedAt : brk.endTs) - brk.startTs
                        Text(TL.clockShort(d))
                            .font(TL.TypeScale.mono(11))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(tint: TL.Palette.citrine, cornerRadius: TL.Radius.l, padding: TL.Space.m)
        }
    }

    // MARK: - Adjust

    @ViewBuilder
    private var adjustPanel: some View {
        VStack(alignment: .leading, spacing: TL.Space.xs) {
            Text("ADJUST TIME (MIN)")
                .font(TL.TypeScale.caption2)
                .foregroundStyle(.secondary)

            TextField("Minutes (+/-)", text: $adjustMinutes)
                .keyboardType(.numbersAndPunctuation)
                .padding(10)
                .background { RoundedRectangle(cornerRadius: 12).fill(.ultraThinMaterial) }

            HStack(spacing: TL.Space.s) {
                Button {
                    adjust(positive: false)
                } label: {
                    Label("Subtract", systemImage: "minus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass(tint: TL.Palette.ember))
                .disabled(Int64(adjustMinutes) == nil)

                Button {
                    adjust(positive: true)
                } label: {
                    Label("Add", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass(tint: TL.Palette.emerald))
                .disabled(Int64(adjustMinutes) == nil)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(tint: TL.Palette.iris, cornerRadius: TL.Radius.l, padding: TL.Space.m)
    }

    @ViewBuilder
    private var deleteButton: some View {
        Button(role: .destructive) {
            if let serverId = entry.serverId {
                modelContext.insert(PendingDeletion(tableName: "time_entries", recordServerId: serverId))
            }
            modelContext.delete(entry)
            try? modelContext.save()
            syncEngine.scheduleSyncAfterMutation()
            dismiss()
        } label: {
            Label("Delete Entry", systemImage: "trash")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glass(tint: TL.Palette.ember, prominent: true))
    }

    // MARK: - Actions

    private func adjust(positive: Bool) {
        guard let raw = Int64(adjustMinutes) else { return }
        let mins = abs(raw)
        guard mins > 0 else { return }
        let delta = positive ? mins * 60 : -mins * 60
        entry.activeSecs = max(entry.activeSecs + delta, 0)
        entry.lastModified = Int64(Date().timeIntervalSince1970)
        entry.needsSync = true
        adjustMinutes = ""
        save()
    }

    private func applyEdits() {
        var changed = false
        if !editName.isEmpty && editName != entry.name {
            entry.name = editName
            changed = true
        }
        if !editCategory.isEmpty && editCategory != entry.category {
            entry.category = editCategory
            changed = true
        }
        if changed {
            entry.lastModified = Int64(Date().timeIntervalSince1970)
            entry.needsSync = true
            save()
        }
    }

    private func save() {
        try? modelContext.save()
        syncEngine.scheduleSyncAfterMutation()
    }

    private func formatTimestamp(_ ts: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(ts))
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
