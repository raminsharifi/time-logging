mod state;
mod timer;
mod todo;

#[cfg(feature = "tui")]
mod tui;

#[cfg(feature = "serve")]
mod api;
#[cfg(feature = "serve")]
mod mdns;
#[cfg(feature = "serve")]
mod models;
#[cfg(feature = "serve")]
mod server;
#[cfg(feature = "serve")]
mod sync;
#[cfg(feature = "ble")]
mod ble;
#[cfg(feature = "icloud")]
mod icloud;

use clap::{Parser, Subcommand};
use state::open_db;

#[derive(Parser)]
#[command(
    name = "tl",
    about = "Time logging & todo CLI",
    after_help = "\
EXAMPLES:
  tl start              Start a new timer (prompts for name, category & todo link)
  tl stop               Stop the running timer and save to log
  tl pause              Pause the running timer
  tl resume             Resume a paused timer
  tl switch             Switch to a different paused timer
  tl status             Show all active timers with linked todos
  tl log                Show all logged time entries
  tl log --today        Show today's entries only
  tl log --week         Show entries from the last 7 days
  tl log rm 5           Delete log entry #5
  tl todo add Fix bug   Add a todo item
  tl todo list          List all todos with tracked time
  tl todo done 3        Mark todo #3 as done
  tl todo rm 3          Remove todo #3

WORKFLOW:
  tl todo add Write tests           Create a todo
  tl start                          Start a timer and link it to the todo
  tl pause                          Take a break
  tl resume                         Continue working
  tl stop                           Stop timer — offers to mark todo as done
  tl todo list                      See todos with total time tracked
  tl log --today                    See what you did today"
)]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// Start a new timer (can link to a todo; pauses current if running)
    #[command(after_help = "\
EXAMPLES:
  tl start       Prompts for name, category, and optional todo link
                 If a timer is already running, asks to pause it first")]
    Start,

    /// Stop the running timer, save to log, and optionally complete linked todo
    #[command(after_help = "\
EXAMPLES:
  tl stop        Stops the running timer and records the time entry
                 If linked to a todo, offers to mark it as done")]
    Stop,

    /// Pause the running timer (take a break)
    #[command(after_help = "\
EXAMPLES:
  tl pause       Pauses the running timer — break time starts counting")]
    Pause,

    /// Resume a paused timer
    #[command(after_help = "\
EXAMPLES:
  tl resume      If one paused timer, resumes it
                 If multiple, lets you pick which one")]
    Resume,

    /// Start a new timer using the details of the most recently stopped timer
    #[command(after_help = "\
EXAMPLES:
  tl restart     Automatically starts a timer with the name, category, and todo
                 link of your last completed activity")]
    Restart,

    /// Start a blocking Pomodoro timer
    #[command(after_help = "\
EXAMPLES:
  tl pomodoro 25     Start a 25-minute timer that blocks the terminal,
                     shows remaining time, auto-stops, and sends a notification.")]
    Pomodoro {
        /// Duration in minutes (default 25)
        #[arg(default_value_t = 25)]
        minutes: u32,
    },

    /// Show all active timers (running and paused)
    #[command(after_help = "\
EXAMPLES:
  tl status      Shows each active timer with state, active time, breaks,
                 and linked todo")]
    Status,

    /// Switch to a different paused timer (pauses the current one)
    #[command(after_help = "\
EXAMPLES:
  tl switch      Lists paused timers and lets you pick one to resume
                 The currently running timer gets paused automatically")]
    Switch,

    /// Show or manage time log entries
    #[command(after_help = "\
EXAMPLES:
  tl log             Show all log entries
  tl log --today     Show only today's entries
  tl log --week      Show entries from the last 7 days
  tl log rm 5        Delete log entry #5")]
    Log {
        #[command(subcommand)]
        action: Option<LogAction>,
        /// Show only today's entries
        #[arg(long)]
        today: bool,
        /// Show entries from the last 7 days
        #[arg(long)]
        week: bool,
    },

    /// Start the REST API server for Watch app sync
    #[cfg(feature = "serve")]
    #[command(after_help = "\
EXAMPLES:
  tl serve             Start API server on port 9746
  tl serve --port 8080 Start on a custom port")]
    Serve {
        /// Port to listen on
        #[arg(long, default_value_t = 9746)]
        port: u16,
        /// Enable BLE peripheral for iPhone sync
        #[cfg(feature = "ble")]
        #[arg(long)]
        ble: bool,
        /// Enable iCloud sync
        #[cfg(feature = "icloud")]
        #[arg(long)]
        icloud: bool,
    },

    /// Open the interactive TUI dashboard
    #[cfg(feature = "tui")]
    Ui,

    /// Manage todo list
    #[command(after_help = "\
