//// Auth
////
//// Controllers shouldn't use raw session keys like
//// "_auth_user_id" directly — that couples every auth check to
//// a magic string that could drift between modules. This
//// module wraps the session with semantic helpers (login,
//// logout, check, id) so auth logic reads clearly and the
//// session key is passed explicitly by the caller (typically
//// from the generated middleware's `session_key` constant).
////

import gleam/int
import gleam/option
import gleam/result
import glimr/session/session.{type Session}
import glimr/utils/unix_timestamp

// ------------------------------------------------------------- Public Types

/// Login can fail for two very different reasons and the caller
/// needs to tell them apart — wrong credentials get a "try
/// again" message, while throttled means "wait a bit". Lumping
/// them into one error would force controllers to show the same
/// response for both cases.
///
pub type AuthError {
  InvalidCredentials
  Throttled
}

// ------------------------------------------------------------- Public Functions

/// Regenerating the session ID after storing the user ID is
/// critical — without it, an attacker who planted a known
/// session ID before authentication could hijack the post-
/// login session. The regenerate call rotates the ID while
/// preserving all session data so the user doesn't lose
/// pre-login state like a shopping cart.
///
pub fn login(session: Session, user_id: String, session_key: String) -> Nil {
  session.put(session, session_key, user_id)
  session.regenerate(session)
}

/// Invalidate rather than just deleting the auth key — a
/// partial logout that leaves other session data intact could
/// leak state between users on shared devices. Invalidation
/// clears everything, generates a fresh ID, and tells the
/// middleware to delete the old entry from the store so it can
/// never be replayed.
///
pub fn logout(session: Session) -> Nil {
  session.invalidate(session)
}

/// A Bool check is the most common auth gate — middleware and
/// guards typically just need to know "logged in or not" to
/// decide whether to redirect. Returning Bool instead of the
/// full user ID keeps the call site clean when the ID itself
/// isn't needed for the decision.
///
pub fn check(session: Session, session_key: String) -> Bool {
  session.has(session, session_key)
}

/// Returns a Result so callers can distinguish "not logged in"
/// from a logged-in user with an empty string ID. Controllers
/// that need the actual user ID to load a profile or check
/// permissions use this, while simple auth gates use check
/// instead.
///
pub fn id(session: Session, session_key: String) -> Result(String, Nil) {
  session.get(session, session_key)
}

/// Templates and context structs often use Option(String) for
/// the current user rather than Result — Option maps naturally
/// to "present or absent" while Result implies an operation
/// that could fail. This bridges the two so middleware can
/// populate ctx.user without unwrapping a Result at every call
/// site.
///
pub fn resolve_user(
  session: Session,
  session_key: String,
) -> option.Option(String) {
  id(session, session_key)
  |> option.from_result
}

/// Brute-force login attacks hammer the same session with
/// thousands of password guesses. Checking the attempt count
/// before even looking up the user means a locked-out session
/// gets rejected instantly without touching the database. If
/// the lockout window has expired, the counters are cleared so
/// the user can try again.
///
pub fn check_throttle(
  session: Session,
  session_key: String,
) -> Result(Nil, AuthError) {
  let attempts_key = session_key <> "_attempts"
  let locked_until_key = session_key <> "_locked_until"

  let throttled = {
    use locked_until_str <- result.try(session.get(session, locked_until_key))
    use locked_until <- result.try(int.parse(locked_until_str))
    Ok(locked_until)
  }

  case throttled {
    Error(_) -> Ok(Nil)
    Ok(locked_until) -> {
      case unix_timestamp.now() < locked_until {
        True -> Error(Throttled)
        False -> {
          session.forget(session, attempts_key)
          session.forget(session, locked_until_key)
          Ok(Nil)
        }
      }
    }
  }
}

/// Each wrong password bumps a counter in the session. Once it
/// hits the max, a lockout timestamp is stored so
/// check_throttle can reject future attempts without any
/// database work. Storing this in the session rather than the
/// database means throttling works even for nonexistent
/// accounts — attackers can't enumerate valid emails by
/// observing different rate-limit behavior.
///
pub fn record_failure(
  session: Session,
  session_key: String,
  max_attempts: Int,
  lockout_seconds: Int,
) -> Nil {
  let attempts_key = session_key <> "_attempts"
  let locked_until_key = session_key <> "_locked_until"

  let attempts = {
    use str <- result.try(session.get(session, attempts_key))
    int.parse(str)
  }
  let attempts = case attempts {
    Ok(n) -> n + 1
    Error(_) -> 1
  }

  session.put(session, attempts_key, int.to_string(attempts))

  case attempts >= max_attempts {
    True -> {
      let locked_until = unix_timestamp.now() + lockout_seconds
      session.put(session, locked_until_key, int.to_string(locked_until))
    }
    False -> Nil
  }
}

/// A successful login should reset the attempt counter —
/// otherwise a user who fat-fingered their password 4 times
/// then got it right would get locked out on their next typo
/// because the counter never reset.
///
pub fn clear_throttle(session: Session, session_key: String) -> Nil {
  let attempts_key = session_key <> "_attempts"
  let locked_until_key = session_key <> "_locked_until"
  session.forget(session, attempts_key)
  session.forget(session, locked_until_key)
}
