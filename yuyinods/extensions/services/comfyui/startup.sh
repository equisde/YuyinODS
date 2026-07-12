#!/bin/bash
#=============================================================================
# startup.sh — ComfyUI Container Entrypoint
#
# Sets up model symlinks from bind-mounted /models into ComfyUI's expected
# directory structure, links output/input dirs, copies workflow templates,
# and launches the ComfyUI server.
#=============================================================================

set -euo pipefail

COMFYUI_DIR="/opt/comfyui"
MODELS_MOUNT="/models"
OUTPUT_MOUNT="/output"
INPUT_MOUNT="/input"
WORKFLOWS_MOUNT="/workflows"

#-----------------------------------------------------------------------------
# Create model subdirectories in bind mount (idempotent)
#-----------------------------------------------------------------------------
for subdir in checkpoints text_encoders diffusion_models vae latent_upscale_models loras; do
    mkdir -p "${MODELS_MOUNT}/${subdir}"
done

#-----------------------------------------------------------------------------
# Symlink bind-mounted model dirs → ComfyUI's models/ tree
#-----------------------------------------------------------------------------
MODEL_TARGET="${COMFYUI_DIR}/models"

for subdir in checkpoints text_encoders diffusion_models vae latent_upscale_models loras; do
    target="${MODEL_TARGET}/${subdir}"
    # Remove existing dir/link and replace with symlink
    if [ -L "$target" ]; then
        rm "$target"
    elif [ -d "$target" ]; then
        rm -rf "$target"
    fi
    ln -s "${MODELS_MOUNT}/${subdir}" "$target"
done

#-----------------------------------------------------------------------------
# Symlink output and input directories
#-----------------------------------------------------------------------------
for pair in "output:${OUTPUT_MOUNT}" "input:${INPUT_MOUNT}"; do
    dir_name="${pair%%:*}"
    mount_path="${pair#*:}"
    target="${COMFYUI_DIR}/${dir_name}"
    if [ -L "$target" ]; then
        rm "$target"
    elif [ -d "$target" ]; then
        rm -rf "$target"
    fi
    ln -s "$mount_path" "$target"
done

#-----------------------------------------------------------------------------
# Copy workflow templates (read-only mount → writable user dir)
#-----------------------------------------------------------------------------
if [ -d "$WORKFLOWS_MOUNT" ] && [ "$(ls -A "$WORKFLOWS_MOUNT" 2>/dev/null)" ]; then
    WORKFLOW_DIR="${COMFYUI_DIR}/user/default/workflows"
    mkdir -p "$WORKFLOW_DIR"
    cp -u "$WORKFLOWS_MOUNT"/*.json "$WORKFLOW_DIR/" 2>/dev/null || true
    echo "[startup] Copied workflow templates to ${WORKFLOW_DIR}"
fi

#-----------------------------------------------------------------------------
# Launch ComfyUI
#-----------------------------------------------------------------------------
echo "[startup] Starting ComfyUI server..."
cd "$COMFYUI_DIR"

# Patch torch.library.custom_op, torch.serialization.add_safe_globals, and torch.nn.RMSNorm for PyTorch < 2.4 compatibility
if [ -f "main.py" ]; then
    if ! grep -q "torch.library.custom_op" main.py; then
        echo "[startup] Patching main.py for PyTorch < 2.4 compatibility..."
        cat << 'EOF' > main.py.tmp
import torch
if not hasattr(torch.library, 'custom_op'):
    def dummy_custom_op(*args, **kwargs):
        def decorator(func):
            return func
        return decorator
    torch.library.custom_op = dummy_custom_op
if not hasattr(torch.serialization, 'add_safe_globals'):
    torch.serialization.add_safe_globals = lambda *args, **kwargs: None
if not hasattr(torch.nn, 'RMSNorm'):
    class PyTorchRMSNorm(torch.nn.Module):
        def __init__(self, normalized_shape, eps=1e-6, elementwise_affine=True, device=None, dtype=None):
            super().__init__()
            self.eps = eps
            self.normalized_shape = (normalized_shape,) if isinstance(normalized_shape, int) else tuple(normalized_shape)
            if elementwise_affine:
                self.weight = torch.nn.Parameter(torch.ones(self.normalized_shape, device=device, dtype=dtype))
            else:
                self.register_parameter('weight', None)
        def forward(self, x):
            variance = x.pow(2).mean(-1, keepdim=True)
            x = x * torch.rsqrt(variance + self.eps)
            if self.weight is not None:
                return self.weight * x
            return x
    torch.nn.RMSNorm = PyTorchRMSNorm
EOF
        cat main.py >> main.py.tmp
        mv main.py.tmp main.py
    fi
fi

pip install --user "numpy<2" || true

PYTHON_CMD="python3"
if command -v python3 >/dev/null 2>&1 && python3 -c 'import sys; sys.exit(0)' >/dev/null 2>&1; then
    PYTHON_CMD="python3"
elif command -v python >/dev/null 2>&1 && python -c 'import sys; sys.exit(0)' >/dev/null 2>&1; then
    PYTHON_CMD="python"
fi

exec "$PYTHON_CMD" main.py --listen 0.0.0.0 --port 8188
