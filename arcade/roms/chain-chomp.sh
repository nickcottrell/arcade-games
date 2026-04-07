#!/usr/bin/env bash
# ============================================================
#  CHAIN CHOMP  --  Pac-Man meets provenance chains
# ============================================================
#  Arrow keys. Eat dots. Avoid ghosts. That is it.
#
#  Dots decay from hot to cold to gone (thermal decay).
#  Consecutive eats build your chain (provenance chain).
#  Chain = score multiplier. Ghost hit = chain breaks.
#  Power pellets (*) let you eat ghosts.
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/lib/tui.sh"
source "${SCRIPT_DIR}/lib/vrgb.sh"
source "${SCRIPT_DIR}/lib/arcade-tokens.sh"

ARCADE_GAME_ID="chomp"

# ============================================================
# MAP  (21 wide x 11 tall)
# ============================================================
# # = wall   . = token   o = power pellet

MAP_W=21
MAP_H=11

MAP_TMPL=(
    "#####################"
    "#o........#........o#"
    "#.###.##..#..##.###.#"
    "#...................#"
    "#.#.#.#.#####.#.#.#.#"
    "#.....#.......#.....#"
    "#.#.#.#.#####.#.#.#.#"
    "#...................#"
    "#.###.##..#..##.###.#"
    "#o........#........o#"
    "#####################"
)

# Player start
START_PX=10
START_PY=7

# Ghost starts
START_GX=(5 15)
START_GY=(5 5)
NUM_GHOSTS=2

# ============================================================
# GAME STATE
# ============================================================

# Cell data (flat arrays, index = y * MAP_W + x)
WALL=()
TOKEN=()     # 0=none 1=cold 2=warm 3=hot 9=power

PX=0 PY=0
GX=() GY=()
SCARED=0     # ticks remaining in power mode

SCORE=0
CHAIN=0
BEST_CHAIN=0
LIVES=3
LEVEL=1
TICK=0
TOKENS_LEFT=0
GAME_OVER=0
STATE="play"  # play | dead | over

# ============================================================
# LEVEL INIT
# ============================================================

init_level() {
    WALL=()
    TOKEN=()
    TOKENS_LEFT=0

    local y=0
    while [[ "${y}" -lt "${MAP_H}" ]]; do
        local row="${MAP_TMPL[$y]}"
        local x=0
        while [[ "${x}" -lt "${MAP_W}" ]]; do
            local idx=$((y * MAP_W + x))
            local ch="${row:${x}:1}"
            case "${ch}" in
                "#") WALL[${idx}]=1; TOKEN[${idx}]=0 ;;
                ".") WALL[${idx}]=0; TOKEN[${idx}]=3; TOKENS_LEFT=$((TOKENS_LEFT + 1)) ;;
                "o") WALL[${idx}]=0; TOKEN[${idx}]=9; TOKENS_LEFT=$((TOKENS_LEFT + 1)) ;;
                *)   WALL[${idx}]=0; TOKEN[${idx}]=0 ;;
            esac
            x=$((x + 1))
        done
        y=$((y + 1))
    done

    PX="${START_PX}"
    PY="${START_PY}"
    GX=("${START_GX[@]}")
    GY=("${START_GY[@]}")
    SCARED=0
    TICK=0
}

# ============================================================
# MOVEMENT
# ============================================================

can_move() {
    local x="$1" y="$2"
    if [[ "${x}" -lt 0 ]] || [[ "${x}" -ge "${MAP_W}" ]]; then return 1; fi
    if [[ "${y}" -lt 0 ]] || [[ "${y}" -ge "${MAP_H}" ]]; then return 1; fi
    if [[ "${WALL[$((y * MAP_W + x))]}" -eq 1 ]]; then return 1; fi
    return 0
}

move_player() {
    local dx="$1" dy="$2"
    local nx=$((PX + dx)) ny=$((PY + dy))
    if can_move "${nx}" "${ny}"; then
        PX="${nx}"
        PY="${ny}"
        pickup_token
        check_collision
    fi
}

