#!/bin/bash
# ============================================================================
# ODS Installer — Phase 05: Docker Setup
# ============================================================================
# Part of: installers/phases/
# Purpose: Install Docker, Docker Compose, and NVIDIA Container Toolkit
#
# Expects: SKIP_DOCKER, DRY_RUN, INTERACTIVE, GPU_COUNT, GPU_BACKEND,
#           LOG_FILE, MIN_DRIVER_VERSION, PKG_MANAGER,
#           show_phase(), ai(), ai_ok(), ai_warn(), log(), warn(), error(),
#           detect_pkg_manager(), pkg_install(), pkg_update(), pkg_resolve()
# Provides: DOCKER_CMD, DOCKER_COMPOSE_CMD
#
# Modder notes:
#   Change Docker installation method or add Podman support here.
#   Multi-distro: uses packaging.sh for distro-agnostic package installs.
# ============================================================================

ods_progress 30 "docker" "Setting up Docker"
show_phase 3 6 "Docker Setup" "~2 minutes"
ai "Preparing container runtime..."

# Ensure package manager is detected
[[ -z "${PKG_MANAGER:-}" ]] && detect_pkg_manager

# Helper wrappers that are safe even if DOCKER_CMD contains spaces (e.g. "sudo docker")
_docker_cmd_arr() {
    case "${DOCKER_CMD:-docker}" in
        "sudo docker") printf '%s %s\n' "sudo" "docker" ;;
        *)             printf '%s\n' "docker" ;;
    esac
}

docker_run() {
    # shellcheck disable=SC2207
    local -a cmd=($(_docker_cmd_arr))
    "${cmd[@]}" "$@"
}

docker_compose_run() {
    # shellcheck disable=SC2207
    local -a cmd=($(_docker_cmd_arr))
    "${cmd[@]}" compose "$@"
}

_docker_install_from_script() {
    local tmpfile
    tmpfile=$(mktemp /tmp/install-docker.XXXXXX.sh)
    if ! curl -fsSL --max-time 300 https://get.docker.com -o "$tmpfile" || ! sh "$tmpfile"; then
        rm -f "$tmpfile"
        return 1
    fi
    rm -f "$tmpfile"
}

_docker_install_dnf_rhel_family() {
    local distro_id="unknown"
    if [[ -r /etc/os-release ]]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        distro_id="${ID:-unknown}"
    fi

    case "$distro_id" in
        rocky|almalinux|rhel|ol|centos)
            ai "Using Docker CE CentOS/RHEL repository for ${distro_id}..."
            ods_sudo dnf install -y dnf-plugins-core >> "$LOG_FILE" 2>&1
            ods_sudo rm -f /etc/yum.repos.d/docker-ce.repo /etc/yum.repos.d/docker-ce-staging.repo
            ods_sudo dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo >> "$LOG_FILE" 2>&1
            ods_sudo dnf makecache >> "$LOG_FILE" 2>&1
            ods_sudo dnf install -y \
                docker-ce \
                docker-ce-cli \
                containerd.io \
                docker-compose-plugin \
                docker-buildx-plugin \
                >> "$LOG_FILE" 2>&1
            ods_sudo systemctl enable --now docker.service >> "$LOG_FILE" 2>&1 || true
            ;;
        *)
            return 1
            ;;
    esac
}

# Track whether docker group membership is active in this shell
DOCKER_NEEDS_SUDO=false

_docker_read_server_version() {
    local version=""

    if version="$(docker version --format '{{.Server.Version}}' 2>/dev/null)" && [[ -n "$version" ]]; then
        printf '%s\n' "$version"
        return 0
    fi

    # Fresh Linux installs often add the user to the docker group, but that
    # membership is not active until the next login shell. The AMD downgrade
    # must still see Docker 29.3.x in that first installer run.
    if command -v sudo >/dev/null 2>&1; then
        if version="$(ods_sudo docker version --format '{{.Server.Version}}' 2>/dev/null)" && [[ -n "$version" ]]; then
            printf '%s\n' "$version"
            return 0
        fi
    fi

    return 1
}

