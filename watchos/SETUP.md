# WatchOS App — Xcode Setup

## Create the Xcode Project

1. Open Xcode 16+
2. File > New > Project
3. Select **watchOS** tab > **App**
4. Product Name: `TimeLogger`
5. Team: your Apple Developer account
6. Organization Identifier: `com.raminsharifi`
7. Interface: **SwiftUI**
8. Storage: **SwiftData**
9. **Uncheck** "Include Companion iPhone App"
10. Click Create, save inside `watchos/` directory

## Add Source Files

After creating the project, **delete** the auto-generated files (ContentView.swift, TimeLoggerApp.swift, Item.swift) and add the files from this directory:

### Watch App Target
- `TimeLoggerApp.swift`
- `ContentView.swift`
- `Models/` — all 6 files (ActiveTimerLocal, BreakPeriod, TimeEntryLocal, TodoItemLocal, PendingDeletion, SyncMetadata)
- `Views/` — all 5 files (TimerView, TimerControlSheet, TodoListView, LogSummaryView, SettingsView)
- `Networking/` — all 3 files (APIClient, ServerDiscovery, SyncEngine)
- `Info.plist` — replace the generated one

### Widget Extension Target
1. File > New > Target > **Widget Extension**
2. Product Name: `TimeLoggerWidget`
3. Uncheck "Include Configuration App Intent"
4. Delete the generated Swift file
5. Add `TimeLoggerWidget/TimeLoggerWidget.swift`
6. Add the Models/ files to this target too (shared SwiftData models)

## Build Settings

- Deployment Target: **watchOS 10.0**
- Add `Network.framework` to both targets (for NWBrowser)

## Running

1. Start the server on your Mac: `tl serve`
2. Build and run on Watch simulator or device
3. The Watch will auto-discover the Mac via Bonjour
4. If discovery fails, go to Settings tab and enter Mac's IP manually