pickup_token() {
    local idx=$((PY * MAP_W + PX))
    local t="${TOKEN[${idx}]}"
    if [[ "${t}" -eq 0 ]]; then return; fi

    CHAIN=$((CHAIN + 1))
    if [[ "${CHAIN}" -gt "${BEST_CHAIN}" ]]; then BEST_CHAIN="${CHAIN}"; fi

    local base=0
    case "${t}" in
        1) base=10 ;;
        2) base=20 ;;
        3) base=30 ;;
        9) base=50; SCARED=35 ;;
    esac

    local mult=$((1 + CHAIN / 5))
    SCORE=$((SCORE + base * mult))
    TOKEN[${idx}]=0
    TOKENS_LEFT=$((TOKENS_LEFT - 1))

    # Token integration: heat chain token on every eat
    if [[ -n "${_ARCADE_CHAIN_TOKEN_ID:-}" ]]; then
        arcade_heat_token "${_ARCADE_CHAIN_TOKEN_ID}"
    fi

    # Power pellet creates a short-lived token
    if [[ "${t}" -eq 9 ]]; then
        arcade_buffer_token "power" "active" \
            --base-temp "${ARCADE_PRESET_BURST_TEMP}" --cooling-rate "${ARCADE_PRESET_BURST_RATE}"
    fi

    if [[ "${TOKENS_LEFT}" -le 0 ]]; then
        LEVEL=$((LEVEL + 1))
        if [[ $((LEVEL % 3)) -eq 0 ]] && [[ "${LIVES}" -lt 5 ]]; then
            LIVES=$((LIVES + 1))
        fi
        # Record level completion token
        arcade_create_token "level_complete" "${LEVEL}" \
            --base-temp "${ARCADE_PRESET_PULSE_TEMP}" --cooling-rate "${ARCADE_PRESET_PULSE_RATE}"
        init_level
    fi
}

check_collision() {
    local i=0
    while [[ "${i}" -lt "${NUM_GHOSTS}" ]]; do
        if [[ "${GX[$i]}" -eq "${PX}" ]] && [[ "${GY[$i]}" -eq "${PY}" ]]; then
            if [[ "${SCARED}" -gt 0 ]]; then
                SCORE=$((SCORE + 200 * LEVEL))
                GX[$i]=10
                GY[$i]=5
                # Token: ghost kill event
                arcade_buffer_token "ghost_kill" "${LEVEL}" \
                    --base-temp "${ARCADE_PRESET_BURST_TEMP}" --cooling-rate "${ARCADE_PRESET_BURST_RATE}"
            else
                CHAIN=0
                LIVES=$((LIVES - 1))
                PX="${START_PX}"
                PY="${START_PY}"
                # Token: chain broken event
                arcade_buffer_token "chain_break" "${BEST_CHAIN}" \
                    --base-temp "${ARCADE_PRESET_FLASH_TEMP}" --cooling-rate "${ARCADE_PRESET_FLASH_RATE}"
                if [[ "${LIVES}" -le 0 ]]; then
                    GAME_OVER=1
                fi
                return
            fi
        fi
        i=$((i + 1))
    done
}

# ============================================================
# GHOST AI
# ============================================================

