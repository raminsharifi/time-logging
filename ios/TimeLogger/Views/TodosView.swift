import SwiftUI
import SwiftData

struct TodosView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var syncEngine: SyncEngine

    @Query(sort: \TodoItemLocal.createdAt, order: .reverse)
    private var todos: [TodoItemLocal]

    @State private var newText = ""
    @FocusState private var newFocused: Bool

    private var active: [TodoItemLocal] { todos.filter { !$0.done } }
    private var done:   [TodoItemLocal] { todos.filter {  $0.done } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                StatusStrip(
                    title: "Todos",
                    caption: tlStatusCaption(),
                    right: { MonoLabel("\(active.count) open", color: TL.Palette.ink) }
                )

                VStack(alignment: .leading, spacing: 20) {
                    addBar.padding(.top, 16)

                    section(title: "Active · \(active.count)") {
                        if active.isEmpty {
                            Text("Clear. Nice.")
                                .font(.system(size: 13))
                                .foregroundStyle(TL.Palette.dim)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 20)
                        } else {
                            ForEach(active, id: \.localId) { t in
                                todoRow(t)
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button(role: .destructive) { delete(t) } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                            }
                        }
                    }

                    if !done.isEmpty {
                        section(title: "Done · \(done.count)") {
                            ForEach(done, id: \.localId) { t in
                                todoRow(t)
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button(role: .destructive) { delete(t) } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                            }
                        }
                    }
                }
                .padding(.horizontal, TL.Space.l)
                .padding(.bottom, TL.Space.l)
            }
        }
        .background(TL.Palette.bg)
        .scrollContentBackground(.hidden)
    }

    // MARK: - Add bar

    private var addBar: some View {
        HStack(spacing: 0) {
            TextField("New task…", text: $newText)
                .font(.system(size: 14))
                .foregroundStyle(TL.Palette.ink)
                .focused($newFocused)
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                .onSubmit { add() }

            Button(action: add) {
                HStack(spacing: 6) {
                    Image(systemName: "plus").font(.system(size: 12, weight: .bold))
                    Text("ADD").tracking(1.2)
                }
                .font(TL.TypeScale.label(10))
                .foregroundStyle(TL.Palette.bg)
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .background(TL.Palette.accent)
            }
            .buttonStyle(.plain)
            .disabled(newText.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .background(TL.Palette.surface)
        .overlay {
            RoundedRectangle(cornerRadius: TL.Radius.m)
                .strokeBorder(TL.Palette.line, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: TL.Radius.m, style: .continuous))
    }

    // MARK: - Row

    @ViewBuilder
    private func todoRow(_ t: TodoItemLocal) -> some View {
        HStack(spacing: 12) {
            Button {
                toggle(t)
            } label: {
                checkbox(on: t.done)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 3) {
                Text(t.text)
                    .font(.system(size: 14))
                    .foregroundStyle(t.done ? TL.Palette.dim : TL.Palette.ink)
                    .strikethrough(t.done)
            }
            Spacer()
            if !t.done {
                Button { startTimer(from: t) } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(TL.Palette.ink)
                        .frame(width: 28, height: 28)
                        .overlay {
                            RoundedRectangle(cornerRadius: TL.Radius.s)
                                .strokeBorder(TL.Palette.line, lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            Rectangle().fill(TL.Palette.line).frame(height: 1)
        }
    }

    private func checkbox(on: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: TL.Radius.s, style: .continuous)
                .fill(on ? TL.Palette.accent : Color.clear)
            RoundedRectangle(cornerRadius: TL.Radius.s, style: .continuous)
                .strokeBorder(on ? TL.Palette.accent : TL.Palette.lineHi, lineWidth: 1.5)
            if on {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(TL.Palette.bg)
            }
        }
        .frame(width: 18, height: 18)
    }

    // MARK: - Section wrapper

    @ViewBuilder
    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            MonoLabel(title)
            VStack(spacing: 0) { content() }
        }
    }

    // MARK: - Actions

    private func add() {
        let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let t = TodoItemLocal(text: trimmed)
        modelContext.insert(t)
        try? modelContext.save()
        newText = ""
        syncEngine.scheduleSyncAfterMutation()
    }

    private func toggle(_ t: TodoItemLocal) {
        t.done.toggle()
        t.lastModified = Int64(Date().timeIntervalSince1970)
        try? modelContext.save()
        syncEngine.scheduleSyncAfterMutation()
    }

    private func delete(_ t: TodoItemLocal) {
        if let sid = t.serverId {
            modelContext.insert(PendingDeletion(tableName: "todos", recordServerId: sid))
        }
        modelContext.delete(t)
        try? modelContext.save()
        syncEngine.scheduleSyncAfterMutation()
    }

    private func startTimer(from t: TodoItemLocal) {
        // Pause a running timer if any, then start a new one linked to this todo.
        let running = (try? modelContext.fetch(
            FetchDescriptor<ActiveTimerLocal>(predicate: #Predicate { $0.state == "running" })
        ))?.first
        running?.pause()
        let timer = ActiveTimerLocal(name: t.text, category: "General", todoId: t.serverId)
        modelContext.insert(timer)
        try? modelContext.save()
        syncEngine.scheduleSyncAfterMutation()
    }
}
