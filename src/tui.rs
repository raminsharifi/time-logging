use std::io;
use std::time::Duration;

use chrono::{Local, TimeZone};
use crossterm::event::{self, Event, KeyCode, KeyEventKind, KeyModifiers};
use crossterm::terminal::{
    disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen,
};
use crossterm::execute;
use ratatui::prelude::*;
use ratatui::widgets::*;
use rusqlite::Connection;

use crate::state::*;

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

#[derive(PartialEq, Clone, Copy)]
enum Tab {
    Timers,
    Log,
    Todos,
}

#[derive(PartialEq)]
enum Mode {
    Normal,
    Input(InputTarget),
    Confirm(ConfirmAction),
    Pick(PickTarget),
}

#[derive(PartialEq, Clone)]
enum InputTarget {
    TimerName,
    TimerCategory,
    TodoAdd,
    TodoEdit(u32),
    LogEditName(u32),
    LogEditCategory(u32),
}

#[derive(PartialEq, Clone)]
enum ConfirmAction {
    StopTimer(u32),
    DeleteTimer(u32),
    DeleteLog(u32),
    DeleteTodo(u32),
    ToggleTodo(u32, bool), // (id, currently_done)
}

#[derive(PartialEq, Clone)]
enum PickTarget {
    LinkTodo, // picking a todo to link when starting a timer
}

struct App {
    tab: Tab,
    mode: Mode,
    // selections
    timer_sel: usize,
    log_sel: usize,
    todo_sel: usize,
    // input
    input_buf: String,
    // start-timer flow
    new_timer_name: String,
    new_timer_todo_id: Option<u32>,
    // pick list
    pick_items: Vec<(u32, String)>, // (id, label)
    pick_sel: usize,
    // flash message
    flash: Option<(String, std::time::Instant)>,
}

impl App {
    fn new() -> Self {
        Self {
            tab: Tab::Timers,
            mode: Mode::Normal,
            timer_sel: 0,
            log_sel: 0,
            todo_sel: 0,
            input_buf: String::new(),
            new_timer_name: String::new(),
            new_timer_todo_id: None,
            pick_items: Vec::new(),
            pick_sel: 0,
            flash: None,
        }
    }

    fn flash(&mut self, msg: impl Into<String>) {
        self.flash = Some((msg.into(), std::time::Instant::now()));
    }

    fn cur_sel(&self) -> usize {
        match self.tab {
            Tab::Timers => self.timer_sel,
            Tab::Log => self.log_sel,
            Tab::Todos => self.todo_sel,
        }
    }

    fn cur_sel_mut(&mut self) -> &mut usize {
        match self.tab {
            Tab::Timers => &mut self.timer_sel,
            Tab::Log => &mut self.log_sel,
            Tab::Todos => &mut self.todo_sel,
        }
    }
}

// ---------------------------------------------------------------------------
// Main loop
// ---------------------------------------------------------------------------

pub fn run(conn: &Connection) {
    enable_raw_mode().unwrap();
    let mut stdout = io::stdout();
    execute!(stdout, EnterAlternateScreen).unwrap();
    let backend = CrosstermBackend::new(stdout);
    let mut terminal = Terminal::new(backend).unwrap();

    let mut app = App::new();

    loop {
        terminal.draw(|f| ui(f, conn, &app)).unwrap();

        if event::poll(Duration::from_millis(250)).unwrap() {
            if let Event::Key(key) = event::read().unwrap() {
                if key.kind != KeyEventKind::Press {
                    continue;
                }
                if key.code == KeyCode::Char('c')
                    && key.modifiers.contains(KeyModifiers::CONTROL)
                {
                    break;
                }
                match &app.mode {
                    Mode::Normal => {
                        if handle_normal(conn, &mut app, key.code) {
                            break;
                        }
                    }
                    Mode::Input(_) => handle_input(conn, &mut app, key.code),
                    Mode::Confirm(_) => handle_confirm(conn, &mut app, key.code),
                    Mode::Pick(_) => handle_pick(conn, &mut app, key.code),
                }
            }
        }

        // expire flash after 3s
        if let Some((_, t)) = &app.flash {
            if t.elapsed() > Duration::from_secs(3) {
                app.flash = None;
            }
        }
    }

    disable_raw_mode().unwrap();
    execute!(terminal.backend_mut(), LeaveAlternateScreen).unwrap();
}

// ---------------------------------------------------------------------------
// Key handlers
// ---------------------------------------------------------------------------

