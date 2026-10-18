#!/usr/bin/env bash
# ============================================================
#  HEAT TRAIL (FAST)  --  a cooling trail you keep fed
# ============================================================
#  Experimental variant: high frame rate (0.08s / ~12.5 FPS)
#  Same decay rate in ticks -- faster real-time decay.
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/lib/tui.sh"
source "${SCRIPT_DIR}/lib/vrgb.sh"
source "${SCRIPT_DIR}/lib/arcade-tokens.sh"

ARCADE_GAME_ID="trail-fast"

# ============================================================
# FRAME RATE -- the universal speed knob
# ============================================================

FRAME_RATE=0.08

# ============================================================
# ARENA (bordered rectangle)
# ============================================================

ARENA_W=30
ARENA_H=15

# ============================================================
# GAME STATE
# ============================================================

# Trail body: parallel arrays (head = index 0)
BODY_X=()
BODY_Y=()
BODY_HEAT=()

# Direction: 0=up 1=right 2=down 3=left
DIR=1
NEXT_DIR=1

# Food position and heat value
FOOD_X=0
FOOD_Y=0
FOOD_HEAT=0

SCORE=0
HIGH_SCORE=0
TICK=0
GAME_OVER=0
DECAY_RATE=3    # ticks between decay steps
GROW_AMOUNT=0   # pending growth from eating

# ============================================================
# HELPERS
# ============================================================

