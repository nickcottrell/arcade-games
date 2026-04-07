#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/lib/tui.sh"
source "${SCRIPT_DIR}/lib/vrgb.sh"
source "${SCRIPT_DIR}/lib/arcade-tokens.sh"
cleanup(){ arcade_flush_buffer; tput sgr0 2>/dev/null || true; tput cnorm 2>/dev/null || true; _tui_restore_stty 2>/dev/null || true; stty sane 2>/dev/null || true; }
trap cleanup EXIT INT TERM
ARCADE_GAME_ID="observatory"; LEVEL=1; SCORE=0; FAIL=0; INT=12
cats=(thermal pressure vrgb lifecycle sync policy context pipeline trust)
main(){ _tui_init; arcade_require_server || return 1; stty -icanon -echo; h=(80 82 84 78 76 88 74 86 83); while ((LEVEL<=3)); do printf "\033[H"; vrgb_gradient_bar 280 70 50 60 70 50 "${_TUI_COLS}"; echo; echo " Observatory L$LEVEL Uptime:$SCORE Interventions:$INT (1-9 intervene, q quit)"; for ((i=0;i<9;i++)); do d=$((RANDOM%11-5+LEVEL)); h[$i]=$((h[$i]-d)); ((h[$i]>100))&&h[$i]=100; ((h[$i]<0))&&h[$i]=0; printf " %d:%-10s %3d%%\n" $((i+1)) "${cats[$i]}" "${h[$i]}"; done; _tui_game_read 0.6; c="${_GAME_CHAR}"; [[ "$c" == "q" || "$c" == "Q" ]]&&break; if [[ "$c" =~ [1-9] ]] && ((INT>0)); then i=$((c-1)); h[$i]=80; INT=$((INT-1)); arcade_buffer_token intervene "$c" --tags "tuning:constellation,subsystem:${cats[$i]}" --base-temp "$ARCADE_PRESET_BURST_TEMP" --cooling-rate "$ARCADE_PRESET_BURST_RATE"; fi; for ((i=0;i<9;i++)); do if ((h[$i]<20)); then FAIL=$((FAIL+1)); SCORE=$((SCORE-5)); arcade_buffer_token failure "$i" --tags "tuning:constellation,subsystem:${cats[$i]}" --base-temp "$ARCADE_PRESET_BURST_TEMP" --cooling-rate "$ARCADE_PRESET_BURST_RATE"; else SCORE=$((SCORE+1)); fi; done; ((SCORE>LEVEL*120))&&LEVEL=$((LEVEL+1)); done; _tui_restore_stty; tput clear; echo "Observatory summary"; echo "Uptime:$SCORE Failures:$FAIL Interventions left:$INT Tokens:$ARCADE_TOKEN_COUNT"; }
main
