import SwiftUI
import SwiftData
import WatchKit

struct TodoListView: View {
    let syncEngine: SyncEngine

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TodoItemLocal.lastModified, order: .reverse) private var todos: [TodoItemLocal]
    @State private var newTodoText = ""
    @State private var showAddSheet = false
    @State private var errorBanner: String?

    private var open: [TodoItemLocal] { todos.filter { !$0.done } }
    private var done: [TodoItemLocal] { todos.filter { $0.done } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TL.Space.s) {
                header

                if let err = errorBanner {
                    errorRow(err)
                }

                if todos.isEmpty {
                    emptyState
                } else {
                    if !open.isEmpty {
                        sectionHeader("Open · \(open.count)")
                        ForEach(open, id: \.localId) { todo in
                            todoCard(todo)
                        }
                    }
                    if !done.isEmpty {
                        sectionHeader("Done · \(done.count)")
                            .padding(.top, TL.Space.s)
                        ForEach(done.prefix(5), id: \.localId) { todo in
                            todoCard(todo)
                                .opacity(0.55)
                        }
                    }
                }
            }
            .padding(.horizontal, TL.Space.s)
            .padding(.bottom, TL.Space.m)
        }
        .sheet(isPresented: $showAddSheet) {
            addSheet
        }
    }

    private var header: some View {
        HStack {
            Text("Todos")
                .font(TL.TypeScale.title2)
            Spacer()
            Button {
                WKInterfaceDevice.current().play(.click)
                showAddSheet = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 26, height: 26)
                    .background { Circle().fill(TL.Palette.emerald.gradient) }
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 4)
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(TL.TypeScale.caption2)
            .foregroundStyle(.secondary)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "checklist")
                .font(.system(size: 30))
                .foregroundStyle(.white.opacity(0.55))
            Text("No todos yet").font(TL.TypeScale.caption)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, TL.Space.xl)
    }

    @ViewBuilder
    private func todoCard(_ todo: TodoItemLocal) -> some View {
        let linkedTint: Color = todo.done ? TL.Palette.emerald : TL.Palette.sky
        HStack(alignment: .top, spacing: 10) {
            Button {
                WKInterfaceDevice.current().play(todo.done ? .click : .success)
                toggleDone(todo)
            } label: {
                Image(systemName: todo.done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(todo.done ? TL.Palette.emerald : .secondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(todo.text)
                    .font(TL.TypeScale.callout)
                    .strikethrough(todo.done)
                    .lineLimit(3)
            }
            Spacer(minLength: 0)
        }
        .glassCard(tint: linkedTint, cornerRadius: TL.Radius.m, padding: TL.Space.s)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                delete(todo)
            } label: {
                Label("Delete", systemImage: "trash")
            }
            if !todo.done {
                Button {
                    startTimerLinked(to: todo)
                } label: {
                    Label("Start", systemImage: "play.fill")
                }
                .tint(TL.Palette.sky)
            }
        }
    }

    private var addSheet: some View {
        VStack(spacing: TL.Space.s) {
            Text("New Todo")
                .font(TL.TypeScale.headline)
            TextField("What to do?", text: $newTodoText)
                .textFieldStyle(.plain)
                .padding(8)
                .background {
                    RoundedRectangle(cornerRadius: 10).fill(.ultraThinMaterial)
                }
            Button {
                WKInterfaceDevice.current().play(.success)
                addTodo()
            } label: {
                Label("Add", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass(tint: TL.Palette.emerald, prominent: true))
            .disabled(newTodoText.isEmpty)
        }
        .padding()
    }

    // MARK: - Actions

    private func toggleDone(_ todo: TodoItemLocal) {
        let previous = todo.done
        todo.done.toggle()
        todo.lastModified = .now
        todo.needsSync = true
        guard persist("update todo") else {
            todo.done = previous
            return
        }
        syncEngine.scheduleSyncAfterMutation()
    }

    private func delete(_ todo: TodoItemLocal) {
        if let serverId = todo.serverId {
            modelContext.insert(PendingDeletion(tableName: "todos", recordServerId: serverId))
        }
        modelContext.delete(todo)
        guard persist("delete todo") else { return }
        syncEngine.scheduleSyncAfterMutation()
    }

    private func addTodo() {
        let trimmed = newTodoText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let todo = TodoItemLocal(text: trimmed)
        modelContext.insert(todo)
        guard persist("add todo") else { return }
        newTodoText = ""
        showAddSheet = false
        syncEngine.scheduleSyncAfterMutation()
    }

    @discardableResult
    private func persist(_ action: String) -> Bool {
        do {
            try modelContext.save()
            errorBanner = nil
            return true
        } catch {
            errorBanner = "Couldn't \(action): \(error.localizedDescription)"
            return false
        }
    }

    @ViewBuilder
    private func errorRow(_ message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10))
                .foregroundStyle(TL.Palette.ember)
            Text(message)
                .font(TL.TypeScale.caption2)
                .lineLimit(3)
            Spacer(minLength: 0)
        }
        .padding(8)
        .background {
            RoundedRectangle(cornerRadius: 8).fill(.ultraThinMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(TL.Palette.ember.opacity(0.4), lineWidth: 1)
        }
        .onTapGesture { errorBanner = nil }
    }

    private func startTimerLinked(to todo: TodoItemLocal) {
        Task {
            if syncEngine.isOnline {
                _ = try? await syncEngine.apiClient.startTimer(
                    name: todo.text,
                    category: "Todo",
                    todoId: todo.serverId
                )
                await syncEngine.syncIfReachable(modelContainer: modelContext.container)
            } else {
                // Offline: pause any running timer first
                let runningDesc = FetchDescriptor<ActiveTimerLocal>(
                    predicate: #Predicate { $0.state == "running" }
                )
                if let running = try? modelContext.fetch(runningDesc).first {
                    running.state = "paused"
                    running.breaks.append(.now())
                    running.lastModified = .now
                    running.needsSync = true
                }
                let newTimer = ActiveTimerLocal(
                    name: todo.text,
                    category: "Todo",
                    todoId: todo.serverId
                )
                modelContext.insert(newTimer)
                try? modelContext.save()
                syncEngine.scheduleSyncAfterMutation()
            }
        }
    }
}
