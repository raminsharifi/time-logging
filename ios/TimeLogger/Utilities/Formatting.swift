import Foundation

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

func formatDurationShort(_ totalSeconds: Int64) -> String {
    let h = totalSeconds / 3600
    let m = (totalSeconds % 3600) / 60
    let s = totalSeconds % 60
    if h > 0 {
        return String(format: "%d:%02d:%02d", h, m, s)
    } else {
        return String(format: "%d:%02d", m, s)
    }
}