_docker_server_version_for_amd_downgrade() {
    if _docker_read_server_version; then
        return 0
    fi

    # get.docker.com usually starts the daemon, but derivative distros and
    # first-boot images can leave it stopped until systemd is nudged.
    if command -v systemctl >/dev/null 2>&1; then
        ods_sudo systemctl start docker 2>>"${LOG_FILE:-/dev/null}" || true
        sleep 2
        if _docker_read_server_version; then
            return 0
        fi
    fi

    return 1
}

if [[ "$SKIP_DOCKER" == "true" ]]; then
    log "Skipping Docker installation (--skip-docker)"
elif command -v docker &> /dev/null; then
    ai_ok "Docker already installed: $(docker --version)"
else
    ods_progress 31 "docker" "Installing Docker engine"
    ai "Installing Docker..."

    if $DRY_RUN; then
        log "[DRY RUN] Would install Docker via official script"
    else
        # In non-interactive mode, fail fast if sudo requires a password
        if [[ "${INTERACTIVE:-true}" != "true" ]] && ! sudo -n true 2>/dev/null; then
            ai_bad "Docker is not installed and sudo requires a password."
            ai_bad "In non-interactive mode, either:"
            ai "  1. Run with passwordless sudo (NOPASSWD in sudoers)"
            ai "  2. Install Docker manually first, then re-run with --skip-docker"
            ai "  3. Run the installer interactively (without --non-interactive)"
            error "Cannot install Docker without sudo in non-interactive mode."
        fi

        case "$PKG_MANAGER" in
            apt|zypper)
                # Docker CE via get.docker.com (supports Debian/Ubuntu/Fedora/SLES)
                if ! _docker_install_from_script; then
                    error "Docker installation failed. Check network connectivity and try again."
                fi
                ;;
            dnf)
                # Fedora works with get.docker.com; RHEL-family rebuilds need the
                # CentOS/RHEL Docker CE repo because the Rocky repo can be empty.
                if ! _docker_install_dnf_rhel_family && ! _docker_install_from_script; then
                    error "Docker installation failed. Check network connectivity and try again."
                fi
                ;;
            pacman)
                # Arch/Manjaro/CachyOS/EndeavourOS -- Docker is in the official repos
                pkg_install docker
                ods_sudo systemctl enable --now docker.service 2>>"$LOG_FILE" || true
                ;;
            xbps)
                # Void Linux -- runit service management
                pkg_install docker
                ods_sudo ln -s /etc/sv/docker /var/service/ 2>/dev/null || true
                ;;
            apk)
                # Alpine -- OpenRC service management
                pkg_install docker
                ods_sudo rc-update add docker boot 2>>"$LOG_FILE" || true
                ods_sudo service docker start 2>>"$LOG_FILE" || true
                ;;
            *)
                # Unknown distro -- try get.docker.com as best-effort fallback
                if ! _docker_install_from_script; then
                    error "Docker installation failed. Your distro (${DISTRO_ID:-unknown}) may not be supported. Install Docker manually and re-run with --skip-docker."
                fi
                ;;
        esac

        # Add the invoking user (not root) to the docker group
        target_user="${SUDO_USER:-$USER}"
        ods_sudo usermod -aG docker "$target_user"

        # In most cases group membership won't take effect until a new login shell.
        if ! id -nG "$target_user" 2>/dev/null | tr ' ' '\n' | grep -qx docker; then
            DOCKER_NEEDS_SUDO=true
        fi
    fi
fi

