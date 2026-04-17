import Foundation
import SwiftUI

// MARK: - API Responses

struct TimerResponse: Codable, Identifiable, Equatable {
    let id: Int
    let name: String
    let category: String
    let started_at: Int64
    let state: String
    let breaks: [BreakPeriodDTO]
    let todo_id: Int?
    let last_modified: Int64
    let active_secs: Int64
    let break_secs: Int64

    var isRunning: Bool { state == "running" }
    var isPaused: Bool { state == "paused" }
}

struct BreakPeriodDTO: Codable, Equatable {
    let start_ts: Int64
    let end_ts: Int64
}

struct EntryResponse: Codable, Identifiable {
    let id: Int
    let name: String
    let category: String
    let started_at: Int64
    let ended_at: Int64
    let active_secs: Int64
    let break_secs: Int64
    let todo_id: Int?
    let last_modified: Int64
}

struct TodoResponse: Codable, Identifiable {
    let id: Int
    let text: String
    let done: Bool
    let created_at: Int64
    let last_modified: Int64
    let total_secs: Int64
}

struct SuggestionsResponse: Codable {
    let names: [String]
    let categories: [String]
}

struct DevicesResponse: Codable {
    let ble_connected: [BLEDevice]
    let sync_clients: [SyncClient]
}

struct BLEDevice: Codable, Identifiable {
    let identifier: String
    let name: String
    let connected_at: Int64

    var id: String { identifier }
}

struct SyncClient: Codable, Identifiable {
    let client_id: String
    let last_sync: Int64

    var id: String { client_id }
}

// MARK: - Request Bodies

struct StartTimerRequest: Codable {
    let name: String
    let category: String
    let todo_id: Int?
}

struct EditEntryRequest: Codable {
    let name: String?
    let category: String?
    let add_mins: Int?
    let sub_mins: Int?
}

struct AddTodoRequest: Codable {
    let text: String
}

struct EditTodoRequest: Codable {
    let text: String?
    let done: Bool?
}

// MARK: - Navigation

enum SidebarItem: String, CaseIterable, Identifiable {
    case timers = "Timers"
    case log = "Log"
    case analytics = "Analytics"
    case todos = "Todos"
    case pomodoro = "Pomodoro"
    case devices = "Devices"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .timers: "timer"
        case .log: "clock.arrow.circlepath"
        case .analytics: "chart.bar.xaxis"
        case .todos: "checklist"
        case .pomodoro: "hourglass"
        case .devices: "network"
        }
    }

    var tint: Color {
        switch self {
        case .timers: TL.Palette.emerald
        case .log: TL.Palette.citrine
        case .analytics: TL.Palette.iris
        case .todos: TL.Palette.sky
        case .pomodoro: TL.Palette.ember
        case .devices: TL.Palette.mist
        }
    }
}

// MARK: - Formatting

func formatDuration(_ totalSeconds: Int64) -> String {
    let h = totalSeconds / 3600
    let m = (totalSeconds % 3600) / 60
    let s = totalSeconds % 60
    if h > 0 {
        return String(format: "%dh %02dm %02ds", h, m, s)
    } else if m > 0 {
        return String(format: "%dm %02ds", m, s)
    } else {
        return String(format: "%ds", s)
    }
}

func formatTimestamp(_ ts: Int64) -> String {
    let date = Date(timeIntervalSince1970: TimeInterval(ts))
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter.string(from: date)
}

func formatDateShort(_ ts: Int64) -> String {
    let date = Date(timeIntervalSince1970: TimeInterval(ts))
    let formatter = DateFormatter()
    formatter.dateStyle = .short
    formatter.timeStyle = .short
    return formatter.string(from: date)
}

func formatRelative(_ ts: Int64) -> String {
    let date = Date(timeIntervalSince1970: TimeInterval(ts))
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .abbreviated
    return formatter.localizedString(for: date, relativeTo: Date())
}