/// Returns true if we should quit
fn handle_normal(conn: &Connection, app: &mut App, key: KeyCode) -> bool {
    match key {
        KeyCode::Char('q') | KeyCode::Esc => return true,

        // tab switching
        KeyCode::Char('1') => app.tab = Tab::Timers,
        KeyCode::Char('2') => app.tab = Tab::Log,
        KeyCode::Char('3') => app.tab = Tab::Todos,
        KeyCode::Tab => {
            app.tab = match app.tab {
                Tab::Timers => Tab::Log,
                Tab::Log => Tab::Todos,
                Tab::Todos => Tab::Timers,
            }
        }
        KeyCode::BackTab => {
            app.tab = match app.tab {
                Tab::Timers => Tab::Todos,
                Tab::Log => Tab::Timers,
                Tab::Todos => Tab::Log,
            }
        }

        // navigation
        KeyCode::Down | KeyCode::Char('j') => {
            *app.cur_sel_mut() = app.cur_sel().saturating_add(1);
        }
        KeyCode::Up | KeyCode::Char('k') => {
            *app.cur_sel_mut() = app.cur_sel().saturating_sub(1);
        }

        // ---------- Timer actions ----------
        // s = start new timer
        KeyCode::Char('s') if app.tab == Tab::Timers => {
            // first offer todo linking
            let open_todos: Vec<_> = list_todos(conn).into_iter().filter(|t| !t.done).collect();
            if !open_todos.is_empty() {
                app.pick_items = open_todos
                    .iter()
                    .map(|t| (t.id, format!("#{} {}", t.id, t.text)))
                    .collect();
                app.pick_items.push((0, "None".into()));
                app.pick_sel = app.pick_items.len() - 1;
                app.new_timer_todo_id = None;
                app.new_timer_name.clear();
                app.mode = Mode::Pick(PickTarget::LinkTodo);
            } else {
                app.new_timer_todo_id = None;
                app.new_timer_name.clear();
                app.input_buf.clear();
                app.mode = Mode::Input(InputTarget::TimerName);
            }
        }
        // p = pause/resume selected timer
        KeyCode::Char('p') if app.tab == Tab::Timers => {
            let all = get_all_active(conn);
            if let Some(timer) = all.get(app.timer_sel) {
                let id = timer.id.unwrap();
                if timer.state == "running" {
                    action_pause(conn, id);
                    app.flash("Paused timer");
                } else if timer.state == "paused" {
                    if get_running(conn).is_some() {
                        app.flash("Another timer is running — stop or pause it first");
                    } else {
                        action_resume(conn, id);
                        app.flash("Resumed timer");
                    }
                }
            }
        }
        // x = stop selected timer (confirm)
        KeyCode::Char('x') if app.tab == Tab::Timers => {
            let all = get_all_active(conn);
            if let Some(timer) = all.get(app.timer_sel) {
                let id = timer.id.unwrap();
                app.mode = Mode::Confirm(ConfirmAction::StopTimer(id));
            }
        }
        // w = switch — pause running, resume selected paused
        KeyCode::Char('w') if app.tab == Tab::Timers => {
            let all = get_all_active(conn);
            if let Some(timer) = all.get(app.timer_sel) {
                if timer.state == "paused" {
                    let id = timer.id.unwrap();
                    // pause current running
                    if let Some(running) = get_running(conn) {
                        action_pause(conn, running.id.unwrap());
                    }
                    action_resume(conn, id);
                    app.flash("Switched timer");
                }
            }
        }
        // r = restart (start from last entry)
        KeyCode::Char('r') if app.tab == Tab::Timers => {
            if let Some(last) = get_last_entry(conn) {
                // pause current if running
                if let Some(running) = get_running(conn) {
                    action_pause(conn, running.id.unwrap());
                }
                let now = Local::now();
                let timer = ActiveTimer {
                    id: None,
                    name: last.name.clone(),
                    category: last.category.clone(),
                    started_at: now.timestamp(),
                    state: "running".into(),
                    breaks: vec![],
                    todo_id: last.todo_id,
                    last_modified: 0,
                };
                insert_active(conn, &timer);
                app.flash(format!("Restarted \"{}\"", last.name));
            } else {
                app.flash("No past entries to restart from");
            }
        }
        // d = delete selected timer (discard without logging)
        KeyCode::Char('d') if app.tab == Tab::Timers => {
            let all = get_all_active(conn);
            if let Some(timer) = all.get(app.timer_sel) {
                app.mode = Mode::Confirm(ConfirmAction::DeleteTimer(timer.id.unwrap()));
            }
        }

        // ---------- Log actions ----------
        // d = delete log entry
        KeyCode::Char('d') if app.tab == Tab::Log => {
            let entries = query_entries(conn, None);
            if let Some(entry) = entries.get(app.log_sel) {
                app.mode = Mode::Confirm(ConfirmAction::DeleteLog(entry.id));
            }
        }
        // e = edit log entry name
        KeyCode::Char('e') if app.tab == Tab::Log => {
            let entries = query_entries(conn, None);
            if let Some(entry) = entries.get(app.log_sel) {
                app.input_buf = entry.name.clone();
                app.mode = Mode::Input(InputTarget::LogEditName(entry.id));
            }
        }
        // c = edit log entry category
        KeyCode::Char('c') if app.tab == Tab::Log => {
            let entries = query_entries(conn, None);
            if let Some(entry) = entries.get(app.log_sel) {
                app.input_buf = entry.category.clone();
                app.mode = Mode::Input(InputTarget::LogEditCategory(entry.id));
            }
        }

        // ---------- Todo actions ----------
        // a = add todo
        KeyCode::Char('a') if app.tab == Tab::Todos => {
            app.input_buf.clear();
            app.mode = Mode::Input(InputTarget::TodoAdd);
        }
        // Enter / space = toggle done
        KeyCode::Enter | KeyCode::Char(' ') if app.tab == Tab::Todos => {
            let todos = list_todos(conn);
            if let Some(todo) = todos.get(app.todo_sel) {
                app.mode = Mode::Confirm(ConfirmAction::ToggleTodo(todo.id, todo.done));
            }
        }
        // e = edit todo text
        KeyCode::Char('e') if app.tab == Tab::Todos => {
            let todos = list_todos(conn);
            if let Some(todo) = todos.get(app.todo_sel) {
                app.input_buf = todo.text.clone();
                app.mode = Mode::Input(InputTarget::TodoEdit(todo.id));
            }
        }
        // d = delete todo
        KeyCode::Char('d') if app.tab == Tab::Todos => {
            let todos = list_todos(conn);
            if let Some(todo) = todos.get(app.todo_sel) {
                app.mode = Mode::Confirm(ConfirmAction::DeleteTodo(todo.id));
            }
        }

        _ => {}
    }
    false
}

