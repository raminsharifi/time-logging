use axum::extract::{Path, Query, State};
use axum::http::StatusCode;
use axum::Json;
use chrono::Local;
use rusqlite::Connection;
use std::sync::{Arc, Mutex};

use crate::models::*;
use crate::state;
use crate::state::proto;

pub type Db = Arc<Mutex<Connection>>;

/// Push a BLE change event to all subscribed centrals (no-op without the BLE
/// feature). Call after any mutation so connected iOS/watchOS devices pull
/// the fresh state immediately instead of waiting for their next poll.
fn bump_clients() {
    #[cfg(feature = "ble")]
    crate::ble::notify_change();
}

fn breaks_to_periods(breaks: &[proto::Break]) -> Vec<BreakPeriod> {
    breaks.iter().map(|b| BreakPeriod { start_ts: b.start_ts, end_ts: b.end_ts }).collect()
}

fn timer_to_response(t: &state::ActiveTimer) -> TimerResponse {
    let now_ts = Local::now().timestamp();
    let elapsed = now_ts - t.started_at;
    let break_secs = state::total_break_secs(&t.breaks, now_ts);
    let active_secs = (elapsed - break_secs).max(0);
    TimerResponse {
        id: t.id.unwrap(),
        name: t.name.clone(),
        category: t.category.clone(),
        started_at: t.started_at,
        state: t.state.clone(),
        breaks: breaks_to_periods(&t.breaks),
        todo_id: t.todo_id,
        last_modified: t.last_modified,
        active_secs,
        break_secs,
    }
}

fn entry_to_response(e: &state::TimeEntry) -> EntryResponse {
    let break_secs = state::total_break_secs(&e.breaks, e.ended_at);
    EntryResponse {
        id: e.id,
        name: e.name.clone(),
        category: e.category.clone(),
        started_at: e.started_at,
        ended_at: e.ended_at,
        active_secs: e.active_secs,
        break_secs,
        todo_id: e.todo_id,
        last_modified: e.last_modified,
    }
}

fn todo_to_response(conn: &Connection, t: &state::TodoItem) -> TodoResponse {
    let entry_secs = state::get_todo_total_secs(conn, t.id);
    let active_secs = state::get_active_todo_secs(conn, t.id);
    TodoResponse {
        id: t.id,
        text: t.text.clone(),
        done: t.done,
        created_at: t.created_at,
        last_modified: t.last_modified,
        total_secs: entry_secs + active_secs,
    }
}

// --- Timer handlers ---

pub async fn get_status(State(db): State<Db>) -> Json<Vec<TimerResponse>> {
    let conn = db.lock().unwrap();
    let timers = state::get_all_active(&conn);
    Json(timers.iter().map(timer_to_response).collect())
}

pub async fn start_timer(
    State(db): State<Db>,
    Json(req): Json<StartTimerRequest>,
) -> (StatusCode, Json<TimerResponse>) {
    let conn = db.lock().unwrap();

    if let Some(running) = state::get_running(&conn) {
        let now_ts = Local::now().timestamp();
        let mut paused = running;
        paused.state = "paused".into();
        paused.breaks.push(proto::Break { start_ts: now_ts, end_ts: 0 });
        state::update_active(&conn, &paused);
    }

    let now = Local::now();
    let timer = state::ActiveTimer {
        id: None,
        name: req.name,
        category: req.category,
        started_at: now.timestamp(),
        state: "running".into(),
        breaks: vec![],
        todo_id: req.todo_id,
        last_modified: 0,
    };
    let id = state::insert_active(&conn, &timer);
    let inserted = state::get_active_by_id(&conn, id).unwrap();
    drop(conn);
    bump_clients();
    (StatusCode::CREATED, Json(timer_to_response(&inserted)))
}

pub async fn stop_timer(
    State(db): State<Db>,
    Path(id): Path<u32>,
) -> Result<Json<EntryResponse>, StatusCode> {
    let conn = db.lock().unwrap();
    let timer = state::get_active_by_id(&conn, id).ok_or(StatusCode::NOT_FOUND)?;
    if timer.state != "running" {
        return Err(StatusCode::CONFLICT);
    }

    let now_ts = Local::now().timestamp();
    let elapsed = now_ts - timer.started_at;
    let break_secs = state::total_break_secs(&timer.breaks, now_ts);
    let active_secs = (elapsed - break_secs).max(0);

    let entry = state::TimeEntry {
        id: 0,
        name: timer.name.clone(),
        category: timer.category.clone(),
        started_at: timer.started_at,
        ended_at: now_ts,
        active_secs,
        breaks: timer.breaks.clone(),
        todo_id: timer.todo_id,
        last_modified: 0,
    };
    state::insert_entry(&conn, &entry);
    state::clear_active(&conn, id);

    let last = state::get_last_entry(&conn).unwrap();
    drop(conn);
    bump_clients();
    Ok(Json(entry_to_response(&last)))
}

