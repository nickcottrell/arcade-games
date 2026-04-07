#!/usr/bin/env bash
# ============================================================
#  PRESSURE COOKER  --  Ride the pressure curve or meltdown
# ============================================================
#  The pressure system IS the game. Catch falling items to
#  manage reactor pressure. Medium zone = optimal multiplier.
#  High zone risks meltdown. Critical zone = stalling (0x).
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/lib/tui.sh"
source "${SCRIPT_DIR}/lib/vrgb.sh"
source "${SCRIPT_DIR}/lib/arcade-tokens.sh"

ARCADE_GAME_ID="cooker"

# ============================================================
# ARENA
# ============================================================

ARENA_W=30
ARENA_H=18

# ============================================================
# GAME STATE
# ============================================================

# Player paddle: 3-char wide [=] at bottom row
PADDLE_X=0
PADDLE_Y=0

# Falling items: parallel arrays
ITEM_X=()
ITEM_Y=()
ITEM_TYPE=()    # F=fuel  C=coolant  X=hazard
NUM_ITEMS=0

# Scoring and lives
SCORE=0
LIVES=3
LEVEL=1
TICK=0
GAME_OVER=0

# Meltdown tracking
MELTDOWN_FRAMES=0
MELTDOWN_THRESHOLD=120
MELTDOWN_WARNING=60

# Item fall speed (ticks between drops)
FALL_RATE=4
SPAWN_RATE=8

# Leak rate (pressure drain per tick)
LEAK_RATE=2

# Reactor visual center
REACTOR_X=0
REACTOR_Y=0

# ============================================================
# INIT
# ============================================================

init_game() {
    PADDLE_X=$((ARENA_W / 2))
    PADDLE_Y=$((ARENA_H - 2))

    ITEM_X=()
    ITEM_Y=()
    ITEM_TYPE=()
    NUM_ITEMS=0

    SCORE=0
    LIVES=3
    LEVEL=1
    TICK=0
    GAME_OVER=0
    MELTDOWN_FRAMES=0

    FALL_RATE=4
    SPAWN_RATE=8
    LEAK_RATE=2

    # Reactor display position (center of arena, cosmetic)
    REACTOR_X=$((ARENA_W / 2))
    REACTOR_Y=$((ARENA_H / 2))
}

# ============================================================
# ITEM SPAWNING
# ============================================================

spawn_item() {
    # Random X within arena bounds (avoid walls)
    local ix=$((2 + RANDOM % (ARENA_W - 4)))
    local iy=1

    # Item type distribution changes with level
    local roll=$((RANDOM % 100))
    local itype="F"
    local hazard_chance=$((15 + LEVEL * 5))
    if [[ "${hazard_chance}" -gt 40 ]]; then hazard_chance=40; fi
    local coolant_chance=25

    if [[ "${roll}" -lt "${hazard_chance}" ]]; then
        itype="X"
    elif [[ "${roll}" -lt $((hazard_chance + coolant_chance)) ]]; then
        itype="C"
    else
        itype="F"
    fi

    ITEM_X+=("${ix}")
    ITEM_Y+=("${iy}")
    ITEM_TYPE+=("${itype}")
    NUM_ITEMS=$((NUM_ITEMS + 1))
}

# ============================================================
# ITEM MOVEMENT
# ============================================================

move_items() {
    local i=0
    local caught=()
    local missed=()

    while [[ "${i}" -lt "${NUM_ITEMS}" ]]; do
        ITEM_Y[$i]=$((ITEM_Y[$i] + 1))

        # Check if item reached paddle row
        if [[ "${ITEM_Y[$i]}" -ge "${PADDLE_Y}" ]]; then
            local ix="${ITEM_X[$i]}"
            # Paddle occupies PADDLE_X-1, PADDLE_X, PADDLE_X+1
            if [[ "${ix}" -ge $((PADDLE_X - 1)) ]] && [[ "${ix}" -le $((PADDLE_X + 1)) ]]; then
                caught+=("${i}")
            else
                missed+=("${i}")
            fi
        fi

        i=$((i + 1))
    done

    # Process catches
    local ci=${#caught[@]}
    while [[ "${ci}" -gt 0 ]]; do
        ci=$((ci - 1))
        local idx="${caught[$ci]}"
        local itype="${ITEM_TYPE[$idx]}"
        process_catch "${itype}"
        remove_item "${idx}"
    done

    # Remove items that fell past paddle
    local mi=${#missed[@]}
    while [[ "${mi}" -gt 0 ]]; do
        mi=$((mi - 1))
        local idx="${missed[$mi]}"
        remove_item "${idx}"
    done
}

process_catch() {
    local itype="$1"

    # Get current zone multiplier
    local mult=0
    case "${ARCADE_PRESSURE_ZONE}" in
        critical) mult=0 ;;
        low)      mult=1 ;;
        medium)   mult=3 ;;
        high)     mult=5 ;;
    esac

    case "${itype}" in
        F)
            # Fuel: score + pressure
            SCORE=$((SCORE + 10 * mult))
            arcade_buffer_token "fuel" "${mult}" \
                --base-temp "${ARCADE_PRESET_FLASH_TEMP}" --cooling-rate "${ARCADE_PRESET_FLASH_RATE}"
            ;;
        C)
            # Coolant: reduce pressure directly
            ARCADE_PRESSURE_RAW=$((ARCADE_PRESSURE_RAW - 200))
            if [[ "${ARCADE_PRESSURE_RAW}" -lt 0 ]]; then
                ARCADE_PRESSURE_RAW=0
            fi
            SCORE=$((SCORE + 5 * mult))
            arcade_buffer_token "coolant" "${mult}" \
                --base-temp "${ARCADE_PRESET_FLASH_TEMP}" --cooling-rate "${ARCADE_PRESET_FLASH_RATE}"
            ;;
        X)
            # Hazard: lose a life
            LIVES=$((LIVES - 1))
            if [[ "${LIVES}" -le 0 ]]; then
                GAME_OVER=1
            fi
            ;;
    esac
}

