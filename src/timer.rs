use chrono::{Local, TimeZone};
use dialoguer::{Confirm, Input, Select};
use rusqlite::Connection;

use crate::state::*;

pub fn start(conn: &Connection) {
    if let Some(running) = get_running(conn) {
        let now_ts = Local::now().timestamp();
        let elapsed = now_ts - running.started_at;
        let break_secs = total_break_secs(&running.breaks, now_ts);
        let active_secs = (elapsed - break_secs).max(0);

        println!(
            "Running: \"{}\" [{}] — active: {}",
            running.name,
            running.category,
            format_duration(active_secs),
        );

        let confirm = Confirm::new()
            .with_prompt("Pause current timer and start a new one?")
            .default(false)
            .interact()
            .unwrap();

        if !confirm {
            return;
        }

        // Pause the running timer
        let mut paused = running;
        paused.state = "paused".into();
        paused.breaks.push(proto::Break {
            start_ts: now_ts,
            end_ts: 0,
        });
        update_active(conn, &paused);

        println!("Paused \"{}\".", paused.name);
    }

    // Offer to link a todo first — if linked, use the todo text as the name
    let mut todo_id: Option<u32> = None;
    let mut name = String::new();
    let open_todos: Vec<_> = list_todos(conn).into_iter().filter(|t| !t.done).collect();
    if !open_todos.is_empty() {
        let mut items: Vec<String> = open_todos
            .iter()
            .map(|t| format!("#{} {}", t.id, t.text))
            .collect();
        items.push("None".into());

        let selection = Select::new()
            .with_prompt("Link to a todo?")
            .items(&items)
            .default(items.len() - 1)
            .interact()
            .unwrap();

        if selection < open_todos.len() {
            todo_id = Some(open_todos[selection].id);
            name = open_todos[selection].text.clone();
        }
    }

    if name.is_empty() {
        name = Input::new()
            .with_prompt("Activity name")
            .interact_text()
            .unwrap();
    }

    let category: String = Input::new()
        .with_prompt("Category")
        .interact_text()
        .unwrap();

    let now = Local::now();
    let timer = ActiveTimer {
        id: None,
        name: name.clone(),
        category: category.clone(),
        started_at: now.timestamp(),
        state: "running".into(),
        breaks: vec![],
        todo_id,
    };
    insert_active(conn, &timer);

    println!("Started \"{name}\" [{category}] at {}", now.format("%H:%M:%S"));
}

pub fn stop(conn: &Connection) {
    let timer = match get_running(conn) {
        Some(t) => t,
        None => {
            eprintln!("No running timer.");
            std::process::exit(1);
        }
    };

    let now_ts = Local::now().timestamp();
    let timer_id = timer.id.unwrap();

    let breaks = timer.breaks;
    let elapsed = now_ts - timer.started_at;
    let break_secs = total_break_secs(&breaks, now_ts);
    let active_secs = (elapsed - break_secs).max(0);

    let entry = TimeEntry {
        id: 0,
        name: timer.name.clone(),
        category: timer.category.clone(),
        started_at: timer.started_at,
        ended_at: now_ts,
        active_secs,
        breaks,
        todo_id: timer.todo_id,
    };

    insert_entry(conn, &entry);
    clear_active(conn, timer_id);

    println!(
        "Stopped \"{}\" [{}] — active: {}, breaks: {}",
        timer.name,
        timer.category,
        format_duration(active_secs),
        format_duration(break_secs),
    );

    if let Some(tid) = timer.todo_id {
        let confirm = Confirm::new()
            .with_prompt(format!("Mark todo #{tid} as done?"))
            .default(false)
            .interact()
            .unwrap();
        if confirm {
            mark_todo_done(conn, tid);
            println!("Marked todo #{tid} as done.");
        }
    }
}

