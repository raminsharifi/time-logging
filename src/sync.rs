use axum::extract::State;
use axum::Json;
use chrono::Local;

use crate::api::Db;
use crate::models::*;
use crate::state;
use crate::state::proto;

fn periods_to_breaks(periods: &[BreakPeriod]) -> Vec<proto::Break> {
    periods.iter().map(|p| proto::Break { start_ts: p.start_ts, end_ts: p.end_ts }).collect()
}

fn breaks_to_periods(breaks: &[proto::Break]) -> Vec<BreakPeriod> {
    breaks.iter().map(|b| BreakPeriod { start_ts: b.start_ts, end_ts: b.end_ts }).collect()
}

pub async fn handle_sync(
    State(db): State<Db>,
    Json(req): Json<SyncRequest>,
) -> Json<SyncResponse> {
    let conn = db.lock().unwrap();
    let now_ts = Local::now().timestamp();
    let client_last_sync = state::get_sync_ts(&conn, &req.client_id);
    let effective_since = client_last_sync.min(req.last_sync_ts);

    let mut id_mappings: Vec<IdMapping> = Vec::new();
    let mut updated_server_ids: Vec<(String, u32)> = Vec::new();

    // --- Apply Watch timer changes ---
    for wt in &req.changes.active_timers {
        if let Some(server_id) = wt.server_id {
            if let Some(existing) = state::get_active_by_id(&conn, server_id) {
                if wt.last_modified > existing.last_modified {
                    let timer = state::ActiveTimer {
                        id: Some(server_id),
                        name: wt.name.clone(),
                        category: wt.category.clone(),
                        started_at: wt.started_at,
                        state: wt.state.clone(),
                        breaks: periods_to_breaks(&wt.breaks),
                        todo_id: wt.todo_id,
                        last_modified: wt.last_modified,
                    };
                    state::upsert_active_timer(&conn, server_id, &timer);
                    updated_server_ids.push(("active_timers".into(), server_id));
                }
            }
        } else {
            let timer = state::ActiveTimer {
                id: None,
                name: wt.name.clone(),
                category: wt.category.clone(),
                started_at: wt.started_at,
                state: wt.state.clone(),
                breaks: periods_to_breaks(&wt.breaks),
                todo_id: wt.todo_id,
                last_modified: wt.last_modified,
            };
            let new_id = state::insert_active(&conn, &timer);
            id_mappings.push(IdMapping {
                table_name: "active_timers".into(),
                local_id: wt.local_id.clone(),
                server_id: new_id,
            });
            updated_server_ids.push(("active_timers".into(), new_id));
        }
    }

    // If Watch has a running timer, pause any conflicting Mac running timer
    let watch_has_running = req.changes.active_timers.iter().any(|t| t.state == "running");
    if watch_has_running {
        let all = state::get_all_active(&conn);
        let watch_running_ids: Vec<u32> = id_mappings.iter()
            .filter(|m| m.table_name == "active_timers")
            .map(|m| m.server_id)
            .chain(
                req.changes.active_timers.iter()
                    .filter(|t| t.state == "running")
                    .filter_map(|t| t.server_id)
            )
            .collect();

        for t in &all {
            let tid = t.id.unwrap();
            if t.state == "running" && !watch_running_ids.contains(&tid) {
                let mut paused = state::ActiveTimer {
                    id: t.id,
                    name: t.name.clone(),
                    category: t.category.clone(),
                    started_at: t.started_at,
                    state: "paused".into(),
                    breaks: t.breaks.clone(),
                    todo_id: t.todo_id,
                    last_modified: 0,
                };
                paused.breaks.push(proto::Break { start_ts: now_ts, end_ts: 0 });
                state::update_active(&conn, &paused);
            }
        }
    }

    // --- Apply Watch entry changes ---
    for we in &req.changes.time_entries {
        if let Some(server_id) = we.server_id {
            if let Some(existing) = state::get_entry_by_id(&conn, server_id) {
                if we.last_modified > existing.last_modified {
                    let entry = state::TimeEntry {
                        id: server_id,
                        name: we.name.clone(),
                        category: we.category.clone(),
                        started_at: we.started_at,
                        ended_at: we.ended_at,
                        active_secs: we.active_secs,
                        breaks: periods_to_breaks(&we.breaks),
                        todo_id: we.todo_id,
                        last_modified: we.last_modified,
                    };
                    state::upsert_entry(&conn, server_id, &entry);
                    updated_server_ids.push(("time_entries".into(), server_id));
                }
            }
        } else {
            let entry = state::TimeEntry {
                id: 0,
                name: we.name.clone(),
                category: we.category.clone(),
                started_at: we.started_at,
                ended_at: we.ended_at,
                active_secs: we.active_secs,
                breaks: periods_to_breaks(&we.breaks),
                todo_id: we.todo_id,
                last_modified: we.last_modified,
            };
            state::insert_entry(&conn, &entry);
            let last = state::get_last_entry(&conn).unwrap();
            id_mappings.push(IdMapping {
                table_name: "time_entries".into(),
                local_id: we.local_id.clone(),
                server_id: last.id,
            });
            updated_server_ids.push(("time_entries".into(), last.id));
        }
    }

    // --- Apply Watch todo changes ---
    for wt in &req.changes.todos {
        if let Some(server_id) = wt.server_id {
            if let Some(existing) = state::get_todo_by_id(&conn, server_id) {
                if wt.last_modified > existing.last_modified {
                    let todo = state::TodoItem {
                        id: server_id,
                        text: wt.text.clone(),
                        done: wt.done,
                        created_at: wt.created_at,
                        last_modified: wt.last_modified,
                    };
                    state::upsert_todo(&conn, server_id, &todo);
                    updated_server_ids.push(("todos".into(), server_id));
                }
            }
        } else {
            let id = state::add_todo(&conn, &wt.text, wt.created_at);
            if wt.done {
                state::mark_todo_done(&conn, id);
            }
            id_mappings.push(IdMapping {
                table_name: "todos".into(),
                local_id: wt.local_id.clone(),
                server_id: id,
            });
            updated_server_ids.push(("todos".into(), id));
        }
    }

    // --- Apply Watch deletions ---
    for del in &req.changes.deletions {
        match del.table_name.as_str() {
            "active_timers" => {
                if let Some(existing) = state::get_active_by_id(&conn, del.record_id) {
                    if del.deleted_at > existing.last_modified {
                        state::clear_active(&conn, del.record_id);
                    }
                }
            }
            "time_entries" => {
                if let Some(existing) = state::get_entry_by_id(&conn, del.record_id) {
                    if del.deleted_at > existing.last_modified {
                        state::delete_entry(&conn, del.record_id);
                    }
                }
            }
            "todos" => {
                if let Some(existing) = state::get_todo_by_id(&conn, del.record_id) {
                    if del.deleted_at > existing.last_modified {
                        state::remove_todo(&conn, del.record_id);
                    }
                }
            }
            _ => {}
        }
    }

    // --- Gather Mac changes to send to Watch ---
    let server_timers: Vec<SyncTimerData> = state::query_modified_timers(&conn, effective_since)
        .into_iter()
        .filter(|t| !updated_server_ids.contains(&("active_timers".into(), t.id.unwrap())))
        .map(|t| SyncTimerData {
            server_id: t.id,
            local_id: String::new(),
            name: t.name,
            category: t.category,
            started_at: t.started_at,
            state: t.state,
            breaks: breaks_to_periods(&t.breaks),
            todo_id: t.todo_id,
            last_modified: t.last_modified,
        })
        .collect();

    let server_entries: Vec<SyncEntryData> = state::query_modified_entries(&conn, effective_since)
        .into_iter()
        .filter(|e| !updated_server_ids.contains(&("time_entries".into(), e.id)))
        .map(|e| SyncEntryData {
            server_id: Some(e.id),
            local_id: String::new(),
            name: e.name,
            category: e.category,
            started_at: e.started_at,
            ended_at: e.ended_at,
            active_secs: e.active_secs,
            breaks: breaks_to_periods(&e.breaks),
            todo_id: e.todo_id,
            last_modified: e.last_modified,
        })
        .collect();

    let server_todos: Vec<SyncTodoData> = state::query_modified_todos(&conn, effective_since)
        .into_iter()
        .filter(|t| !updated_server_ids.contains(&("todos".into(), t.id)))
        .map(|t| SyncTodoData {
            server_id: Some(t.id),
            local_id: String::new(),
            text: t.text,
            done: t.done,
            created_at: t.created_at,
            last_modified: t.last_modified,
        })
        .collect();

    let server_deletions: Vec<SyncDeletion> = state::query_deletions(&conn, effective_since)
        .into_iter()
        .map(|d| SyncDeletion {
            table_name: d.table_name,
            record_id: d.record_id,
            deleted_at: d.deleted_at,
        })
        .collect();

    state::set_sync_ts(&conn, &req.client_id, now_ts);

    // If the client contributed changes, bump every other connected central
    // so they pull the fresh state without waiting for their own poll.
    let pushed_anything = !req.changes.active_timers.is_empty()
        || !req.changes.time_entries.is_empty()
        || !req.changes.todos.is_empty()
        || !req.changes.deletions.is_empty();
    drop(conn);
    if pushed_anything {
        #[cfg(feature = "ble")]
        crate::ble::notify_change();
    }

    Json(SyncResponse {
        server_changes: SyncChanges {
            active_timers: server_timers,
            time_entries: server_entries,
            todos: server_todos,
            deletions: server_deletions,
        },
        new_sync_ts: now_ts,
        id_mappings,
    })
}