move_ghosts() {
    local i=0
    while [[ "${i}" -lt "${NUM_GHOSTS}" ]]; do
        local gx="${GX[$i]}" gy="${GY[$i]}"

        # Direction toward (or away from) player
        local dx=0 dy=0
        if [[ "${PX}" -gt "${gx}" ]]; then dx=1; elif [[ "${PX}" -lt "${gx}" ]]; then dx=-1; fi
        if [[ "${PY}" -gt "${gy}" ]]; then dy=1; elif [[ "${PY}" -lt "${gy}" ]]; then dy=-1; fi

        # Flip when scared
        if [[ "${SCARED}" -gt 0 ]]; then
            dx=$((-dx))
            dy=$((-dy))
        fi

        # 30% random
        if [[ $((RANDOM % 10)) -lt 3 ]]; then
            local roll=$((RANDOM % 4))
            case "${roll}" in
                0) dx=1;  dy=0 ;;
                1) dx=-1; dy=0 ;;
                2) dx=0;  dy=1 ;;
                3) dx=0;  dy=-1 ;;
            esac
        fi

        # Try to move (prefer axis with larger distance)
        local moved=0
        local adx="${dx}" ady="${dy}"
        if [[ "${adx}" -lt 0 ]]; then adx=$((-adx)); fi
        if [[ "${ady}" -lt 0 ]]; then ady=$((-ady)); fi

        if [[ "${adx}" -ge "${ady}" ]]; then
            if [[ "${dx}" -ne 0 ]] && can_move $((gx + dx)) "${gy}"; then
                GX[$i]=$((gx + dx)); moved=1
            elif [[ "${dy}" -ne 0 ]] && can_move "${gx}" $((gy + dy)); then
                GY[$i]=$((gy + dy)); moved=1
            fi
        else
            if [[ "${dy}" -ne 0 ]] && can_move "${gx}" $((gy + dy)); then
                GY[$i]=$((gy + dy)); moved=1
            elif [[ "${dx}" -ne 0 ]] && can_move $((gx + dx)) "${gy}"; then
                GX[$i]=$((gx + dx)); moved=1
            fi
        fi

        # If stuck, try any open direction
        if [[ "${moved}" -eq 0 ]]; then
            local dirs=("1 0" "-1 0" "0 1" "0 -1")
            local start=$((RANDOM % 4))
            local d=0
            while [[ "${d}" -lt 4 ]]; do
                local pick=$(( (start + d) % 4 ))
                local tdx="${dirs[${pick}]%% *}"
                local tdy="${dirs[${pick}]##* }"
                if can_move $((gx + tdx)) $((gy + tdy)); then
                    GX[$i]=$((gx + tdx))
                    GY[$i]=$((gy + tdy))
                    break
                fi
                d=$((d + 1))
            done
        fi

        # Check ghost-player collision after ghost moves
        if [[ "${GX[$i]}" -eq "${PX}" ]] && [[ "${GY[$i]}" -eq "${PY}" ]]; then
            if [[ "${SCARED}" -gt 0 ]]; then
                SCORE=$((SCORE + 200 * LEVEL))
                GX[$i]=10
                GY[$i]=5
                arcade_buffer_token "ghost_kill" "${LEVEL}" \
                    --base-temp "${ARCADE_PRESET_BURST_TEMP}" --cooling-rate "${ARCADE_PRESET_BURST_RATE}"
            else
                CHAIN=0
                LIVES=$((LIVES - 1))
                PX="${START_PX}"
                PY="${START_PY}"
                arcade_buffer_token "chain_break" "${BEST_CHAIN}" \
                    --base-temp "${ARCADE_PRESET_FLASH_TEMP}" --cooling-rate "${ARCADE_PRESET_FLASH_RATE}"
                if [[ "${LIVES}" -le 0 ]]; then
                    GAME_OVER=1
                fi
            fi
        fi

        i=$((i + 1))
    done
}

# ============================================================
# THERMAL DECAY
# ============================================================

decay_tokens() {
    local total=$((MAP_W * MAP_H))
    local i=0
    while [[ "${i}" -lt "${total}" ]]; do
        local t="${TOKEN[$i]}"
        if [[ "${t}" -ge 1 ]] && [[ "${t}" -le 3 ]]; then
            TOKEN[$i]=$((t - 1))
            if [[ "${TOKEN[$i]}" -eq 0 ]]; then
                TOKENS_LEFT=$((TOKENS_LEFT - 1))
            fi
        fi
        i=$((i + 1))
    done

    if [[ "${TOKENS_LEFT}" -le 0 ]]; then
        LEVEL=$((LEVEL + 1))
        init_level
    fi
}

# ============================================================
# RENDER
# ============================================================