fn handle_input(conn: &Connection, app: &mut App, key: KeyCode) {
    match key {
        KeyCode::Esc => {
            app.mode = Mode::Normal;
        }
        KeyCode::Enter => {
            let target = match &app.mode {
                Mode::Input(t) => t.clone(),
                _ => return,
            };
            let text = app.input_buf.trim().to_string();
            match target {
                InputTarget::TimerName => {
                    if text.is_empty() && app.new_timer_todo_id.is_none() {
                        app.flash("Name cannot be empty");
                        return;
                    }
                    app.new_timer_name = text;
                    app.input_buf.clear();
                    app.mode = Mode::Input(InputTarget::TimerCategory);
                }
                InputTarget::TimerCategory => {
                    if text.is_empty() {
                        app.flash("Category cannot be empty");
                        return;
                    }
                    // pause current if running
                    if let Some(running) = get_running(conn) {
                        action_pause(conn, running.id.unwrap());
                    }
                    let name = if app.new_timer_name.is_empty() {
                        // linked todo — get text
                        if let Some(tid) = app.new_timer_todo_id {
                            get_todo_by_id(conn, tid)
                                .map(|t| t.text)
                                .unwrap_or_else(|| "Timer".into())
                        } else {
                            "Timer".into()
                        }
                    } else {
                        app.new_timer_name.clone()
                    };
                    let now = Local::now();
                    let timer = ActiveTimer {
                        id: None,
                        name: name.clone(),
                        category: text.clone(),
                        started_at: now.timestamp(),
                        state: "running".into(),
                        breaks: vec![],
                        todo_id: app.new_timer_todo_id,
                        last_modified: 0,
                    };
                    insert_active(conn, &timer);
                    app.flash(format!("Started \"{name}\" [{text}]"));
                    app.mode = Mode::Normal;
                }
                InputTarget::TodoAdd => {
                    if text.is_empty() {
                        app.flash("Todo text cannot be empty");
                        return;
                    }
                    let now_ts = Local::now().timestamp();
                    let id = add_todo(conn, &text, now_ts);
                    app.flash(format!("Added todo #{id}"));
                    app.mode = Mode::Normal;
                }
                InputTarget::TodoEdit(id) => {
                    if text.is_empty() {
                        app.flash("Todo text cannot be empty");
                        return;
                    }
                    edit_todo(conn, id, &text);
                    app.flash(format!("Edited todo #{id}"));
                    app.mode = Mode::Normal;
                }
                InputTarget::LogEditName(id) => {
                    if !text.is_empty() {
                        if let Some(mut entry) = get_entry_by_id(conn, id) {
                            entry.name = text;
                            update_entry(conn, &entry);
                            app.flash(format!("Updated entry #{id} name"));
                        }
                    }
                    app.mode = Mode::Normal;
                }
                InputTarget::LogEditCategory(id) => {
                    if !text.is_empty() {
                        if let Some(mut entry) = get_entry_by_id(conn, id) {
                            entry.category = text;
                            update_entry(conn, &entry);
                            app.flash(format!("Updated entry #{id} category"));
                        }
                    }
                    app.mode = Mode::Normal;
                }
            }
        }
        KeyCode::Backspace => {
            app.input_buf.pop();
        }
        KeyCode::Char(c) => {
            app.input_buf.push(c);
        }
        _ => {}
    }
}

