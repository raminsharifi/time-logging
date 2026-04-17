use chrono::Local;
use prost::Message;
use rusqlite::{Connection, params};
use serde::{Deserialize, Serialize};
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

    let has_last_modified: bool = conn
        .prepare("SELECT last_modified FROM active_timers LIMIT 0")
        .is_ok();
    if !has_last_modified {
        conn.execute_batch(
            "ALTER TABLE active_timers ADD COLUMN last_modified INTEGER NOT NULL DEFAULT 0;
             ALTER TABLE time_entries ADD COLUMN last_modified INTEGER NOT NULL DEFAULT 0;
             ALTER TABLE todos ADD COLUMN last_modified INTEGER NOT NULL DEFAULT 0;",
        )
        .expect("failed to add last_modified columns");
    }

    conn.execute_batch(
        "CREATE TABLE IF NOT EXISTS deleted_records (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            table_name TEXT NOT NULL,
            record_id INTEGER NOT NULL,
            deleted_at INTEGER NOT NULL
        );
        CREATE TABLE IF NOT EXISTS sync_clients (
            client_id TEXT PRIMARY KEY,
            last_sync_ts INTEGER NOT NULL DEFAULT 0
        );",
    )
    .expect("failed to create sync tables");

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
    pub last_modified: i64,
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
        last_modified: row.get(7)?,
    })
}

fn now_ts() -> i64 {
    Local::now().timestamp()
}

pub fn get_running(conn: &Connection) -> Option<ActiveTimer> {
    conn.query_row(
        "SELECT id, name, category, started_at, state, breaks, todo_id, last_modified FROM active_timers WHERE state = 'running'",
        [],
        row_to_timer,
    )
    .ok()
}

pub fn get_all_active(conn: &Connection) -> Vec<ActiveTimer> {
    let mut stmt = conn
        .prepare("SELECT id, name, category, started_at, state, breaks, todo_id, last_modified FROM active_timers ORDER BY id")
        .unwrap();
    let rows = stmt.query_map([], row_to_timer).unwrap();
    rows.filter_map(|r| r.ok()).collect()
}

pub fn get_active_by_id(conn: &Connection, id: u32) -> Option<ActiveTimer> {
    conn.query_row(
        "SELECT id, name, category, started_at, state, breaks, todo_id, last_modified FROM active_timers WHERE id = ?1",
        params![id],
        row_to_timer,
    )
    .ok()
}

pub fn insert_active(conn: &Connection, timer: &ActiveTimer) -> u32 {
    let modified = now_ts();
    conn.execute(
        "INSERT INTO active_timers (name, category, started_at, state, breaks, todo_id, last_modified)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
        params![
            timer.name,
            timer.category,
            timer.started_at,
            timer.state,
            encode_breaks(&timer.breaks),
            timer.todo_id,
            modified,
        ],
    )
    .expect("failed to insert active timer");
    conn.last_insert_rowid() as u32
}

pub fn update_active(conn: &Connection, timer: &ActiveTimer) {
    let id = timer.id.expect("cannot update timer without id");
    let modified = now_ts();
    conn.execute(
        "UPDATE active_timers SET name = ?1, category = ?2, started_at = ?3, state = ?4, breaks = ?5, todo_id = ?6, last_modified = ?7 WHERE id = ?8",
        params![
            timer.name,
            timer.category,
            timer.started_at,
            timer.state,
            encode_breaks(&timer.breaks),
            timer.todo_id,
            modified,
            id,
        ],
    )
    .expect("failed to update active timer");
}

pub fn clear_active(conn: &Connection, id: u32) {
    conn.execute(
        "INSERT INTO deleted_records (table_name, record_id, deleted_at) VALUES ('active_timers', ?1, ?2)",
        params![id, now_ts()],
    ).expect("failed to record deletion");
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
    pub last_modified: i64,
}

