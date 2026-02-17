mod state;
mod timer;
mod todo;

use clap::{Parser, Subcommand};
use state::open_db;

#[derive(Parser)]
#[command(
    name = "tl",
    about = "Time logging & todo CLI",
    after_help = "\
EXAMPLES:
  tl start              Start a new timer (prompts for name & category)
  tl stop               Stop the currently running timer
  tl pause              Pause the running timer
  tl resume             Resume a paused timer
  tl switch             Switch to a different paused timer
  tl status             Show all active timers (running & paused)
  tl log                Show all logged time entries
  tl log --today        Show today's entries only
  tl log --week         Show entries from the last 7 days
  tl log rm 5           Delete log entry #5
  tl todo add Fix bug   Add a todo item
  tl todo list          List all todos
  tl todo done 3        Mark todo #3 as done
  tl todo rm 3          Remove todo #3

WORKFLOW:
  tl start              Start \"coding\" [work]
  tl start              Already running — pause it and start \"review\" [work]
  tl switch             Switch back to \"coding\"
  tl stop               Stop \"coding\", saves to log
  tl switch             Switch to \"review\"
  tl stop               Stop \"review\", saves to log
  tl log --today        See what you did today"
)]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// Start a new timer (pauses the current one if running)
    #[command(after_help = "\
EXAMPLES:
  tl start       Prompts for activity name and category, then starts
                 If a timer is already running, asks to pause it first")]
    Start,

    /// Stop the currently running timer and save it to the log
    #[command(after_help = "\
EXAMPLES:
  tl stop        Stops the running timer and records the time entry")]
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

    /// Show all active timers (running and paused)
    #[command(after_help = "\
EXAMPLES:
  tl status      Shows each active timer with state, active time, and breaks")]
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

    /// Manage todo list
    #[command(after_help = "\
EXAMPLES:
  tl todo add Fix the login bug    Add a new todo
  tl todo list                     List all todos
  tl todo done 3                   Mark todo #3 as done
  tl todo rm 3                     Remove todo #3")]
    Todo {
        #[command(subcommand)]
        action: TodoAction,
    },
}

#[derive(Subcommand)]
enum LogAction {
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
    /// List all todo items
    List,
    /// Mark a todo as done
    Done {
        /// Todo ID
        id: u32,
    },
    /// Remove a todo item
    Rm {
        /// Todo ID
        id: u32,
    },
}

fn main() {
    let cli = Cli::parse();
    let conn = open_db();

    match cli.command {
        Commands::Start => timer::start(&conn),
        Commands::Stop => timer::stop(&conn),
        Commands::Pause => timer::pause(&conn),
        Commands::Resume => timer::resume(&conn),
        Commands::Status => timer::status(&conn),
        Commands::Switch => timer::switch(&conn),
        Commands::Log { action, today, week } => match action {
            None => timer::log(&conn, today, week),
            Some(LogAction::Rm { id }) => timer::rm(&conn, id),
        },
        Commands::Todo { action } => match action {
            TodoAction::Add { text } => todo::add(&conn, &text.join(" ")),
            TodoAction::List => todo::list(&conn),
            TodoAction::Done { id } => todo::done(&conn, id),
            TodoAction::Rm { id } => todo::rm(&conn, id),
        },
    }
}