fn handle_confirm(conn: &Connection, app: &mut App, key: KeyCode) {
    match key {
        KeyCode::Char('y') | KeyCode::Enter => {
            let action = match &app.mode {
                Mode::Confirm(a) => a.clone(),
                _ => return,
            };
            match action {
                ConfirmAction::StopTimer(id) => {
                    action_stop(conn, id);
                    app.flash("Stopped timer and saved to log");
                }
                ConfirmAction::DeleteTimer(id) => {
                    clear_active(conn, id);
                    app.flash("Discarded timer");
                }
                ConfirmAction::DeleteLog(id) => {
                    delete_entry(conn, id);
                    app.flash(format!("Deleted log entry #{id}"));
                    let entries = query_entries(conn, None);
                    if app.log_sel >= entries.len() && !entries.is_empty() {
                        app.log_sel = entries.len() - 1;
                    }
                }
                ConfirmAction::DeleteTodo(id) => {
                    remove_todo(conn, id);
                    app.flash(format!("Removed todo #{id}"));
                    let todos = list_todos(conn);
                    if app.todo_sel >= todos.len() && !todos.is_empty() {
                        app.todo_sel = todos.len() - 1;
                    }
                }
                ConfirmAction::ToggleTodo(id, was_done) => {
                    if was_done {
                        unmark_todo_done(conn, id);
                        app.flash(format!("Todo #{id} marked as not done"));
                    } else {
                        mark_todo_done(conn, id);
                        app.flash(format!("Todo #{id} marked as done"));
                    }
                }
            }
            app.mode = Mode::Normal;
        }
        KeyCode::Char('n') | KeyCode::Esc => {
            app.mode = Mode::Normal;
        }
        _ => {}
    }
}

fn handle_pick(conn: &Connection, app: &mut App, key: KeyCode) {
    match key {
        KeyCode::Esc => {
            app.mode = Mode::Normal;
        }
        KeyCode::Down | KeyCode::Char('j') => {
            if app.pick_sel + 1 < app.pick_items.len() {
                app.pick_sel += 1;
            }
        }
        KeyCode::Up | KeyCode::Char('k') => {
            app.pick_sel = app.pick_sel.saturating_sub(1);
        }
        KeyCode::Enter => {
            let target = match &app.mode {
                Mode::Pick(t) => t.clone(),
                _ => return,
            };
            match target {
                PickTarget::LinkTodo => {
                    let (id, _) = &app.pick_items[app.pick_sel];
                    if *id == 0 {
                        // "None" selected
                        app.new_timer_todo_id = None;
                        app.new_timer_name.clear();
                    } else {
                        app.new_timer_todo_id = Some(*id);
                        // use todo text as default name
                        if let Some(todo) = get_todo_by_id(conn, *id) {
                            app.new_timer_name = todo.text;
                        }
                    }
                    app.input_buf = app.new_timer_name.clone();
                    app.mode = Mode::Input(InputTarget::TimerName);
                }
            }
        }
        _ => {}
    }
}

// ---------------------------------------------------------------------------
// Timer mutation helpers
// ---------------------------------------------------------------------------

