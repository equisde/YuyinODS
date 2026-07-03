#!/usr/bin/env bash
# Static checks for voice doctor/repair command wiring.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
YUYINODS_CLI="$ROOT_DIR/yuyinods-cli"
YUYINODS_DOCTOR="$ROOT_DIR/scripts/yuyinods-doctor.sh"
WINDOWS_CLI="$ROOT_DIR/installers/windows/yuyinods.ps1"

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'
PASS=0
FAIL=0

pass() { echo -e "  ${GREEN}PASS${NC} $1"; PASS=$((PASS + 1)); }
fail() { echo -e "  ${RED}FAIL${NC} $1"; FAIL=$((FAIL + 1)); }

echo ""
echo "=== Voice repair command tests ==="
echo ""

[[ -f "$YUYINODS_CLI" ]] && pass "yuyinods-cli exists" || fail "yuyinods-cli missing"
[[ -f "$YUYINODS_DOCTOR" ]] && pass "yuyinods-doctor.sh exists" || fail "yuyinods-doctor.sh missing"
[[ -f "$WINDOWS_CLI" ]] && pass "Windows yuyinods.ps1 exists" || fail "Windows yuyinods.ps1 missing"

grep -q '^cmd_repair()' "$YUYINODS_CLI" && pass "yuyinods-cli defines cmd_repair" || fail "cmd_repair missing"
grep -q 'cmd_stt download' "$YUYINODS_CLI" && pass "repair reuses STT download command" || fail "repair does not cache STT model"
grep -q 'Starting voice services' "$YUYINODS_CLI" && pass "repair starts voice services" || fail "repair does not start voice services"
grep -q 'Voice Readiness' "$YUYINODS_CLI" && pass "doctor displays voice readiness" || fail "doctor voice readiness missing"
grep -q 'repair|fix \[voice\]' "$YUYINODS_CLI" && pass "help documents repair voice" || fail "help missing repair voice"

grep -q '"tts_http"' "$YUYINODS_DOCTOR" && pass "doctor report includes TTS status" || fail "doctor missing TTS status"
grep -q 'ods repair voice' "$YUYINODS_DOCTOR" && pass "doctor suggests repair voice" || fail "doctor missing repair hint"

grep -q 'function Invoke-Doctor' "$WINDOWS_CLI" && pass "Windows CLI defines doctor" || fail "Windows doctor missing"
grep -q 'function Invoke-RepairVoice' "$WINDOWS_CLI" && pass "Windows CLI defines repair voice" || fail "Windows repair voice missing"
grep -q '".*doctor".*Invoke-Doctor' "$WINDOWS_CLI" && pass "Windows dispatch includes doctor" || fail "Windows doctor dispatch missing"
grep -q '".*repair".*Invoke-Repair' "$WINDOWS_CLI" && pass "Windows dispatch includes repair" || fail "Windows repair dispatch missing"
grep -q 'repair voice' "$WINDOWS_CLI" && pass "Windows help documents repair voice" || fail "Windows help missing repair voice"

if bash -n "$YUYINODS_CLI" 2>/dev/null; then
    pass "yuyinods-cli syntax valid"
else
    fail "yuyinods-cli syntax invalid"
fi

if bash -n "$YUYINODS_DOCTOR" 2>/dev/null; then
    pass "yuyinods-doctor syntax valid"
else
    fail "yuyinods-doctor syntax invalid"
fi

echo ""
echo "Result: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