# Docker 29.3.x has a bug with /dev/dri device passthrough on AMD GPUs.
# Containers fail with: "error gathering device information while adding custom device /dev/dri"
# Pin to 29.2.x until this is resolved upstream.
# See: https://github.com/moby/moby/issues — device passthrough regression in 29.3.0
if command -v docker &>/dev/null && ! $DRY_RUN; then
    _docker_ver="$(_docker_server_version_for_amd_downgrade || echo "0.0.0")"
    if [[ "$_docker_ver" == 29.3.* ]] && [[ "${GPU_BACKEND:-}" == "amd" ]]; then
        ai_warn "Docker $_docker_ver has a known bug with AMD GPU device passthrough."
        ai "Downgrading to Docker 29.2.1 for AMD GPU compatibility..."
        # Detect package format
        if command -v apt-get &>/dev/null; then
            # Docker CE's apt version string embeds the distro id + codename,
            # e.g. 5:29.2.1-1~ubuntu.24.04~noble or 5:29.2.1-1~debian.13~trixie.
            # Resolve the exact installable 29.2.1 version from the configured
            # repo rather than hand-constructing it — hardcoding "~ubuntu" broke
            # the downgrade on Debian/derivatives (Debian trixie, AMD boxes).
            _docker_2921=$(apt-cache madison docker-ce 2>/dev/null \
                | awk '$3 ~ /(^|:)29\.2\.1/ {print $3; exit}')
            if [[ -n "$_docker_2921" ]]; then
                ods_sudo apt-get install -y --allow-downgrades \
                    docker-ce="$_docker_2921" docker-ce-cli="$_docker_2921" \
                    >> "$LOG_FILE" 2>&1 && \
                    ai_ok "Docker downgraded to 29.2.1 (AMD GPU fix)" || \
                    ai_warn "Could not downgrade Docker. GPU containers may fail. Manual fix: sudo apt install docker-ce=$_docker_2921"
            else
                ai_warn "Docker 29.2.1 not found in apt repos; cannot downgrade. AMD GPU containers may fail with /dev/dri passthrough errors."
                ai "  Manual fix: ensure Docker's apt repo is configured (get.docker.com), then 'apt-cache madison docker-ce' to find the 29.2.1 version string."
            fi
        elif command -v dnf &>/dev/null; then
            ods_sudo dnf downgrade -y docker-ce-29.2.1 docker-ce-cli-29.2.1 >> "$LOG_FILE" 2>&1 && \
                ai_ok "Docker downgraded to 29.2.1 (AMD GPU fix)" || \
                ai_warn "Could not downgrade Docker. GPU containers may fail."
        elif command -v pacman &>/dev/null; then
            # pacman does not support version pinning from official repos.
            # Warn the user with clear manual instructions.
            ai_warn "Automatic Docker downgrade is not supported on pacman-based distros."
            ai_warn "GPU containers may fail with device passthrough errors."
            ai "  Manual fix: downgrade Docker from the Arch Linux Archive:"
            ai "    sudo pacman -U https://archive.archlinux.org/packages/d/docker/docker-1%3A29.2.1-1-x86_64.pkg.tar.zst"
            ai "  Or wait for Docker to fix the bug in a future release."
        else
            ai_warn "Could not downgrade Docker on this system. GPU containers may fail."
        fi
        ods_sudo systemctl restart docker 2>/dev/null || true
    fi
fi

# Decide whether to use sudo for the rest of this installer session
if [[ "${DOCKER_CMD:-}" == "" ]]; then
    if $DOCKER_NEEDS_SUDO; then
        warn "Docker installed, but group membership may not be active yet (re-login required)."
        if [[ "${INTERACTIVE:-true}" == "true" ]]; then
            echo ""
            read -p "  Continue this installer using 'sudo docker' for now? [Y/n] " -r < /dev/tty
            if [[ $REPLY =~ ^[Nn]$ ]]; then
                log "Please re-run after logging out and back in (or after 'newgrp docker')."
                exit 0
            fi
        else
            warn "Non-interactive mode: continuing with 'sudo docker'."
        fi
        DOCKER_CMD="sudo docker"
        DOCKER_COMPOSE_CMD="sudo docker compose"
    fi
fi

# Set docker command (use sudo if needed)
DOCKER_CMD="${DOCKER_CMD:-docker}"
DOCKER_COMPOSE_CMD="${DOCKER_COMPOSE_CMD:-docker compose}"

# Docker Compose check (v2 preferred, v1 fallback)
ods_progress 33 "docker" "Checking Docker Compose"
if docker_compose_run version &> /dev/null 2>&1; then
    ai_ok "Docker Compose v2 available"