fn action_pause(conn: &Connection, id: u32) {
    let mut timer = match get_active_by_id(conn, id) {
        Some(t) => t,
        None => return,
    };
    let now_ts = Local::now().timestamp();
    timer.state = "paused".into();
    timer.breaks.push(proto::Break {
        start_ts: now_ts,
        end_ts: 0,
    });
    update_active(conn, &timer);
}

fn action_resume(conn: &Connection, id: u32) {
    let mut timer = match get_active_by_id(conn, id) {
        Some(t) => t,
        None => return,
    };
    let now_ts = Local::now().timestamp();
    timer.state = "running".into();
    if let Some(last) = timer.breaks.last_mut() {
        if last.end_ts == 0 {
            last.end_ts = now_ts;
        }
    }
    update_active(conn, &timer);
}

fn action_stop(conn: &Connection, id: u32) {
    let timer = match get_active_by_id(conn, id) {
        Some(t) => t,
        None => return,
    };
    let now_ts = Local::now().timestamp();
    let elapsed = now_ts - timer.started_at;
    let break_secs = total_break_secs(&timer.breaks, now_ts);
    let active_secs = (elapsed - break_secs).max(0);

    let entry = TimeEntry {
        id: 0,
        name: timer.name,
        category: timer.category,
        started_at: timer.started_at,
        ended_at: now_ts,
        active_secs,
        breaks: timer.breaks,
        todo_id: timer.todo_id,
        last_modified: 0,
    };
    insert_entry(conn, &entry);
    clear_active(conn, id);
}

// ---------------------------------------------------------------------------
// UI rendering
// ---------------------------------------------------------------------------

fn ui(f: &mut Frame, conn: &Connection, app: &App) {
    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(3), // tabs
            Constraint::Min(0),   // content
            Constraint::Length(1), // help / flash
        ])
        .split(f.area());

    // Tab bar
    let titles = vec![
        Line::from(" 1 Timers "),
        Line::from(" 2 Log "),
        Line::from(" 3 Todos "),
    ];
    let tab_idx = match app.tab {
        Tab::Timers => 0,
        Tab::Log => 1,
        Tab::Todos => 2,
    };
    let tabs_widget = Tabs::new(titles)
        .block(Block::default().borders(Borders::ALL).title(" tl "))
        .select(tab_idx)
        .highlight_style(
            Style::default()
                .fg(Color::Cyan)
                .add_modifier(Modifier::BOLD),
        );
    f.render_widget(tabs_widget, chunks[0]);

    // Content
    match app.tab {
        Tab::Timers => render_timers(f, conn, chunks[1], app.timer_sel),
        Tab::Log => render_log(f, conn, chunks[1], app.log_sel),
        Tab::Todos => render_todos(f, conn, chunks[1], app.todo_sel),
    }

    // Help bar / flash
    let help_line = if let Some((msg, _)) = &app.flash {
        Line::from(vec![Span::styled(
            format!(" {msg}"),
            Style::default()
                .fg(Color::Green)
                .add_modifier(Modifier::BOLD),
        )])
    } else {
        match app.tab {
            Tab::Timers => Line::from(vec![
                Span::styled(" s", Style::default().fg(Color::Yellow)),
                Span::raw(" start  "),
                Span::styled("x", Style::default().fg(Color::Yellow)),
                Span::raw(" stop  "),
                Span::styled("p", Style::default().fg(Color::Yellow)),
                Span::raw(" pause/resume  "),
                Span::styled("w", Style::default().fg(Color::Yellow)),
                Span::raw(" switch  "),
                Span::styled("r", Style::default().fg(Color::Yellow)),
                Span::raw(" restart  "),
                Span::styled("d", Style::default().fg(Color::Yellow)),
                Span::raw(" discard  "),
                Span::styled("q", Style::default().fg(Color::Yellow)),
                Span::raw(" quit"),
            ]),
            Tab::Log => Line::from(vec![
                Span::styled(" e", Style::default().fg(Color::Yellow)),
                Span::raw(" edit name  "),
                Span::styled("c", Style::default().fg(Color::Yellow)),
                Span::raw(" edit category  "),
                Span::styled("d", Style::default().fg(Color::Yellow)),
                Span::raw(" delete  "),
                Span::styled("q", Style::default().fg(Color::Yellow)),
                Span::raw(" quit"),
            ]),
            Tab::Todos => Line::from(vec![
                Span::styled(" a", Style::default().fg(Color::Yellow)),
                Span::raw(" add  "),
                Span::styled("Enter", Style::default().fg(Color::Yellow)),
                Span::raw(" toggle done  "),
                Span::styled("e", Style::default().fg(Color::Yellow)),
                Span::raw(" edit  "),
                Span::styled("d", Style::default().fg(Color::Yellow)),
                Span::raw(" delete  "),
                Span::styled("q", Style::default().fg(Color::Yellow)),
                Span::raw(" quit"),
            ]),
        }
    };
    f.render_widget(
        Paragraph::new(help_line).style(Style::default().fg(Color::DarkGray)),
        chunks[2],
    );

    // Overlays
    match &app.mode {
        Mode::Input(target) => render_input_popup(f, target, &app.input_buf),
        Mode::Confirm(action) => render_confirm_popup(f, action),
        Mode::Pick(_) => render_pick_popup(f, &app.pick_items, app.pick_sel),
        Mode::Normal => {}
    }
}

