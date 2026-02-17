# tl — Time Logging & Todo CLI

A lightweight command-line tool for tracking time and managing todos. Built with Rust.

## Features

- **Timer management** — start, stop, pause, resume, and switch between multiple concurrent timers
- **Time log** — view logged entries with filtering (today, last 7 days) and totals
- **Todo list** — add, complete, and remove tasks
- **Persistent storage** — SQLite database stored in your config directory
- **Break tracking** — automatic break duration tracking with protobuf serialization

## Installation

```sh
cargo install --path .
```

## Usage

### Timers

```sh
tl start              # Start a new timer (prompts for name & category)
tl stop               # Stop the running timer and save to log
tl pause              # Pause the running timer
tl resume             # Resume a paused timer
tl switch             # Switch to a different paused timer
tl status             # Show all active timers (running & paused)
```

Starting a new timer while one is already running will offer to pause the current one.

### Time Log

```sh
tl log                # Show all logged entries
tl log --today        # Show today's entries only
tl log --week         # Show entries from the last 7 days
tl log rm 5           # Delete log entry #5
```

### Todos

```sh
tl todo add Fix bug   # Add a todo item
tl todo list          # List all todos
tl todo done 3        # Mark todo #3 as done
tl todo rm 3          # Remove todo #3
```

### Typical Workflow

```
tl start              → Start "coding" [work]
tl start              → Already running — pause it, start "review" [work]
tl switch             → Switch back to "coding"
tl stop               → Stop "coding", saves to log
tl switch             → Switch to "review"
tl stop               → Stop "review", saves to log
tl log --today        → See what you did today
```

## Data Storage

Data is stored in a SQLite database at:

| OS    | Path                                          |
|-------|-----------------------------------------------|
| macOS | `~/Library/Application Support/time-logging/data.db` |
| Linux | `~/.config/time-logging/data.db`              |

## Building from Source

Requires Rust 2024 edition and `protoc` (Protocol Buffers compiler).

```sh
cargo build --release
```

The binary will be at `target/release/tl`.
