#!/bin/bash
# ============================================================================
# ODS Installer — Logging
# ============================================================================
# Part of: installers/lib/
# Purpose: Log, success, warn, error helpers and elapsed time
#
# Expects: GRN, BGRN, AMB, RED, NC, LOG_FILE, INSTALL_START_EPOCH
# Provides: install_elapsed(), log(), success(), warn(), error()
#
# Modder notes:
#   Change log format or add log levels here.
# ============================================================================

install_elapsed() {
  local now_epoch="${INSTALL_NOW_EPOCH:-$(date +%s)}"
  local secs=$(( now_epoch - INSTALL_START_EPOCH ))
  local m=$(( secs / 60 ))
  local s=$(( secs % 60 ))
  printf '%dm %02ds' "$m" "$s"
}

_ensure_log_file() {
  local dir
  dir="$(dirname "${LOG_FILE:-/tmp/yuyinods-install.log}")"
  if [[ -n "$dir" ]] && mkdir -p "$dir" 2>/dev/null && touch "$LOG_FILE" 2>/dev/null; then
    return 0
  fi

  local fallback="/tmp/yuyinods-install.log"
  if [[ "${LOG_FILE:-}" != "$fallback" ]]; then
    printf '[WARN] Cannot write installer log at %s; using %s for this run.\n' "${LOG_FILE:-unset}" "$fallback" >&2
  fi
  LOG_FILE="$fallback"
  touch "$LOG_FILE" 2>/dev/null || true
}

_log_line() {
  _ensure_log_file
  echo -e "$1" | tee -a "$LOG_FILE"
}

log() { _log_line "${GRN}[INFO]${NC} $1"; }
success() { _log_line "${BGRN}[OK]${NC} $1"; }
warn() { _log_line "${AMB}[WARN]${NC} $1"; }
error() { _log_line "${RED}[ERROR]${NC} $1"; exit 1; }