remove_item() {
    local idx="$1"
    local last=$((NUM_ITEMS - 1))

    if [[ "${idx}" -lt "${last}" ]]; then
        ITEM_X[$idx]="${ITEM_X[$last]}"
        ITEM_Y[$idx]="${ITEM_Y[$last]}"
        ITEM_TYPE[$idx]="${ITEM_TYPE[$last]}"
    fi

    unset "ITEM_X[${last}]"
    unset "ITEM_Y[${last}]"
    unset "ITEM_TYPE[${last}]"

    ITEM_X=("${ITEM_X[@]+"${ITEM_X[@]}"}")
    ITEM_Y=("${ITEM_Y[@]+"${ITEM_Y[@]}"}")
    ITEM_TYPE=("${ITEM_TYPE[@]+"${ITEM_TYPE[@]}"}")

    NUM_ITEMS=$((NUM_ITEMS - 1))
    if [[ "${NUM_ITEMS}" -lt 0 ]]; then NUM_ITEMS=0; fi
}

# ============================================================
# MELTDOWN CHECK
# ============================================================

check_meltdown() {
    if [[ "${ARCADE_PRESSURE_ZONE}" = "high" ]]; then
        MELTDOWN_FRAMES=$((MELTDOWN_FRAMES + 1))
        if [[ "${MELTDOWN_FRAMES}" -ge "${MELTDOWN_THRESHOLD}" ]]; then
            # MELTDOWN -- game over
            GAME_OVER=1
            arcade_create_token "meltdown" "${LEVEL}" \
                --base-temp "${ARCADE_PRESET_BURST_TEMP}" --cooling-rate "${ARCADE_PRESET_BURST_RATE}"
        fi
    else
        MELTDOWN_FRAMES=0
    fi
}

# ============================================================
# RENDER
# ============================================================

