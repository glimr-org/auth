import gleam/string
import gleeunit/should
import glimr_auth/internal/services/auth_setup_service

// ------------------------------------------------------------- Import Injection

pub fn adds_import_after_last_import_line_test() {
  let input =
    "import app/http/context/ctx.{type Context}
import app/http/middleware/load_session
import glimr/http/kernel.{type MiddlewareGroup}
import wisp.{type Request, type Response}

pub fn handle() {
}"

  let result = auth_setup_service.inject_load_auth(input)

  should.be_true(has_line(result, "import app/http/middleware/load_auth"))
}

pub fn import_placed_after_last_import_test() {
  let input =
    "import app/http/context/ctx.{type Context}
import glimr/http/kernel.{type MiddlewareGroup}
import wisp.{type Request, type Response}

pub fn handle() {
}"

  let result = auth_setup_service.inject_load_auth(input)
  let lines = string.split(result, "\n")

  // The load_auth import should come right after the wisp import (last import)
  let wisp_idx = find_line_index(lines, "import wisp", 0)
  let load_auth_idx =
    find_line_index(lines, "import app/http/middleware/load_auth", 0)

  should.be_true(load_auth_idx == wisp_idx + 1)
}

// ------------------------------------------------------------- Middleware Entry Injection

pub fn adds_load_auth_run_to_single_middleware_group_test() {
  let input =
    "import app/http/middleware/load_session
import wisp.{type Request, type Response}

pub fn handle() {
  case middleware_group {
    kernel.Web | _ -> {
      [
        serve_static.run,
        log_request.run,
        load_session.run,
        // ...
      ]
      |> middleware.apply(req, ctx, router)
    }
  }
}"

  let result = auth_setup_service.inject_load_auth(input)

  should.be_true(has_line(result, "load_auth.run,"))
}

pub fn adds_load_auth_run_to_multiple_middleware_groups_test() {
  let input =
    "import app/http/middleware/load_session
import wisp.{type Request, type Response}

pub fn handle() {
  case middleware_group {
    kernel.Api -> {
      [
        json_errors.run,
        load_session.run,
        // ...
      ]
      |> middleware.apply(req, ctx, router)
    }
    kernel.Web | _ -> {
      [
        serve_static.run,
        load_session.run,
        // ...
      ]
      |> middleware.apply(req, ctx, router)
    }
  }
}"

  let result = auth_setup_service.inject_load_auth(input)

  // Count occurrences of load_auth.run
  let count = count_occurrences(result, "load_auth.run,")
  should.equal(count, 2)
}

pub fn load_auth_run_inserted_after_last_run_entry_test() {
  let input =
    "import app/http/middleware/load_session
import wisp.{type Request, type Response}

pub fn handle() {
  case middleware_group {
    kernel.Web | _ -> {
      [
        serve_static.run,
        log_request.run,
        load_session.run,
        // ...
      ]
      |> middleware.apply(req, ctx, router)
    }
  }
}"

  let result = auth_setup_service.inject_load_auth(input)
  let lines = string.split(result, "\n")

  let load_session_idx = find_line_index(lines, "load_session.run,", 0)
  let load_auth_idx = find_line_index(lines, "load_auth.run,", 0)

  // load_auth.run should come right after load_session.run
  should.be_true(load_auth_idx == load_session_idx + 1)
}

// ------------------------------------------------------------- Helpers

fn has_line(content: String, needle: String) -> Bool {
  find_line_index(string.split(content, "\n"), needle, 0) >= 0
}

fn find_line_index(lines: List(String), needle: String, current: Int) -> Int {
  case lines {
    [] -> -1
    [line, ..rest] ->
      case string.contains(line, needle) {
        True -> current
        False -> find_line_index(rest, needle, current + 1)
      }
  }
}

fn count_occurrences(haystack: String, needle: String) -> Int {
  case string.split_once(haystack, needle) {
    Ok(#(_, rest)) -> 1 + count_occurrences(rest, needle)
    Error(_) -> 0
  }
}