pub fn insert_entry(conn: &Connection, entry: &TimeEntry) {
    let modified = now_ts();
    conn.execute(
        "INSERT INTO time_entries (name, category, started_at, ended_at, active_secs, breaks, todo_id, last_modified)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)",
        params![
            entry.name,
            entry.category,
            entry.started_at,
            entry.ended_at,
            entry.active_secs,
            encode_breaks(&entry.breaks),
            entry.todo_id,
            modified,
        ],
    )
    .expect("failed to insert time entry");
}

pub fn get_entry_by_id(conn: &Connection, id: u32) -> Option<TimeEntry> {
    conn.query_row(
        "SELECT id, name, category, started_at, ended_at, active_secs, breaks, todo_id, last_modified FROM time_entries WHERE id = ?1",
        params![id],
        row_to_entry,
    )
    .ok()
}

fn row_to_entry(row: &rusqlite::Row) -> rusqlite::Result<TimeEntry> {
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
        last_modified: row.get(8)?,
    })
}

pub fn update_entry(conn: &Connection, entry: &TimeEntry) {
    let modified = now_ts();
    conn.execute(
        "UPDATE time_entries SET name = ?1, category = ?2, active_secs = ?3, last_modified = ?4 WHERE id = ?5",
        params![
            entry.name,
            entry.category,
            entry.active_secs,
            modified,
            entry.id,
        ],
    )
    .expect("failed to update time entry");
}

pub fn delete_entry(conn: &Connection, id: u32) -> bool {
    conn.execute(
        "INSERT INTO deleted_records (table_name, record_id, deleted_at) VALUES ('time_entries', ?1, ?2)",
        params![id, now_ts()],
    ).expect("failed to record deletion");
    let changed = conn
        .execute("DELETE FROM time_entries WHERE id = ?1", params![id])
        .unwrap_or(0);
    changed > 0
}

pub fn query_entries(conn: &Connection, since_ts: Option<i64>) -> Vec<TimeEntry> {
    let (sql, bind_ts) = match since_ts {
        Some(ts) => (
            "SELECT id, name, category, started_at, ended_at, active_secs, breaks, todo_id, last_modified FROM time_entries WHERE started_at >= ?1 ORDER BY started_at",
            Some(ts),
        ),
        None => (
            "SELECT id, name, category, started_at, ended_at, active_secs, breaks, todo_id, last_modified FROM time_entries ORDER BY started_at",
            None,
        ),
    };

    let mut stmt = conn.prepare(sql).unwrap();
    let rows = if let Some(ts) = bind_ts {
        stmt.query_map(params![ts], row_to_entry).unwrap()
    } else {
        stmt.query_map([], row_to_entry).unwrap()
    };

    rows.filter_map(|r| r.ok()).collect()
}

pub fn get_last_entry(conn: &Connection) -> Option<TimeEntry> {
    conn.query_row(
        "SELECT id, name, category, started_at, ended_at, active_secs, breaks, todo_id, last_modified FROM time_entries ORDER BY ended_at DESC LIMIT 1",
        [],
        row_to_entry,
    )
    .ok()
}

pub fn distinct_names(conn: &Connection) -> Vec<String> {
    let mut stmt = conn
        .prepare("SELECT DISTINCT name FROM time_entries ORDER BY id DESC")
        .unwrap();
    stmt.query_map([], |row| row.get(0))
        .unwrap()
        .filter_map(|r| r.ok())
        .collect()
}

pub fn distinct_categories(conn: &Connection) -> Vec<String> {
    let mut stmt = conn
        .prepare("SELECT DISTINCT category FROM time_entries ORDER BY id DESC")
        .unwrap();
    stmt.query_map([], |row| row.get(0))
        .unwrap()
        .filter_map(|r| r.ok())
        .collect()
}