render() {
    # Home cursor at vertical offset (no clear -- overwrite in place for less flicker)
    printf "\033[H"

    # Title
    local v="${_C_MAGENTA}" r="${_C_RED}" g="${_C_GREEN}" b="${_C_BLUE}"
    local w="${_C_BOLD}${_C_WHITE}" d="${_C_DIM}" z="${_C_RESET}"
    printf "${w}CHAIN CHOMP${z}  ${d}Level %d${z}\n\n" "${LEVEL}"

    # Map
    local y=0
    while [[ "${y}" -lt "${MAP_H}" ]]; do
        local x=0
        while [[ "${x}" -lt "${MAP_W}" ]]; do
            local idx=$((y * MAP_W + x))

            # Player?
            if [[ "${x}" -eq "${PX}" ]] && [[ "${y}" -eq "${PY}" ]]; then
                if [[ "${SCARED}" -gt 0 ]]; then
                    printf "${_C_BOLD}${_C_CYAN}C${z}"
                else
                    printf "${_C_BOLD}${_C_GREEN}C${z}"
                fi
            # Ghost?
            elif _is_ghost "${x}" "${y}"; then
                if [[ "${SCARED}" -gt 0 ]]; then
                    printf "${_C_BLUE}${_C_DIM}W${z}"
                else
                    printf "${_C_BOLD}${_C_RED}W${z}"
                fi
            # Wall?
            elif [[ "${WALL[${idx}]}" -eq 1 ]]; then
                printf "${_C_BLUE}${_BAR_FULL}${z}"
            # Token?
            else
                case "${TOKEN[${idx}]}" in
                    0) printf " " ;;
                    1) printf "${d}.${z}" ;;
                    2) printf "${_C_YELLOW}.${z}" ;;
                    3) printf "${_C_BOLD}${r}.${z}" ;;
                    9) if [[ $((TICK % 4)) -lt 2 ]]; then
                           printf "${_C_BOLD}${v}*${z}"
                       else
                           printf "${_C_BOLD}${_C_WHITE}*${z}"
                       fi ;;
                esac
            fi
            x=$((x + 1))
        done
        tput el 2>/dev/null || true
        printf "\n"
        y=$((y + 1))
    done

    # Chain bar
    printf "\nChain "
    local bar_max=20
    local bar_fill="${CHAIN}"
    if [[ "${bar_fill}" -gt "${bar_max}" ]]; then bar_fill="${bar_max}"; fi
    local bi=0
    while [[ "${bi}" -lt "${bar_max}" ]]; do
        if [[ "${bi}" -lt "${bar_fill}" ]]; then
            if [[ "${CHAIN}" -ge 15 ]]; then
                printf "${r}${_BAR_FULL}${z}"
            elif [[ "${CHAIN}" -ge 8 ]]; then
                printf "${_C_YELLOW}${_BAR_FULL}${z}"
            else
                printf "${g}${_BAR_FULL}${z}"
            fi
        else
            printf "${d}${_BAR_EMPTY}${z}"
        fi
        bi=$((bi + 1))
    done

    local mult=$((1 + CHAIN / 5))
    printf " ${_C_BOLD}x%d${z}" "${mult}"
    printf "  Score ${_C_BOLD}%d${z}" "${SCORE}"

    printf "  Lives "
    local li=0
    while [[ "${li}" -lt "${LIVES}" ]]; do
        printf "${r}${_BAR_FULL}${z}"
        li=$((li + 1))
    done
    tput el 2>/dev/null || true
    printf "\n"

    # Token integration line
    printf "${d}Tokens: ${_C_CYAN}%d${z}  ${d}High: ${_C_BOLD}%d${z}" "${ARCADE_TOKEN_COUNT}" "${ARCADE_HIGH_SCORE}"
    tput el 2>/dev/null || true
    printf "\n"

    # Pressure bar (10-char wide, color-coded by zone)
    printf "${d}Pressure${z} "
    local _p_fill=$((ARCADE_PRESSURE_RAW / 150))
    if [[ "${_p_fill}" -gt 10 ]]; then _p_fill=10; fi
    local _pi=0
    while [[ "${_pi}" -lt 10 ]]; do
        if [[ "${_pi}" -lt "${_p_fill}" ]]; then
            case "${ARCADE_PRESSURE_ZONE}" in
                critical) printf "${r}${_BAR_FULL}${z}" ;;
                low) printf "${_C_YELLOW}${_BAR_FULL}${z}" ;;
                medium) printf "${g}${_BAR_FULL}${z}" ;;
                high) printf "${_C_CYAN}${_BAR_FULL}${z}" ;;
            esac
        else
            printf "${d}${_BAR_EMPTY}${z}"
        fi
        _pi=$((_pi + 1))
    done
    tput el 2>/dev/null || true
    printf "\n"

    printf "${d}Arrows move  Q quit${z}"
    tput el 2>/dev/null || true
}

_is_ghost() {
    local x="$1" y="$2"
    local i=0
    while [[ "${i}" -lt "${NUM_GHOSTS}" ]]; do
        if [[ "${GX[$i]}" -eq "${x}" ]] && [[ "${GY[$i]}" -eq "${y}" ]]; then
            return 0
        fi
        i=$((i + 1))
    done
    return 1
}

render_game_over() {
    printf "\033[H"
    local w="${_C_BOLD}${_C_WHITE}" r="${_C_RED}" z="${_C_RESET}" d="${_C_DIM}"
    local c="${_C_CYAN}"

    printf "\n\n\n\n\n"
    _tui_center "${r}${_C_BOLD}GAME OVER${z}"
    printf "\n\n"
    _tui_center "Score: ${w}${SCORE}${z}   Best Chain: ${w}${BEST_CHAIN}${z}   Level: ${w}${LEVEL}${z}"
    printf "\n"
    _tui_center "${d}Tokens created: ${c}${ARCADE_TOKEN_COUNT}${z}  ${d}High score: ${w}${ARCADE_HIGH_SCORE}${z}"
    printf "\n\n"
    _tui_center "${d}SPACE to continue${z}"
    printf "\n\033[J"
}

# ============================================================
# MAIN LOOP
# ============================================================

_ARCADE_CHAIN_TOKEN_ID=""

