#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/lib/tui.sh"
source "${SCRIPT_DIR}/lib/vrgb.sh"
source "${SCRIPT_DIR}/lib/arcade-tokens.sh"
ARCADE_GAME_ID="reheat"
GRID=8; LEVEL=1; SCORE=0; CHAIN=0; HEATS=0; BREAKS=0
CUR_X=0; CUR_Y=0; LAST_HEAT=101
cells=()
cleanup(){ arcade_flush_buffer; tput sgr0 2>/dev/null || true; tput cnorm 2>/dev/null || true; _tui_restore_stty 2>/dev/null || true; stty sane 2>/dev/null || true; }
trap cleanup EXIT INT TERM
idx(){ echo $(( $2 * GRID + $1 )); }
init(){ cells=(); for ((i=0;i<GRID*GRID;i++)); do cells+=( $((RANDOM%16)) ); done; }
avg_temp(){ local s=0; for v in "${cells[@]}"; do s=$((s+v)); done; echo $((s/(GRID*GRID))); }
decay(){ for ((i=0;i<${#cells[@]};i++)); do v=${cells[$i]}; ((v>0)) && v=$((v-1-LEVEL/2)); ((v<0)) && v=0; cells[$i]=$v; done; }
render(){ printf "\033[H"; vrgb_gradient_bar 15 75 50 5 75 55 "${_TUI_COLS}"; echo; echo " Reheat  L${LEVEL}  Score:${SCORE}  Chain:${CHAIN}  Avg:$(avg_temp)"; echo " arrows move · enter heat · q quit"; for ((y=0;y<GRID;y++)); do line=" "; for ((x=0;x<GRID;x++)); do i=$(idx $x $y); t=${cells[$i]}; ch='.'; ((t>33))&&ch='o'; ((t>66))&&ch='O'; if ((x==CUR_X&&y==CUR_Y)); then line+="[${ch}]"; else line+=" ${ch} "; fi; done; echo "$line"; done; }
heat_cell(){ local i=$(idx $CUR_X $CUR_Y); local t=${cells[$i]}; local hottest=0; for v in "${cells[@]}"; do ((v>hottest))&&hottest=$v; done; if ((t+2>=hottest)); then CHAIN=$((CHAIN+1)); bonus=2; else ((CHAIN>0))&&BREAKS=$((BREAKS+1)); CHAIN=0; bonus=1; arcade_buffer_token "chain_break" "$t" --tags "tuning:thermal_decay" --base-temp "$ARCADE_PRESET_BURST_TEMP" --cooling-rate "$ARCADE_PRESET_BURST_RATE"; fi; t=$((t+20)); ((t>100))&&t=100; cells[$i]=$t; add=$((5*bonus+CHAIN)); SCORE=$((SCORE+add)); HEATS=$((HEATS+1)); arcade_buffer_token "reheat" "$add" --tags "tuning:thermal_decay" --base-temp "$ARCADE_PRESET_FLASH_TEMP" --cooling-rate "$ARCADE_PRESET_FLASH_RATE"; }
main(){ _tui_init; arcade_require_server || return 1; init; stty -icanon -echo; while ((LEVEL<=3)); do render; _tui_game_read 0.18; c="${_GAME_CHAR}"; if [[ "$c" == $'\x1b' ]]; then _tui_game_seq_read; [[ "${_GAME_CHAR}" == "[" ]] && _tui_game_seq_read && case "${_GAME_CHAR}" in A) ((CUR_Y>0))&&CUR_Y=$((CUR_Y-1));;B) ((CUR_Y<GRID-1))&&CUR_Y=$((CUR_Y+1));;C) ((CUR_X<GRID-1))&&CUR_X=$((CUR_X+1));;D) ((CUR_X>0))&&CUR_X=$((CUR_X-1));; esac; elif [[ "$c" == "" ]]; then heat_cell; elif [[ "$c" == "q" || "$c" == "Q" ]]; then break; fi; decay; if (( $(avg_temp) > 60 )); then LEVEL=$((LEVEL+1)); SCORE=$((SCORE+100)); arcade_buffer_token "level_up" "$LEVEL" --tags "tuning:thermal_decay" --base-temp "$ARCADE_PRESET_PULSE_TEMP" --cooling-rate "$ARCADE_PRESET_PULSE_RATE"; init; fi; done; _tui_restore_stty; tput clear; echo "Reheat summary"; echo "Score: $SCORE  Levels: $((LEVEL-1))  Heats:$HEATS  Chain breaks:$BREAKS  Tokens:$ARCADE_TOKEN_COUNT"; }
main