pub async fn pause_timer(
    State(db): State<Db>,
    Path(id): Path<u32>,
) -> Result<Json<TimerResponse>, StatusCode> {
    let conn = db.lock().unwrap();
    let mut timer = state::get_active_by_id(&conn, id).ok_or(StatusCode::NOT_FOUND)?;
    if timer.state != "running" {
        return Err(StatusCode::CONFLICT);
    }

    let now_ts = Local::now().timestamp();
    timer.state = "paused".into();
    timer.breaks.push(proto::Break { start_ts: now_ts, end_ts: 0 });
    state::update_active(&conn, &timer);

    let updated = state::get_active_by_id(&conn, id).unwrap();
    drop(conn);
    bump_clients();
    Ok(Json(timer_to_response(&updated)))
}

pub async fn resume_timer(
    State(db): State<Db>,
    Path(id): Path<u32>,
) -> Result<Json<TimerResponse>, StatusCode> {
    let conn = db.lock().unwrap();

    if state::get_running(&conn).is_some() {
        return Err(StatusCode::CONFLICT);
    }

    let mut timer = state::get_active_by_id(&conn, id).ok_or(StatusCode::NOT_FOUND)?;
    if timer.state != "paused" {
        return Err(StatusCode::CONFLICT);
    }

    let now_ts = Local::now().timestamp();
    timer.state = "running".into();
    if let Some(last) = timer.breaks.last_mut() {
        if last.end_ts == 0 {
            last.end_ts = now_ts;
        }
    }
    state::update_active(&conn, &timer);

    let updated = state::get_active_by_id(&conn, id).unwrap();
    drop(conn);
    bump_clients();
    Ok(Json(timer_to_response(&updated)))
}

// --- Entry handlers ---

pub async fn get_entries(
    State(db): State<Db>,
    Query(q): Query<EntriesQuery>,
) -> Json<Vec<EntryResponse>> {
    let conn = db.lock().unwrap();
    let since_ts = if q.today.unwrap_or(false) {
        Some(
            Local::now()
                .date_naive()
                .and_hms_opt(0, 0, 0)
                .unwrap()
                .and_local_timezone(Local)
                .unwrap()
                .timestamp(),
        )
    } else if q.week.unwrap_or(false) {
        Some((Local::now() - chrono::Duration::days(7)).timestamp())
    } else {
        None
    };
    let entries = state::query_entries(&conn, since_ts);
    Json(entries.iter().map(entry_to_response).collect())
}

pub async fn get_entry(
    State(db): State<Db>,
    Path(id): Path<u32>,
) -> Result<Json<EntryResponse>, StatusCode> {
    let conn = db.lock().unwrap();
    let entry = state::get_entry_by_id(&conn, id).ok_or(StatusCode::NOT_FOUND)?;
    Ok(Json(entry_to_response(&entry)))
}

pub async fn edit_entry(
    State(db): State<Db>,
    Path(id): Path<u32>,
    Json(req): Json<EditEntryRequest>,
) -> Result<Json<EntryResponse>, StatusCode> {
    let conn = db.lock().unwrap();
    let mut entry = state::get_entry_by_id(&conn, id).ok_or(StatusCode::NOT_FOUND)?;

    if let Some(n) = req.name { entry.name = n; }
    if let Some(c) = req.category { entry.category = c; }
    if let Some(m) = req.add_mins { entry.active_secs += (m * 60) as i64; }
    if let Some(m) = req.sub_mins { entry.active_secs = (entry.active_secs - (m * 60) as i64).max(0); }

    state::update_entry(&conn, &entry);
    let updated = state::get_entry_by_id(&conn, id).unwrap();
    drop(conn);
    bump_clients();
    Ok(Json(entry_to_response(&updated)))
}

pub async fn delete_entry(
    State(db): State<Db>,
    Path(id): Path<u32>,
) -> StatusCode {
    let conn = db.lock().unwrap();
    let ok = state::delete_entry(&conn, id);
    drop(conn);
    if ok {
        bump_clients();
        StatusCode::NO_CONTENT
    } else {
        StatusCode::NOT_FOUND
    }
}

// --- Todo handlers ---

pub async fn get_todos(State(db): State<Db>) -> Json<Vec<TodoResponse>> {
    let conn = db.lock().unwrap();
    let todos = state::list_todos(&conn);
    Json(todos.iter().map(|t| todo_to_response(&conn, t)).collect())
}

