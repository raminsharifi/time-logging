import SwiftUI
import SwiftData
import WatchKit
import WidgetKit

struct TimerControlSheet: View {
    let syncEngine: SyncEngine

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<TodoItemLocal> { !$0.done })
    private var openTodos: [TodoItemLocal]

    @State private var name = ""
    @State private var category = ""
    @State private var selectedTodoId: UUID?
    @State private var suggestedNames: [String] = []
    @State private var suggestedCategories: [String] = []
    @State private var recentTodos: [APITodoResponse] = []
    @State private var step: Step = .name

    private enum Step {
        case name, category, confirm
    }

    var body: some View {
        Group {
            switch step {
            case .name:     namePickerView
            case .category: categoryPickerView
            case .confirm:  confirmView
            }
        }
        .task { await loadSuggestions() }
    }

    // MARK: - Step 1: Pick name

    @ViewBuilder
    private var namePickerView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TL.Space.s) {
                Text("WHAT")
                    .font(TL.TypeScale.caption2)
                    .foregroundStyle(.secondary)

                if !recentTodos.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Recent Todos")
                            .font(TL.TypeScale.caption2)
                            .foregroundStyle(.secondary)
                        ForEach(recentTodos.prefix(3), id: \.id) { todo in
                            Button {
                                WKInterfaceDevice.current().play(.click)
                                name = todo.text
                                selectedTodoId = nil  // server id set at start time
                                step = .category
                            } label: {
                                HStack {
                                    Image(systemName: "checklist")
                                        .font(.system(size: 10))
                                        .foregroundStyle(TL.Palette.emerald)
                                    Text(todo.text)
                                        .font(TL.TypeScale.caption)
                                        .lineLimit(1)
                                    Spacer()
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 4)
                                .padding(.horizontal, 8)
                                .background {
                                    RoundedRectangle(cornerRadius: 8).fill(.ultraThinMaterial)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.bottom, 4)
                }

                if !suggestedNames.isEmpty {
                    Text("Recent")
                        .font(TL.TypeScale.caption2)
                        .foregroundStyle(.secondary)
                }

                ForEach(suggestedNames, id: \.self) { n in
                    Button {
                        WKInterfaceDevice.current().play(.click)
                        name = n
                        step = .category
                    } label: {
                        HStack {
                            Text(n).font(TL.TypeScale.callout)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .background {
                            RoundedRectangle(cornerRadius: 10).fill(.ultraThinMaterial)
                        }
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    WKInterfaceDevice.current().play(.click)
                    name = ""
                    step = .category
                } label: {
                    Label("Custom…", systemImage: "keyboard")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass(tint: TL.Palette.mist))
            }
            .padding()
        }
    }

    // MARK: - Step 2: Pick category

    @ViewBuilder
    private var categoryPickerView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TL.Space.s) {
                if name.isEmpty {
                    TextField("Activity", text: $name)
                        .padding(8)
                        .background {
                            RoundedRectangle(cornerRadius: 10).fill(.ultraThinMaterial)
                        }
                }

                Text("CATEGORY")
                    .font(TL.TypeScale.caption2)
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                    ForEach(suggestedCategories, id: \.self) { c in
                        Button {
                            WKInterfaceDevice.current().play(.click)
                            category = c
                            step = .confirm
                        } label: {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(TL.categoryColor(c).gradient)
                                    .frame(width: 8, height: 8)
                                Text(c)
                                    .font(TL.TypeScale.caption)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                                    .truncationMode(.middle)
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 8)
                            .background {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(.ultraThinMaterial)
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 10)
                                            .strokeBorder(TL.categoryColor(c).opacity(0.4), lineWidth: 1)
                                    }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                Button {
                    WKInterfaceDevice.current().play(.click)
                    category = ""
                    step = .confirm
                } label: {
                    Label("Custom…", systemImage: "keyboard")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass(tint: TL.Palette.mist))
            }
            .padding()
        }
    }

    // MARK: - Step 3: Confirm & start

    @ViewBuilder
    private var confirmView: some View {
        let tint = TL.categoryColor(category)
        ScrollView {
            VStack(spacing: TL.Space.s) {
                if category.isEmpty {
                    TextField("Category", text: $category)
                        .padding(8)
                        .background {
                            RoundedRectangle(cornerRadius: 10).fill(.ultraThinMaterial)
                        }
                }

                VStack(spacing: 4) {
                    Text(name.isEmpty ? "Timer" : name)
                        .font(TL.TypeScale.headline)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                    CategoryChip(name: category.isEmpty ? "—" : category, compact: true)
                }
                .frame(maxWidth: .infinity)
                .glassCard(tint: tint, cornerRadius: TL.Radius.m, padding: TL.Space.s)

                if !openTodos.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("LINK TODO")
                            .font(TL.TypeScale.caption2)
                            .foregroundStyle(.secondary)
                        Picker("Todo", selection: $selectedTodoId) {
                            Text("None").tag(nil as UUID?)
                            ForEach(openTodos, id: \.localId) { todo in
                                Text(todo.text)
                                    .lineLimit(1)
                                    .tag(todo.localId as UUID?)
                            }
                        }
                        .labelsHidden()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button {
                    WKInterfaceDevice.current().play(.start)
                    startTimer()
                } label: {
                    Label("Start", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass(tint: tint, prominent: true))
                .disabled(category.isEmpty)

                Button {
                    step = .category
                } label: {
                    Label("Back", systemImage: "chevron.left")
                        .font(TL.TypeScale.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .padding()
        }
    }

    // MARK: - Data

    private func loadSuggestions() async {
        guard let suggestions = try? await syncEngine.apiClient.getSuggestions() else { return }
        suggestedNames = suggestions.names
        suggestedCategories = suggestions.categories
        recentTodos = suggestions.recent_todos ?? []
    }

    private func startTimer() {
        let linkedTodo = openTodos.first { $0.localId == selectedTodoId }
        let todoId = linkedTodo?.serverId
        let timerName = name.isEmpty ? (linkedTodo?.text ?? "Timer") : name
        let timerCategory = category.isEmpty ? "General" : category

        Task {
            if syncEngine.isOnline {
                _ = try? await syncEngine.apiClient.startTimer(
                    name: timerName,
                    category: timerCategory,
                    todoId: todoId
                )
                await syncEngine.syncIfReachable(modelContainer: modelContext.container)
            } else {
                let runningDescriptor = FetchDescriptor<ActiveTimerLocal>(
                    predicate: #Predicate { $0.state == "running" }
                )
                if let running = try? modelContext.fetch(runningDescriptor).first {
                    running.state = "paused"
                    running.breaks.append(.now())
                    running.lastModified = .now
                    running.needsSync = true
                }
                let timer = ActiveTimerLocal(
                    name: timerName,
                    category: timerCategory,
                    todoId: todoId
                )
                modelContext.insert(timer)
                try? modelContext.save()
                syncEngine.scheduleSyncAfterMutation()
            }
        }

        // Optimistic widget update
        let temp = ActiveTimerLocal(name: timerName, category: timerCategory, todoId: todoId)
        updateWidget(running: temp)
        dismiss()
    }
}
