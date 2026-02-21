import glimr/console/command.{type Args, type Command}
import glimr/console/console
import glimr/filesystem/filesystem

/// The console command description.
const description = "Set up auth middleware and configuration"

/// Define the Command and its properties.
///
pub fn command() -> Command {
  command.new()
  |> command.description(description)
  |> command.handler(run)
}

/// Execute the console command.
///
fn run(_args: Args) -> Nil {
  create_auth_middleware()
}

fn create_auth_middleware() -> Nil {
  let file_path = "src/app/http/middleware/auth.gleam"
  let assert Ok(file_exists) = filesystem.file_exists(file_path)

  case file_exists {
    True -> {
      console.output()
      |> console.line_warning("Skipped: " <> file_path <> " (already exists)")
      |> console.print()
    }
    False -> {
      case
        filesystem.write_from_stub(
          "glimr_auth",
          "http/middleware/auth.stub",
          file_path,
        )
      {
        Ok(_) -> {
          console.output()
          |> console.line_success("Created: " <> file_path)
          |> console.print()
        }
        Error(_) -> {
          console.output()
          |> console.line_error("Failed to create auth middleware")
          |> console.print()
        }
      }
    }
  }
}

/// Console command's entry point
///
pub fn main() {
  command.run(command())
}
