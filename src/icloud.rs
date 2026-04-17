use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::Duration;

use crate::state;
use rusqlite::Connection;

unsafe extern "C" {
    fn icloud_init() -> i32;
    fn icloud_push(records_json: *const c_char);
    fn icloud_delete(deletions_json: *const c_char);
    fn icloud_fetch_changes() -> *const c_char;
    fn icloud_free(ptr: *const c_char);
}

/// Initialize iCloud sync. Returns true if iCloud is available.
pub fn init_icloud() -> bool {
    let result = unsafe { icloud_init() };
    result != 0
}

/// Push local changes to CloudKit.
pub fn push_changes(conn: &Connection) {
    // Push active timers
    let timers = state::get_all_active(conn);
    if !timers.is_empty() {
        let records: Vec<serde_json::Value> = timers
            .iter()
            .map(|t| {
                let breaks_json: Vec<serde_json::Value> = t
                    .breaks
                    .iter()
                    .map(|b| {
                        serde_json::json!({"start_ts": b.start_ts, "end_ts": b.end_ts})
                    })
                    .collect();
                serde_json::json!({
                    "type": "ActiveTimer",
                    "id": t.id.unwrap(),
                    "fields": {
                        "serverId": t.id.unwrap(),
                        "name": t.name,
                        "category": t.category,
                        "startedAt": t.started_at,
                        "state": t.state,
                        "breaksJSON": serde_json::to_string(&breaks_json).unwrap_or_default(),
                        "todoId": t.todo_id.unwrap_or(0),
                        "lastModified": t.last_modified,
                    }
                })
            })
            .collect();
        let json = serde_json::to_string(&records).unwrap();
        let c_json = CString::new(json).unwrap();
        unsafe { icloud_push(c_json.as_ptr()); }
    }

    // Push time entries
    let entries = state::query_entries(conn, None);
    if !entries.is_empty() {
        let records: Vec<serde_json::Value> = entries
            .iter()
            .map(|e| {
                let breaks_json: Vec<serde_json::Value> = e
                    .breaks
                    .iter()
                    .map(|b| {
                        serde_json::json!({"start_ts": b.start_ts, "end_ts": b.end_ts})
                    })
                    .collect();
                serde_json::json!({
                    "type": "TimeEntry",
                    "id": e.id,
                    "fields": {
                        "serverId": e.id,
                        "name": e.name,
                        "category": e.category,
                        "startedAt": e.started_at,
                        "endedAt": e.ended_at,
                        "activeSecs": e.active_secs,
                        "breaksJSON": serde_json::to_string(&breaks_json).unwrap_or_default(),
                        "todoId": e.todo_id.unwrap_or(0),
                        "lastModified": e.last_modified,
                    }
                })
            })
            .collect();
        let json = serde_json::to_string(&records).unwrap();
        let c_json = CString::new(json).unwrap();
        unsafe { icloud_push(c_json.as_ptr()); }
    }

    // Push todos
    let todos = state::list_todos(conn);
    if !todos.is_empty() {
        let records: Vec<serde_json::Value> = todos
            .iter()
            .map(|t| {
                serde_json::json!({
                    "type": "TodoItem",
                    "id": t.id,
                    "fields": {
                        "serverId": t.id,
                        "text": t.text,
                        "done": if t.done { 1 } else { 0 },
                        "createdAt": t.created_at,
                        "lastModified": t.last_modified,
                    }
                })
            })
            .collect();
        let json = serde_json::to_string(&records).unwrap();
        let c_json = CString::new(json).unwrap();
        unsafe { icloud_push(c_json.as_ptr()); }
    }
}