render() {
    printf "\033[H"

    local w="${_C_BOLD}${_C_WHITE}" d="${_C_DIM}" z="${_C_RESET}"
    local r="${_C_RED}" g="${_C_GREEN}" y="${_C_YELLOW}" c="${_C_CYAN}"

    # Zone label and color
    local zone_label="" zone_color=""
    case "${ARCADE_PRESSURE_ZONE}" in
        critical) zone_label="STALLING"; zone_color="${r}" ;;
        low)      zone_label="LOW";      zone_color="${y}" ;;
        medium)   zone_label="OPTIMAL";  zone_color="${g}" ;;
        high)     zone_label="DANGER";   zone_color="${r}${_C_BOLD}" ;;
    esac

    # Multiplier
    local mult=0
    case "${ARCADE_PRESSURE_ZONE}" in
        critical) mult=0 ;;
        low)      mult=1 ;;
        medium)   mult=3 ;;
        high)     mult=5 ;;
    esac

    printf "${w}PRESSURE COOKER${z}  ${zone_color}%s${z}  ${w}x%d${z}  ${d}Level %d${z}\n\n" \
        "${zone_label}" "${mult}" "${LEVEL}"

    # Arena
    local row=0
    while [[ "${row}" -lt "${ARENA_H}" ]]; do
        local col=0
        while [[ "${col}" -lt "${ARENA_W}" ]]; do
            # Border
            if [[ "${col}" -eq 0 ]] || [[ "${col}" -eq $((ARENA_W - 1)) ]] || \
               [[ "${row}" -eq 0 ]] || [[ "${row}" -eq $((ARENA_H - 1)) ]]; then
                printf "${_C_BLUE}${_BAR_FULL}${z}"
                col=$((col + 1))
                continue
            fi

            # Paddle
            if [[ "${row}" -eq "${PADDLE_Y}" ]] && \
               [[ "${col}" -ge $((PADDLE_X - 1)) ]] && [[ "${col}" -le $((PADDLE_X + 1)) ]]; then
                if [[ "${col}" -eq $((PADDLE_X - 1)) ]]; then
                    printf "${w}[${z}"
                elif [[ "${col}" -eq "${PADDLE_X}" ]]; then
                    printf "${w}=${z}"
                else
                    printf "${w}]${z}"
                fi
                col=$((col + 1))
                continue
            fi

            # Reactor core (cosmetic 3x3 box in center)
            local rx_lo=$((REACTOR_X - 1)) rx_hi=$((REACTOR_X + 1))
            local ry_lo=$((REACTOR_Y - 1)) ry_hi=$((REACTOR_Y + 1))
            if [[ "${col}" -ge "${rx_lo}" ]] && [[ "${col}" -le "${rx_hi}" ]] && \
               [[ "${row}" -ge "${ry_lo}" ]] && [[ "${row}" -le "${ry_hi}" ]]; then
                # Reactor changes color with zone, pulses in high
                if [[ "${ARCADE_PRESSURE_ZONE}" = "high" ]] && [[ $((TICK % 4)) -lt 2 ]]; then
                    printf "${r}${_C_BOLD}${_BAR_FULL}${z}"
                else
                    printf "${zone_color}${_BAR_SHADE3}${z}"
                fi
                col=$((col + 1))
                continue
            fi

            # Items
            local found_item=0
            local ii=0
            while [[ "${ii}" -lt "${NUM_ITEMS}" ]]; do
                if [[ "${ITEM_X[$ii]}" -eq "${col}" ]] && [[ "${ITEM_Y[$ii]}" -eq "${row}" ]]; then
                    found_item=1
                    case "${ITEM_TYPE[$ii]}" in
                        F) printf "${y}${_C_BOLD}F${z}" ;;
                        C) printf "${c}${_C_BOLD}C${z}" ;;
                        X) printf "${r}${_C_BOLD}X${z}" ;;
                    esac
                    break
                fi
                ii=$((ii + 1))
            done

            if [[ "${found_item}" -eq 0 ]]; then
                printf " "
            fi

            col=$((col + 1))
        done
        tput el 2>/dev/null || true
        printf "\n"
        row=$((row + 1))
    done

    # Pressure gauge (large, 20-char)
    printf "\n${w}Reactor${z} "
    local _p_fill=$((ARCADE_PRESSURE_RAW / 100))
    if [[ "${_p_fill}" -gt 20 ]]; then _p_fill=20; fi
    local _pi=0
    while [[ "${_pi}" -lt 20 ]]; do
        if [[ "${_pi}" -lt "${_p_fill}" ]]; then
            printf "${zone_color}${_BAR_FULL}${z}"
        else
            printf "${d}${_BAR_EMPTY}${z}"
        fi
        _pi=$((_pi + 1))
    done
    printf " ${zone_color}%s${z}" "${zone_label}"
    tput el 2>/dev/null || true
    printf "\n"

    # Meltdown bar (only in high zone)
    if [[ "${ARCADE_PRESSURE_ZONE}" = "high" ]]; then
        printf "${r}${_C_BOLD}MELTDOWN${z} "
        local md_fill=$((MELTDOWN_FRAMES * 20 / MELTDOWN_THRESHOLD))
        if [[ "${md_fill}" -gt 20 ]]; then md_fill=20; fi
        local mi=0
        while [[ "${mi}" -lt 20 ]]; do
            if [[ "${mi}" -lt "${md_fill}" ]]; then
                if [[ "${MELTDOWN_FRAMES}" -ge "${MELTDOWN_WARNING}" ]] && [[ $((TICK % 2)) -eq 0 ]]; then
                    printf "${r}${_C_BOLD}${_BAR_FULL}${z}"
                else
                    printf "${r}${_BAR_FULL}${z}"
                fi
            else
                printf "${d}${_BAR_EMPTY}${z}"
            fi
            mi=$((mi + 1))
        done
    else
        printf "${d}                              ${z}"
    fi
    tput el 2>/dev/null || true
    printf "\n"

    # Score / lives / stats
    printf "Score ${w}%d${z}  Lives " "${SCORE}"
    local li=0
    while [[ "${li}" -lt "${LIVES}" ]]; do
        printf "${r}${_BAR_FULL}${z}"
        li=$((li + 1))
    done
    printf "  ${d}Leak: %d${z}" "${LEAK_RATE}"
    tput el 2>/dev/null || true
    printf "\n"

    # Token line
    printf "${d}Tokens: ${c}%d${z}  ${d}High: ${w}%d${z}" "${ARCADE_TOKEN_COUNT}" "${ARCADE_HIGH_SCORE}"
    tput el 2>/dev/null || true
    printf "\n"

    printf "${d}L/R move paddle  Q quit${z}"
    tput el 2>/dev/null || true
}

