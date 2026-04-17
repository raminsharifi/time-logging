# TimeLogger

A multi-device time tracker with native apps for iOS, macOS, watchOS, and a
Rust CLI/server. All clients sync to the same database over Wi-Fi (HTTP),
BLE, or iCloud.

## Architecture

```
                ┌────────────────────────────────────────┐
                │  Rust binary  `tl`                     │
                │  ─────────────                         │
                │  · CLI (start/stop/log/todo)           │
                │  · TUI dashboard                       │
                │  · HTTP server (axum, port 9746)       │
                │  · BLE peripheral (optional)           │
                │  · iCloud/CloudKit sync (optional)     │
                │  · SQLite (single source of truth)     │
                └────────────────────────────────────────┘
                                  ▲
              ┌───────────────────┼───────────────────┐
              │ Wi-Fi (mDNS)      │ BLE              │ iCloud
              │                   │                   │
        ┌─────┴─────┐       ┌─────┴─────┐       ┌─────┴─────┐
        │   iOS     │       │  watchOS  │       │   macOS   │
        │   app     │       │   app     │       │   app     │
        │ + widgets │       │ + widget  │       │ + menubar │
        └───────────┘       └───────────┘       └───────────┘
```

The Rust binary is the canonical server. All apps are clients that read and
write to it via REST. Apps maintain a local SwiftData cache so they remain
usable offline; changes are reconciled on next sync.

## Components

### Rust binary (`tl`)
- **CLI**: timer / log / todo subcommands.
- **TUI**: full-screen interactive dashboard (`tl ui`).
- **Server**: HTTP API on port 9746 with mDNS discovery (`_tl._tcp`).
- **Optional transports**: BLE peripheral (iPhone direct), iCloud (CloudKit).
- **Storage**: SQLite at `~/Library/Application Support/time-logging/data.db`
  (macOS) or `~/.config/time-logging/data.db` (Linux). CLI and server share
  the same DB.

### iOS app (`ios/`)
- iOS 17+, bundle id `com.raminsharifi.TimeLogger`.
- Tabs: Timers, Entries, Todos, Analytics, Settings.
- Home-screen widgets, Lock Screen widgets, Live Activities.
- Discovers the Rust server via Bonjour; falls back to BLE or iCloud.

### macOS app (`macos/`)
- macOS 14+, bundle id `com.raminsharifi.TimeLogger.mac`.
- Tabs: Timers, Entries, Todos, Analytics, Pomodoro, Devices.
- Menu-bar item with running-timer label and quick actions.
- Global hotkey support.

### watchOS app (`watchos/`)
- watchOS 11+, bundle id `com.raminsharifi.TimeLogger.watchkitapp`.
- Vertical-page tabs: Timer, Todos, Breaks, Log, Settings.
- Complications + watch widget.
- Connects via BLE (paired iPhone) or Wi-Fi to the Rust server.

## Quick start

### 1. Install the server

```sh
cargo install --path .
```

Default features (`serve`, `tui`) are enabled. To opt into BLE and iCloud:

```sh
cargo install --path . --features "ble,icloud"
```

Requires Rust 2024 edition and `protoc` (Protocol Buffers compiler).

### 2. Run the server

```sh
tl serve                  # HTTP only, port 9746
tl serve --port 8080
tl serve --ble --icloud   # all transports (requires features)
```

The server announces itself over mDNS so the iOS / watchOS / macOS apps find
it automatically when on the same Wi-Fi network.

### 3. Build and run an app

Each app uses [XcodeGen](https://github.com/yonaskolb/XcodeGen) to generate
its `.xcodeproj` from `project.yml`:

```sh
brew install xcodegen

cd ios     && xcodegen generate && open TimeLogger.xcodeproj
cd macos   && xcodegen generate && open TimeLoggerMac.xcodeproj
cd watchos && xcodegen generate && open TimeLogger.xcodeproj
```

See `watchos/SETUP.md` for watchOS pairing notes.

## CLI reference

### Timers

```sh
tl start                # Start a new timer (prompts for name & category)
tl stop                 # Stop the running timer and save to log
tl pause                # Pause the running timer
tl resume               # Resume a paused timer
tl switch               # Switch to a different paused timer
tl status               # Show all active timers (running & paused)
tl restart              # Restart your most recently stopped timer
tl pomodoro 25          # Start a blocking 25-minute Pomodoro
```

Starting a new timer while one is running prompts to pause the current one.

### Time log

```sh
tl log                          # All logged entries
tl log --today                  # Today only
tl log --week                   # Last 7 days
tl log rm 5                     # Delete entry #5
tl log edit 5 --name "New" --add 15
tl log edit 5 --sub 5
tl log export --week            # CSV export
```

### Todos

```sh
tl todo add Fix bug
tl todo list
tl todo done 3
tl todo undo 3
tl todo edit 3 "New text"
tl todo rm 3
```

### Server / TUI

```sh
tl serve [--port N] [--ble] [--icloud]
tl ui                   # Interactive dashboard
```

## HTTP API

Default base URL: `http://<host>:9746/api/v1/`

| Endpoint | Method | Purpose |
|---|---|---|
| `/ping` | GET | Health check |
| `/status` | GET | Active timers |
| `/timers/start` | POST | Create a timer |
| `/timers/{id}/pause` | POST | Pause |
| `/timers/{id}/resume` | POST | Resume |
| `/timers/{id}/stop` | POST | Stop and persist as entry |
| `/entries` | GET | List entries (`?today=true`, `?week=true`) |
| `/entries/{id}` | GET / PATCH / DELETE | Manage an entry |
| `/todos` | GET / POST | List / create |
| `/todos/{id}` | PATCH / DELETE | Update / remove |
| `/analytics` | GET | Aggregates (`?range=week\|month\|year`) |
| `/suggestions` | GET | Recent names, categories, todos |
| `/devices` | GET | BLE + sync clients |
| `/sync` | POST | Bidirectional sync (used by apps) |

## Sync model

Each client (app) keeps a local SwiftData store. On sync it sends
`{client_id, last_sync_ts, local_changes}` to `/sync`; the server merges by
`last_modified` timestamp, returns server-side changes plus id mappings,
and tracks tombstones for deletions.

Multi-device timer coordination: if a second device starts a timer while
another has one running, the server pauses the older one to keep state
coherent.

## Data storage

| Platform | Path |
|---|---|
| macOS / iOS server | `~/Library/Application Support/time-logging/data.db` |
| Linux | `~/.config/time-logging/data.db` |

Break periods are stored as protobuf-encoded blobs (see
`proto/time_logging.proto`).

## Building from source

### Rust

```sh
cargo build --release                                # default features
cargo build --release --features "ble,icloud"       # all transports
```

The binary lands at `target/release/tl`. The `build.rs` script compiles:
1. Protobuf via `prost-build`
2. Objective-C BLE peripheral (with `ble` feature)
3. Objective-C iCloud bridge (with `icloud` feature)

BLE and iCloud features only build on macOS (CoreBluetooth + CloudKit).

### Swift apps

Open the generated `.xcodeproj` in Xcode and build the desired scheme. Each
app shares an App Group (`group.com.raminsharifi.TimeLogger`) with its
widget extension for state hand-off.

## License

MIT — see [LICENSE](LICENSE).