/// Aggregate entries since `since_ts`, grouped by day (yyyy-MM-dd in local tz)
/// and by category. Also computes a streak (consecutive days with any entry).
pub fn aggregate_entries(
    conn: &Connection,
    since_ts: i64,
) -> (i64, Vec<(String, i64)>, Vec<(String, i64)>, u32) {
    use chrono::{Local, TimeZone};

    // by day
    let mut day_stmt = conn
        .prepare(
            "SELECT started_at, active_secs, category FROM time_entries WHERE started_at >= ?1",
        )
        .unwrap();
    let rows = day_stmt
        .query_map(params![since_ts], |row| {
            let ts: i64 = row.get(0)?;
            let secs: i64 = row.get(1)?;
            let cat: String = row.get(2)?;
            Ok((ts, secs, cat))
        })
        .unwrap();

    let mut by_day_map: std::collections::BTreeMap<String, i64> = std::collections::BTreeMap::new();
    let mut by_cat_map: std::collections::HashMap<String, i64> = std::collections::HashMap::new();
    let mut total: i64 = 0;

    for r in rows.flatten() {
        let (ts, secs, cat) = r;
        let dt = Local.timestamp_opt(ts, 0).single();
        if let Some(dt) = dt {
            let key = dt.format("%Y-%m-%d").to_string();
            *by_day_map.entry(key).or_insert(0) += secs;
        }
        *by_cat_map.entry(cat).or_insert(0) += secs;
        total += secs;
    }

    let by_day: Vec<(String, i64)> = by_day_map.into_iter().collect();
    let mut by_cat: Vec<(String, i64)> = by_cat_map.into_iter().collect();
    by_cat.sort_by(|a, b| b.1.cmp(&a.1));

    // streak — consecutive days ending today (local) with any entry
    let today = Local::now().date_naive();
    let mut day_set: std::collections::HashSet<String> = std::collections::HashSet::new();
    for (d, _) in &by_day {
        day_set.insert(d.clone());
    }
    let mut streak: u32 = 0;
    for i in 0..365 {
        let d = today - chrono::Duration::days(i);
        let key = d.format("%Y-%m-%d").to_string();
        if day_set.contains(&key) {
            streak += 1;
        } else if i == 0 {
            // today has no entries yet — still count backwards from yesterday
            continue;
        } else {
            break;
        }
    }

    (total, by_day, by_cat, streak)
}

/// Return the N most recent todos (by last_modified), used for autocomplete in the new-timer UI.
pub fn recent_todos(conn: &Connection, limit: u32) -> Vec<TodoItem> {
    let mut stmt = conn
        .prepare(
            "SELECT id, text, done, created_at, last_modified FROM todos ORDER BY last_modified DESC LIMIT ?1",
        )
        .unwrap();
    stmt.query_map(params![limit], |row| {
        Ok(TodoItem {
            id: row.get(0)?,
            text: row.get(1)?,
            done: {
                let v: i64 = row.get(2)?;
                v != 0
            },
            created_at: row.get(3)?,
            last_modified: row.get(4)?,
        })
    })
    .unwrap()
    .filter_map(|r| r.ok())
    .collect()
}

// --- Todo DB ops ---

pub struct TodoItem {
    pub id: u32,
    pub text: String,
    pub done: bool,
    pub created_at: i64,
    pub last_modified: i64,
}

pub fn add_todo(conn: &Connection, text: &str, created_at: i64) -> u32 {
    let modified = now_ts();
    conn.execute(
        "INSERT INTO todos (text, done, created_at, last_modified) VALUES (?1, 0, ?2, ?3)",
        params![text, created_at, modified],
    )
    .expect("failed to add todo");
    conn.last_insert_rowid() as u32
}

pub fn list_todos(conn: &Connection) -> Vec<TodoItem> {
    let mut stmt = conn
        .prepare("SELECT id, text, done, created_at, last_modified FROM todos ORDER BY id")
        .unwrap();
    let rows = stmt
        .query_map([], |row| {
            Ok(TodoItem {
                id: row.get(0)?,
                text: row.get(1)?,
                done: row.get::<_, i32>(2)? != 0,
                created_at: row.get(3)?,
                last_modified: row.get(4)?,
            })
        })
        .unwrap();
    rows.filter_map(|r| r.ok()).collect()
}