elif command -v docker-compose &> /dev/null; then
    if [[ "$DOCKER_CMD" == "sudo docker" ]]; then
        DOCKER_COMPOSE_CMD="sudo docker-compose"
    else
        DOCKER_COMPOSE_CMD="docker-compose"
    fi
    ai_ok "Docker Compose v1 available (using docker-compose)"
else
    if [[ "$SKIP_DOCKER" == "true" ]]; then
        warn "Docker Compose not found (docker compose / docker-compose). Install manually or re-run without --skip-docker."
    elif $DRY_RUN; then
        log "[DRY RUN] Would install Docker Compose plugin"
    else
        ai "Installing Docker Compose plugin..."
        pkg_update
        # shellcheck disable=SC2046
        pkg_install $(pkg_resolve docker-compose-plugin)
    fi
fi

# ---------------------------------------------------------------------------
# Runtime sanity checks
# ---------------------------------------------------------------------------
# Goal: make this phase resilient across:
# - fresh installs (daemon not started yet)
# - non-interactive runs (can't prompt)
# - sudo-required sessions (docker group not applied yet)
# - systems where docker exists but user permissions are wrong

_docker_try_with_optional_sudo() {
    # If DOCKER_CMD isn't already sudo docker, try docker first and fall back to sudo docker.
    if docker_run "$@" &>/dev/null; then
        return 0
    fi

    if [[ "$DOCKER_CMD" != "sudo docker" ]] && command -v sudo &>/dev/null; then
        DOCKER_CMD="sudo docker"
        DOCKER_COMPOSE_CMD="sudo docker compose"
        if docker_run "$@" &>/dev/null; then
            return 0
        fi
    fi

    return 1
}

_docker_daemon_start_hint() {
    warn "Docker daemon does not appear to be running or accessible."
    warn "Common fixes:"
    warn "  - Linux (systemd): sudo systemctl enable --now docker"
    warn "  - Linux (non-systemd): start dockerd using your init system"
    warn "  - WSL2: ensure Docker Desktop is running"
}

_docker_ensure_daemon() {
    # Returns 0 if docker responds to 'info' (with optional sudo fallback).
    # If not, tries to start docker on systemd systems, then retries.

    if _docker_try_with_optional_sudo info; then
        return 0
    fi

    # Try to start docker service if systemd is present
    if command -v systemctl &>/dev/null; then
        ai_warn "Docker not responding; attempting to start docker service..."
        if ! $DRY_RUN; then
            # Clear start-limit-hit if docker has been restarted too many times
            if systemctl is-failed docker &>/dev/null; then
                ai_warn "Docker is in failed state (possible start-limit-hit). Resetting..."
                ods_sudo systemctl reset-failed docker 2>>"$LOG_FILE" || true
            fi
            ods_sudo systemctl start docker 2>>"$LOG_FILE" || true
            # Give the daemon a moment to initialize
            sleep 2
        fi
        if _docker_try_with_optional_sudo info; then
            return 0
        fi
    fi

    _docker_daemon_start_hint
    return 1
}

_docker_compose_detect_cmd() {
    # Prefer v2 (docker compose). If docker requires sudo, wrapper will handle it.
    if docker_compose_run version &>/dev/null 2>&1; then
        echo "docker compose"
        return 0
    fi

    # v1 fallback
    if command -v docker-compose &>/dev/null; then
        echo "docker-compose"
        return 0
    fi

    echo ""
    return 1
}

_docker_compose_verify() {
    local detected
    detected="$(_docker_compose_detect_cmd || true)"

    if [[ -n "$detected" ]]; then
        ai_ok "Compose detected: $detected"
        return 0
    fi

    return 1
}