pub async fn add_todo(
    State(db): State<Db>,
    Json(req): Json<AddTodoRequest>,
) -> (StatusCode, Json<TodoResponse>) {
    let conn = db.lock().unwrap();
    let now_ts = Local::now().timestamp();
    let id = state::add_todo(&conn, &req.text, now_ts);
    let todo = state::get_todo_by_id(&conn, id).unwrap();
    let response = todo_to_response(&conn, &todo);
    drop(conn);
    bump_clients();
    (StatusCode::CREATED, Json(response))
}

pub async fn edit_todo(
    State(db): State<Db>,
    Path(id): Path<u32>,
    Json(req): Json<EditTodoRequest>,
) -> Result<Json<TodoResponse>, StatusCode> {
    let conn = db.lock().unwrap();
    let todo = state::get_todo_by_id(&conn, id).ok_or(StatusCode::NOT_FOUND)?;

    if let Some(text) = &req.text {
        state::edit_todo(&conn, id, text);
    }
    if let Some(done) = req.done {
        if done && !todo.done {
            state::mark_todo_done(&conn, id);
        } else if !done && todo.done {
            state::unmark_todo_done(&conn, id);
        }
    }

    let updated = state::get_todo_by_id(&conn, id).unwrap();
    let response = todo_to_response(&conn, &updated);
    drop(conn);
    bump_clients();
    Ok(Json(response))
}

pub async fn delete_todo(
    State(db): State<Db>,
    Path(id): Path<u32>,
) -> StatusCode {
    let conn = db.lock().unwrap();
    let ok = state::remove_todo(&conn, id);
    drop(conn);
    if ok {
        bump_clients();
        StatusCode::NO_CONTENT
    } else {
        StatusCode::NOT_FOUND
    }
}

// --- Suggestions ---

pub async fn get_suggestions(State(db): State<Db>) -> Json<SuggestionsResponse> {
    let conn = db.lock().unwrap();
    let recent = state::recent_todos(&conn, 8);
    let recent_todos: Vec<TodoResponse> =
        recent.iter().map(|t| todo_to_response(&conn, t)).collect();
    Json(SuggestionsResponse {
        names: state::distinct_names(&conn),
        categories: state::distinct_categories(&conn),
        recent_todos,
    })
}

// --- Analytics ---

pub async fn get_analytics(
    State(db): State<Db>,
    Query(q): Query<AnalyticsQuery>,
) -> Json<AnalyticsResponse> {
    let range = q.range.unwrap_or_else(|| "week".to_string());
    let days: i64 = match range.as_str() {
        "month" => 30,
        "year" => 365,
        _ => 7,
    };
    let since_ts = (Local::now() - chrono::Duration::days(days)).timestamp();

    let conn = db.lock().unwrap();
    let (total, by_day_raw, by_cat_raw, streak) = state::aggregate_entries(&conn, since_ts);

    Json(AnalyticsResponse {
        range,
        total_secs: total,
        by_day: by_day_raw
            .into_iter()
            .map(|(date, secs)| DayBucket { date, secs })
            .collect(),
        by_category: by_cat_raw
            .into_iter()
            .map(|(name, secs)| CategoryBucket { name, secs })
            .collect(),
        streak_days: streak,
    })
}

// --- Devices ---

pub async fn get_devices(State(db): State<Db>) -> Json<serde_json::Value> {
    let conn = db.lock().unwrap();

    // Sync clients
    let mut stmt = conn.prepare("SELECT client_id, last_sync_ts FROM sync_clients ORDER BY last_sync_ts DESC").unwrap();
    let clients: Vec<serde_json::Value> = stmt
        .query_map([], |row| {
            let client_id: String = row.get(0)?;
            let last_sync: i64 = row.get(1)?;
            Ok(serde_json::json!({"client_id": client_id, "last_sync": last_sync}))
        })
        .unwrap()
        .filter_map(|r| r.ok())
        .collect();

    // BLE connected devices
    #[cfg(feature = "ble")]
    let ble_devices: serde_json::Value = {
        let json_str = crate::ble::connected_devices_json();
        serde_json::from_str(&json_str).unwrap_or(serde_json::json!([]))
    };
    #[cfg(not(feature = "ble"))]
    let ble_devices = serde_json::json!([]);

    Json(serde_json::json!({
        "ble_connected": ble_devices,
        "sync_clients": clients
    }))
}

// --- Health ---

pub async fn ping() -> Json<serde_json::Value> {
    Json(serde_json::json!({ "ok": true }))
}
