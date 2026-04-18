import SwiftUI

struct EntryDetailSheet: View {
    @EnvironmentObject var api: APIClient
    @Environment(\.dismiss) private var dismiss

    let entry: EntryResponse
    let onDone: () async -> Void

    @State private var name: String = ""
    @State private var category: String = ""
    @State private var addMinutes: String = ""
    @State private var subMinutes: String = ""
    @State private var calendarAdded = false

    var body: some View {
        let tint = TL.categoryColor(category.isEmpty ? entry.category : category)
        VStack(alignment: .leading, spacing: TL.Space.l) {
            // Hero
            HStack(spacing: TL.Space.m) {
                RingProgress(progress: 1.0, tint: tint) {
                    Text(formatDuration(entry.active_secs))
                        .font(TL.TypeScale.mono(14, weight: .semibold))
                        .foregroundStyle(tint)
                        .monospacedDigit()
                }
                .frame(width: 90, height: 90)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Entry").font(TL.TypeScale.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text(name.isEmpty ? entry.name : name)
                        .font(TL.TypeScale.title3)
                        .lineLimit(2)
                    CategoryChip(name: category.isEmpty ? entry.category : category)
                }
                Spacer()
            }

            // Metadata
            VStack(alignment: .leading, spacing: 4) {
                row(label: "Started", value: formatTimestamp(entry.started_at))
                row(label: "Ended",   value: formatTimestamp(entry.ended_at))
                row(label: "Active",  value: formatDuration(entry.active_secs))
                if entry.break_secs > 0 {
                    row(label: "Breaks", value: formatDuration(entry.break_secs))
                }
            }

            // Edit
            VStack(alignment: .leading, spacing: 8) {
                Text("EDIT")
                    .font(TL.TypeScale.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField("Name", text: $name)
                    .textFieldStyle(.plain)
                    .padding(8)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                TextField("Category", text: $category)
                    .textFieldStyle(.plain)
                    .padding(8)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("ADJUST TIME")
                    .font(TL.TypeScale.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                HStack {
                    TextField("± minutes", text: $addMinutes)
                        .textFieldStyle(.plain)
                        .padding(8)
                        .frame(width: 120)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    Button("Add") { addTime() }
                        .disabled(Int(addMinutes) == nil)
                }
                HStack {
                    TextField("minutes", text: $subMinutes)
                        .textFieldStyle(.plain)
                        .padding(8)
                        .frame(width: 120)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    Button("Subtract") { subtractTime() }
                        .disabled(Int(subMinutes) == nil)
                }
            }

            HStack {
                Button(role: .destructive) {
                    Task {
                        try? await api.deleteEntry(id: entry.id)
                        await onDone()
                        dismiss()
                    }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                Button {
                    addToCalendar()
                } label: {
                    Label(calendarAdded ? "Added" : "Add to Calendar",
                          systemImage: calendarAdded ? "checkmark.circle.fill" : "calendar.badge.plus")
                }
                .disabled(calendarAdded)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button {
                    save()
                } label: {
                    Text("Save")
                        .frame(minWidth: 80)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(tint)
                .controlSize(.large)
            }
        }
        .padding(TL.Space.l)
        .frame(width: 480)
        .background(.ultraThinMaterial)
        .onAppear {
            name = entry.name
            category = entry.category
        }
    }

    @ViewBuilder
    private func row(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(TL.TypeScale.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(TL.TypeScale.caption.monospacedDigit())
        }
    }

    private func save() {
        Task {
            let req = EditEntryRequest(
                name: name == entry.name ? nil : name,
                category: category == entry.category ? nil : category,
                add_mins: nil,
                sub_mins: nil
            )
            _ = try? await api.editEntry(id: entry.id, request: req)
            await onDone()
            dismiss()
        }
    }

    private func addTime() {
        guard let mins = Int(addMinutes), mins > 0 else { return }
        Task {
            _ = try? await api.editEntry(id: entry.id, request: EditEntryRequest(name: nil, category: nil, add_mins: mins, sub_mins: nil))
            addMinutes = ""
            await onDone()
        }
    }

    private func subtractTime() {
        guard let mins = Int(subMinutes), mins > 0 else { return }
        Task {
            _ = try? await api.editEntry(id: entry.id, request: EditEntryRequest(name: nil, category: nil, add_mins: nil, sub_mins: mins))
            subMinutes = ""
            await onDone()
        }
    }

    private func addToCalendar() {
        Task {
            if CalendarService.authorization != .fullAccess {
                _ = await CalendarService.requestAccess()
            }
            let start = Date(timeIntervalSince1970: TimeInterval(entry.started_at))
            let end = Date(timeIntervalSince1970: TimeInterval(entry.ended_at))
            let title = name.isEmpty ? entry.name : name
            let cat = category.isEmpty ? entry.category : category
            let ok = CalendarService.addEvent(
                title: title,
                notes: "TimeLogger · \(cat) · \(formatDuration(entry.active_secs))",
                start: start,
                end: end
            )
            calendarAdded = ok
        }
    }
}