_docker_configure_data_root() {
    local desired current desired_real current_real daemon_json backup should_migrate
    desired="${YUYINODS_DOCKER_ROOT:-/home/parallax/ODS/root-container}"
    daemon_json="/etc/docker/daemon.json"

    [[ -n "$desired" ]] || return 0
    if ! mkdir -p "$desired/tmp" 2>>"$LOG_FILE"; then
        ods_sudo mkdir -p "$desired/tmp" 2>>"$LOG_FILE" || {
            warn "Could not create Docker data-root temp dir: $desired/tmp"
            return 0
        }
    fi

    current="$(docker_run info --format '{{.DockerRootDir}}' 2>/dev/null || true)"
    [[ -n "$current" ]] || return 0
    desired_real="$(readlink -f "$desired" 2>/dev/null || printf '%s\n' "$desired")"
    current_real="$(readlink -f "$current" 2>/dev/null || printf '%s\n' "$current")"
    if [[ "$current" == "$desired" || "$current_real" == "$desired_real" ]]; then
        log "Docker data-root already uses YuyinODS root-container: $current"
        return 0
    fi

    should_migrate=false
    case "$current_real" in
        /media/parallax/ods|/media/parallax/ods/*|*/ODS/root-container)
            should_migrate=true
            ;;
    esac
    [[ "${YUYINODS_CONFIGURE_DOCKER_ROOT:-false}" == "true" ]] && should_migrate=true

    if [[ "$should_migrate" != "true" ]]; then
        warn "Docker data-root is $current, not $desired."
        warn "Set YUYINODS_CONFIGURE_DOCKER_ROOT=true to let the installer update /etc/docker/daemon.json."
        return 0
    fi

    ai "Configuring Docker data-root: $desired"
    backup="${daemon_json}.bak.$(date +%Y%m%d%H%M%S)"
    ods_sudo mkdir -p /etc/docker "$desired/tmp" 2>>"$LOG_FILE" || true
    [[ -f "$daemon_json" ]] && ods_sudo cp "$daemon_json" "$backup" 2>>"$LOG_FILE" || true

    if ! python3 - "$daemon_json" "$desired" > "${YUYINODS_TEMP_DIR:-/tmp}/daemon.json.yuyinods.$$" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
desired = sys.argv[2]
data = {}
if path.exists():
    text = path.read_text(encoding="utf-8").strip()
    if text:
        data = json.loads(text)
data["data-root"] = desired
print(json.dumps(data, indent=2, sort_keys=True))
PY
    then
        warn "Could not render updated Docker daemon.json; leaving Docker data-root unchanged."
        return 0
    fi

    if ! ods_sudo install -m 0644 "${YUYINODS_TEMP_DIR:-/tmp}/daemon.json.yuyinods.$$" "$daemon_json" 2>>"$LOG_FILE"; then
        rm -f "${YUYINODS_TEMP_DIR:-/tmp}/daemon.json.yuyinods.$$"
        warn "Could not write $daemon_json; leaving Docker data-root unchanged."
        return 0
    fi
    rm -f "${YUYINODS_TEMP_DIR:-/tmp}/daemon.json.yuyinods.$$"

    if command -v systemctl >/dev/null 2>&1; then
        ai "Restarting Docker to apply data-root change..."
        ods_sudo systemctl restart docker 2>>"$LOG_FILE" || {
            warn "Docker restart failed after data-root update. Restore from $backup if needed."
            return 0
        }
        sleep 2
        if _docker_ensure_daemon; then
            current="$(docker_run info --format '{{.DockerRootDir}}' 2>/dev/null || true)"
            current_real="$(readlink -f "$current" 2>/dev/null || printf '%s\n' "$current")"
            if [[ "$current" == "$desired" || "$current_real" == "$desired_real" ]]; then
                ai_ok "Docker data-root is now $desired"
            else
                warn "Docker data-root is still ${current:-unknown}; expected $desired"
            fi
        fi
    else
        warn "Docker daemon.json updated, but systemctl is unavailable. Restart Docker before continuing."
    fi
}

