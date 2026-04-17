use axum::routing::{delete, get, patch, post};
use axum::Router;
use rusqlite::Connection;
use std::sync::{Arc, Mutex};
use tower_http::cors::CorsLayer;

use crate::api;
use crate::sync;

pub async fn run(conn: Connection, port: u16) {
    let db: api::Db = Arc::new(Mutex::new(conn));

    let app = Router::new()
        .route("/api/v1/ping", get(api::ping))
        // Timers
        .route("/api/v1/status", get(api::get_status))
        .route("/api/v1/timers/start", post(api::start_timer))
        .route("/api/v1/timers/{id}/stop", post(api::stop_timer))
        .route("/api/v1/timers/{id}/pause", post(api::pause_timer))
        .route("/api/v1/timers/{id}/resume", post(api::resume_timer))
        // Suggestions
        .route("/api/v1/suggestions", get(api::get_suggestions))
        // Analytics
        .route("/api/v1/analytics", get(api::get_analytics))
        // Entries
        .route("/api/v1/entries", get(api::get_entries))
        .route("/api/v1/entries/{id}", get(api::get_entry))
        .route("/api/v1/entries/{id}", patch(api::edit_entry))
        .route("/api/v1/entries/{id}", delete(api::delete_entry))
        // Todos
        .route("/api/v1/todos", get(api::get_todos))
        .route("/api/v1/todos", post(api::add_todo))
        .route("/api/v1/todos/{id}", patch(api::edit_todo))
        .route("/api/v1/todos/{id}", delete(api::delete_todo))
        // Devices
        .route("/api/v1/devices", get(api::get_devices))
        // Sync
        .route("/api/v1/sync", post(sync::handle_sync))
        .layer(CorsLayer::permissive())
        .with_state(db);

    let addr = format!("0.0.0.0:{port}");
    println!("tl serve listening on {addr}");

    let listener = tokio::net::TcpListener::bind(&addr).await.unwrap();
    axum::serve(listener, app).await.unwrap();
}
