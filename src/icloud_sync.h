#ifndef ICLOUD_SYNC_H
#define ICLOUD_SYNC_H

#include <stdint.h>

// Initialize CloudKit with the container identifier.
// Returns 1 if iCloud is available, 0 otherwise.
int icloud_init(void);

// Push a JSON payload to CloudKit. The JSON is an array of records:
// [{"type":"ActiveTimer|TimeEntry|TodoItem","id":N,"fields":{...}}, ...]
void icloud_push(const char *records_json);

// Push deletions to CloudKit. JSON array:
// [{"type":"ActiveTimer|TimeEntry|TodoItem","id":N}, ...]
void icloud_delete(const char *deletions_json);

// Fetch changes from CloudKit since last sync.
// Returns a JSON string (caller must free with icloud_free).
// Format: {"timers":[...],"entries":[...],"todos":[...],"deletions":[...]}
const char* icloud_fetch_changes(void);

// Free a string returned by icloud_fetch_changes.
void icloud_free(const char *ptr);

#endif
