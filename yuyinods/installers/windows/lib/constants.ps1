# ============================================================================
# ODS Windows Installer -- Constants
# ============================================================================
# Part of: installers/windows/lib/
# Purpose: Version, paths, colors, configuration defaults
#
# Canonical source: installers/lib/constants.sh (keep VERSION in sync)
#
# Modder notes:
#   Change YUYINODS_VERSION for custom builds. Must match constants.sh VERSION.
# ============================================================================

$script:YUYINODS_VERSION = "2.5.3"

# Install location (override via $env:YUYINODS_HOME, $env:YUYINODS_APP_DIR, or $env:YUYINODS_HOME)
# NOTE: $(if ...) syntax required for PS 5.1 compatibility (bare if-as-expression is PS 7+ only)
$script:YUYINODS_BASE_DIR = $(if ($env:YUYINODS_BASE_DIR) { $env:YUYINODS_BASE_DIR } else { "/home/parallax/ODS" })
$script:YUYINODS_INSTALL_DIR = $(if ($env:YUYINODS_HOME) { $env:YUYINODS_HOME } elseif ($env:YUYINODS_APP_DIR) { $env:YUYINODS_APP_DIR } else { Join-Path $script:YUYINODS_BASE_DIR "yuyinods" })
$script:YUYINODS_APP_DIR = $script:YUYINODS_INSTALL_DIR
$script:YUYINODS_MODELS_DIR = $(if ($env:YUYINODS_MODELS_DIR) { $env:YUYINODS_MODELS_DIR } else { Join-Path $script:YUYINODS_BASE_DIR "models" })
$script:YUYINODS_TEMP_DIR = $(if ($env:YUYINODS_TEMP_DIR) { $env:YUYINODS_TEMP_DIR } else { Join-Path $script:YUYINODS_BASE_DIR "temp" })
$script:YUYINODS_DOCKER_ROOT = $(if ($env:YUYINODS_DOCKER_ROOT) { $env:YUYINODS_DOCKER_ROOT } else { Join-Path $script:YUYINODS_BASE_DIR "root-container" })
New-Item -ItemType Directory -Path $script:YUYINODS_TEMP_DIR -Force -ErrorAction SilentlyContinue | Out-Null

# Logging
$script:YUYINODS_LOG_FILE = Join-Path $script:YUYINODS_TEMP_DIR "yuyinods-install.log"
$script:YUYINODS_PREFLIGHT_REPORT = Join-Path $script:YUYINODS_TEMP_DIR "yuyinods-windows-preflight.json"

# Native inference server paths (AMD path)
# PID file is shared -- only one native inference server runs at a time
$script:INFERENCE_PID_FILE = Join-Path (Join-Path $script:YUYINODS_INSTALL_DIR "data") "llama-server.pid"

# AMD Lemonade (preferred AMD backend: Vulkan + NPU + ROCm)
$script:LEMONADE_VERSION     = "10.0.0"
$script:LEMONADE_MSI_FILE    = "lemonade-server-minimal.msi"
$script:LEMONADE_MSI_URL     = "https://github.com/lemonade-sdk/lemonade/releases/download/v$($script:LEMONADE_VERSION)/$($script:LEMONADE_MSI_FILE)"
# Default path; install-windows.ps1 resolves both Program Files roots at runtime.
$script:LEMONADE_INSTALL_DIR = Join-Path $env:ProgramFiles "Lemonade Server"
$script:LEMONADE_EXE         = Join-Path (Join-Path $script:LEMONADE_INSTALL_DIR "bin") "lemonade-server.exe"
$script:LEMONADE_PORT        = 8080
$script:LEMONADE_API_KEY     = "lemonade"
$script:LEMONADE_HEALTH_URL  = "http://localhost:8080/api/v1/health"

# llama-server fallback (Vulkan build, used if Lemonade install is declined/fails)
$script:LLAMA_SERVER_DIR = Join-Path $script:YUYINODS_INSTALL_DIR "llama-server"
$script:LLAMA_SERVER_EXE = Join-Path $script:LLAMA_SERVER_DIR "llama-server.exe"
$script:LLAMA_CPP_RELEASE_TAG = "b8248"
$script:LLAMA_CPP_VULKAN_ASSET = "llama-$($script:LLAMA_CPP_RELEASE_TAG)-bin-win-vulkan-x64.zip"
$script:LLAMA_CPP_VULKAN_URL = "https://github.com/ggml-org/llama.cpp/releases/download/$($script:LLAMA_CPP_RELEASE_TAG)/$($script:LLAMA_CPP_VULKAN_ASSET)"

# Docker
$script:DOCKER_COMPOSE_CMD = "docker compose"
$script:MIN_DOCKER_VERSION = "4.20.0"

# Minimum NVIDIA driver version for CUDA in Docker Desktop
$script:MIN_NVIDIA_DRIVER = 570

# OpenCode (host-level AI coding IDE, not a Docker service)
$script:OPENCODE_VERSION = "1.2.18"
$script:OPENCODE_ZIP = "opencode-windows-x64.zip"
$script:OPENCODE_URL = "https://github.com/anomalyco/opencode/releases/download/v$($script:OPENCODE_VERSION)/$($script:OPENCODE_ZIP)"
$script:OPENCODE_DIR = Join-Path $env:USERPROFILE ".opencode"
$script:OPENCODE_BIN = Join-Path (Join-Path $env:USERPROFILE ".opencode") "bin"
$script:OPENCODE_EXE = Join-Path (Join-Path $env:USERPROFILE ".opencode") "bin\opencode.exe"
$script:OPENCODE_CONFIG_DIR = Join-Path (Join-Path $env:USERPROFILE ".config") "opencode"
$script:OPENCODE_PORT = 3003

# ODS Host Agent (host-level extension lifecycle manager)
$script:YUYINODS_AGENT_PORT       = 7710
$script:YUYINODS_AGENT_PID_FILE   = Join-Path (Join-Path $script:YUYINODS_INSTALL_DIR "data") "yuyinods-host-agent.pid"
$script:YUYINODS_AGENT_LOG_FILE   = Join-Path (Join-Path $script:YUYINODS_INSTALL_DIR "data") "yuyinods-host-agent.log"
$script:YUYINODS_AGENT_HEALTH_URL = "http://127.0.0.1:7710/health"
$script:YUYINODS_AGENT_TASK_NAME  = "ODSHostAgent"

# Timing
$script:INSTALL_START = Get-Date

# ============================================================================
# Colors -- green phosphor CRT theme (PowerShell console colors)
# ============================================================================
$script:C = @{
    Red       = "Red"
    Green     = "Green"
    BrightGrn = "DarkGreen"
    DimGrn    = "DarkGray"
    Amber     = "Yellow"
    White     = "White"
    Cyan      = "Cyan"
    Reset     = "Gray"
}
