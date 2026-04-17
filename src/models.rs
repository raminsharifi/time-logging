use serde::{Deserialize, Serialize};

#[derive(Debug, Serialize, Deserialize)]
pub struct BreakPeriod {
    pub start_ts: i64,
    pub end_ts: i64,
}

#[derive(Debug, Serialize)]
pub struct TimerResponse {
    pub id: u32,
    pub name: String,
    pub category: String,
    pub started_at: i64,
    pub state: String,
    pub breaks: Vec<BreakPeriod>,
    pub todo_id: Option<u32>,
    pub last_modified: i64,
    pub active_secs: i64,
    pub break_secs: i64,
}

#[derive(Debug, Deserialize)]
pub struct StartTimerRequest {
    pub name: String,
    pub category: String,
    pub todo_id: Option<u32>,
}

#[derive(Debug, Serialize)]
pub struct EntryResponse {
    pub id: u32,
    pub name: String,
    pub category: String,
    pub started_at: i64,
    pub ended_at: i64,
    pub active_secs: i64,
    pub break_secs: i64,
    pub todo_id: Option<u32>,
    pub last_modified: i64,
}

#[derive(Debug, Deserialize)]
pub struct EditEntryRequest {
    pub name: Option<String>,
    pub category: Option<String>,
    pub add_mins: Option<u32>,
    pub sub_mins: Option<u32>,
}

#[derive(Debug, Serialize)]
pub struct TodoResponse {
    pub id: u32,
    pub text: String,
    pub done: bool,
    pub created_at: i64,
    pub last_modified: i64,
    pub total_secs: i64,
}

#[derive(Debug, Deserialize)]
pub struct AddTodoRequest {
    pub text: String,
}

#[derive(Debug, Deserialize)]
pub struct EditTodoRequest {
    pub text: Option<String>,
    pub done: Option<bool>,
}

#[derive(Debug, Deserialize)]
pub struct EntriesQuery {
    pub today: Option<bool>,
    pub week: Option<bool>,
}

#[derive(Debug, Serialize)]
pub struct SuggestionsResponse {
    pub names: Vec<String>,
    pub categories: Vec<String>,
    pub recent_todos: Vec<TodoResponse>,
}

// --- Analytics ---

#[derive(Debug, Deserialize)]
pub struct AnalyticsQuery {
    pub range: Option<String>, // "week" | "month" | "year"
}

#[derive(Debug, Serialize)]
pub struct DayBucket {
    pub date: String, // yyyy-MM-dd
    pub secs: i64,
}

#[derive(Debug, Serialize)]
pub struct CategoryBucket {
    pub name: String,
    pub secs: i64,
}

#[derive(Debug, Serialize)]
pub struct AnalyticsResponse {
    pub range: String,
    pub total_secs: i64,
    pub by_day: Vec<DayBucket>,
    pub by_category: Vec<CategoryBucket>,
    pub streak_days: u32,
}

// --- Sync types ---

#[derive(Debug, Serialize, Deserialize)]
pub struct SyncTimerData {
    pub server_id: Option<u32>,
    pub local_id: String,
    pub name: String,
    pub category: String,
    pub started_at: i64,
    pub state: String,
    pub breaks: Vec<BreakPeriod>,
    pub todo_id: Option<u32>,
    pub last_modified: i64,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct SyncEntryData {
    pub server_id: Option<u32>,
    pub local_id: String,
    pub name: String,
    pub category: String,
    pub started_at: i64,
    pub ended_at: i64,
    pub active_secs: i64,
    pub breaks: Vec<BreakPeriod>,
    pub todo_id: Option<u32>,
    pub last_modified: i64,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct SyncTodoData {
    pub server_id: Option<u32>,
    pub local_id: String,
    pub text: String,
    pub done: bool,
    pub created_at: i64,
    pub last_modified: i64,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct SyncDeletion {
    pub table_name: String,
    pub record_id: u32,
    pub deleted_at: i64,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct SyncChanges {
    #[serde(default)]
    pub active_timers: Vec<SyncTimerData>,
    #[serde(default)]
    pub time_entries: Vec<SyncEntryData>,
    #[serde(default)]
    pub todos: Vec<SyncTodoData>,
    #[serde(default)]
    pub deletions: Vec<SyncDeletion>,
}

#[derive(Debug, Deserialize)]
pub struct SyncRequest {
    pub client_id: String,
    pub last_sync_ts: i64,
    pub changes: SyncChanges,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct IdMapping {
    pub table_name: String,
    pub local_id: String,
    pub server_id: u32,
}

#[derive(Debug, Serialize)]
pub struct SyncResponse {
    pub server_changes: SyncChanges,
    pub new_sync_ts: i64,
    pub id_mappings: Vec<IdMapping>,
}
