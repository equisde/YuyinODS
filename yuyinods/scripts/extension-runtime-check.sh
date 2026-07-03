#!/usr/bin/env bash
# Extension runtime check — non-core services with an on-disk compose fragment.
# Compares Docker container state to the service registry and optionally probes
# HTTP health endpoints (same paths/timeouts as the installer health phase).
#
# Usage:
#   scripts/extension-runtime-check.sh [YUYINODS_ROOT]
#   YUYINODS_ROOT defaults to the repository root (parent of scripts/).
#
# Environment:
#   EXTENSION_RUNTIME_CHECK_STRICT=1 — exit 1 if any health probe fails (running
#     container but endpoint not reachable). Default is non-blocking (exit 0).
#
# Requires: bash 4+, docker (optional — skips if daemon unreachable), curl for HTTP probes.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
YUYINODS_ROOT="$(cd "${1:-$ROOT_DIR}" && pwd)"
export SCRIPT_DIR="$YUYINODS_ROOT"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${BLUE}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
ok_line() { echo -e "${GREEN}[OK]${NC} $1"; }
bad_line() { echo -e "${RED}[BAD]${NC} $1"; }

if [[ ! -f "$YUYINODS_ROOT/lib/service-registry.sh" ]]; then
    warn "ODS root missing lib/service-registry.sh — skipping ($YUYINODS_ROOT)"
    exit 0
fi

# shellcheck source=../lib/service-registry.sh
. "$YUYINODS_ROOT/lib/service-registry.sh"

if [[ -f "$YUYINODS_ROOT/lib/safe-env.sh" ]]; then
    # shellcheck source=../lib/safe-env.sh
    . "$YUYINODS_ROOT/lib/safe-env.sh"
    [[ -f "$YUYINODS_ROOT/.env" ]] && load_env_file "$YUYINODS_ROOT/.env"
fi

sr_load
sr_resolve_ports

if [[ ${#SERVICE_IDS[@]} -eq 0 ]]; then
    info "No services in registry — nothing to check"
    exit 0
fi

if ! command -v docker >/dev/null 2>&1; then
    info "Extension runtime check — docker not in PATH (skipping)"
    exit 0
fi

if ! docker info >/dev/null 2>&1; then
    info "Extension runtime check — Docker daemon not reachable (skipping)"
    exit 0
fi

HAVE_CURL=false
command -v curl >/dev/null 2>&1 && HAVE_CURL=true

strict="${EXTENSION_RUNTIME_CHECK_STRICT:-0}"
had_health_fail=0

info "Extension runtime check (non-core, compose enabled) — root: $YUYINODS_ROOT"

for sid in "${SERVICE_IDS[@]}"; do
    svc_category="${SERVICE_CATEGORIES[$sid]:-optional}"
    [[ "$svc_category" == "core" ]] && continue

    cf="${SERVICE_COMPOSE[$sid]:-}"
    [[ -z "$cf" || ! -f "$cf" ]] && continue

    cname="${SERVICE_CONTAINERS[$sid]:-yuyinods-$sid}"
    disp="${SERVICE_NAMES[$sid]:-$sid}"

    if ! docker inspect "$cname" >/dev/null 2>&1; then
        info "[$sid] $disp — no container '$cname' (not in current compose stack or not started)"
        continue
    fi

    status="$(docker inspect -f '{{.State.Status}}' "$cname" 2>/dev/null || echo unknown)"
    if [[ "$status" != "running" ]]; then
        warn "[$sid] $disp — container exists but status=$status (try: docker logs $cname)"
        continue
    fi

    port="${SERVICE_PORTS[$sid]:-0}"
    health="${SERVICE_HEALTH[$sid]:-}"
    timeout_sec="${SERVICE_HEALTH_TIMEOUTS[$sid]:-5}"

    if [[ ! "$port" =~ ^[0-9]+$ ]] || [[ "$port" -le 0 ]]; then
        ok_line "[$sid] $disp — running (no external port to probe)"
        continue
    fi

    if [[ -z "$health" ]]; then
        ok_line "[$sid] $disp — running (no health path in manifest)"
        continue
    fi

    if ! $HAVE_CURL; then
        warn "[$sid] $disp — running; curl missing, cannot probe http://127.0.0.1:${port}${health}"
        continue
    fi

    url="http://127.0.0.1:${port}${health}"
    if curl -sf --max-time "$timeout_sec" "$url" >/dev/null; then
        ok_line "[$sid] $disp — running, health OK ($url)"
    else
        bad_line "[$sid] $disp — running but health failed ($url) — try: docker compose logs $sid"
        had_health_fail=1
    fi
done

if [[ "$strict" == "1" && "$had_health_fail" -ne 0 ]]; then
    exit 1
fi
exit 0
