import gleam/dict
import gleam/int
import gleam/option
import gleeunit/should
import glimr/session/session
import glimr/utils/unix_timestamp
import glimr_auth/auth

const session_key = "_auth_user_id"

// ------------------------------------------------------------- Login

pub fn login_stores_user_id_in_session_test() {
  let s = session.start("sess-auth-1", dict.new(), dict.new())

  auth.login(s, "42", session_key)

  auth.id(s, session_key) |> should.equal(Ok("42"))

  session.stop(s)
}

pub fn login_regenerates_session_id_test() {
  let s = session.start("original-id", dict.new(), dict.new())

  auth.login(s, "42", session_key)

  let new_id = session.id(s)
  should.not_equal(new_id, "original-id")
  should.not_equal(new_id, "")

  session.stop(s)
}

// ------------------------------------------------------------- Logout

pub fn logout_clears_session_test() {
  let s = session.start("sess-auth-2", dict.new(), dict.new())

  auth.login(s, "42", session_key)
  auth.logout(s)

  auth.check(s, session_key) |> should.equal(False)
  auth.id(s, session_key) |> should.be_error

  session.stop(s)
}

pub fn logout_invalidates_session_test() {
  let s = session.start("sess-auth-3", dict.new(), dict.new())

  auth.login(s, "42", session_key)
  session.put(s, "other_data", "value")
  auth.logout(s)

  // All session data should be gone
  session.get(s, "other_data") |> should.be_error
  session.all(s) |> should.equal(dict.new())

  session.stop(s)
}

// ------------------------------------------------------------- Check

pub fn check_returns_false_when_not_logged_in_test() {
  let s = session.start("sess-auth-4", dict.new(), dict.new())

  auth.check(s, session_key) |> should.equal(False)

  session.stop(s)
}

pub fn check_returns_true_when_logged_in_test() {
  let s = session.start("sess-auth-5", dict.new(), dict.new())

  auth.login(s, "42", session_key)

  auth.check(s, session_key) |> should.equal(True)

  session.stop(s)
}

// ------------------------------------------------------------- Id

pub fn id_returns_error_when_not_logged_in_test() {
  let s = session.start("sess-auth-6", dict.new(), dict.new())

  auth.id(s, session_key) |> should.be_error

  session.stop(s)
}

pub fn id_returns_user_id_when_logged_in_test() {
  let s = session.start("sess-auth-7", dict.new(), dict.new())

  auth.login(s, "99", session_key)

  auth.id(s, session_key) |> should.equal(Ok("99"))

  session.stop(s)
}

// ------------------------------------------------------------- Empty Session

pub fn check_on_empty_session_returns_false_test() {
  let s = session.empty()

  auth.check(s, session_key) |> should.equal(False)
}

pub fn id_on_empty_session_returns_error_test() {
  let s = session.empty()

  auth.id(s, session_key) |> should.be_error
}

pub fn login_on_empty_session_does_not_crash_test() {
  let s = session.empty()

  auth.login(s, "42", session_key)
}

pub fn logout_on_empty_session_does_not_crash_test() {
  let s = session.empty()

  auth.logout(s)
}

// ------------------------------------------------------------- Custom Session Key

pub fn custom_session_key_test() {
  let custom_key = "_auth_customer_id"
  let s = session.start("sess-auth-8", dict.new(), dict.new())

  auth.login(s, "123", custom_key)

  // Should be stored under the custom key
  session.get(s, "_auth_customer_id") |> should.equal(Ok("123"))

  // Auth functions should still work with the custom key
  auth.check(s, custom_key) |> should.equal(True)
  auth.id(s, custom_key) |> should.equal(Ok("123"))

  session.stop(s)
}

// ------------------------------------------------------------- Preloaded Session

pub fn check_with_preloaded_auth_data_test() {
  let data =
    dict.new()
    |> dict.insert(session_key, "77")

  let s = session.start("sess-auth-9", data, dict.new())

  auth.check(s, session_key) |> should.equal(True)
  auth.id(s, session_key) |> should.equal(Ok("77"))

  session.stop(s)
}

// ------------------------------------------------------------- Resolve User

pub fn resolve_user_returns_some_when_logged_in_test() {
  let s = session.start("sess-resolve-1", dict.new(), dict.new())

  auth.login(s, "42", session_key)

  auth.resolve_user(s, session_key) |> should.equal(option.Some("42"))

  session.stop(s)
}

