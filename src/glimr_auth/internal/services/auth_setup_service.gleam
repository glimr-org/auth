//// Auth Setup Service
////
//// The make:auth command needs to scaffold several files and
//// patch the kernel middleware list, but mixing file I/O,
//// string manipulation, and console output in a single command
//// handler would be hard to test and read. This service owns
//// all the mutation logic so the command handler stays thin
//// and each operation can be called or tested independently.
////

import gleam/list
import gleam/string
import glimr/console/console
import glimr/filesystem/filesystem
import shellout
import simplifile

// ------------------------------------------------------------- Public Functions

/// Scaffolds the auth guard middleware that redirects
/// unauthenticated users to the login page.
///
pub fn create_auth_middleware() -> Nil {
  scaffold_file(
    "glimr_auth",
    "http/middleware/auth.stub",
    "src/app/http/middleware/auth.gleam",
  )
}

/// Scaffolds the load_auth middleware that resolves the 
/// current user from the session and attaches it to the 
/// request context.
///
pub fn create_load_auth_middleware() -> Nil {
  scaffold_file(
    "glimr_auth",
    "http/middleware/load_auth.stub",
    "src/app/http/middleware/load_auth.gleam",
  )
}

/// Patching the kernel file programmatically saves the user from
/// manually finding the right spot in the middleware list and
/// adding both the import and the pipeline entry. The idempotency
/// check prevents duplicate entries if the command is run twice,
/// and the format-then-rollback strategy ensures the kernel file
/// is never left in a broken state.
///
pub fn register_load_auth_in_kernel() -> Nil {
  let kernel_path = "src/app/http/kernel.gleam"

  case simplifile.read(kernel_path) {
    Error(_) -> {
      console.output()
      |> console.line_error(
        "Could not read " <> kernel_path <> " — does it exist?",
      )
      |> console.print()
    }

    Ok(content) -> {
      case string.contains(content, "load_auth") {
        True -> {
          console.output()
          |> console.line_warning(
            "Skipped: " <> kernel_path <> " (load_auth already registered)",
          )
          |> console.print()
        }
        False -> {
          let modified = inject_load_auth(content)
          write_and_format(kernel_path, original: content, modified: modified)
        }
      }
    }
  }
}

/// Exposed as public so the command's test suite can verify the
/// string transformation without touching the filesystem. The
/// two-pass approach — insert import then insert middleware entry
/// — keeps each transformation simple and order-independent.
///
pub fn inject_load_auth(content: String) -> String {
  let lines = string.split(content, "\n")

  let lines = insert_import(lines)
  let lines = insert_middleware_entries(lines)

  string.join(lines, "\n")
}

// ------------------------------------------------------------- Private Functions

/// Checks for an existing file before writing to avoid silently
/// overwriting user customizations — a warning makes it clear
/// the step was intentionally skipped rather than failed.
///
fn scaffold_file(
  stub_package: String,
  stub_name: String,
  file_path: String,
) -> Nil {
  let assert Ok(file_exists) = filesystem.file_exists(file_path)

  case file_exists {
    True -> {
      console.output()
      |> console.line_warning("Skipped: " <> file_path <> " (already exists)")
      |> console.print()
    }
    False -> {
      case filesystem.write_from_stub(stub_package, stub_name, file_path) {
        Ok(_) -> {
          console.output()
          |> console.line_success("Created: " <> file_path)
          |> console.print()
        }
        Error(_) -> {
          console.output()
          |> console.line_error("Failed to create " <> file_path)
          |> console.print()
        }
      }
    }
  }
}

/// Writes modified content to a file and runs gleam format.
/// Rolls back to the original content if formatting fails so
/// the file is never left in a broken state.
///
fn write_and_format(
  path: String,
  original original: String,
  modified modified: String,
) -> Nil {
  case simplifile.write(path, modified) {
    Error(_) -> {
      console.output()
      |> console.line_error("Failed to write " <> path)
      |> console.print()
    }
    Ok(_) -> {
      case shellout.command("gleam", ["format", path], in: ".", opt: []) {
        Ok(_) -> {
          console.output()
          |> console.line_success("Updated: " <> path <> " (added load_auth)")
          |> console.print()
        }
        Error(_) -> {
          let _ = simplifile.write(path, original)
          console.output()
          |> console.line_error(
            "Failed to format " <> path <> ", changes reverted",
          )
          |> console.print()
        }
      }
    }
  }
}

/// Placing the new import after the last existing import keeps
/// the import block contiguous. If no imports exist the new one
/// goes at the top so gleam format can sort it later.
///
fn insert_import(lines: List(String)) -> List(String) {
  let last_import_index = find_last_import_index(lines, 0, -1)

  case last_import_index >= 0 {
    True ->
      insert_at(
        lines,
        last_import_index + 1,
        "import app/http/middleware/load_auth",
      )
    False -> ["import app/http/middleware/load_auth", ..lines]
  }
}