pub fn pause(conn: &Connection) {
    let mut timer = match get_running(conn) {
        Some(t) => t,
        None => {
            eprintln!("No running timer.");
            std::process::exit(1);
        }
    };

    let now_ts = Local::now().timestamp();
    timer.state = "paused".into();
    timer.breaks.push(proto::Break {
        start_ts: now_ts,
        end_ts: 0,
    });
    update_active(conn, &timer);

    let now = Local::now();
    println!("Paused \"{}\" at {}", timer.name, now.format("%H:%M:%S"));
}

pub fn resume(conn: &Connection) {
    if get_running(conn).is_some() {
        eprintln!("A timer is already running. Pause or stop it first.");
        std::process::exit(1);
    }

    let all = get_all_active(conn);
    let paused: Vec<&ActiveTimer> = all.iter().filter(|t| t.state == "paused").collect();

    if paused.is_empty() {
        eprintln!("No paused timers.");
        std::process::exit(1);
    }

    let timer_to_resume = if paused.len() == 1 {
        paused[0]
    } else {
        let now_ts = Local::now().timestamp();
        let items: Vec<String> = paused
            .iter()
            .map(|t| {
                let elapsed = now_ts - t.started_at;
                let break_secs = total_break_secs(&t.breaks, now_ts);
                let active_secs = (elapsed - break_secs).max(0);
                format!(
                    "#{} \"{}\" [{}] — active: {}",
                    t.id.unwrap(),
                    t.name,
                    t.category,
                    format_duration(active_secs),
                )
            })
            .collect();

        let selection = Select::new()
            .with_prompt("Which timer to resume?")
            .items(&items)
            .default(0)
            .interact()
            .unwrap();

        paused[selection]
    };

    let now_ts = Local::now().timestamp();
    let mut resumed = ActiveTimer {
        id: timer_to_resume.id,
        name: timer_to_resume.name.clone(),
        category: timer_to_resume.category.clone(),
        started_at: timer_to_resume.started_at,
        state: "running".into(),
        breaks: timer_to_resume.breaks.clone(),
        todo_id: timer_to_resume.todo_id,
    };
    if let Some(last) = resumed.breaks.last_mut() {
        if last.end_ts == 0 {
            last.end_ts = now_ts;
        }
    }
    update_active(conn, &resumed);

    let now = Local::now();
    println!("Resumed \"{}\" at {}", resumed.name, now.format("%H:%M:%S"));
}

pub fn switch(conn: &Connection) {
    let all = get_all_active(conn);
    let running = all.iter().find(|t| t.state == "running");
    let paused: Vec<&ActiveTimer> = all.iter().filter(|t| t.state == "paused").collect();

    if paused.is_empty() {
        println!("No other timers to switch to.");
        return;
    }

    let now_ts = Local::now().timestamp();
    let items: Vec<String> = paused
        .iter()
        .map(|t| {
            let elapsed = now_ts - t.started_at;
            let break_secs = total_break_secs(&t.breaks, now_ts);
            let active_secs = (elapsed - break_secs).max(0);
            format!(
                "#{} \"{}\" [{}] — active: {}",
                t.id.unwrap(),
                t.name,
                t.category,
                format_duration(active_secs),
            )
        })
        .collect();

    let selection = Select::new()
        .with_prompt("Switch to which timer?")
        .items(&items)
        .default(0)
        .interact()
        .unwrap();

    let selected = paused[selection];

    // Pause the currently running timer (if any)
    if let Some(r) = running {
        let mut paused_timer = ActiveTimer {
            id: r.id,
            name: r.name.clone(),
            category: r.category.clone(),
            started_at: r.started_at,
            state: "paused".into(),
            breaks: r.breaks.clone(),
            todo_id: r.todo_id,
        };
        paused_timer.breaks.push(proto::Break {
            start_ts: now_ts,
            end_ts: 0,
        });
        update_active(conn, &paused_timer);
        println!("Paused \"{}\".", r.name);
    }

    // Resume the selected timer
    let mut resumed = ActiveTimer {
        id: selected.id,
        name: selected.name.clone(),
        category: selected.category.clone(),
        started_at: selected.started_at,
        state: "running".into(),
        breaks: selected.breaks.clone(),
        todo_id: selected.todo_id,
    };
    if let Some(last) = resumed.breaks.last_mut() {
        if last.end_ts == 0 {
            last.end_ts = now_ts;
        }
    }
    update_active(conn, &resumed);

    println!("Switched to \"{}\" [{}].", resumed.name, resumed.category);
}