EXAMPLES:
  tl todo add Fix the login bug    Add a new todo
  tl todo list                     List all todos with tracked time
  tl todo done 3                   Mark todo #3 as done
  tl todo rm 3                     Remove todo #3")]
    Todo {
        #[command(subcommand)]
        action: TodoAction,
    },
}

#[derive(Subcommand)]
enum LogAction {
    /// Edit a log entry
    Edit {
        /// Log entry ID
        id: u32,
        /// New name
        #[arg(long)]
        name: Option<String>,
        /// New category
        #[arg(long)]
        category: Option<String>,
        /// Add time in minutes
        #[arg(long)]
        add: Option<u32>,
        /// Subtract time in minutes
        #[arg(long)]
        sub: Option<u32>,
    },
    /// Export log entries to CSV
    Export {
        /// Show only today's entries
        #[arg(long)]
        today: bool,
        /// Show entries from the last 7 days
        #[arg(long)]
        week: bool,
    },
    /// Remove a log entry
    Rm {
        /// Log entry ID
        id: u32,
    },
}

#[derive(Subcommand)]
enum TodoAction {
    /// Add a new todo item
    Add {
        /// The todo text
        text: Vec<String>,
    },
    /// List all todo items with tracked time
    List,
    /// Mark a todo as done
    Done {
        /// Todo ID
        id: u32,
    },
    Edit {
        /// Todo ID
        id: u32,
        /// New text
        text: Vec<String>,
    },
    /// Un-mark a completed todo item
    Undo {
        /// Todo ID
        id: u32,
    },
    /// Remove a todo item
    Rm {
        /// Todo ID
        id: u32,
    },
}

#[cfg(feature = "serve")]
fn run_server(port: u16, #[allow(unused)] enable_ble: bool, #[allow(unused)] enable_icloud: bool) {
    let conn = open_db();
    mdns::advertise(port);

    #[cfg(feature = "ble")]
    if enable_ble {
        ble::start(port);
    }

    #[cfg(feature = "icloud")]
    if enable_icloud {
        let db = std::sync::Arc::new(std::sync::Mutex::new(open_db()));
        icloud::start_background_sync(db);
    }

    let rt = tokio::runtime::Runtime::new().unwrap();
    rt.block_on(server::run(conn, port));
}

fn main() {
    let cli = Cli::parse();
    let conn = open_db();

    match cli.command {
        #[cfg(feature = "serve")]
        Commands::Serve {
            port,
            #[cfg(feature = "ble")]
            ble: enable_ble,
            #[cfg(feature = "icloud")]
            icloud: enable_icloud,
        } => {
            drop(conn);

            let ble_flag;
            #[cfg(feature = "ble")]
            { ble_flag = enable_ble; }
            #[cfg(not(feature = "ble"))]
            { ble_flag = false; }

            let icloud_flag;
            #[cfg(feature = "icloud")]
            { icloud_flag = enable_icloud; }
            #[cfg(not(feature = "icloud"))]
            { icloud_flag = false; }

            run_server(port, ble_flag, icloud_flag);
            return;
        }
        #[cfg(feature = "tui")]
        Commands::Ui => {
            tui::run(&conn);
            return;
        }
        Commands::Start => timer::start(&conn),
        Commands::Stop => timer::stop(&conn),
        Commands::Pause => timer::pause(&conn),
        Commands::Resume => timer::resume(&conn),
        Commands::Restart => timer::restart(&conn),
        Commands::Pomodoro { minutes } => timer::pomodoro(&conn, minutes),
        Commands::Status => timer::status(&conn),
        Commands::Switch => timer::switch(&conn),
        Commands::Log { action, today, week } => match action {
            None => timer::log(&conn, today, week),
            Some(LogAction::Edit { id, name, category, add, sub }) => timer::edit_log(&conn, id, name, category, add, sub),
            Some(LogAction::Export { today, week }) => timer::export_log(&conn, today, week),
            Some(LogAction::Rm { id }) => timer::rm(&conn, id),
        },
        Commands::Todo { action } => match action {
            TodoAction::Add { text } => todo::add(&conn, &text.join(" ")),
            TodoAction::List => todo::list(&conn),
            TodoAction::Edit { id, text } => todo::edit(&conn, id, &text.join(" ")),
            TodoAction::Done { id } => todo::done(&conn, id),
            TodoAction::Undo { id } => todo::undo(&conn, id),
            TodoAction::Rm { id } => todo::rm(&conn, id),
        },
    }
}
