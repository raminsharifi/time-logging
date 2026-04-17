import SwiftUI

struct TodosView: View {
    @EnvironmentObject var api: APIClient
    @State private var todos: [TodoResponse] = []
    @State private var newText = ""

    var openTodos: [TodoResponse] { todos.filter { !$0.done } }
    var doneTodos: [TodoResponse] { todos.filter { $0.done } }

    var body: some View {
        VStack(alignment: .leading, spacing: TL.Space.m) {
            addBar
                .padding(.horizontal, TL.Space.m)
                .padding(.top, TL.Space.m)

            HStack(alignment: .top, spacing: TL.Space.m) {
                column(title: "OPEN", items: openTodos, tint: TL.Palette.sky)
                column(title: "DONE", items: doneTodos, tint: TL.Palette.emerald)
            }
            .padding(.horizontal, TL.Space.m)
            .padding(.bottom, TL.Space.m)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .task { await loadTodos() }
    }

    @ViewBuilder
    private var addBar: some View {
        HStack(spacing: TL.Space.s) {
            TextField("Add a todo…", text: $newText)
                .textFieldStyle(.plain)
                .padding(8)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .onSubmit { addTodo() }

            Button {
                addTodo()
            } label: {
                Label("Add", systemImage: "plus")
            }
            .disabled(newText.isEmpty)
            .buttonStyle(.borderedProminent)
            .tint(TL.Palette.sky)
            .controlSize(.large)
        }
    }

    @ViewBuilder
    private func column(title: String, items: [TodoResponse], tint: Color) -> some View {
        VStack(alignment: .leading, spacing: TL.Space.s) {
            HStack {
                Text(title)
                    .font(TL.TypeScale.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("\(items.count)")
                    .font(TL.TypeScale.caption2)
                    .foregroundStyle(tint)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(tint.opacity(0.18), in: Capsule())
                Spacer()
            }
            ScrollView {
                VStack(spacing: TL.Space.s) {
                    if items.isEmpty {
                        Text("Nothing here")
                            .font(TL.TypeScale.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, TL.Space.l)
                    } else {
                        ForEach(items) { t in
                            todoCard(t, tint: tint)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func todoCard(_ todo: TodoResponse, tint: Color) -> some View {
        HStack(alignment: .top, spacing: TL.Space.s) {
            Button {
                toggleDone(todo)
            } label: {
                Image(systemName: todo.done ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(todo.done ? TL.Palette.emerald : .secondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(todo.text)
                    .font(TL.TypeScale.body)
                    .strikethrough(todo.done)
                    .foregroundStyle(todo.done ? .secondary : .primary)
                    .lineLimit(3)
                if todo.total_secs > 0 {
                    Text(formatDuration(todo.total_secs))
                        .font(TL.TypeScale.caption2.monospacedDigit())
                        .foregroundStyle(tint)
                }
            }
            Spacer(minLength: 0)

            Button(role: .destructive) {
                Task { try? await api.deleteTodo(id: todo.id); await loadTodos() }
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(TL.Palette.ember.opacity(0.8))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(tint: tint, cornerRadius: TL.Radius.m, padding: TL.Space.s, elevation: 4)
    }

    private func addTodo() {
        guard !newText.isEmpty else { return }
        Task {
            _ = try? await api.addTodo(text: newText)
            newText = ""
            await loadTodos()
        }
    }

    private func toggleDone(_ todo: TodoResponse) {
        Task {
            _ = try? await api.editTodo(id: todo.id, request: EditTodoRequest(text: nil, done: !todo.done))
            await loadTodos()
        }
    }

    private func loadTodos() async {
        todos = (try? await api.getTodos()) ?? []
    }
}
