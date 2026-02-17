use chrono::{Local, TimeZone};
use rusqlite::Connection;

use crate::state::*;

pub fn add(conn: &Connection, text: &str) {
    let now_ts = Local::now().timestamp();
    let id = add_todo(conn, text, now_ts);
    println!("Added todo #{id}: {text}");
}

pub fn list(conn: &Connection) {
    let todos = list_todos(conn);
    if todos.is_empty() {
        println!("No todos.");
        return;
    }

    for item in &todos {
        let check = if item.done { "x" } else { " " };
        let date = Local
            .timestamp_opt(item.created_at, 0)
            .single()
            .unwrap();
        println!(
            "  [{check}] #{:<4} {}  ({})",
            item.id,
            item.text,
            date.format("%Y-%m-%d"),
        );
    }

    let done = todos.iter().filter(|t| t.done).count();
    let total = todos.len();
    println!("\n  {done}/{total} completed");
}

pub fn done(conn: &Connection, id: u32) {
    if mark_todo_done(conn, id) {
        println!("Marked todo #{id} as done.");
    } else {
        eprintln!("Todo #{id} not found.");
        std::process::exit(1);
    }
}

pub fn rm(conn: &Connection, id: u32) {
    if remove_todo(conn, id) {
        println!("Removed todo #{id}.");
    } else {
        eprintln!("Todo #{id} not found.");
        std::process::exit(1);
    }
}