main() {
    # Require cue-vox server for token integration
    if ! arcade_require_server; then
        echo "  Press any key to exit..."
        read -rsn1
        return 1
    fi

    # Load high score from existing tokens
    arcade_get_high_score
    ARCADE_TOKEN_COUNT=0
    arcade_init_pressure
    arcade_set_leak_rate 3

    tput civis 2>/dev/null || true
    tput clear 2>/dev/null || printf "\033[2J"

    # Raw terminal mode -- perl select() handles frame timing
    _TUI_SAVED_STTY=$(stty -g 2>/dev/null || echo "")
    stty -icanon -echo 2>/dev/null || true
    # Cleanup on any exit (catches set -e crashes)
    trap 'arcade_flush_buffer; _tui_restore_stty; tput cnorm 2>/dev/null' EXIT

    SCORE=0
    LIVES=3
    LEVEL=1
    BEST_CHAIN=0
    GAME_OVER=0
    init_level

    # Create a chain token to heat during gameplay
    arcade_create_token "chain" "active" \
        --base-temp "${ARCADE_PRESET_GLOW_TEMP}" --cooling-rate "${ARCADE_PRESET_GLOW_RATE}"
    # Grab the token id (predictable format: ctx_arcade_chain_<timestamp>)
    _ARCADE_CHAIN_TOKEN_ID=""

    # Ghost speed: ticks between moves
    local ghost_rate=3
    # Token decay: ticks between decay steps
    local decay_rate=50

    local _score_recorded=0

    while true; do
        if [[ "${GAME_OVER}" -eq 1 ]]; then
            # Record score once on game over
            if [[ "${_score_recorded}" -eq 0 ]]; then
                arcade_record_score "${SCORE}"
                arcade_announce "Game over. Score: ${SCORE}. Best chain: ${BEST_CHAIN}. Level ${LEVEL}."
                _score_recorded=1
            fi

            render_game_over

            # Wait for SPACE to continue (prevents accidental dismissal)
            local ch=""
            IFS= read -rsn1 ch || true
            if [[ "${ch}" = " " ]]; then
                break
            fi
            continue
        fi

        render

        # Non-blocking input (stty min 0 time 0 + sleep, macOS compatible)
        _tui_game_read 0.15
        local char="${_GAME_CHAR}"

        if [[ -n "${char}" ]]; then
            if [[ "${char}" = $'\x1b' ]]; then
                _tui_game_seq_read; local s1="${_GAME_CHAR}"
                if [[ "${s1}" = "[" ]]; then
                    _tui_game_seq_read; local s2="${_GAME_CHAR}"
                    case "${s2}" in
                        A) move_player 0 -1 ;;
                        B) move_player 0 1 ;;
                        C) move_player 1 0 ;;
                        D) move_player -1 0 ;;
                    esac
                fi
            elif [[ "${char}" = "q" ]] || [[ "${char}" = "Q" ]]; then
                break
            fi
        fi

        TICK=$((TICK + 1))

        # Pressure gauge
        arcade_check_pressure

        # Ghost movement (faster at higher levels)
        ghost_rate=$((4 - LEVEL / 3))
        if [[ "${ghost_rate}" -lt 2 ]]; then ghost_rate=2; fi
        if [[ "${SCARED}" -gt 0 ]]; then ghost_rate=$((ghost_rate + 2)); fi
        # Pressure: high = ghosts slow down
        if [[ "${ARCADE_PRESSURE_ZONE}" = "high" ]]; then ghost_rate=$((ghost_rate + 1)); fi

        if [[ $((TICK % ghost_rate)) -eq 0 ]]; then
            move_ghosts
        fi

        # Token thermal decay (faster at higher levels)
        decay_rate=$((60 - LEVEL * 5))
        if [[ "${decay_rate}" -lt 20 ]]; then decay_rate=20; fi
        # Pressure: critical = dots decay faster
        if [[ "${ARCADE_PRESSURE_ZONE}" = "critical" ]]; then
            decay_rate=$((decay_rate - 10))
            if [[ "${decay_rate}" -lt 10 ]]; then decay_rate=10; fi
        fi

        if [[ $((TICK % decay_rate)) -eq 0 ]]; then
            decay_tokens
        fi

        # Scared countdown
        if [[ "${SCARED}" -gt 0 ]]; then
            SCARED=$((SCARED - 1))
        fi
    done

    arcade_flush_buffer
    _tui_restore_stty
    tput cnorm 2>/dev/null || true
    tput clear 2>/dev/null || true
}

main "$@"