// ---------------------------------------------------------------------------
// Tab content renderers
// ---------------------------------------------------------------------------

fn render_timers(f: &mut Frame, conn: &Connection, area: Rect, sel: usize) {
    let all = get_all_active(conn);
    let now_ts = Local::now().timestamp();

    if all.is_empty() {
        let msg = Paragraph::new("\n  No active timers. Press 's' to start one.")
            .style(Style::default().fg(Color::DarkGray))
            .block(
                Block::default()
                    .borders(Borders::ALL)
                    .title(" Active Timers "),
            );
        f.render_widget(msg, area);
        return;
    }

    let mut rows: Vec<Row> = Vec::new();

    for (i, timer) in all.iter().enumerate() {
        let elapsed = now_ts - timer.started_at;
        let break_secs = total_break_secs(&timer.breaks, now_ts);
        let active_secs = (elapsed - break_secs).max(0);
        let started = Local
            .timestamp_opt(timer.started_at, 0)
            .single()
            .unwrap();

        let (state_str, state_color) = if timer.state == "running" {
            ("▶ RUNNING", Color::Green)
        } else {
            ("⏸ PAUSED", Color::Yellow)
        };

        let todo_str = if let Some(tid) = timer.todo_id {
            let todos = list_todos(conn);
            todos
                .iter()
                .find(|t| t.id == tid)
                .map(|t| format!("→ #{} {}", tid, t.text))
                .unwrap_or_else(|| format!("→ #{tid}"))
        } else {
            String::new()
        };

        let time_color = if timer.state == "running" {
            Color::Cyan
        } else {
            Color::DarkGray
        };

        let row_style = if i == sel {
            Style::default().bg(Color::DarkGray).fg(Color::White)
        } else {
            Style::default()
        };

        rows.push(
            Row::new(vec![
                Cell::from(format!("#{}", timer.id.unwrap()))
                    .style(Style::default().fg(Color::DarkGray)),
                Cell::from(timer.name.clone())
                    .style(Style::default().fg(Color::White).add_modifier(Modifier::BOLD)),
                Cell::from(timer.category.clone()).style(Style::default().fg(Color::Blue)),
                Cell::from(state_str)
                    .style(Style::default().fg(state_color).add_modifier(Modifier::BOLD)),
                Cell::from(format_duration(active_secs))
                    .style(Style::default().fg(time_color).add_modifier(Modifier::BOLD)),
                Cell::from(format_duration(break_secs))
                    .style(Style::default().fg(Color::Yellow)),
                Cell::from(started.format("%H:%M:%S").to_string())
                    .style(Style::default().fg(Color::DarkGray)),
                Cell::from(todo_str).style(Style::default().fg(Color::Magenta)),
            ])
            .style(row_style),
        );
    }

    let widths = [
        Constraint::Length(5),  // id
        Constraint::Min(12),    // name
        Constraint::Length(12), // category
        Constraint::Length(11), // state
        Constraint::Length(12), // active
        Constraint::Length(10), // breaks
        Constraint::Length(9),  // started
        Constraint::Min(10),    // todo
    ];

    let header_style = Style::default()
        .fg(Color::DarkGray)
        .add_modifier(Modifier::BOLD);
    let table = Table::new(rows, widths)
        .header(
            Row::new(vec![
                "ID", "Name", "Category", "State", "Active", "Breaks", "Started", "Todo",
            ])
            .style(header_style)
            .bottom_margin(1),
        )
        .block(
            Block::default()
                .borders(Borders::ALL)
                .title(format!(" Active Timers ({}) ", all.len())),
        )
        .row_highlight_style(Style::default().bg(Color::DarkGray));

    let mut state = TableState::default();
    if !all.is_empty() {
        state.select(Some(sel.min(all.len() - 1)));
    }
    f.render_stateful_widget(table, area, &mut state);
}

