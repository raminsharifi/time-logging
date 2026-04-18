import Foundation
import EventKit

/// A single suggestion derived from the user's Calendar — either an event
/// happening right now or the next one starting within the look-ahead window.
struct CalendarSuggestion: Equatable {
    let title: String
    let startDate: Date
    let endDate: Date
    let isCurrent: Bool
    let calendarTitle: String
}

/// Thin EventKit wrapper. Uses the iOS 17 / macOS 14 full-access API and
/// returns a single best-guess suggestion the UI can prefill from.
@MainActor
enum CalendarService {
    private static let store = EKEventStore()

    /// Current authorization for events. Does not prompt.
    static var authorization: EKAuthorizationStatus {
        EKEventStore.authorizationStatus(for: .event)
    }

    /// Prompt the user for full access. Safe to call repeatedly — the system
    /// remembers the decision after the first prompt.
    static func requestAccess() async -> Bool {
        (try? await store.requestFullAccessToEvents()) ?? false
    }

    /// Return the event happening now, or the next one within `lookAhead`.
    /// `nil` if nothing relevant is scheduled or access isn't granted.
    static func nextSuggestion(lookAhead: TimeInterval = 2 * 3600) -> CalendarSuggestion? {
        guard authorization == .fullAccess else { return nil }
        let now = Date()
        // Look back as well as forward so an event that's already started but
        // still running shows up as "NOW".
        let predicate = store.predicateForEvents(
            withStart: now.addingTimeInterval(-lookAhead),
            end: now.addingTimeInterval(lookAhead),
            calendars: nil
        )
        let events = store.events(matching: predicate)
            .filter { !$0.isAllDay && $0.endDate > now }

        if let current = events.first(where: { $0.startDate <= now && $0.endDate > now }) {
            return suggestion(from: current, isCurrent: true)
        }
        if let next = events
            .filter({ $0.startDate > now })
            .min(by: { $0.startDate < $1.startDate })
        {
            return suggestion(from: next, isCurrent: false)
        }
        return nil
    }

    private static func suggestion(from event: EKEvent, isCurrent: Bool) -> CalendarSuggestion {
        CalendarSuggestion(
            title: event.title ?? "Event",
            startDate: event.startDate,
            endDate: event.endDate,
            isCurrent: isCurrent,
            calendarTitle: event.calendar?.title ?? ""
        )
    }
}

// MARK: - Todo matching

/// Fuzzy-matches a calendar event title against a list of todos and returns
/// the best candidate above a confidence threshold.
enum TodoMatcher {
    /// Returns the id of the best-matching todo for `eventTitle`, or nil if
    /// no candidate scores above `threshold` (0…1, Jaccard on word tokens).
    /// Generic over id type so iOS/macOS (Int server ids) and watchOS
    /// (UUID local ids) can share the same matcher.
    static func bestMatchId<ID: Hashable>(
        for eventTitle: String,
        in todos: [(id: ID, text: String)],
        threshold: Double = 0.25
    ) -> ID? {
        let eventTokens = tokens(from: eventTitle)
        guard !eventTokens.isEmpty else { return nil }
        var best: (id: ID, score: Double)?
        for todo in todos {
            let todoTokens = tokens(from: todo.text)
            guard !todoTokens.isEmpty else { continue }
            let intersection = eventTokens.intersection(todoTokens).count
            guard intersection > 0 else { continue }
            let union = eventTokens.union(todoTokens).count
            let score = Double(intersection) / Double(union)
            if score >= threshold, best == nil || score > best!.score {
                best = (todo.id, score)
            }
        }
        return best?.id
    }

    private static let stopwords: Set<String> = [
        "the", "a", "an", "and", "or", "to", "for", "of", "on", "in", "at",
        "with", "w/", "re", "meeting", "call", "sync",
    ]

    private static func tokens(from s: String) -> Set<String> {
        let lowered = s.lowercased()
        let allowed = CharacterSet.alphanumerics
        let parts = lowered.unicodeScalars
            .split { !allowed.contains($0) }
            .map { String($0) }
            .filter { $0.count >= 3 && !stopwords.contains($0) }
        return Set(parts)
    }
}

// MARK: - Formatting

extension CalendarSuggestion {
    /// Short label shown next to the event title, e.g. "NOW" or "IN 15M".
    var relativeLabel: String {
        if isCurrent { return "NOW" }
        let mins = max(0, Int(startDate.timeIntervalSince(Date()) / 60))
        if mins < 60 { return "IN \(mins)M" }
        let hrs = mins / 60
        let rem = mins % 60
        return rem == 0 ? "IN \(hrs)H" : "IN \(hrs)H \(rem)M"
    }
}
