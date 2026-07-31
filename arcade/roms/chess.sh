#!/usr/bin/env bash
# ============================================================
#  MAESTRO CHESS  --  arcade launcher
# ============================================================
#  Real chess on the Maestro substrate. python-chess is the
#  referee; any seat is you, the CPU engine, or a GPU model.
#  Every move becomes a thermal cue-mem token, hex-addressed by
#  the position's VRGB eval-color.
#
#  This ROM is the front-end: pick a matchup, choose models, and
#  hand off to the python game loop.
# ============================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MAESTRO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

source "${SCRIPT_DIR}/lib/tui.sh"
source "${SCRIPT_DIR}/lib/vrgb.sh"

PY="${MAESTRO_ROOT}/.venv/bin/python"
GAME="${SCRIPT_DIR}/maestro-chess/play.py"

if [[ ! -x "${PY}" ]] || [[ ! -f "${GAME}" ]]; then
    echo "  ${_C_RED}Maestro Chess is not installed correctly.${_C_RESET}"
    echo "  expected engine: ${PY}"
    echo "  expected game:   ${GAME}"
    exit 1
fi

# List installed ollama models (the GPU/Metal players), one per line.
list_models() {
    curl -s --max-time 3 http://localhost:11434/api/tags 2>/dev/null \
        | "${PY}" -c 'import sys, json
try:
    d = json.load(sys.stdin)
    for m in d.get("models", []):
        print(m["name"])
except Exception:
    pass'
}

PICKED=""
pick_model() {
    local title="$1"
    local models=() line
    while IFS= read -r line; do
        [[ -n "${line}" ]] && models+=("${line}")
    done < <(list_models)

    if [[ ${#models[@]} -eq 0 ]]; then
        tput clear 2>/dev/null || true
        echo ""
        echo "  ${_C_RED}No GPU models found -- is ollama running?${_C_RESET}"
        echo "  ${_C_DIM}start ollama, or pick a match that has no model.${_C_RESET}"
        echo ""
        echo "  ${_C_DIM}press any key...${_C_RESET}"
        read -rsn1
        return 1
    fi

    tui_menu "${title}" "${models[@]}" || return 1
    PICKED="${TUI_RESULT}"
    return 0
}

tput clear 2>/dev/null || true
echo ""
vrgb_gradient_bar 18 80 50 210 80 50 "${_TUI_COLS:-60}"
echo ""
_tui_center "${_C_BOLD}MAESTRO CHESS${_C_RESET}"
_tui_center "${_C_DIM}real chess on the substrate -- moves become VRGB tokens${_C_RESET}"
echo ""

tui_menu "Choose a match" \
    "You vs CPU engine" \
    "You vs GPU model" \
    "CPU engine vs GPU model" \
    "GPU model vs GPU model" \
    "You vs You" \
    || exit 0

WHITE=""
BLACK=""
case "${TUI_INDEX}" in
    0) WHITE="human"; BLACK="cpu" ;;
    1) pick_model "Your opponent (GPU / Metal)" || exit 0; WHITE="human"; BLACK="${PICKED}" ;;
    2) pick_model "GPU opponent" || exit 0; WHITE="cpu"; BLACK="${PICKED}" ;;
    3) pick_model "White (GPU)" || exit 0; WHITE="${PICKED}"
       pick_model "Black (GPU)" || exit 0; BLACK="${PICKED}" ;;
    4) WHITE="human"; BLACK="human" ;;
    *) exit 0 ;;
esac

# Hand off to the game loop in normal terminal mode (human seats use line input).
tput clear 2>/dev/null || true
_tui_restore_stty 2>/dev/null || true
stty sane 2>/dev/null || true
tput cnorm 2>/dev/null || true

"${PY}" "${GAME}" --white "${WHITE}" --black "${BLACK}"

echo ""
echo "  ${_C_DIM}press any key to return to the arcade...${_C_RESET}"
read -rsn1