fn render_log(f: &mut Frame, conn: &Connection, area: Rect, sel: usize) {
    let entries = query_entries(conn, None);
    let header_style = Style::default()
        .fg(Color::DarkGray)
        .add_modifier(Modifier::BOLD);
    let mut rows: Vec<Row> = Vec::new();
    let mut total_active: i64 = 0;
    let mut total_breaks: i64 = 0;

    for e in &entries {
        let break_secs = total_break_secs(&e.breaks, e.ended_at);
        total_active += e.active_secs;
        total_breaks += break_secs;
        let date = Local.timestamp_opt(e.started_at, 0).single().unwrap();
        let todo_col = match e.todo_id {
            Some(tid) => format!("#{tid}"),
            None => String::new(),
        };

        rows.push(Row::new(vec![
            Cell::from(format!("{}", e.id)).style(Style::default().fg(Color::DarkGray)),
            Cell::from(e.name.clone()).style(Style::default().fg(Color::White)),
            Cell::from(e.category.clone()).style(Style::default().fg(Color::Blue)),
            Cell::from(date.format("%Y-%m-%d").to_string()),
            Cell::from(format_duration(e.active_secs)).style(Style::default().fg(Color::Cyan)),
            Cell::from(format_duration(break_secs)).style(Style::default().fg(Color::Yellow)),
            Cell::from(todo_col).style(Style::default().fg(Color::Magenta)),
        ]));
    }

    // Total row
    rows.push(Row::new(vec![
        Cell::from(""),
        Cell::from("TOTAL").style(Style::default().add_modifier(Modifier::BOLD)),
        Cell::from(""),
        Cell::from(""),
        Cell::from(format_duration(total_active))
            .style(Style::default().fg(Color::Cyan).add_modifier(Modifier::BOLD)),
        Cell::from(format_duration(total_breaks)).style(
            Style::default()
                .fg(Color::Yellow)
                .add_modifier(Modifier::BOLD),
        ),
        Cell::from(""),
    ]));

    let widths = [
        Constraint::Length(5),
        Constraint::Min(15),
        Constraint::Length(12),
        Constraint::Length(11),
        Constraint::Length(12),
        Constraint::Length(12),
        Constraint::Length(6),
    ];

    let table = Table::new(rows, widths)
        .header(
            Row::new(vec![
                "ID", "Name", "Category", "Date", "Active", "Breaks", "Todo",
            ])
            .style(header_style)
            .bottom_margin(1),
        )
        .block(
            Block::default()
                .borders(Borders::ALL)
                .title(format!(" Log ({} entries) ", entries.len())),
        )
        .row_highlight_style(Style::default().bg(Color::DarkGray));

    let mut state = TableState::default();
    let max = entries.len() + 1; // +1 for total row
    if max > 0 {
        state.select(Some(sel.min(max - 1)));
    }
    f.render_stateful_widget(table, area, &mut state);
}

fn render_todos(f: &mut Frame, conn: &Connection, area: Rect, sel: usize) {
    let todos = list_todos(conn);
    let header_style = Style::default()
        .fg(Color::DarkGray)
        .add_modifier(Modifier::BOLD);
    let mut rows: Vec<Row> = Vec::new();

    for item in &todos {
        let (check, style) = if item.done {
            ("✓", Style::default().fg(Color::Green))
        } else {
            (" ", Style::default().fg(Color::White))
        };

        let date = Local
            .timestamp_opt(item.created_at, 0)
            .single()
            .unwrap();
        let entry_secs = get_todo_total_secs(conn, item.id);
        let active_secs = get_active_todo_secs(conn, item.id);
        let total_secs = entry_secs + active_secs;
        let time_str = if total_secs > 0 {
            format_duration(total_secs)
        } else {
            String::new()
        };

        rows.push(Row::new(vec![
            Cell::from(format!("[{}]", check)).style(style),
            Cell::from(format!("#{}", item.id)).style(Style::default().fg(Color::DarkGray)),
            Cell::from(item.text.clone()).style(style),
            Cell::from(date.format("%Y-%m-%d").to_string())
                .style(Style::default().fg(Color::DarkGray)),
            Cell::from(time_str).style(Style::default().fg(Color::Cyan)),
        ]));
    }

    let done = todos.iter().filter(|t| t.done).count();
    let total = todos.len();

    let widths = [
        Constraint::Length(4),
        Constraint::Length(6),
        Constraint::Min(15),
        Constraint::Length(11),
        Constraint::Length(12),
    ];

    let table = Table::new(rows, widths)
        .header(
            Row::new(vec!["", "ID", "Text", "Created", "Time"])
                .style(header_style)
                .bottom_margin(1),
        )
        .block(
            Block::default()
                .borders(Borders::ALL)
                .title(format!(" Todos ({done}/{total} done) ")),
        )
        .row_highlight_style(Style::default().bg(Color::DarkGray));

    let mut state = TableState::default();
    if total > 0 {
        state.select(Some(sel.min(total - 1)));
    }
    f.render_stateful_widget(table, area, &mut state);
}