pub fn mark_todo_done(conn: &Connection, id: u32) -> bool {
    let modified = now_ts();
    let changed = conn
        .execute("UPDATE todos SET done = 1, last_modified = ?1 WHERE id = ?2", params![modified, id])
        .unwrap_or(0);
    changed > 0
}

pub fn unmark_todo_done(conn: &Connection, id: u32) -> bool {
    let modified = now_ts();
    let changed = conn
        .execute("UPDATE todos SET done = 0, last_modified = ?1 WHERE id = ?2", params![modified, id])
        .unwrap_or(0);
    changed > 0
}

pub fn edit_todo(conn: &Connection, id: u32, text: &str) -> bool {
    let modified = now_ts();
    let changed = conn
        .execute("UPDATE todos SET text = ?1, last_modified = ?2 WHERE id = ?3", params![text, modified, id])
        .unwrap_or(0);
    changed > 0
}

pub fn remove_todo(conn: &Connection, id: u32) -> bool {
    conn.execute(
        "INSERT INTO deleted_records (table_name, record_id, deleted_at) VALUES ('todos', ?1, ?2)",
        params![id, now_ts()],
    ).expect("failed to record deletion");
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

// --- Sync query functions ---

#[derive(Debug, Serialize, Deserialize)]
pub struct DeletionRecord {
    pub id: u32,
    pub table_name: String,
    pub record_id: u32,
    pub deleted_at: i64,
}

pub fn query_modified_timers(conn: &Connection, since_ts: i64) -> Vec<ActiveTimer> {
    let mut stmt = conn
        .prepare("SELECT id, name, category, started_at, state, breaks, todo_id, last_modified FROM active_timers WHERE last_modified > ?1 ORDER BY id")
        .unwrap();
    let rows = stmt.query_map(params![since_ts], row_to_timer).unwrap();
    rows.filter_map(|r| r.ok()).collect()
}

pub fn query_modified_entries(conn: &Connection, since_ts: i64) -> Vec<TimeEntry> {
    let mut stmt = conn
        .prepare("SELECT id, name, category, started_at, ended_at, active_secs, breaks, todo_id, last_modified FROM time_entries WHERE last_modified > ?1 ORDER BY id")
        .unwrap();
    let rows = stmt.query_map(params![since_ts], row_to_entry).unwrap();
    rows.filter_map(|r| r.ok()).collect()
}

pub fn query_modified_todos(conn: &Connection, since_ts: i64) -> Vec<TodoItem> {
    let mut stmt = conn
        .prepare("SELECT id, text, done, created_at, last_modified FROM todos WHERE last_modified > ?1 ORDER BY id")
        .unwrap();
    let rows = stmt
        .query_map(params![since_ts], |row| {
            Ok(TodoItem {
                id: row.get(0)?,
                text: row.get(1)?,
                done: row.get::<_, i32>(2)? != 0,
                created_at: row.get(3)?,
                last_modified: row.get(4)?,
            })
        })
        .unwrap();
    rows.filter_map(|r| r.ok()).collect()
}

pub fn query_deletions(conn: &Connection, since_ts: i64) -> Vec<DeletionRecord> {
    let mut stmt = conn
        .prepare("SELECT id, table_name, record_id, deleted_at FROM deleted_records WHERE deleted_at > ?1 ORDER BY id")
        .unwrap();
    let rows = stmt
        .query_map(params![since_ts], |row| {
            Ok(DeletionRecord {
                id: row.get(0)?,
                table_name: row.get(1)?,
                record_id: row.get(2)?,
                deleted_at: row.get(3)?,
            })
        })
        .unwrap();
    rows.filter_map(|r| r.ok()).collect()
}

pub fn get_sync_ts(conn: &Connection, client_id: &str) -> i64 {
    conn.query_row(
        "SELECT last_sync_ts FROM sync_clients WHERE client_id = ?1",
        params![client_id],
        |row| row.get(0),
    )
    .unwrap_or(0)
}

pub fn set_sync_ts(conn: &Connection, client_id: &str, ts: i64) {
    conn.execute(
        "INSERT INTO sync_clients (client_id, last_sync_ts) VALUES (?1, ?2)
         ON CONFLICT(client_id) DO UPDATE SET last_sync_ts = ?2",
        params![client_id, ts],
    )
    .expect("failed to update sync timestamp");
}

pub fn upsert_active_timer(conn: &Connection, id: u32, timer: &ActiveTimer) {
    let exists: bool = conn
        .query_row("SELECT COUNT(*) FROM active_timers WHERE id = ?1", params![id], |row| row.get::<_, i32>(0))
        .unwrap_or(0) > 0;

    if exists {
        conn.execute(
            "UPDATE active_timers SET name = ?1, category = ?2, started_at = ?3, state = ?4, breaks = ?5, todo_id = ?6, last_modified = ?7 WHERE id = ?8",
            params![timer.name, timer.category, timer.started_at, timer.state, encode_breaks(&timer.breaks), timer.todo_id, timer.last_modified, id],
        ).expect("failed to upsert active timer");
    } else {
        conn.execute(
            "INSERT INTO active_timers (id, name, category, started_at, state, breaks, todo_id, last_modified) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)",
            params![id, timer.name, timer.category, timer.started_at, timer.state, encode_breaks(&timer.breaks), timer.todo_id, timer.last_modified],
        ).expect("failed to upsert active timer");
    }
}

pub fn upsert_entry(conn: &Connection, id: u32, entry: &TimeEntry) {
    let exists: bool = conn
        .query_row("SELECT COUNT(*) FROM time_entries WHERE id = ?1", params![id], |row| row.get::<_, i32>(0))
        .unwrap_or(0) > 0;

    if exists {
        conn.execute(
            "UPDATE time_entries SET name = ?1, category = ?2, started_at = ?3, ended_at = ?4, active_secs = ?5, breaks = ?6, todo_id = ?7, last_modified = ?8 WHERE id = ?9",
            params![entry.name, entry.category, entry.started_at, entry.ended_at, entry.active_secs, encode_breaks(&entry.breaks), entry.todo_id, entry.last_modified, id],
        ).expect("failed to upsert time entry");
    } else {
        conn.execute(
            "INSERT INTO time_entries (id, name, category, started_at, ended_at, active_secs, breaks, todo_id, last_modified) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)",
            params![id, entry.name, entry.category, entry.started_at, entry.ended_at, entry.active_secs, encode_breaks(&entry.breaks), entry.todo_id, entry.last_modified],
        ).expect("failed to upsert time entry");
    }
}

pub fn upsert_todo(conn: &Connection, id: u32, todo: &TodoItem) {
    let exists: bool = conn
        .query_row("SELECT COUNT(*) FROM todos WHERE id = ?1", params![id], |row| row.get::<_, i32>(0))
        .unwrap_or(0) > 0;

    if exists {
        conn.execute(
            "UPDATE todos SET text = ?1, done = ?2, created_at = ?3, last_modified = ?4 WHERE id = ?5",
            params![todo.text, todo.done as i32, todo.created_at, todo.last_modified, id],
        ).expect("failed to upsert todo");
    } else {
        conn.execute(
            "INSERT INTO todos (id, text, done, created_at, last_modified) VALUES (?1, ?2, ?3, ?4, ?5)",
            params![id, todo.text, todo.done as i32, todo.created_at, todo.last_modified],
        ).expect("failed to upsert todo");
    }
}

pub fn get_todo_by_id(conn: &Connection, id: u32) -> Option<TodoItem> {
    conn.query_row(
        "SELECT id, text, done, created_at, last_modified FROM todos WHERE id = ?1",
        params![id],
        |row| {
            Ok(TodoItem {
                id: row.get(0)?,
                text: row.get(1)?,
                done: row.get::<_, i32>(2)? != 0,
                created_at: row.get(3)?,
                last_modified: row.get(4)?,
            })
        },
    )
    .ok()
}