pub fn status(conn: &Connection) {
    let all = get_all_active(conn);

    if all.is_empty() {
        println!("No active timers.");
        return;
    }

    let now_ts = Local::now().timestamp();

    for timer in &all {
        let elapsed = now_ts - timer.started_at;
        let break_secs = total_break_secs(&timer.breaks, now_ts);
        let active_secs = (elapsed - break_secs).max(0);

        let started = Local
            .timestamp_opt(timer.started_at, 0)
            .single()
            .unwrap();

        let state_label = if timer.state == "running" {
            "RUNNING"
        } else {
            "PAUSED"
        };

        println!(
            "#{} \"{}\" [{}] — {}",
            timer.id.unwrap(),
            timer.name,
            timer.category,
            state_label,
        );
        println!("  Started:  {}", started.format("%H:%M:%S"));
        println!("  Active:   {}", format_duration(active_secs));
        println!("  Breaks:   {}", format_duration(break_secs));
        if let Some(tid) = timer.todo_id {
            let todos = list_todos(conn);
            if let Some(todo) = todos.iter().find(|t| t.id == tid) {
                println!("  -> todo #{} \"{}\"", tid, todo.text);
            } else {
                println!("  -> todo #{tid}");
            }
        }
    }
}

pub fn log(conn: &Connection, today: bool, week: bool) {
    let since_ts = if today {
        Some(
            Local::now()
                .date_naive()
                .and_hms_opt(0, 0, 0)
                .unwrap()
                .and_local_timezone(Local)
                .unwrap()
                .timestamp(),
        )
    } else if week {
        Some(
            (Local::now() - chrono::Duration::days(7))
                .timestamp(),
        )
    } else {
        None
    };

    let entries = query_entries(conn, since_ts);

    if entries.is_empty() {
        println!("No log entries found.");
        return;
    }

    println!(
        "{:<5} {:<20} {:<15} {:<10} {:<12} {:<10} {}",
        "ID", "Name", "Category", "Date", "Active", "Breaks", "Todo"
    );
    println!("{}", "-".repeat(86));

    let mut total_active: i64 = 0;
    let mut total_breaks: i64 = 0;

    for e in &entries {
        let break_secs = total_break_secs(&e.breaks, e.ended_at);
        total_active += e.active_secs;
        total_breaks += break_secs;

        let date = Local
            .timestamp_opt(e.started_at, 0)
            .single()
            .unwrap();

        let todo_col = match e.todo_id {
            Some(tid) => format!("#{tid}"),
            None => String::new(),
        };

        println!(
            "{:<5} {:<20} {:<15} {:<10} {:<12} {:<10} {}",
            e.id,
            truncate(&e.name, 19),
            truncate(&e.category, 14),
            date.format("%Y-%m-%d"),
            format_duration(e.active_secs),
            format_duration(break_secs),
            todo_col,
        );
    }

    println!("{}", "-".repeat(86));
    println!(
        "{:<5} {:<20} {:<15} {:<10} {:<12} {}",
        "",
        "TOTAL",
        "",
        "",
        format_duration(total_active),
        format_duration(total_breaks),
    );
}

pub fn rm(conn: &Connection, id: u32) {
    if delete_entry(conn, id) {
        println!("Deleted log entry #{id}.");
    } else {
        eprintln!("Log entry #{id} not found.");
        std::process::exit(1);
    }
}

fn truncate(s: &str, max: usize) -> String {
    if s.len() > max {
        format!("{}…", &s[..max - 1])
    } else {
        s.to_string()
    }
}