// ---------------------------------------------------------------------------
// Popups
// ---------------------------------------------------------------------------

fn popup_area(f: &Frame, width: u16, height: u16) -> Rect {
    let area = f.area();
    let x = area.x + (area.width.saturating_sub(width)) / 2;
    let y = area.y + (area.height.saturating_sub(height)) / 2;
    Rect::new(x, y, width.min(area.width), height.min(area.height))
}

fn render_input_popup(f: &mut Frame, target: &InputTarget, buf: &str) {
    let title = match target {
        InputTarget::TimerName => " Activity Name (Enter to confirm, Esc to cancel) ",
        InputTarget::TimerCategory => " Category (Enter to confirm, Esc to cancel) ",
        InputTarget::TodoAdd => " New Todo (Enter to confirm, Esc to cancel) ",
        InputTarget::TodoEdit(_) => " Edit Todo (Enter to confirm, Esc to cancel) ",
        InputTarget::LogEditName(_) => " Edit Name (Enter to confirm, Esc to cancel) ",
        InputTarget::LogEditCategory(_) => " Edit Category (Enter to confirm, Esc to cancel) ",
    };

    let area = popup_area(f, 50, 3);
    f.render_widget(Clear, area);
    let block = Block::default()
        .borders(Borders::ALL)
        .border_style(Style::default().fg(Color::Cyan))
        .title(title);
    let input = Paragraph::new(format!("{buf}▌"))
        .style(Style::default().fg(Color::White))
        .block(block);
    f.render_widget(input, area);
}

fn render_confirm_popup(f: &mut Frame, action: &ConfirmAction) {
    let msg = match action {
        ConfirmAction::StopTimer(id) => format!("Stop timer #{id} and save to log?"),
        ConfirmAction::DeleteTimer(id) => format!("Discard timer #{id}? (won't save to log)"),
        ConfirmAction::DeleteLog(id) => format!("Delete log entry #{id}?"),
        ConfirmAction::DeleteTodo(id) => format!("Delete todo #{id}?"),
        ConfirmAction::ToggleTodo(id, done) => {
            if *done {
                format!("Mark todo #{id} as not done?")
            } else {
                format!("Mark todo #{id} as done?")
            }
        }
    };

    let area = popup_area(f, 50, 3);
    f.render_widget(Clear, area);
    let block = Block::default()
        .borders(Borders::ALL)
        .border_style(Style::default().fg(Color::Yellow))
        .title(" Confirm (y/n) ");
    let text = Paragraph::new(format!(" {msg}"))
        .style(Style::default().fg(Color::White))
        .block(block);
    f.render_widget(text, area);
}

fn render_pick_popup(f: &mut Frame, items: &[(u32, String)], sel: usize) {
    let height = (items.len() as u16 + 2).min(15);
    let area = popup_area(f, 50, height);
    f.render_widget(Clear, area);

    let list_items: Vec<ListItem> = items
        .iter()
        .enumerate()
        .map(|(i, (_, label))| {
            let style = if i == sel {
                Style::default()
                    .fg(Color::Cyan)
                    .add_modifier(Modifier::BOLD)
            } else {
                Style::default().fg(Color::White)
            };
            let prefix = if i == sel { "▸ " } else { "  " };
            ListItem::new(format!("{prefix}{label}")).style(style)
        })
        .collect();

    let list = List::new(list_items).block(
        Block::default()
            .borders(Borders::ALL)
            .border_style(Style::default().fg(Color::Cyan))
            .title(" Link to todo? (Enter to select, Esc to cancel) "),
    );
    f.render_widget(list, area);
}