_docker_configure_containerd_root() {
    local desired desired_real current current_real config backup tmp
    desired="${YUYINODS_CONTAINERD_ROOT:-${YUYINODS_DOCKER_ROOT:-/home/parallax/ODS/root-container}/containerd}"
    config="/etc/containerd/config.toml"

    [[ -n "$desired" ]] || return 0
    if ! mkdir -p "$desired" 2>>"$LOG_FILE"; then
        ods_sudo mkdir -p "$desired" 2>>"$LOG_FILE" || {
            warn "Could not create containerd root: $desired"
            return 0
        }
    fi

    current=""
    if [[ -f "$config" ]]; then
        current="$(sed -n 's/^[[:space:]]*root[[:space:]]*=[[:space:]]*"\(.*\)".*/\1/p' "$config" 2>/dev/null | head -n 1 || true)"
    fi
    current="${current:-/var/lib/containerd}"
    desired_real="$(readlink -f "$desired" 2>/dev/null || printf '%s\n' "$desired")"
    current_real="$(readlink -f "$current" 2>/dev/null || printf '%s\n' "$current")"

    if [[ "$current" == "$desired" || "$current_real" == "$desired_real" ]]; then
        log "containerd root already uses YuyinODS root-container: $current"
        return 0
    fi

    case "$current_real" in
        /var/lib/containerd|/media/parallax/ods/*|*/ODS/root-container/containerd)
            ;;
        *)
            if [[ "${YUYINODS_CONFIGURE_CONTAINERD_ROOT:-false}" != "true" ]]; then
                warn "containerd root is $current, not $desired."
                warn "Set YUYINODS_CONFIGURE_CONTAINERD_ROOT=true to let the installer update $config."
                return 0
            fi
            ;;
    esac

    ai "Configuring containerd root: $desired"
    ods_sudo mkdir -p /etc/containerd "$desired" 2>>"$LOG_FILE" || true
    backup="${config}.bak.$(date +%Y%m%d%H%M%S)"
    [[ -f "$config" ]] && ods_sudo cp "$config" "$backup" 2>>"$LOG_FILE" || true

    tmp="${YUYINODS_TEMP_DIR:-/tmp}/containerd.toml.yuyinods.$$"
    if ! python3 - "$config" "$desired" > "$tmp" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
desired = sys.argv[2]
lines = path.read_text(encoding="utf-8").splitlines() if path.exists() else []
out = []
set_root = False
inserted = False
root_re = re.compile(r'^(\s*#?\s*)root\s*=')

for line in lines:
    if root_re.match(line) and not set_root:
        out.append(f'root = "{desired}"')
        set_root = True
        inserted = True
        continue
    out.append(line)

if not inserted:
    if out:
        out.append("")
    out.append(f'root = "{desired}"')

print("\n".join(out) + "\n")
PY
    then
        warn "Could not render updated containerd config; leaving containerd root unchanged."
        return 0
    fi

    if ! ods_sudo install -m 0644 "$tmp" "$config" 2>>"$LOG_FILE"; then
        rm -f "$tmp"
        warn "Could not write $config; leaving containerd root unchanged."
        return 0
    fi
    rm -f "$tmp"

    if command -v systemctl >/dev/null 2>&1; then
        ai "Restarting containerd and Docker to apply containerd root..."
        ods_sudo systemctl restart containerd 2>>"$LOG_FILE" || {
            warn "containerd restart failed after root update. Restore from $backup if needed."
            return 0
        }
        ods_sudo systemctl restart docker 2>>"$LOG_FILE" || {
            warn "Docker restart failed after containerd root update. Restore from $backup if needed."
            return 0
        }
        sleep 2
        _docker_ensure_daemon || warn "Docker did not respond after containerd root update."
    else
        warn "containerd config updated, but systemctl is unavailable. Restart containerd and Docker before continuing."
    fi
}

