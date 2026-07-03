#!/bin/bash
# YuyinODS Root Installer
# Delegates to yuyinods/install.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}YuyinODS Installer${NC}"
echo ""

# Check if yuyinods directory exists
if [ ! -d "$SCRIPT_DIR/yuyinods" ]; then
    echo "Error: yuyinods directory not found"
    echo "Expected: $SCRIPT_DIR/yuyinods"
    exit 1
fi

# Delegate to yuyinods installer
cd "$SCRIPT_DIR/yuyinods"
exec ./install.sh "$@"
