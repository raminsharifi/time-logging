import SwiftUI

struct NewTimerSheet: View {
    @EnvironmentObject var api: APIClient
    @Environment(\.dismiss) private var dismiss

    let onDone: () async -> Void

    @State private var name = ""
    @State private var category = ""
    @State private var selectedTodoId: Int?
    @State private var suggestedNames: [String] = []
    @State private var suggestedCategories: [String] = []
    @State private var todos: [TodoResponse] = []
    @State private var calendarSuggestion: CalendarSuggestion?
    @State private var calendarAccessRequested = false

    private let categoryColumns = [GridItem(.adaptive(minimum: 70), spacing: 8)]

    var body: some View {
        VStack(alignment: .leading, spacing: TL.Space.l) {
            Text("New Timer")
                .font(TL.TypeScale.title2)

            calendarPanel

            // Name
            VStack(alignment: .leading, spacing: 6) {
                Text("ACTIVITY")
                    .font(TL.TypeScale.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField("What are you working on?", text: $name)
                    .textFieldStyle(.plain)
                    .padding(10)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                if !suggestedNames.isEmpty && name.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(suggestedNames.prefix(8), id: \.self) { s in
                                Button(s) { name = s }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                            }
                        }
                    }
                }
            }

            // Category
            VStack(alignment: .leading, spacing: 6) {
                Text("CATEGORY")
                    .font(TL.TypeScale.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField("Category", text: $category)
                    .textFieldStyle(.plain)
                    .padding(10)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                LazyVGrid(columns: categoryColumns, spacing: 8) {
                    ForEach(suggestedCategories.prefix(8), id: \.self) { s in
                        Button {
                            category = s
                        } label: {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(TL.categoryColor(s))
                                    .frame(width: 8, height: 8)
                                Text(s)
                                    .font(TL.TypeScale.caption)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                category == s
                                    ? AnyShapeStyle(TL.categoryColor(s).opacity(0.25))
                                    : AnyShapeStyle(.ultraThinMaterial),
                                in: Capsule()
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Todo link
            let openTodos = todos.filter { !$0.done }
            if !openTodos.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("LINK TO TODO")
                        .font(TL.TypeScale.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Picker("Todo", selection: $selectedTodoId) {
                        Text("None").tag(nil as Int?)
                        ForEach(openTodos) { todo in
                            Text(todo.text).tag(todo.id as Int?)
                        }
                    }
                    .labelsHidden()
                }
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button {
                    startTimer()
                } label: {
                    Label("Start", systemImage: "play.fill")
                        .frame(minWidth: 80)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.isEmpty || category.isEmpty)
                .buttonStyle(.borderedProminent)
                .tint(TL.Palette.emerald)
                .controlSize(.large)
            }
        }
        .padding(TL.Space.l)
        .frame(width: 460)
        .background(.ultraThinMaterial)
        .task {
            if let s = try? await api.getSuggestions() {
                suggestedNames = s.names
                suggestedCategories = s.categories
            }
            todos = (try? await api.getTodos()) ?? []
            calendarSuggestion = CalendarService.nextSuggestion()
        }
    }

    @ViewBuilder
    private var calendarPanel: some View {
        let status = CalendarService.authorization
        if let s = calendarSuggestion {
            Button {
                applyCalendarSuggestion(s)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "calendar")
                            .foregroundStyle(TL.Palette.iris)
                        Text("FROM CALENDAR · \(s.relativeLabel)")
                            .font(TL.TypeScale.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("Use")
                            .font(TL.TypeScale.caption.weight(.semibold))
                            .foregroundStyle(TL.Palette.iris)
                    }
                    Text(s.title)
                        .font(TL.TypeScale.body.weight(.medium))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if !s.calendarTitle.isEmpty {
                        Text(s.calendarTitle)
                            .font(TL.TypeScale.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
        } else if status == .notDetermined && !calendarAccessRequested {
            Button {
                Task {
                    calendarAccessRequested = true
                    _ = await CalendarService.requestAccess()
                    calendarSuggestion = CalendarService.nextSuggestion()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "calendar")
                    Text("Suggest timers from calendar")
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                }
                .padding(10)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private func applyCalendarSuggestion(_ s: CalendarSuggestion) {
        name = s.title
        let candidates: [(id: Int, text: String)] = todos
            .filter { !$0.done }
            .map { ($0.id, $0.text) }
        if let matchId = TodoMatcher.bestMatchId(for: s.title, in: candidates) {
            selectedTodoId = matchId
        }
    }

    private func startTimer() {
        Task {
            _ = try? await api.startTimer(name: name, category: category, todoId: selectedTodoId)
            await onDone()
            dismiss()
        }
    }
}