_docker_post_install_checks() {
    # Best-effort checks. Should not hard-fail in dry-run.
    if $DRY_RUN; then
        log "[DRY RUN] Skipping docker runtime checks"
        return 0
    fi

    # Ensure daemon is reachable (and set DOCKER_CMD to sudo docker if needed)
    if ! _docker_ensure_daemon; then
        error "Docker is installed but not usable (daemon not running or permissions issue)."
    fi

    _docker_configure_data_root
    _docker_configure_containerd_root

    # Show effective docker command (for later phases)
    log "Using docker command: $DOCKER_CMD"

    # Verify compose availability; if missing, install compose plugin when possible.
    if ! _docker_compose_verify; then
        if [[ "$SKIP_DOCKER" == "true" ]]; then
            warn "Compose missing and --skip-docker set; cannot install compose automatically."
            return 0
        fi

        ai_warn "Docker Compose not detected; attempting install of compose plugin..."
        pkg_update
        # shellcheck disable=SC2046
        pkg_install $(pkg_resolve docker-compose-plugin) || true

        if ! _docker_compose_verify; then
            warn "Compose still not detected after install attempt."
            warn "You may need to install Docker Compose manually for your distro."
        fi
    fi

    # Basic engine health
    if docker_run version &>/dev/null 2>&1; then
        ai_ok "Docker engine responding"
    else
        warn "Docker engine did not respond to 'docker version'"
    fi

    # Optional: give the user a clear hint if they are likely missing group perms
    if [[ "$DOCKER_CMD" == "sudo docker" ]]; then
        warn "Docker commands are running via sudo in this installer session."
        warn "After the install finishes, log out/in (or run 'newgrp docker') to use docker without sudo."
    fi
}

ods_progress 35 "docker" "Running Docker post-install checks"
_docker_post_install_checks