is_body() {
    local x="$1" y="$2"
    local i=0
    local len=${#BODY_X[@]}
    while [[ "${i}" -lt "${len}" ]]; do
        if [[ "${BODY_X[$i]}" -eq "${x}" ]] && [[ "${BODY_Y[$i]}" -eq "${y}" ]]; then
            return 0
        fi
        i=$((i + 1))
    done
    return 1
}

spawn_food() {
    local attempts=0
    while [[ "${attempts}" -lt 200 ]]; do
        FOOD_X=$((1 + RANDOM % (ARENA_W - 2)))
        FOOD_Y=$((1 + RANDOM % (ARENA_H - 2)))
        if ! is_body "${FOOD_X}" "${FOOD_Y}"; then
            # Random heat value: 5-15
            FOOD_HEAT=$((5 + RANDOM % 11))
            return
        fi
        attempts=$((attempts + 1))
    done
}

# ============================================================
# INIT
# ============================================================

game_init() {
    # Trail starts in center, 3 segments long, moving right
    local cx=$((ARENA_W / 2))
    local cy=$((ARENA_H / 2))
    BODY_X=("${cx}" "$((cx - 1))" "$((cx - 2))")
    BODY_Y=("${cy}" "${cy}" "${cy}")
    BODY_HEAT=(15 12 9)
    DIR=1
    NEXT_DIR=1
    SCORE=0
    TICK=0
    GAME_OVER=0
    GROW_AMOUNT=0
    spawn_food
}

# ============================================================
# GAME LOGIC
# ============================================================

update() {
    DIR="${NEXT_DIR}"

    # Calculate new head position
    local hx="${BODY_X[0]}" hy="${BODY_Y[0]}"
    case "${DIR}" in
        0) hy=$((hy - 1)) ;;
        1) hx=$((hx + 1)) ;;
        2) hy=$((hy + 1)) ;;
        3) hx=$((hx - 1)) ;;
    esac

    # Wall collision
    if [[ "${hx}" -le 0 ]] || [[ "${hx}" -ge $((ARENA_W - 1)) ]] || \
       [[ "${hy}" -le 0 ]] || [[ "${hy}" -ge $((ARENA_H - 1)) ]]; then
        GAME_OVER=1
        return
    fi

    # Self collision
    if is_body "${hx}" "${hy}"; then
        GAME_OVER=1
        return
    fi

    # Insert new head
    BODY_X=("${hx}" "${BODY_X[@]}")
    BODY_Y=("${hy}" "${BODY_Y[@]}")
    # New head gets heat from the previous head (keeps chain warm)
    local head_heat="${BODY_HEAT[0]}"
    local new_heat=$((head_heat + 1))
    if [[ "${new_heat}" -gt 20 ]]; then new_heat=20; fi
    BODY_HEAT=("${new_heat}" "${BODY_HEAT[@]}")

    # Check food
    if [[ "${hx}" -eq "${FOOD_X}" ]] && [[ "${hy}" -eq "${FOOD_Y}" ]]; then
        # Eat: add heat to head, score, spawn new food
        BODY_HEAT[0]="${FOOD_HEAT}"
        local len=${#BODY_X[@]}
        SCORE=$((SCORE + FOOD_HEAT * len))
        GROW_AMOUNT=$((GROW_AMOUNT + 2))

        # Token: food consumed (flash preset -- 30s lifespan)
        arcade_buffer_token "eat" "${FOOD_HEAT}" \
            --base-temp "${ARCADE_PRESET_FLASH_TEMP}" --cooling-rate "${ARCADE_PRESET_FLASH_RATE}"

        spawn_food
    fi

    # Remove tail (unless growing)
    if [[ "${GROW_AMOUNT}" -gt 0 ]]; then
        GROW_AMOUNT=$((GROW_AMOUNT - 1))
    else
        local last=$(( ${#BODY_X[@]} - 1 ))
        unset "BODY_X[${last}]"
        unset "BODY_Y[${last}]"
        unset "BODY_HEAT[${last}]"
        # Re-index arrays (bash arrays can get sparse after unset)
        BODY_X=("${BODY_X[@]}")
        BODY_Y=("${BODY_Y[@]}")
        BODY_HEAT=("${BODY_HEAT[@]}")
    fi

    # Thermal decay (every N ticks, cool all segments)
    if [[ $((TICK % DECAY_RATE)) -eq 0 ]]; then
        local len=${#BODY_X[@]}
        local i=0
        while [[ "${i}" -lt "${len}" ]]; do
            BODY_HEAT[$i]=$((BODY_HEAT[$i] - 1))
            i=$((i + 1))
        done

        # Remove cold segments from tail
        local _shed_count=0
        while [[ ${#BODY_HEAT[@]} -gt 0 ]]; do
            local tail_idx=$(( ${#BODY_HEAT[@]} - 1 ))
            if [[ "${BODY_HEAT[${tail_idx}]}" -le 0 ]]; then
                unset "BODY_X[${tail_idx}]"
                unset "BODY_Y[${tail_idx}]"
                unset "BODY_HEAT[${tail_idx}]"
                BODY_X=("${BODY_X[@]}")
                BODY_Y=("${BODY_Y[@]}")
                BODY_HEAT=("${BODY_HEAT[@]}")
                _shed_count=$((_shed_count + 1))
            else
                break
            fi
        done

        # Token: record tail shed events (batch)
        if [[ "${_shed_count}" -gt 0 ]]; then
            arcade_buffer_token "tail_shed" "${_shed_count}" \
                --base-temp "${ARCADE_PRESET_FLASH_TEMP}" --cooling-rate "${ARCADE_PRESET_FLASH_RATE}"
        fi

        # If body is empty, game over
        if [[ ${#BODY_X[@]} -eq 0 ]]; then
            GAME_OVER=1
        fi
    fi

    TICK=$((TICK + 1))
}

# ============================================================
# RENDER
# ============================================================

render() {
    printf "\033[H"

    local w="${_C_BOLD}${_C_WHITE}" d="${_C_DIM}" z="${_C_RESET}"
    local v="${_C_MAGENTA}" r="${_C_RED}" g="${_C_GREEN}" b="${_C_BLUE}"
    printf "${w}HEAT TRAIL${z} ${r}FAST${z}  ${d}Chain: %d  Score: %d${z}\n\n" "${#BODY_X[@]}" "${SCORE}"

    local y=0
    while [[ "${y}" -lt "${ARENA_H}" ]]; do
        local x=0
        while [[ "${x}" -lt "${ARENA_W}" ]]; do
            # Wall border
            if [[ "${x}" -eq 0 ]] || [[ "${x}" -eq $((ARENA_W - 1)) ]] || \
               [[ "${y}" -eq 0 ]] || [[ "${y}" -eq $((ARENA_H - 1)) ]]; then
                printf "${_C_BLUE}${_BAR_FULL}${z}"
                x=$((x + 1))
                continue
            fi

            # Food
            if [[ "${x}" -eq "${FOOD_X}" ]] && [[ "${y}" -eq "${FOOD_Y}" ]]; then
                # Pulsing food
                if [[ $((TICK % 4)) -lt 2 ]]; then
                    printf "${_C_BOLD}${v}*${z}"
                else
                    printf "${_C_BOLD}${_C_WHITE}*${z}"
                fi
                x=$((x + 1))
                continue
            fi

            # Body segment
            local found=0
            local seg=0
            local len=${#BODY_X[@]}
            while [[ "${seg}" -lt "${len}" ]]; do
                if [[ "${BODY_X[${seg}]}" -eq "${x}" ]] && [[ "${BODY_Y[${seg}]}" -eq "${y}" ]]; then
                    found=1
                    local heat="${BODY_HEAT[${seg}]}"
                    if [[ "${seg}" -eq 0 ]]; then
                        # Head: bright
                        printf "${_C_BOLD}${g}@${z}"
                    elif [[ "${heat}" -ge 12 ]]; then
                        # Hot segment
                        vrgb_hsl_to_rgb 0 80 55
                        printf "\033[38;2;%d;%d;%dm${_BAR_FULL}\033[0m" "${VRGB_R}" "${VRGB_G}" "${VRGB_B}"
                    elif [[ "${heat}" -ge 8 ]]; then
                        # Warm segment
                        vrgb_hsl_to_rgb 30 70 50
                        printf "\033[38;2;%d;%d;%dm${_BAR_SHADE3}\033[0m" "${VRGB_R}" "${VRGB_G}" "${VRGB_B}"
                    elif [[ "${heat}" -ge 4 ]]; then
                        # Cool segment
                        vrgb_hsl_to_rgb 200 50 45
                        printf "\033[38;2;%d;%d;%dm${_BAR_SHADE2}\033[0m" "${VRGB_R}" "${VRGB_G}" "${VRGB_B}"
                    else
                        # Cold segment (about to fall off)
                        printf "${d}${_BAR_SHADE1}${z}"
                    fi
                    break
                fi
                seg=$((seg + 1))
            done

            if [[ "${found}" -eq 0 ]]; then
                printf " "
            fi

            x=$((x + 1))
        done
        tput el 2>/dev/null || true
        printf "\n"
        y=$((y + 1))
    done

    # Heat bar (shows chain health via thermal gradient)
    printf "\nHeat "
    local len=${#BODY_X[@]}
    local bar_max=25
    local bi=0
    while [[ "${bi}" -lt "${bar_max}" ]]; do
        if [[ "${bi}" -lt "${len}" ]] && [[ "${bi}" -lt ${#BODY_HEAT[@]} ]]; then
            local seg_heat="${BODY_HEAT[${bi}]}"
            if [[ "${seg_heat}" -ge 12 ]]; then
                printf "${r}${_BAR_FULL}${z}"
            elif [[ "${seg_heat}" -ge 8 ]]; then
                printf "${_C_YELLOW}${_BAR_FULL}${z}"
            elif [[ "${seg_heat}" -ge 4 ]]; then
                printf "${_C_CYAN}${_BAR_SHADE3}${z}"
            else
                printf "${d}${_BAR_SHADE1}${z}"
            fi
        else
            printf "${d}${_BAR_EMPTY}${z}"
        fi
        bi=$((bi + 1))
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

    printf "${d}Arrows steer  Q quit${z}  ${d}Frame: ${FRAME_RATE}s${z}"
    tput el 2>/dev/null || true
}

render_game_over() {
    printf "\033[H"
    local w="${_C_BOLD}${_C_WHITE}" r="${_C_RED}" z="${_C_RESET}" d="${_C_DIM}"
    local c="${_C_CYAN}"

    printf "\n\n\n\n\n\n\n"
    _tui_center "${r}${_C_BOLD}CHAIN BROKEN${z}"
    printf "\n\n"
    _tui_center "Score: ${w}${SCORE}${z}   Max Chain: ${w}${_TRAIL_MAX_CHAIN:-0}${z}"
    printf "\n"
    _tui_center "${d}Tokens created: ${c}${ARCADE_TOKEN_COUNT}${z}  ${d}High score: ${w}${ARCADE_HIGH_SCORE}${z}"
    printf "\n\n"
    _tui_center "${d}SPACE to continue${z}"
    printf "\n\033[J"
}

# ============================================================
# MAIN LOOP
# ============================================================

_TRAIL_MAX_CHAIN=0

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

    game_init
    _TRAIL_MAX_CHAIN=${#BODY_X[@]}

    # Tick-based speed: trail moves every MOVE_TICKS ticks
    local move_ticks=1
    local tick_count=0

    local _score_recorded=0

    while true; do
        if [[ "${GAME_OVER}" -eq 1 ]]; then
            # Record score once on game over
            if [[ "${_score_recorded}" -eq 0 ]]; then
                arcade_record_score "${SCORE}"
                arcade_announce "Game over. Score: ${SCORE}."
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

        # Track max chain length
        local _cur_chain=${#BODY_X[@]}
        if [[ "${_cur_chain}" -gt "${_TRAIL_MAX_CHAIN}" ]]; then
            _TRAIL_MAX_CHAIN="${_cur_chain}"
        fi

        # Pressure gauge + decay modulation
        arcade_check_pressure
        case "${ARCADE_PRESSURE_ZONE}" in
            critical) DECAY_RATE=2 ;;
            high) DECAY_RATE=4 ;;
            *) DECAY_RATE=3 ;;
        esac

        render

        # Non-blocking input -- FRAME_RATE controls game speed
        _tui_game_read "${FRAME_RATE}"
        local char="${_GAME_CHAR}"

        if [[ -n "${char}" ]]; then
            if [[ "${char}" = $'\x1b' ]]; then
                _tui_game_seq_read; local s1="${_GAME_CHAR}"
                if [[ "${s1}" = "[" ]]; then
                    _tui_game_seq_read; local s2="${_GAME_CHAR}"
                    case "${s2}" in
                        A) [[ "${DIR}" -ne 2 ]] && NEXT_DIR=0 ;;
                        B) [[ "${DIR}" -ne 0 ]] && NEXT_DIR=2 ;;
                        C) [[ "${DIR}" -ne 3 ]] && NEXT_DIR=1 ;;
                        D) [[ "${DIR}" -ne 1 ]] && NEXT_DIR=3 ;;
                    esac
                fi
            elif [[ "${char}" = "q" ]] || [[ "${char}" = "Q" ]]; then
                break
            fi
        fi

        # Only move trail on tick intervals (controls effective speed)
        tick_count=$((tick_count + 1))
        if [[ "${tick_count}" -ge "${move_ticks}" ]]; then
            update
            tick_count=0
        fi
    done

    arcade_flush_buffer
    _tui_restore_stty
    tput cnorm 2>/dev/null || true
    tput clear 2>/dev/null || true
}

main "$@"
