import glimr/console/command.{type Args, type Command}
import glimr_auth/internal/services/auth_setup_service

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
  auth_setup_service.create_auth_middleware()
  auth_setup_service.create_load_auth_middleware()
  auth_setup_service.register_load_auth_in_kernel()
}

/// Console command's entry point
///
pub fn main() {
  command.run(command())
}
