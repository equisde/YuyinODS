#!/usr/bin/env bats
# ============================================================================
# BATS tests for installers/lib/path-utils.sh
# ============================================================================
# Tests: normalize_path(), resolve_install_dir(), validate_install_path(),
#        get_default_install_dir()

load '../bats/bats-support/load'
load '../bats/bats-assert/load'

setup() {
    # Source the library under test
    source "$BATS_TEST_DIRNAME/../../installers/lib/path-utils.sh"
    # Ensure resolve_install_dir sees a clean env; each test sets its own.
    unset INSTALL_DIR YUYINODS_HOME YUYINODS_INSTALL_DIR YUYINODS_SCRIPT_HINT
}

teardown() {
    unset INSTALL_DIR YUYINODS_HOME YUYINODS_INSTALL_DIR YUYINODS_SCRIPT_HINT
}

# ── normalize_path ──────────────────────────────────────────────────────────

@test "normalize_path: empty input returns error" {
    run normalize_path ""
    assert_failure 1
    assert_output ""
}

@test "normalize_path: absolute path passes through" {
    run normalize_path "/usr/local/bin"
    assert_success
    assert_output "/usr/local/bin"
}

@test "normalize_path: relative path becomes absolute" {
    run normalize_path "some/relative/path"
    assert_success
    # Should start with /
    [[ "$output" == /* ]]
    # Should end with the relative path
    [[ "$output" == *"some/relative/path" ]]
}

@test "normalize_path: tilde expands to HOME" {
    run normalize_path "~/my-project"
    assert_success
    assert_output "$HOME/my-project"
}

@test "normalize_path: removes trailing components via realpath" {
    # Test with a path that has .. in it
    run normalize_path "/tmp/foo/../bar"
    assert_success
    assert_output "/tmp/bar"
}

# ── resolve_install_dir ─────────────────────────────────────────────────────

@test "resolve_install_dir: INSTALL_DIR takes highest precedence" {
    export INSTALL_DIR="/opt/custom-ods"
    export YUYINODS_HOME="/opt/legacy-ods"
    export YUYINODS_INSTALL_DIR="/opt/yuyinods"
    run resolve_install_dir
    assert_success
    assert_output "/opt/custom-ods"
    unset INSTALL_DIR YUYINODS_HOME YUYINODS_INSTALL_DIR
}

@test "resolve_install_dir: YUYINODS_HOME used when INSTALL_DIR unset" {
    unset INSTALL_DIR
    export YUYINODS_HOME="/opt/legacy-ods"
    export YUYINODS_INSTALL_DIR="/opt/yuyinods"
    run resolve_install_dir
    assert_success
    assert_output "/opt/legacy-ods"
    unset YUYINODS_HOME YUYINODS_INSTALL_DIR
}

@test "resolve_install_dir: YUYINODS_INSTALL_DIR used when others unset" {
    unset INSTALL_DIR
    unset YUYINODS_HOME
    export YUYINODS_INSTALL_DIR="/opt/yuyinods"
    run resolve_install_dir
    assert_success
    assert_output "/opt/yuyinods"
    unset YUYINODS_INSTALL_DIR
}

@test "resolve_install_dir: defaults to HOME/yuyinods" {
    unset INSTALL_DIR
    unset YUYINODS_HOME
    unset YUYINODS_INSTALL_DIR
    run resolve_install_dir
    assert_success
    assert_output "$HOME/yuyinods"
}

@test "resolve_install_dir: YUYINODS_SCRIPT_HINT used when sentinel .env present" {
    export YUYINODS_SCRIPT_HINT="$BATS_TEST_TMPDIR/yuyinods-install-hint"
    mkdir -p "$YUYINODS_SCRIPT_HINT"
    touch "$YUYINODS_SCRIPT_HINT/.env"
    run resolve_install_dir
    assert_success
    assert_output "$YUYINODS_SCRIPT_HINT"
}

@test "resolve_install_dir: YUYINODS_SCRIPT_HINT falls through when sentinel .env absent" {
    export YUYINODS_SCRIPT_HINT="$BATS_TEST_TMPDIR/yuyinods-install-no-sentinel"
    mkdir -p "$YUYINODS_SCRIPT_HINT"
    # No .env file created — hint must be rejected and fall through to default.
    run resolve_install_dir
    assert_success
    assert_output "$HOME/yuyinods"
}

# ── validate_install_path ───────────────────────────────────────────────────

@test "validate_install_path: empty path returns error" {
    run validate_install_path ""
    assert_failure 1
    assert_output --partial "ERROR: Installation path is empty"
}

@test "validate_install_path: nonexistent parent returns error" {
    run validate_install_path "/nonexistent/parent/dir/yuyinods"
    assert_failure 1
    assert_output --partial "ERROR: Parent directory does not exist"
}

@test "validate_install_path: valid writable path returns 0 or 2 (disk warning)" {
    run validate_install_path "$BATS_TEST_TMPDIR/yuyinods"
    # Returns 0 (ok) or 2 (low disk warning) — both are valid (not error)
    [[ "$status" -eq 0 || "$status" -eq 2 ]]
}

@test "validate_install_path: non-writable parent returns error" {
    local readonly_dir="$BATS_TEST_TMPDIR/readonly-parent"
    mkdir -p "$readonly_dir"
    chmod 555 "$readonly_dir"

    run validate_install_path "$readonly_dir/yuyinods"
    assert_failure 1
    assert_output --partial "ERROR: Parent directory is not writable"

    # Restore permissions for cleanup
    chmod 755 "$readonly_dir"
}

# ── get_default_install_dir ─────────────────────────────────────────────────

@test "get_default_install_dir: returns HOME/yuyinods" {
    run get_default_install_dir
    assert_success
    assert_output "$HOME/yuyinods"
}
