#!/bin/bash
# ============================================================================
# ODS Installer — GUI Progress Protocol
# ============================================================================
# Part of: installers/lib/
# Purpose: Emit structured progress events for the Tauri GUI installer
#
# Expects: YUYINODS_INSTALLER_GUI (optional env var, set by Tauri)
# Provides: ods_progress()
#
# Modder notes:
#   When YUYINODS_INSTALLER_GUI=1, progress lines are emitted to stdout in a
#   machine-readable format. When unset, this is a complete no-op.
#   Format: YUYINODS_PROGRESS:<percent>:<phase_id>:<human_message>
# ============================================================================

ods_progress() {
  local percent="$1"
  local phase="$2"
  local message="$3"

  if [[ "${YUYINODS_INSTALLER_GUI:-0}" == "1" ]]; then
    echo "YUYINODS_PROGRESS:${percent}:${phase}:${message}"
  fi
}
