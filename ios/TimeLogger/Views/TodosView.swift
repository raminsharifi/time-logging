import SwiftUI
import SwiftData

struct TodosView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var syncEngine: SyncEngine

    @Query(sort: \TodoItemLocal.createdAt, order: .reverse) private var todos: [TodoItemLocal]

    @State private var showAddSheet = false
    @State private var newTodoText = ""
    @State private var editingTodo: TodoItemLocal?
    @State private var editText = ""

    var openTodos: [TodoItemLocal] { todos.filter { !$0.done } }
    var doneTodos: [TodoItemLocal] { todos.filter { $0.done } }

    /// Simple "today" heuristic: modified today or created today.
    var todayTodos: [TodoItemLocal] {
        let cal = Calendar.current
        return openTodos.filter {
            cal.isDateInToday(Date(timeIntervalSince1970: Double($0.lastModified))) ||
            cal.isDateInToday(Date(timeIntervalSince1970: Double($0.createdAt)))
        }
    }

    var upcomingTodos: [TodoItemLocal] {
        let todaySet = Set(todayTodos.map(\.localId))
        return openTodos.filter { !todaySet.contains($0.localId) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: TL.Space.m) {
                    if todos.isEmpty {
                        emptyCard
                    } else {
                        if !todayTodos.isEmpty {
                            sectionHeader("TODAY · \(todayTodos.count)", tint: TL.Palette.emerald)
                            ForEach(todayTodos, id: \.localId) { todo in
                                todoCard(todo)
                            }
                        }
                        if !upcomingTodos.isEmpty {
                            sectionHeader("UPCOMING · \(upcomingTodos.count)", tint: TL.Palette.sky)
                            ForEach(upcomingTodos, id: \.localId) { todo in
                                todoCard(todo)
                            }
                        }
                        if !doneTodos.isEmpty {
                            sectionHeader("DONE · \(doneTodos.count)", tint: TL.Palette.mist)
                            ForEach(doneTodos.prefix(10), id: \.localId) { todo in
                                todoCard(todo)
                                    .opacity(0.6)
                            }
                        }
                    }
                }
                .padding(.horizontal, TL.Space.m)
                .padding(.top, TL.Space.s)
                .padding(.bottom, TL.Space.l)
            }
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Todos").font(TL.TypeScale.headline)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showAddSheet = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundStyle(TL.Palette.emerald.gradient)
                    }
                }
            }
            .alert("Add Todo", isPresented: $showAddSheet) {
                TextField("Todo text", text: $newTodoText)
                Button("Add") { addTodo() }
                Button("Cancel", role: .cancel) { newTodoText = "" }
            }
            .alert("Edit Todo", isPresented: Binding(
                get: { editingTodo != nil },
                set: { if !$0 { editingTodo = nil } }
            )) {
                TextField("Todo text", text: $editText)
                Button("Save") {
                    if let todo = editingTodo, !editText.isEmpty {
                        todo.text = editText
                        todo.lastModified = Int64(Date().timeIntervalSince1970)
                        todo.needsSync = true
                        try? modelContext.save()
                        syncEngine.scheduleSyncAfterMutation()
                    }
                    editingTodo = nil
                }
                Button("Cancel", role: .cancel) {
                    editingTodo = nil
                }
            }
        }
    }

    // MARK: - Components

    private func sectionHeader(_ title: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(tint.gradient).frame(width: 6, height: 6)
            Text(title)
                .font(TL.TypeScale.caption2)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    @ViewBuilder
    private func todoCard(_ todo: TodoItemLocal) -> some View {
        let tint = todo.done ? TL.Palette.emerald : TL.Palette.sky

        HStack(spacing: TL.Space.s) {
            Button {
                withAnimation(TL.Motion.bouncy) {
                    toggleDone(todo)
                }
            } label: {
                Image(systemName: todo.done ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(todo.done ? TL.Palette.emerald : .secondary)
                    .symbolEffect(.bounce, value: todo.done)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(todo.text)
                    .font(TL.TypeScale.callout)
                    .strikethrough(todo.done)
                    .foregroundStyle(todo.done ? .secondary : .primary)
                    .lineLimit(3)
                Text(Date(timeIntervalSince1970: Double(todo.createdAt))
                    .formatted(.relative(presentation: .named)))
                    .font(TL.TypeScale.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(TL.Space.s)
        .glassCard(tint: tint, cornerRadius: TL.Radius.m, padding: 0)
        .sensoryFeedback(.success, trigger: todo.done)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) { deleteTodo(todo) } label: {
                Label("Delete", systemImage: "trash")
            }
            Button {
                editingTodo = todo
                editText = todo.text
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(TL.Palette.citrine)
            if !todo.done {
                Button { startTimerLinked(to: todo) } label: {
                    Label("Start", systemImage: "play.fill")
                }
                .tint(TL.Palette.emerald)
            }
        }
    }

    @ViewBuilder
    private var emptyCard: some View {
        VStack(spacing: 8) {
            Image(systemName: "checklist")
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(.white.opacity(0.6))
            Text("No todos yet")
                .font(TL.TypeScale.callout)
            Text("Tap + to capture something.")
                .font(TL.TypeScale.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, TL.Space.xl)
        .glassCard(tint: TL.Palette.mist, cornerRadius: TL.Radius.l, padding: TL.Space.s)
    }

    // MARK: - Actions

    private func addTodo() {
        let trimmed = newTodoText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let todo = TodoItemLocal(text: trimmed)
        modelContext.insert(todo)
        try? modelContext.save()
        syncEngine.scheduleSyncAfterMutation()
        newTodoText = ""
    }

    private func toggleDone(_ todo: TodoItemLocal) {
        todo.done.toggle()
        todo.lastModified = Int64(Date().timeIntervalSince1970)
        todo.needsSync = true
        try? modelContext.save()
        syncEngine.scheduleSyncAfterMutation()
    }

    private func deleteTodo(_ todo: TodoItemLocal) {
        if let serverId = todo.serverId {
            modelContext.insert(PendingDeletion(tableName: "todos", recordServerId: serverId))
        }
        modelContext.delete(todo)
        try? modelContext.save()
        syncEngine.scheduleSyncAfterMutation()
    }

    private func startTimerLinked(to todo: TodoItemLocal) {
        // Pause any running timer first.
        let runningDesc = FetchDescriptor<ActiveTimerLocal>(
            predicate: #Predicate { $0.state == "running" }
        )
        if let running = try? modelContext.fetch(runningDesc).first {
            running.pause()
        }
        let timer = ActiveTimerLocal(
            name: todo.text,
            category: "Todo",
            todoId: todo.serverId
        )
        modelContext.insert(timer)
        try? modelContext.save()
        syncEngine.scheduleSyncAfterMutation()
    }
}
