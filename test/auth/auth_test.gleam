import gleam/dict
import gleeunit/should
import glimr/session/session
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