# NVIDIA Container Toolkit (skip for AMD — uses /dev/dri + /dev/kfd passthrough)
if [[ $GPU_COUNT -gt 0 && "$GPU_BACKEND" == "nvidia" ]]; then
    ods_progress 36 "docker" "Checking NVIDIA Container Toolkit"
    if command -v nvidia-container-cli &> /dev/null 2>&1; then
        ai_ok "NVIDIA Container Toolkit installed"
        # Always regenerate CDI spec — driver version may have changed since last run
        if command -v nvidia-ctk &>/dev/null && ! $DRY_RUN; then
            ods_sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml 2>>"$LOG_FILE" || true
        fi
    else
        ai "Installing NVIDIA Container Toolkit..."
        if ! $DRY_RUN; then
            # Distro-aware repo setup + install
            case "$PKG_MANAGER" in
                apt)
                    # Add NVIDIA GPG key (apt's signed-by trust anchor for the toolkit repo)
                    curl -fsSL --max-time 60 https://nvidia.github.io/libnvidia-container/gpgkey | \
                        ods_sudo gpg --batch --yes --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
                    if [[ ! -s /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg ]]; then
                        error "NVIDIA Container Toolkit keyring download failed (empty or missing /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg). Check network connectivity to nvidia.github.io."
                    fi
                    # Fingerprint pin: defense against MITM at the CDN/DNS edge serving
                    # nvidia.github.io. NVIDIA does not publish this fingerprint in their
                    # install docs (industry-wide gap), but the value is derivable from
                    # the public key file at the canonical URL.
                    # Source: extracted from the gpgkey blob at
                    # https://nvidia.github.io/libnvidia-container/gpgkey on 2026-05-03
                    # via: gpg --with-colons --import-options show-only --import.
                    # If NVIDIA rotates the key, update this constant and bump the date.
                    _nvidia_expected_fp="C95B321B61E88C1809C4F759DDCAE044F796ECB0"
                    # Read keyring without sudo — /usr/share/keyrings/*.gpg is world-readable
                    # (dearmor output of a public key). show-only avoids touching any keyring.
                    _nvidia_actual_fp=$(gpg --with-colons --import-options show-only --import \
                        /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg 2>/dev/null \
                        | awk -F: '/^fpr:/ {print $10; exit}')
                    if [[ -z "$_nvidia_actual_fp" ]]; then
                        warn "Could not extract fingerprint from downloaded NVIDIA keyring — proceeding without pin verification."
                    elif [[ "$_nvidia_actual_fp" != "$_nvidia_expected_fp" ]]; then
                        warn "NVIDIA Container Toolkit GPG fingerprint MISMATCH:"
                        warn "  expected: $_nvidia_expected_fp"
                        warn "  got:      $_nvidia_actual_fp"
                        warn "Possible MITM, or NVIDIA rotated the key. Manually verify against NVIDIA's published fingerprint before trusting."
                        warn "Proceeding because operator chose pin-and-warn over hard-fail. Set YUYINODS_GPG_HARD_FAIL=1 to error instead."
                        if [[ "${YUYINODS_GPG_HARD_FAIL:-}" == "1" ]]; then
                            error "Aborting due to GPG fingerprint mismatch (YUYINODS_GPG_HARD_FAIL=1)."
                        fi
                    else
                        log "NVIDIA Container Toolkit GPG fingerprint verified: $_nvidia_expected_fp"
                    fi
                    unset _nvidia_expected_fp _nvidia_actual_fp
                    curl -s -L --max-time 60 https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
                        sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
                        ods_sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list > /dev/null
                    # Verify we got a valid repo file, not an HTML 404
                    if grep -q '<html' /etc/apt/sources.list.d/nvidia-container-toolkit.list 2>/dev/null; then
                        warn "Failed to download NVIDIA Container Toolkit repo list. Trying fallback..."
                        echo "deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://nvidia.github.io/libnvidia-container/stable/deb/\$(ARCH) /" | \
                            ods_sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list > /dev/null
                    fi
                    ods_sudo apt-get update
                    if ! ods_sudo apt-get install -y nvidia-container-toolkit; then
                        error "Failed to install NVIDIA Container Toolkit. Check network connectivity and GPU drivers."
                    fi
                    ;;
                dnf)
                    curl -s -L --max-time 60 https://nvidia.github.io/libnvidia-container/stable/rpm/nvidia-container-toolkit.repo | \
                        ods_sudo tee /etc/yum.repos.d/nvidia-container-toolkit.repo > /dev/null
                    if ! ods_sudo dnf install -y nvidia-container-toolkit 2>>"$LOG_FILE"; then
                        error "Failed to install NVIDIA Container Toolkit. Check network connectivity and NVIDIA repo configuration."
                    fi
                    ;;
                pacman)
                    # nvidia-container-toolkit is in AUR; check for common AUR helpers
                    if command -v yay &>/dev/null; then
                        yay -S --noconfirm nvidia-container-toolkit 2>>"$LOG_FILE" || \
                            error "Failed to install nvidia-container-toolkit via yay."
                    elif command -v paru &>/dev/null; then
                        paru -S --noconfirm nvidia-container-toolkit 2>>"$LOG_FILE" || \
                            error "Failed to install nvidia-container-toolkit via paru."
                    else
                        warn "nvidia-container-toolkit requires an AUR helper (yay or paru)."
                        warn "Install one, then run: yay -S nvidia-container-toolkit"
                        error "No AUR helper found. Install yay or paru first."
                    fi
                    ;;
                zypper)
                    ods_sudo zypper addrepo https://nvidia.github.io/libnvidia-container/stable/rpm/nvidia-container-toolkit.repo 2>/dev/null || true
                    ods_sudo zypper --non-interactive --gpg-auto-import-keys refresh 2>>"$LOG_FILE"
                    if ! ods_sudo zypper --non-interactive install nvidia-container-toolkit 2>>"$LOG_FILE"; then
                        error "Failed to install NVIDIA Container Toolkit."
                    fi
                    ;;
                *)
                    error "Cannot install NVIDIA Container Toolkit: unsupported package manager '${PKG_MANAGER}'. Install it manually: https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html"
                    ;;
            esac

            ods_sudo nvidia-ctk runtime configure --runtime=docker
            ods_sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml 2>>"$LOG_FILE" || true
            ods_sudo systemctl restart docker
        fi
        if command -v nvidia-container-cli &> /dev/null 2>&1; then
            ai_ok "NVIDIA Container Toolkit installed"
        else
            $DRY_RUN && ai_ok "[DRY RUN] Would install NVIDIA Container Toolkit" || error "NVIDIA Container Toolkit installation failed — nvidia-container-cli not found after install."
        fi
    fi
fi