/// Scans all lines to find the last import rather than stopping
/// at the first gap, because gleam format may insert blank lines
/// between import groups. Tracking the index rather than the line
/// content lets insert_import splice at the right position.
///
fn find_last_import_index(lines: List(String), current: Int, last: Int) -> Int {
  case lines {
    [] -> last
    [line, ..rest] -> {
      let trimmed = string.trim_start(line)
      case string.starts_with(trimmed, "import ") {
        True -> find_last_import_index(rest, current + 1, current)
        False -> find_last_import_index(rest, current + 1, last)
      }
    }
  }
}

/// Finds every middleware list in the kernel (there may be
/// multiple for web, api, etc.) and appends load_auth.run after
/// the last .run entry in each list. Inserting at the end of
/// each list means load_auth runs after all other middleware,
/// which is correct since it depends on the session being loaded.
///
fn insert_middleware_entries(lines: List(String)) -> List(String) {
  insert_middleware_entries_loop(lines, -1, 0, [])
}

/// Tracks the index of the last .run entry seen so far. When a
/// closing bracket is hit, the accumulated lines are reversed,
/// the new entry is spliced in after that index, then scanning
/// resumes. The index reset to -1 after each insertion prevents
/// re-inserting into the same list on subsequent brackets.
///
fn insert_middleware_entries_loop(
  lines: List(String),
  last_run_index: Int,
  current: Int,
  acc: List(String),
) -> List(String) {
  case lines {
    [] -> list.reverse(acc)
    [line, ..rest] -> {
      let trimmed = string.trim(line)
      case string.contains(trimmed, ".run,") {
        True ->
          insert_middleware_entries_loop(rest, current, current + 1, [
            line,
            ..acc
          ])
        False ->
          case string.starts_with(trimmed, "]") && last_run_index >= 0 {
            True -> {
              // Insert load_auth.run right after the last .run, line
              let ordered = list.reverse(acc)
              let indent = get_indent(get_at(ordered, last_run_index))
              let new_line = indent <> "load_auth.run,"
              let ordered = insert_at(ordered, last_run_index + 1, new_line)
              let acc = list.reverse(ordered)
              insert_middleware_entries_loop(rest, -1, current + 2, [
                line,
                ..acc
              ])
            }
            False ->
              insert_middleware_entries_loop(rest, last_run_index, current + 1, [
                line,
                ..acc
              ])
          }
      }
    }
  }
}

/// Preserves the indentation of the surrounding .run entries so
/// the inserted line matches the existing code style. Without
/// this the injected line would start at column zero and gleam
/// format would need to fix it — which might fail if the file
/// has other issues.
///
fn get_indent(line: String) -> String {
  let chars = string.to_graphemes(line)
  get_indent_loop(chars, "")
}

/// Collects leading whitespace characters one at a time because
/// Gleam strings don't have a built-in "take while" for
/// graphemes. Stops at the first non-whitespace character so
/// only the indent prefix is captured.
///
fn get_indent_loop(chars: List(String), acc: String) -> String {
  case chars {
    [] -> acc
    [" ", ..rest] -> get_indent_loop(rest, acc <> " ")
    ["\t", ..rest] -> get_indent_loop(rest, acc <> "\t")
    _ -> acc
  }
}

/// Gleam lists don't support random access, so this walks the
/// list to the target index. Used only to grab the indentation
/// of a known .run line, so the O(n) cost is negligible on the
/// small line counts of a kernel file.
///
fn get_at(lines: List(String), index: Int) -> String {
  case lines, index {
    [line, ..], 0 -> line
    [_, ..rest], n -> get_at(rest, n - 1)
    [], _ -> ""
  }
}

/// Splices a single value into a list at the given index. Used
/// by both insert_import and insert_middleware_entries to add
/// lines without mutating the original list — Gleam's immutable
/// lists require rebuilding via accumulator reversal.
///
fn insert_at(lines: List(String), index: Int, value: String) -> List(String) {
  insert_at_loop(lines, index, value, 0, [])
}

/// Walks the list with a counter, and when the counter matches
/// the target index the new value is prepended to the
/// accumulator before the current element. This preserves all
/// existing lines and shifts everything after the insertion
/// point forward by one.
///
fn insert_at_loop(
  lines: List(String),
  index: Int,
  value: String,
  current: Int,
  acc: List(String),
) -> List(String) {
  case current == index {
    True -> {
      let acc = [value, ..acc]
      case lines {
        [] -> list.reverse(acc)
        [line, ..rest] ->
          insert_at_loop(rest, index, value, current + 1, [line, ..acc])
      }
    }
    False ->
      case lines {
        [] -> list.reverse(acc)
        [line, ..rest] ->
          insert_at_loop(rest, index, value, current + 1, [line, ..acc])
      }
  }
}