/// Fetch changes from CloudKit and apply them locally.
pub fn fetch_and_apply(conn: &Connection) {
    let json_ptr = unsafe { icloud_fetch_changes() };
    if json_ptr.is_null() {
        return;
    }

    let json_str = unsafe { CStr::from_ptr(json_ptr) }
        .to_str()
        .unwrap_or("{}");
    let parsed: serde_json::Value =
        serde_json::from_str(json_str).unwrap_or(serde_json::json!({}));
    unsafe { icloud_free(json_ptr); }

    // Apply timer changes
    if let Some(timers) = parsed["timers"].as_array() {
        for t in timers {
            if let (Some(sid), Some(name), Some(category), Some(started_at), Some(st), Some(lm)) = (
                t["serverId"].as_i64().or(t["serverId"].as_u64().map(|v| v as i64)),
                t["name"].as_str(),
                t["category"].as_str(),
                t["startedAt"].as_i64(),
                t["state"].as_str(),
                t["lastModified"].as_i64(),
            ) {
                let breaks_json_str = t["breaksJSON"].as_str().unwrap_or("[]");
                let breaks: Vec<state::proto::Break> =
                    serde_json::from_str::<Vec<serde_json::Value>>(breaks_json_str)
                        .unwrap_or_default()
                        .iter()
                        .map(|b| state::proto::Break {
                            start_ts: b["start_ts"].as_i64().unwrap_or(0),
                            end_ts: b["end_ts"].as_i64().unwrap_or(0),
                        })
                        .collect();
                let todo_id = t["todoId"].as_i64().map(|v| if v == 0 { None } else { Some(v as u32) }).flatten();

                let timer = state::ActiveTimer {
                    id: Some(sid as u32),
                    name: name.to_string(),
                    category: category.to_string(),
                    started_at,
                    state: st.to_string(),
                    breaks,
                    todo_id,
                    last_modified: lm,
                };

                if let Some(existing) = state::get_active_by_id(conn, sid as u32) {
                    if lm > existing.last_modified {
                        state::upsert_active_timer(conn, sid as u32, &timer);
                    }
                } else {
                    state::upsert_active_timer(conn, sid as u32, &timer);
                }
            }
        }
    }

    // Apply entry changes
    if let Some(entries) = parsed["entries"].as_array() {
        for e in entries {
            if let (Some(sid), Some(name), Some(category), Some(started_at), Some(ended_at), Some(active_secs), Some(lm)) = (
                e["serverId"].as_i64(),
                e["name"].as_str(),
                e["category"].as_str(),
                e["startedAt"].as_i64(),
                e["endedAt"].as_i64(),
                e["activeSecs"].as_i64(),
                e["lastModified"].as_i64(),
            ) {
                let breaks_json_str = e["breaksJSON"].as_str().unwrap_or("[]");
                let breaks: Vec<state::proto::Break> =
                    serde_json::from_str::<Vec<serde_json::Value>>(breaks_json_str)
                        .unwrap_or_default()
                        .iter()
                        .map(|b| state::proto::Break {
                            start_ts: b["start_ts"].as_i64().unwrap_or(0),
                            end_ts: b["end_ts"].as_i64().unwrap_or(0),
                        })
                        .collect();
                let todo_id = e["todoId"].as_i64().map(|v| if v == 0 { None } else { Some(v as u32) }).flatten();

                let entry = state::TimeEntry {
                    id: sid as u32,
                    name: name.to_string(),
                    category: category.to_string(),
                    started_at,
                    ended_at,
                    active_secs,
                    breaks,
                    todo_id,
                    last_modified: lm,
                };

                if let Some(existing) = state::get_entry_by_id(conn, sid as u32) {
                    if lm > existing.last_modified {
                        state::upsert_entry(conn, sid as u32, &entry);
                    }
                } else {
                    state::upsert_entry(conn, sid as u32, &entry);
                }
            }
        }
    }

    // Apply todo changes
    if let Some(todos) = parsed["todos"].as_array() {
        for t in todos {
            if let (Some(sid), Some(text), Some(done), Some(created_at), Some(lm)) = (
                t["serverId"].as_i64(),
                t["text"].as_str(),
                t["done"].as_i64(),
                t["createdAt"].as_i64(),
                t["lastModified"].as_i64(),
            ) {
                let todo = state::TodoItem {
                    id: sid as u32,
                    text: text.to_string(),
                    done: done != 0,
                    created_at,
                    last_modified: lm,
                };

                if let Some(existing) = state::get_todo_by_id(conn, sid as u32) {
                    if lm > existing.last_modified {
                        state::upsert_todo(conn, sid as u32, &todo);
                    }
                } else {
                    state::upsert_todo(conn, sid as u32, &todo);
                }
            }
        }
    }

    // Apply deletions
    if let Some(deletions) = parsed["deletions"].as_array() {
        for d in deletions {
            if let Some(record_name) = d["recordName"].as_str() {
                if record_name.starts_with("Timer-") {
                    if let Ok(id) = record_name[6..].parse::<u32>() {
                        if state::get_active_by_id(conn, id).is_some() {
                            state::clear_active(conn, id);
                        }
                    }
                } else if record_name.starts_with("Entry-") {
                    if let Ok(id) = record_name[6..].parse::<u32>() {
                        state::delete_entry(conn, id);
                    }
                } else if record_name.starts_with("Todo-") {
                    if let Ok(id) = record_name[5..].parse::<u32>() {
                        state::remove_todo(conn, id);
                    }
                }
            }
        }
    }
}

/// Start a background iCloud sync thread that periodically pushes/fetches.
pub fn start_background_sync(db: Arc<Mutex<Connection>>) {
    if !init_icloud() {
        println!("iCloud not available — skipping cloud sync");
        return;
    }
    println!("iCloud sync active");

    thread::spawn(move || {
        // Initial push
        {
            let conn = db.lock().unwrap();
            push_changes(&conn);
        }

        loop {
            thread::sleep(Duration::from_secs(30));

            let conn = db.lock().unwrap();
            fetch_and_apply(&conn);
            push_changes(&conn);
        }
    });
}