pub fn resolve_user_returns_none_when_not_logged_in_test() {
  let s = session.start("sess-resolve-2", dict.new(), dict.new())

  auth.resolve_user(s, session_key) |> should.equal(option.None)

  session.stop(s)
}

pub fn resolve_user_returns_none_after_logout_test() {
  let s = session.start("sess-resolve-3", dict.new(), dict.new())

  auth.login(s, "42", session_key)
  auth.logout(s)

  auth.resolve_user(s, session_key) |> should.equal(option.None)

  session.stop(s)
}

// ------------------------------------------------------------- Check Throttle

pub fn check_throttle_allows_when_no_attempts_test() {
  let s = session.start("sess-throttle-1", dict.new(), dict.new())

  auth.check_throttle(s, session_key) |> should.equal(Ok(Nil))

  session.stop(s)
}

pub fn check_throttle_allows_when_under_limit_test() {
  let s = session.start("sess-throttle-2", dict.new(), dict.new())

  // Record 4 failures (under limit of 5)
  auth.record_failure(s, session_key, 5, 60)
  auth.record_failure(s, session_key, 5, 60)
  auth.record_failure(s, session_key, 5, 60)
  auth.record_failure(s, session_key, 5, 60)

  auth.check_throttle(s, session_key) |> should.equal(Ok(Nil))

  session.stop(s)
}

pub fn check_throttle_rejects_when_locked_out_test() {
  let s = session.start("sess-throttle-3", dict.new(), dict.new())

  // Hit the limit
  auth.record_failure(s, session_key, 5, 60)
  auth.record_failure(s, session_key, 5, 60)
  auth.record_failure(s, session_key, 5, 60)
  auth.record_failure(s, session_key, 5, 60)
  auth.record_failure(s, session_key, 5, 60)

  auth.check_throttle(s, session_key) |> should.equal(Error(auth.Throttled))

  session.stop(s)
}

pub fn check_throttle_allows_after_lockout_expires_test() {
  let s = session.start("sess-throttle-4", dict.new(), dict.new())

  // Simulate an expired lockout by setting locked_until to the past
  let attempts_key = session_key <> "_attempts"
  let locked_until_key = session_key <> "_locked_until"
  session.put(s, attempts_key, "5")
  session.put(s, locked_until_key, int.to_string(unix_timestamp.now() - 1))

  auth.check_throttle(s, session_key) |> should.equal(Ok(Nil))

  // Should also clear the throttle keys
  session.get(s, attempts_key) |> should.be_error()
  session.get(s, locked_until_key) |> should.be_error()

  session.stop(s)
}

pub fn check_throttle_rejects_during_active_lockout_test() {
  let s = session.start("sess-throttle-5", dict.new(), dict.new())

  // Simulate an active lockout by setting locked_until to the future
  let locked_until_key = session_key <> "_locked_until"
  session.put(s, locked_until_key, int.to_string(unix_timestamp.now() + 300))

  auth.check_throttle(s, session_key)
  |> should.equal(Error(auth.Throttled))

  session.stop(s)
}

pub fn check_throttle_ignores_invalid_locked_until_test() {
  let s = session.start("sess-throttle-6", dict.new(), dict.new())

  // Set a non-integer locked_until — should be treated as not locked
  let locked_until_key = session_key <> "_locked_until"
  session.put(s, locked_until_key, "not_a_number")

  auth.check_throttle(s, session_key) |> should.equal(Ok(Nil))

  session.stop(s)
}

// ------------------------------------------------------------- Record Failure

pub fn record_failure_increments_attempts_test() {
  let s = session.start("sess-fail-1", dict.new(), dict.new())
  let attempts_key = session_key <> "_attempts"

  auth.record_failure(s, session_key, 5, 60)
  session.get(s, attempts_key) |> should.equal(Ok("1"))

  auth.record_failure(s, session_key, 5, 60)
  session.get(s, attempts_key) |> should.equal(Ok("2"))

  auth.record_failure(s, session_key, 5, 60)
  session.get(s, attempts_key) |> should.equal(Ok("3"))

  session.stop(s)
}

