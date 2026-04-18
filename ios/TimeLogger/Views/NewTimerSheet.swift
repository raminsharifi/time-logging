import SwiftUI
import SwiftData

struct NewTimerSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var bleManager: BLEManager
    @EnvironmentObject var syncEngine: SyncEngine

    @Query(sort: \ActiveTimerLocal.startedAt) private var timers: [ActiveTimerLocal]
    @Query(filter: #Predicate<TodoItemLocal> { !$0.done }, sort: \TodoItemLocal.createdAt)
    private var openTodos: [TodoItemLocal]

    @State private var name = ""
    @State private var category = ""
    @State private var selectedTodoId: Int?
    @State private var suggestedNames: [String] = []
    @State private var suggestedCategories: [String] = []
    @State private var recentTodos: [APITodoResponse] = []
    @State private var calendarSuggestion: CalendarSuggestion?
    @State private var calendarAccessRequested = false

    private var tint: Color { TL.categoryColor(category.isEmpty ? "General" : category) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: TL.Space.m) {
                    calendarPanel
                    namePanel
                    categoryPanel
                    todoPanel

                    Button {
                        startTimer()
                    } label: {
                        Label("Start Timer", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass(tint: tint, prominent: true))
                    .disabled(name.isEmpty || category.isEmpty)
                }
                .padding(.horizontal, TL.Space.m)
                .padding(.top, TL.Space.s)
                .padding(.bottom, TL.Space.l)
            }
            .scrollContentBackground(.hidden)
            .background {
                AnimatedMesh(tint: tint, animated: true)
                    .ignoresSafeArea()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("New Timer").font(TL.TypeScale.headline)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task {
                await loadSuggestions()
                await refreshCalendar()
            }
        }
    }

    // MARK: - Calendar

    @ViewBuilder
    private var calendarPanel: some View {
        let status = CalendarService.authorization
        if let s = calendarSuggestion {
            calendarSuggestionRow(s)
        } else if status == .notDetermined && !calendarAccessRequested {
            VStack(alignment: .leading, spacing: TL.Space.xs) {
                Text("FROM CALENDAR")
                    .font(TL.TypeScale.caption2)
                    .foregroundStyle(.secondary)
                Button {
                    Task {
                        calendarAccessRequested = true
                        _ = await CalendarService.requestAccess()
                        await refreshCalendar()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "calendar")
                        Text("Use calendar to suggest timers")
                            .font(TL.TypeScale.body)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(10)
                }
                .buttonStyle(.plain)
                .background {
                    RoundedRectangle(cornerRadius: 12).fill(.ultraThinMaterial)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(tint: TL.Palette.iris, cornerRadius: TL.Radius.l, padding: TL.Space.m)
        }
    }

    @ViewBuilder
    private func calendarSuggestionRow(_ s: CalendarSuggestion) -> some View {
        Button {
            applyCalendarSuggestion(s)
        } label: {
            VStack(alignment: .leading, spacing: TL.Space.xs) {
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .foregroundStyle(TL.Palette.iris)
                    Text("FROM CALENDAR · \(s.relativeLabel)")
                        .font(TL.TypeScale.caption2)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Text("Use")
                        .font(TL.TypeScale.caption.weight(.semibold))
                        .foregroundStyle(TL.Palette.iris)
                }
                Text(s.title)
                    .font(TL.TypeScale.body.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if !s.calendarTitle.isEmpty {
                    Text(s.calendarTitle)
                        .font(TL.TypeScale.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .glassCard(tint: TL.Palette.iris, cornerRadius: TL.Radius.l, padding: TL.Space.m)
    }

    private func refreshCalendar() async {
        calendarSuggestion = CalendarService.nextSuggestion()
    }

    private func applyCalendarSuggestion(_ s: CalendarSuggestion) {
        name = s.title
        let candidates: [(id: Int, text: String)] = openTodos.compactMap {
            guard let id = $0.serverId else { return nil }
            return (id, $0.text)
        }
        if let matchId = TodoMatcher.bestMatchId(for: s.title, in: candidates) {
            selectedTodoId = matchId
        }
    }

    // MARK: - Name

    @ViewBuilder
    private var namePanel: some View {
        VStack(alignment: .leading, spacing: TL.Space.xs) {
            Text("ACTIVITY")
                .font(TL.TypeScale.caption2)
                .foregroundStyle(.secondary)

            TextField("What are you working on?", text: $name)
                .autocorrectionDisabled()
                .padding(10)
                .background {
                    RoundedRectangle(cornerRadius: 12).fill(.ultraThinMaterial)
                }

            if !recentTodos.isEmpty && name.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(recentTodos.prefix(6), id: \.id) { todo in
                            Button {
                                name = todo.text
                                selectedTodoId = todo.id
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "checklist")
                                        .font(.caption2)
                                    Text(todo.text)
                                        .lineLimit(1)
                                }
                                .font(TL.TypeScale.caption)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background {
                                    Capsule().fill(.ultraThinMaterial)
                                }
                                .overlay {
                                    Capsule().strokeBorder(TL.Palette.emerald.opacity(0.4), lineWidth: 1)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            if !suggestedNames.isEmpty && name.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(suggestedNames.prefix(10), id: \.self) { s in
                            Button {
                                name = s
                            } label: {
                                Text(s)
                                    .font(TL.TypeScale.caption)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background {
                                        Capsule().fill(.ultraThinMaterial)
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(tint: TL.Palette.emerald, cornerRadius: TL.Radius.l, padding: TL.Space.m)
    }

    // MARK: - Category

    @ViewBuilder
    private var categoryPanel: some View {
        VStack(alignment: .leading, spacing: TL.Space.xs) {
            HStack {
                Text("CATEGORY")
                    .font(TL.TypeScale.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                if !category.isEmpty {
                    CategoryChip(name: category, compact: true)
                }
            }

            TextField("Category", text: $category)
                .autocorrectionDisabled()
                .padding(10)
                .background {
                    RoundedRectangle(cornerRadius: 12).fill(.ultraThinMaterial)
                }

            let allCats = mergedCategorySuggestions
            if !allCats.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 6)], spacing: 6) {
                    ForEach(allCats, id: \.self) { c in
                        Button {
                            category = c
                        } label: {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(TL.categoryColor(c).gradient)
                                    .frame(width: 10, height: 10)
                                Text(c)
                                    .font(TL.TypeScale.caption)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(.ultraThinMaterial)
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 10)
                                            .strokeBorder(
                                                category == c
                                                ? TL.categoryColor(c)
                                                : TL.categoryColor(c).opacity(0.25),
                                                lineWidth: category == c ? 1.5 : 1
                                            )
                                    }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(tint: tint, cornerRadius: TL.Radius.l, padding: TL.Space.m)
    }

    private var mergedCategorySuggestions: [String] {
        var arr = suggestedCategories
        for fallback in ["Coding", "Meeting", "Research", "Design", "Admin", "Break"] {
            if !arr.contains(fallback) { arr.append(fallback) }
        }
        return arr
    }

    // MARK: - Todo link

    @ViewBuilder
    private var todoPanel: some View {
        if !openTodos.isEmpty {
            VStack(alignment: .leading, spacing: TL.Space.xs) {
                Text("LINK TODO")
                    .font(TL.TypeScale.caption2)
                    .foregroundStyle(.secondary)

                Picker("Todo", selection: $selectedTodoId) {
                    Text("None").tag(nil as Int?)
                    ForEach(openTodos, id: \.localId) { todo in
                        Text(todo.text).tag(todo.serverId as Int?)
                    }
                }
                .pickerStyle(.menu)
                .padding(.horizontal, 10)
                .padding(.vertical, 2)
                .background {
                    RoundedRectangle(cornerRadius: 12).fill(.ultraThinMaterial)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(tint: TL.Palette.sky, cornerRadius: TL.Radius.l, padding: TL.Space.m)
        }
    }

    // MARK: - Data

    private func loadSuggestions() async {
        if bleManager.isConnected,
           let suggestions = try? await bleManager.getSuggestions() {
            suggestedNames = suggestions.names
            suggestedCategories = suggestions.categories
            recentTodos = suggestions.recent_todos ?? []
        }
    }

    private func startTimer() {
        if let running = timers.first(where: { $0.isRunning }) {
            running.pause()
        }
        let timer = ActiveTimerLocal(name: name, category: category, todoId: selectedTodoId)
        modelContext.insert(timer)
        try? modelContext.save()
        syncEngine.scheduleSyncAfterMutation()
        dismiss()
    }
}
