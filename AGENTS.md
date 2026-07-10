# AGENTS.md

Guidance for coding agents working in this repository.

## Project

This repository is the YuyinODS local AI stack. The main product code and
installer live under `yuyinods/`. The root `install.sh` is a thin launcher for
`yuyinods/install-core.sh`.

## Current Priority

The current active work is installer hardening for the target Linux machine:

- AMD APU/unified-memory GPU detection.
- Correct AMD/Lemonade runtime configuration.
- Model downloads under `/home/parallax/ODS/models`.
- Docker root/data under `/home/parallax/ODS/root-container`.
- Temp/log files under `/home/parallax/ODS/temp`.
- App files under `/home/parallax/ODS/yuyinods`.
- Build pressure capped around 80% CPU/RAM.

`/home/parallax/ODS` is expected to resolve to `/mnt/ods` on the target host.

## Do Not Break

- Do not revert user changes unless explicitly asked.
- Do not move persistent model, Docker, data, or install paths back under the
  repo checkout, `$HOME` defaults, `/var/lib/docker`, or arbitrary `/tmp`.
- Do not re-enable ComfyUI on AMD `gfx9012` with the current `gfx1151` image.
  That causes CPU fallback or ROCm hangs on the target hardware.
- Do not assume `/mnt/ods` is writable inside the agent sandbox. Sandbox dry-run
  fallback to `/tmp` is not the same as target host behavior.
- Do not mark installer work complete from dry-run alone. A real install with
  Docker running is required to prove the full objective.

## Editing Rules

- Prefer small, targeted patches.
- Use `rg` for searches.
- Use `apply_patch` for manual file edits.
- Keep shell scripts compatible with Bash.
- Preserve existing installer phase structure.
- Avoid broad rebrands or comment-only churn unless directly requested.

## Validation Commands

Run these from the repo root after installer changes:

```bash
bash -n yuyinods/installers/phases/03-features.sh \
  yuyinods/installers/phases/11-services.sh \
  yuyinods/installers/phases/12-health.sh \
  yuyinods/installers/lib/background-tasks.sh

bash yuyinods/tests/test-validate-env.sh
bash yuyinods/tests/test-amd-topo.sh
bash yuyinods/scripts/detect-hardware.sh --json
bash yuyinods/scripts/build-capability-profile.sh --output /tmp/yuyinods-capabilities-check.json
git diff --check
./install.sh --dry-run --non-interactive --comfyui --skip-docker
```

Expected current baseline:

- Env validation: `9 passed, 0 failed`
- AMD topology: `23 passed, 0 failed`
- Dry-run exits `0`
- Dry-run disables ComfyUI on `gfx9012`

## Hardware Facts For This Host

The target machine has:

- AMD Ryzen 5 5600G with Radeon Graphics
- AMD GPU device `0x1638`
- AMD gfx version `gfx9012`
- 512 MB dedicated VRAM aperture
- About 10 GB effective unified/GTT memory
- 14 GB system RAM

The installer should classify this as:

- `GPU_BACKEND=amd`
- `GPU_MEMORY_TYPE=unified`
- `TIER=SH_COMPACT`
- AMD runtime via Lemonade

## Path Contract

Generated `.env` should contain:

```dotenv
YUYINODS_BASE_DIR=/home/parallax/ODS
YUYINODS_APP_DIR=/home/parallax/ODS/yuyinods
YUYINODS_MODELS_DIR=/home/parallax/ODS/models
YUYINODS_TEMP_DIR=/home/parallax/ODS/temp
YUYINODS_DOCKER_ROOT=/home/parallax/ODS/root-container
YUYINODS_DATA_DIR=/home/parallax/ODS/root-container/data
YUYINODS_CONFIG_DIR=/home/parallax/ODS/yuyinods/config
YUYINODS_BUILD_CPU_PERCENT=80
YUYINODS_BUILD_RAM_PERCENT=80
COMPOSE_BAKE=false
```

The install phase should symlink:

```text
/home/parallax/ODS/yuyinods/data -> /home/parallax/ODS/root-container/data
/home/parallax/ODS/yuyinods/data/models -> /home/parallax/ODS/models
```

## Git

The working branch is usually `rebrand-yuyinods`. Push completed installer fixes
to `origin rebrand-yuyinods` when the user asks to push or when continuing the
existing pushed workflow.