pub fn record_failure_does_not_lock_under_limit_test() {
  let s = session.start("sess-fail-2", dict.new(), dict.new())
  let locked_until_key = session_key <> "_locked_until"

  auth.record_failure(s, session_key, 5, 60)
  auth.record_failure(s, session_key, 5, 60)
  auth.record_failure(s, session_key, 5, 60)
  auth.record_failure(s, session_key, 5, 60)

  session.get(s, locked_until_key) |> should.be_error()

  session.stop(s)
}

pub fn record_failure_sets_lockout_at_limit_test() {
  let s = session.start("sess-fail-3", dict.new(), dict.new())
  let locked_until_key = session_key <> "_locked_until"

  auth.record_failure(s, session_key, 3, 120)
  auth.record_failure(s, session_key, 3, 120)
  auth.record_failure(s, session_key, 3, 120)

  let assert Ok(locked_until_str) = session.get(s, locked_until_key)
  let assert Ok(locked_until) = int.parse(locked_until_str)

  // Locked until should be ~120 seconds from now
  let now = unix_timestamp.now()
  should.be_true(locked_until > now)
  should.be_true(locked_until <= now + 120)

  session.stop(s)
}

pub fn record_failure_respects_custom_max_attempts_test() {
  let s = session.start("sess-fail-4", dict.new(), dict.new())
  let locked_until_key = session_key <> "_locked_until"

  // Max of 2 attempts
  auth.record_failure(s, session_key, 2, 60)
  session.get(s, locked_until_key) |> should.be_error()

  auth.record_failure(s, session_key, 2, 60)
  session.get(s, locked_until_key) |> should.be_ok()

  session.stop(s)
}

pub fn record_failure_respects_custom_lockout_seconds_test() {
  let s = session.start("sess-fail-5", dict.new(), dict.new())
  let locked_until_key = session_key <> "_locked_until"

  // 1 attempt max, 300 second lockout
  auth.record_failure(s, session_key, 1, 300)

  let assert Ok(locked_until_str) = session.get(s, locked_until_key)
  let assert Ok(locked_until) = int.parse(locked_until_str)

  let now = unix_timestamp.now()
  should.be_true(locked_until > now + 299)
  should.be_true(locked_until <= now + 300)

  session.stop(s)
}

// ------------------------------------------------------------- Clear Throttle

pub fn clear_throttle_removes_attempts_and_lockout_test() {
  let s = session.start("sess-clear-1", dict.new(), dict.new())
  let attempts_key = session_key <> "_attempts"
  let locked_until_key = session_key <> "_locked_until"

  // Lock out first
  auth.record_failure(s, session_key, 3, 60)
  auth.record_failure(s, session_key, 3, 60)
  auth.record_failure(s, session_key, 3, 60)
  session.get(s, locked_until_key) |> should.be_ok()

  // Clear
  auth.clear_throttle(s, session_key)

  session.get(s, attempts_key) |> should.be_error()
  session.get(s, locked_until_key) |> should.be_error()

  session.stop(s)
}

pub fn clear_throttle_allows_fresh_attempts_test() {
  let s = session.start("sess-clear-2", dict.new(), dict.new())

  // Lock out
  auth.record_failure(s, session_key, 2, 60)
  auth.record_failure(s, session_key, 2, 60)
  auth.check_throttle(s, session_key) |> should.equal(Error(auth.Throttled))

  // Clear and verify attempts work again
  auth.clear_throttle(s, session_key)
  auth.check_throttle(s, session_key) |> should.equal(Ok(Nil))

  session.stop(s)
}

pub fn clear_throttle_on_clean_session_does_not_crash_test() {
  let s = session.start("sess-clear-3", dict.new(), dict.new())

  auth.clear_throttle(s, session_key)

  session.stop(s)
}

// ------------------------------------------------------------- Throttle Isolation

pub fn throttle_is_isolated_per_session_key_test() {
  let s = session.start("sess-iso-1", dict.new(), dict.new())
  let user_key = "_auth_user_id"
  let admin_key = "_auth_admin_id"

  // Lock out user
  auth.record_failure(s, user_key, 2, 60)
  auth.record_failure(s, user_key, 2, 60)
  auth.check_throttle(s, user_key) |> should.equal(Error(auth.Throttled))

  // Admin should still be fine
  auth.check_throttle(s, admin_key) |> should.equal(Ok(Nil))

  session.stop(s)
}
