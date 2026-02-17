use prost::Message;
use rusqlite::{Connection, params};
use std::path::PathBuf;

pub mod proto {
    include!(concat!(env!("OUT_DIR"), "/time_logging.rs"));
}

fn db_path() -> PathBuf {
    let dir = dirs::config_dir()
        .unwrap_or_else(|| PathBuf::from("."))
        .join("time-logging");
    std::fs::create_dir_all(&dir).ok();
    dir.join("data.db")
}

pub fn open_db() -> Connection {
    let conn = Connection::open(db_path()).expect("failed to open database");

    // Migrate from old single-row active_timer to multi-row active_timers
    let old_exists: bool = conn
        .query_row(
            "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='active_timer'",
            [],
            |row| row.get::<_, i32>(0),
        )
        .unwrap_or(0)
        > 0;

    let new_exists: bool = conn
        .query_row(
            "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='active_timers'",
            [],
            |row| row.get::<_, i32>(0),
        )
        .unwrap_or(0)
        > 0;

    if old_exists && !new_exists {
        conn.execute_batch(
            "CREATE TABLE active_timers (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL,
                category TEXT NOT NULL,
                started_at INTEGER NOT NULL,
                state TEXT NOT NULL,
                breaks BLOB NOT NULL
            );
            INSERT INTO active_timers (name, category, started_at, state, breaks)
                SELECT name, category, started_at, state, breaks FROM active_timer;
            DROP TABLE active_timer;",
        )
        .expect("failed to migrate active_timer to active_timers");
    }

    conn.execute_batch(
        "CREATE TABLE IF NOT EXISTS active_timers (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            category TEXT NOT NULL,
            started_at INTEGER NOT NULL,
            state TEXT NOT NULL,
            breaks BLOB NOT NULL
        );

        CREATE TABLE IF NOT EXISTS time_entries (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            category TEXT NOT NULL,
            started_at INTEGER NOT NULL,
            ended_at INTEGER NOT NULL,
            active_secs INTEGER NOT NULL,
            breaks BLOB NOT NULL
        );

        CREATE TABLE IF NOT EXISTS todos (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            text TEXT NOT NULL,
            done INTEGER NOT NULL DEFAULT 0,
            created_at INTEGER NOT NULL
        );",
    )
    .expect("failed to create tables");

    // Migrate: add todo_id column to active_timers and time_entries
    let has_todo_id: bool = conn
        .prepare("SELECT todo_id FROM active_timers LIMIT 0")
        .is_ok();
    if !has_todo_id {
        conn.execute_batch(
            "ALTER TABLE active_timers ADD COLUMN todo_id INTEGER;
             ALTER TABLE time_entries ADD COLUMN todo_id INTEGER;",
        )
        .expect("failed to add todo_id columns");
    }

    conn
}

// --- Break helpers ---

pub fn encode_breaks(breaks: &[proto::Break]) -> Vec<u8> {
    let msg = proto::Breaks {
        breaks: breaks.to_vec(),
    };
    msg.encode_to_vec()
}

pub fn decode_breaks(data: &[u8]) -> Vec<proto::Break> {
    proto::Breaks::decode(data)
        .map(|b| b.breaks)
        .unwrap_or_default()
}

pub fn total_break_secs(breaks: &[proto::Break], now_ts: i64) -> i64 {
    breaks
        .iter()
        .map(|b| {
            let end = if b.end_ts == 0 { now_ts } else { b.end_ts };
            end - b.start_ts
        })
        .sum()
}

// --- Formatting ---

pub fn format_duration(secs: i64) -> String {
    let h = secs / 3600;
    let m = (secs % 3600) / 60;
    let s = secs % 60;
    if h > 0 {
        format!("{h}h {m:02}m {s:02}s")
    } else if m > 0 {
        format!("{m}m {s:02}s")
    } else {
        format!("{s}s")
    }
}

// --- Active timer DB ops ---

pub struct ActiveTimer {
    pub id: Option<u32>,
    pub name: String,
    pub category: String,
    pub started_at: i64,
    pub state: String,
    pub breaks: Vec<proto::Break>,
    pub todo_id: Option<u32>,
}

fn row_to_timer(row: &rusqlite::Row) -> rusqlite::Result<ActiveTimer> {
    let breaks_blob: Vec<u8> = row.get(5)?;
    Ok(ActiveTimer {
        id: Some(row.get(0)?),
        name: row.get(1)?,
        category: row.get(2)?,
        started_at: row.get(3)?,
        state: row.get(4)?,
        breaks: decode_breaks(&breaks_blob),
        todo_id: row.get(6)?,
    })
}

pub fn get_running(conn: &Connection) -> Option<ActiveTimer> {
    conn.query_row(
        "SELECT id, name, category, started_at, state, breaks, todo_id FROM active_timers WHERE state = 'running'",
        [],
        row_to_timer,
    )
    .ok()
}

pub fn get_all_active(conn: &Connection) -> Vec<ActiveTimer> {
    let mut stmt = conn
        .prepare("SELECT id, name, category, started_at, state, breaks, todo_id FROM active_timers ORDER BY id")
        .unwrap();
    let rows = stmt.query_map([], row_to_timer).unwrap();
    rows.filter_map(|r| r.ok()).collect()
}

pub fn get_active_by_id(conn: &Connection, id: u32) -> Option<ActiveTimer> {
    conn.query_row(
        "SELECT id, name, category, started_at, state, breaks, todo_id FROM active_timers WHERE id = ?1",
        params![id],
        row_to_timer,
    )
    .ok()
}