render_game_over() {
    printf "\033[H"
    local w="${_C_BOLD}${_C_WHITE}" r="${_C_RED}" z="${_C_RESET}" d="${_C_DIM}"
    local c="${_C_CYAN}"

    local reason="GAME OVER"
    if [[ "${MELTDOWN_FRAMES}" -ge "${MELTDOWN_THRESHOLD}" ]]; then
        reason="MELTDOWN"
    fi

    printf "\n\n\n\n\n\n\n\n"
    _tui_center "${r}${_C_BOLD}${reason}${z}"
    printf "\n\n"
    _tui_center "Score: ${w}${SCORE}${z}   Level: ${w}${LEVEL}${z}"
    printf "\n"
    _tui_center "${d}Tokens created: ${c}${ARCADE_TOKEN_COUNT}${z}  ${d}High score: ${w}${ARCADE_HIGH_SCORE}${z}"
    printf "\n\n"
    _tui_center "${d}SPACE to continue${z}"
    printf "\n\033[J"
}

# ============================================================
# MAIN LOOP
# ============================================================

main() {
    if ! arcade_require_server; then
        echo "  Press any key to exit..."
        read -rsn1
        return 1
    fi

    arcade_get_high_score
    ARCADE_TOKEN_COUNT=0
    arcade_init_pressure
    arcade_set_leak_rate "${LEAK_RATE}"

    tput civis 2>/dev/null || true
    tput clear 2>/dev/null || printf "\033[2J"

    # Raw terminal mode -- perl select() handles frame timing
    _TUI_SAVED_STTY=$(stty -g 2>/dev/null || echo "")
    stty -icanon -echo 2>/dev/null || true
    trap 'arcade_flush_buffer; _tui_restore_stty; tput cnorm 2>/dev/null' EXIT

    init_game

    local _score_recorded=0

    while true; do
        if [[ "${GAME_OVER}" -eq 1 ]]; then
            if [[ "${_score_recorded}" -eq 0 ]]; then
                arcade_record_score "${SCORE}"
                arcade_announce "Game over. Score: ${SCORE}. Level ${LEVEL}."
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
                        C) # Right
                            if [[ "${PADDLE_X}" -lt $((ARENA_W - 3)) ]]; then
                                PADDLE_X=$((PADDLE_X + 1))
                            fi
                            ;;
                        D) # Left
                            if [[ "${PADDLE_X}" -gt 2 ]]; then
                                PADDLE_X=$((PADDLE_X - 1))
                            fi
                            ;;
                    esac
                fi
            elif [[ "${char}" = "q" ]] || [[ "${char}" = "Q" ]]; then
                break
            fi
        fi

        TICK=$((TICK + 1))

        # Pressure: leak per tick
        arcade_set_leak_rate "${LEAK_RATE}"
        arcade_check_pressure

        # Item falling
        if [[ $((TICK % FALL_RATE)) -eq 0 ]]; then
            move_items
        fi

        # Item spawning
        if [[ $((TICK % SPAWN_RATE)) -eq 0 ]]; then
            spawn_item
        fi

        # Meltdown check
        check_meltdown

        # Level progression: every 300 pts
        local level_target=$((LEVEL * 300))
        if [[ "${SCORE}" -ge "${level_target}" ]]; then
            LEVEL=$((LEVEL + 1))
            LEAK_RATE=$((2 + LEVEL))
            FALL_RATE=$((4 - LEVEL / 3))
            if [[ "${FALL_RATE}" -lt 2 ]]; then FALL_RATE=2; fi
            SPAWN_RATE=$((8 - LEVEL))
            if [[ "${SPAWN_RATE}" -lt 3 ]]; then SPAWN_RATE=3; fi

            arcade_create_token "reactor_level" "${LEVEL}" \
                --base-temp "${ARCADE_PRESET_PULSE_TEMP}" --cooling-rate "${ARCADE_PRESET_PULSE_RATE}"
        fi
    done

    arcade_flush_buffer
    _tui_restore_stty
    tput cnorm 2>/dev/null || true
    tput clear 2>/dev/null || true
}

main "$@"