pub fn insert_active(conn: &Connection, timer: &ActiveTimer) -> u32 {
    conn.execute(
        "INSERT INTO active_timers (name, category, started_at, state, breaks, todo_id)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
        params![
            timer.name,
            timer.category,
            timer.started_at,
            timer.state,
            encode_breaks(&timer.breaks),
            timer.todo_id,
        ],
    )
    .expect("failed to insert active timer");
    conn.last_insert_rowid() as u32
}

pub fn update_active(conn: &Connection, timer: &ActiveTimer) {
    let id = timer.id.expect("cannot update timer without id");
    conn.execute(
        "UPDATE active_timers SET name = ?1, category = ?2, started_at = ?3, state = ?4, breaks = ?5, todo_id = ?6 WHERE id = ?7",
        params![
            timer.name,
            timer.category,
            timer.started_at,
            timer.state,
            encode_breaks(&timer.breaks),
            timer.todo_id,
            id,
        ],
    )
    .expect("failed to update active timer");
}

pub fn clear_active(conn: &Connection, id: u32) {
    conn.execute("DELETE FROM active_timers WHERE id = ?1", params![id])
        .expect("failed to clear active timer");
}

// --- Time entry DB ops ---

pub struct TimeEntry {
    pub id: u32,
    pub name: String,
    pub category: String,
    pub started_at: i64,
    pub ended_at: i64,
    pub active_secs: i64,
    pub breaks: Vec<proto::Break>,
    pub todo_id: Option<u32>,
}

pub fn insert_entry(conn: &Connection, entry: &TimeEntry) {
    conn.execute(
        "INSERT INTO time_entries (name, category, started_at, ended_at, active_secs, breaks, todo_id)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
        params![
            entry.name,
            entry.category,
            entry.started_at,
            entry.ended_at,
            entry.active_secs,
            encode_breaks(&entry.breaks),
            entry.todo_id,
        ],
    )
    .expect("failed to insert time entry");
}

pub fn delete_entry(conn: &Connection, id: u32) -> bool {
    let changed = conn
        .execute("DELETE FROM time_entries WHERE id = ?1", params![id])
        .unwrap_or(0);
    changed > 0
}

pub fn query_entries(conn: &Connection, since_ts: Option<i64>) -> Vec<TimeEntry> {
    let (sql, bind_ts) = match since_ts {
        Some(ts) => (
            "SELECT id, name, category, started_at, ended_at, active_secs, breaks, todo_id FROM time_entries WHERE started_at >= ?1 ORDER BY started_at",
            Some(ts),
        ),
        None => (
            "SELECT id, name, category, started_at, ended_at, active_secs, breaks, todo_id FROM time_entries ORDER BY started_at",
            None,
        ),
    };

    let mut stmt = conn.prepare(sql).unwrap();
    let row_mapper = |row: &rusqlite::Row| {
        let breaks_blob: Vec<u8> = row.get(6)?;
        Ok(TimeEntry {
            id: row.get(0)?,
            name: row.get(1)?,
            category: row.get(2)?,
            started_at: row.get(3)?,
            ended_at: row.get(4)?,
            active_secs: row.get(5)?,
            breaks: decode_breaks(&breaks_blob),
            todo_id: row.get(7)?,
        })
    };

    let rows = if let Some(ts) = bind_ts {
        stmt.query_map(params![ts], row_mapper).unwrap()
    } else {
        stmt.query_map([], row_mapper).unwrap()
    };

    rows.filter_map(|r| r.ok()).collect()
}

// --- Todo DB ops ---

pub struct TodoItem {
    pub id: u32,
    pub text: String,
    pub done: bool,
    pub created_at: i64,
}

pub fn add_todo(conn: &Connection, text: &str, created_at: i64) -> u32 {
    conn.execute(
        "INSERT INTO todos (text, done, created_at) VALUES (?1, 0, ?2)",
        params![text, created_at],
    )
    .expect("failed to add todo");
    conn.last_insert_rowid() as u32
}

pub fn list_todos(conn: &Connection) -> Vec<TodoItem> {
    let mut stmt = conn
        .prepare("SELECT id, text, done, created_at FROM todos ORDER BY id")
        .unwrap();
    let rows = stmt
        .query_map([], |row| {
            Ok(TodoItem {
                id: row.get(0)?,
                text: row.get(1)?,
                done: row.get::<_, i32>(2)? != 0,
                created_at: row.get(3)?,
            })
        })
        .unwrap();
    rows.filter_map(|r| r.ok()).collect()
}

pub fn mark_todo_done(conn: &Connection, id: u32) -> bool {
    let changed = conn
        .execute("UPDATE todos SET done = 1 WHERE id = ?1", params![id])
        .unwrap_or(0);
    changed > 0
}

pub fn remove_todo(conn: &Connection, id: u32) -> bool {
    let changed = conn
        .execute("DELETE FROM todos WHERE id = ?1", params![id])
        .unwrap_or(0);
    changed > 0
}

pub fn get_todo_total_secs(conn: &Connection, todo_id: u32) -> i64 {
    conn.query_row(
        "SELECT COALESCE(SUM(active_secs), 0) FROM time_entries WHERE todo_id = ?1",
        params![todo_id],
        |row| row.get(0),
    )
    .unwrap_or(0)
}

pub fn get_active_todo_secs(conn: &Connection, todo_id: u32) -> i64 {
    let now_ts = chrono::Local::now().timestamp();
    let timers = get_all_active(conn);
    timers
        .iter()
        .filter(|t| t.todo_id == Some(todo_id))
        .map(|t| {
            let elapsed = now_ts - t.started_at;
            let break_secs = total_break_secs(&t.breaks, now_ts);
            (elapsed - break_secs).max(0)
        })
        .sum()
}
