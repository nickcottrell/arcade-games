#!/usr/bin/env bash
# ============================================================
#  SPECTRAL  --  colorspace navigation and combat
# ============================================================
#  Your ship IS an HSL coordinate. Combat is proximity in
#  colorspace. Rotate your hue to match enemies and destroy
#  them. Trail cells decay and burn you if revisited hot.
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/lib/tui.sh"
source "${SCRIPT_DIR}/lib/vrgb.sh"
source "${SCRIPT_DIR}/lib/arcade-tokens.sh"

ARCADE_GAME_ID="spectral"

# ============================================================
# ARENA
# ============================================================

ARENA_W=40
ARENA_H=20

# ============================================================
# GAME STATE
# ============================================================

# Ship: position, facing (0=up 1=right 2=down 3=left), HSL color
SX=0 SY=0
SHIP_DIR=1
SHIP_H=0
SHIP_S=70
SHIP_L=50

# Enemies: parallel arrays
EX=()
EY=()
EH=()   # hue
ES=()   # saturation
EL=()   # lightness
NUM_ENEMIES=0
MAX_ENEMIES=5

# Trail: flat array indexed by y * ARENA_W + x
# Values: 0=empty, 1-5=heat level
TRAIL=()
# Trail color snapshot (hue at time of laying)
TRAIL_HUE=()

# Shield and scoring
SHIELD=100
SCORE=0
CHAIN=0
BEST_CHAIN=0
LEVEL=1
TICK=0
GAME_OVER=0

# Spawn timing
SPAWN_INTERVAL=30
SPAWN_TIMER=0

# Ship glyph per direction
SHIP_GLYPHS=("^" ">" "v" "<")

# ============================================================
# INIT
# ============================================================

init_level() {
    SX=$((ARENA_W / 2))
    SY=$((ARENA_H / 2))
    SHIP_DIR=1
    SHIP_H=$((RANDOM % 360))

    EX=()
    EY=()
    EH=()
    ES=()
    EL=()
    NUM_ENEMIES=0

    # Clear trail
    local total=$((ARENA_W * ARENA_H))
    TRAIL=()
    TRAIL_HUE=()
    local i=0
    while [[ "${i}" -lt "${total}" ]]; do
        TRAIL[$i]=0
        TRAIL_HUE[$i]=0
        i=$((i + 1))
    done

    SHIELD=100
    TICK=0
    SPAWN_TIMER=0

    # Spawn initial enemies
    local e=0
    while [[ "${e}" -lt 3 ]]; do
        spawn_enemy
        e=$((e + 1))
    done
}

# ============================================================
# ENEMY SPAWNING
# ============================================================

spawn_enemy() {
    if [[ "${NUM_ENEMIES}" -ge "${MAX_ENEMIES}" ]]; then return; fi

    # Spawn at random edge
    local ex=0 ey=0
    local edge=$((RANDOM % 4))
    case "${edge}" in
        0) ex=$((1 + RANDOM % (ARENA_W - 2))); ey=1 ;;
        1) ex=$((1 + RANDOM % (ARENA_W - 2))); ey=$((ARENA_H - 2)) ;;
        2) ex=1; ey=$((1 + RANDOM % (ARENA_H - 2))) ;;
        3) ex=$((ARENA_W - 2)); ey=$((1 + RANDOM % (ARENA_H - 2))) ;;
    esac

    vrgb_random_color
    EX+=("${ex}")
    EY+=("${ey}")
    EH+=("${VRGB_H}")
    ES+=("${VRGB_S}")
    EL+=("${VRGB_L}")
    NUM_ENEMIES=$((NUM_ENEMIES + 1))
}

# ============================================================
# MOVEMENT
# ============================================================

wrap_coord() {
    local val="$1" max="$2"
    if [[ "${val}" -lt 1 ]]; then
        echo $((max - 2))
    elif [[ "${val}" -ge $((max - 1)) ]]; then
        echo 1
    else
        echo "${val}"
    fi
}

move_ship() {
    local dx=0 dy=0
    case "${SHIP_DIR}" in
        0) dy=-1 ;;
        1) dx=1 ;;
        2) dy=1 ;;
        3) dx=-1 ;;
    esac

    SX=$(wrap_coord $((SX + dx)) "${ARENA_W}")
    SY=$(wrap_coord $((SY + dy)) "${ARENA_H}")

    # Lay trail at new position
    local idx=$((SY * ARENA_W + SX))
    local old_heat="${TRAIL[$idx]}"

    # Check if stepping on hot trail
    if [[ "${old_heat}" -ge 3 ]]; then
        SHIELD=$((SHIELD - (old_heat * 2)))
        arcade_buffer_token "trail_burn" "${old_heat}" \
            --base-temp "${ARCADE_PRESET_FLASH_TEMP}" --cooling-rate "${ARCADE_PRESET_FLASH_RATE}"
    fi

    TRAIL[$idx]=5
    TRAIL_HUE[$idx]="${SHIP_H}"

    if [[ "${SHIELD}" -le 0 ]]; then
        SHIELD=0
        GAME_OVER=1
    fi
}

move_enemies() {
    local i=0
    while [[ "${i}" -lt "${NUM_ENEMIES}" ]]; do
        local ex="${EX[$i]}" ey="${EY[$i]}"

        # Simple chase AI toward player (30% random)
        local dx=0 dy=0
        if [[ $((RANDOM % 10)) -lt 3 ]]; then
            local roll=$((RANDOM % 4))
            case "${roll}" in
                0) dx=1 ;;
                1) dx=-1 ;;
                2) dy=1 ;;
                3) dy=-1 ;;
            esac
        else
            if [[ "${SX}" -gt "${ex}" ]]; then dx=1
            elif [[ "${SX}" -lt "${ex}" ]]; then dx=-1; fi
            if [[ "${SY}" -gt "${ey}" ]]; then dy=1
            elif [[ "${SY}" -lt "${ey}" ]]; then dy=-1; fi

            # Prefer axis with larger distance
            local adx="${dx}" ady="${dy}"
            if [[ "${adx}" -lt 0 ]]; then adx=$((-adx)); fi
            if [[ "${ady}" -lt 0 ]]; then ady=$((-ady)); fi
            if [[ "${adx}" -ge "${ady}" ]]; then
                dy=0
            else
                dx=0
            fi
        fi

        local nx=$((ex + dx)) ny=$((ey + dy))
        nx=$(wrap_coord "${nx}" "${ARENA_W}")
        ny=$(wrap_coord "${ny}" "${ARENA_H}")
        EX[$i]="${nx}"
        EY[$i]="${ny}"

        i=$((i + 1))
    done
}

# ============================================================
# COMBAT (colorspace proximity)
# ============================================================

check_combat() {
    local i=0
    local killed=()

    while [[ "${i}" -lt "${NUM_ENEMIES}" ]]; do
        # Only check enemies that share our cell or adjacent
        local ex="${EX[$i]}" ey="${EY[$i]}"
        local dist_x=$((SX - ex))
        local dist_y=$((SY - ey))
        if [[ "${dist_x}" -lt 0 ]]; then dist_x=$((-dist_x)); fi
        if [[ "${dist_y}" -lt 0 ]]; then dist_y=$((-dist_y)); fi

        # Only engage within 3-cell spatial range
        if [[ "${dist_x}" -le 3 ]] && [[ "${dist_y}" -le 3 ]]; then
            vrgb_color_distance "${SHIP_H}" "${SHIP_S}" "${SHIP_L}" \
                                "${EH[$i]}" "${ES[$i]}" "${EL[$i]}"
            local cdist="${VRGB_DIST}"
            vrgb_proximity_label "${cdist}"

            if [[ "${cdist}" -lt 15 ]]; then
                # Kill: hot or exact match
                killed+=("${i}")
                local pts=100
                if [[ "${cdist}" -lt 5 ]]; then
                    pts=300
                fi
                CHAIN=$((CHAIN + 1))
                if [[ "${CHAIN}" -gt "${BEST_CHAIN}" ]]; then BEST_CHAIN="${CHAIN}"; fi
                local mult=$((1 + CHAIN / 3))
                SCORE=$((SCORE + pts * mult))

                arcade_buffer_token "kill" "${cdist}" \
                    --base-temp "${ARCADE_PRESET_BURST_TEMP}" --cooling-rate "${ARCADE_PRESET_BURST_RATE}"

            elif [[ "${cdist}" -lt 30 ]]; then
                # Warm: mutual damage
                SHIELD=$((SHIELD - 3))
                CHAIN=0
                if [[ "${SHIELD}" -le 0 ]]; then
                    SHIELD=0
                    GAME_OVER=1
                fi
            fi
        fi

        i=$((i + 1))
    done

    # Remove killed enemies (reverse order to keep indices valid)
    local k=${#killed[@]}
    while [[ "${k}" -gt 0 ]]; do
        k=$((k - 1))
        local idx="${killed[$k]}"
        remove_enemy "${idx}"
    done
}

remove_enemy() {
    local idx="$1"
    local last=$((NUM_ENEMIES - 1))

    if [[ "${idx}" -lt "${last}" ]]; then
        EX[$idx]="${EX[$last]}"
        EY[$idx]="${EY[$last]}"
        EH[$idx]="${EH[$last]}"
        ES[$idx]="${ES[$last]}"
        EL[$idx]="${EL[$last]}"
    fi

    unset "EX[${last}]"
    unset "EY[${last}]"
    unset "EH[${last}]"
    unset "ES[${last}]"
    unset "EL[${last}]"

    EX=("${EX[@]}")
    EY=("${EY[@]}")
    EH=("${EH[@]}")
    ES=("${ES[@]}")
    EL=("${EL[@]}")

    NUM_ENEMIES=$((NUM_ENEMIES - 1))
}

# ============================================================
# TRAIL DECAY
# ============================================================

decay_trail() {
    local total=$((ARENA_W * ARENA_H))
    local i=0
    while [[ "${i}" -lt "${total}" ]]; do
        if [[ "${TRAIL[$i]}" -gt 0 ]]; then
            TRAIL[$i]=$((TRAIL[$i] - 1))
        fi
        i=$((i + 1))
    done
}

# ============================================================
# SHIELD RECHARGE
# ============================================================

recharge_shield() {
    # Recharge 1 per tick when no damage taken this frame
    if [[ "${SHIELD}" -gt 0 ]] && [[ "${SHIELD}" -lt 100 ]]; then
        SHIELD=$((SHIELD + 1))
    fi
}

# ============================================================
# RENDER
# ============================================================

render() {
    printf "\033[H"

    local w="${_C_BOLD}${_C_WHITE}" d="${_C_DIM}" z="${_C_RESET}"
    local r="${_C_RED}" g="${_C_GREEN}" v="${_C_MAGENTA}"

    # Title line
    vrgb_hue_name "${SHIP_H}"
    printf "${w}SPECTRAL${z}  ${d}Level %d${z}  " "${LEVEL}"
    # Ship color swatch
    vrgb_hsl_to_rgb "${SHIP_H}" "${SHIP_S}" "${SHIP_L}"
    vrgb_swatch "${VRGB_R}" "${VRGB_G}" "${VRGB_B}" 2
    printf " ${d}%s${z}\n\n" "${VRGB_HUE_NAME}"

    # Arena
    local y=0
    while [[ "${y}" -lt "${ARENA_H}" ]]; do
        local x=0
        while [[ "${x}" -lt "${ARENA_W}" ]]; do
            # Border
            if [[ "${x}" -eq 0 ]] || [[ "${x}" -eq $((ARENA_W - 1)) ]] || \
               [[ "${y}" -eq 0 ]] || [[ "${y}" -eq $((ARENA_H - 1)) ]]; then
                printf "${_C_BLUE}${_BAR_FULL}${z}"
                x=$((x + 1))
                continue
            fi

            # Player ship
            if [[ "${x}" -eq "${SX}" ]] && [[ "${y}" -eq "${SY}" ]]; then
                vrgb_hsl_to_rgb "${SHIP_H}" "${SHIP_S}" "${SHIP_L}"
                printf "\033[38;2;%d;%d;%dm${_C_BOLD}%s\033[0m" \
                    "${VRGB_R}" "${VRGB_G}" "${VRGB_B}" "${SHIP_GLYPHS[$SHIP_DIR]}"
                x=$((x + 1))
                continue
            fi

            # Enemy
            local found_enemy=0
            local ei=0
            while [[ "${ei}" -lt "${NUM_ENEMIES}" ]]; do
                if [[ "${EX[$ei]}" -eq "${x}" ]] && [[ "${EY[$ei]}" -eq "${y}" ]]; then
                    found_enemy=1
                    vrgb_hsl_to_rgb "${EH[$ei]}" "${ES[$ei]}" "${EL[$ei]}"
                    printf "\033[38;2;%d;%d;%dm@\033[0m" "${VRGB_R}" "${VRGB_G}" "${VRGB_B}"
                    break
                fi
                ei=$((ei + 1))
            done

            if [[ "${found_enemy}" -eq 1 ]]; then
                x=$((x + 1))
                continue
            fi

            # Trail
            local tidx=$((y * ARENA_W + x))
            local th="${TRAIL[$tidx]}"
            if [[ "${th}" -gt 0 ]]; then
                local trail_hue="${TRAIL_HUE[$tidx]}"
                vrgb_hsl_to_rgb "${trail_hue}" 60 $((20 + th * 6))
                case "${th}" in
                    5|4) printf "\033[38;2;%d;%d;%dm${_BAR_SHADE3}\033[0m" "${VRGB_R}" "${VRGB_G}" "${VRGB_B}" ;;
                    3|2) printf "\033[38;2;%d;%d;%dm${_BAR_SHADE2}\033[0m" "${VRGB_R}" "${VRGB_G}" "${VRGB_B}" ;;
                    1)   printf "\033[38;2;%d;%d;%dm${_BAR_SHADE1}\033[0m" "${VRGB_R}" "${VRGB_G}" "${VRGB_B}" ;;
                esac
            else
                printf " "
            fi

            x=$((x + 1))
        done
        tput el 2>/dev/null || true
        printf "\n"
        y=$((y + 1))
    done

    # Shield bar
    printf "\nShield "
    local bar_max=20
    local bar_fill=$((SHIELD * bar_max / 100))
    local bi=0
    while [[ "${bi}" -lt "${bar_max}" ]]; do
        if [[ "${bi}" -lt "${bar_fill}" ]]; then
            if [[ "${SHIELD}" -le 25 ]]; then
                printf "${r}${_BAR_FULL}${z}"
            elif [[ "${SHIELD}" -le 50 ]]; then
                printf "${_C_YELLOW}${_BAR_FULL}${z}"
            else
                printf "${g}${_BAR_FULL}${z}"
            fi
        else
            printf "${d}${_BAR_EMPTY}${z}"
        fi
        bi=$((bi + 1))
    done
    printf " ${d}%d%%${z}" "${SHIELD}"

    printf "  Score ${_C_BOLD}%d${z}" "${SCORE}"
    printf "  Chain ${_C_BOLD}%d${z}" "${CHAIN}"
    tput el 2>/dev/null || true
    printf "\n"

    # Proximity alert
    local closest_dist=999
    local ci=0
    while [[ "${ci}" -lt "${NUM_ENEMIES}" ]]; do
        local edx=$((SX - EX[$ci]))
        local edy=$((SY - EY[$ci]))
        if [[ "${edx}" -lt 0 ]]; then edx=$((-edx)); fi
        if [[ "${edy}" -lt 0 ]]; then edy=$((-edy)); fi
        if [[ "${edx}" -le 5 ]] && [[ "${edy}" -le 5 ]]; then
            vrgb_color_distance "${SHIP_H}" "${SHIP_S}" "${SHIP_L}" \
                                "${EH[$ci]}" "${ES[$ci]}" "${EL[$ci]}"
            if [[ "${VRGB_DIST}" -lt "${closest_dist}" ]]; then
                closest_dist="${VRGB_DIST}"
            fi
        fi
        ci=$((ci + 1))
    done

    if [[ "${closest_dist}" -lt 30 ]]; then
        vrgb_proximity_label "${closest_dist}"
        if [[ "${closest_dist}" -lt 5 ]]; then
            printf "${_C_BOLD}${g}EXACT MATCH${z}"
        elif [[ "${closest_dist}" -lt 15 ]]; then
            printf "${_C_BOLD}${_C_YELLOW}HOT${z}"
        else
            printf "${r}WARM - DANGER${z}"
        fi
    else
        printf "${d}No targets in range${z}"
    fi
    tput el 2>/dev/null || true
    printf "\n"

    # Token / High score / Pressure line
    printf "${d}Tokens: ${_C_CYAN}%d${z}  ${d}High: ${_C_BOLD}%d${z}" "${ARCADE_TOKEN_COUNT}" "${ARCADE_HIGH_SCORE}"
    tput el 2>/dev/null || true
    printf "\n"

    # Pressure bar
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

    printf "${d}L/R hue  Up thrust  Q quit${z}"
    tput el 2>/dev/null || true
}

render_game_over() {
    printf "\033[H"
    local w="${_C_BOLD}${_C_WHITE}" r="${_C_RED}" z="${_C_RESET}" d="${_C_DIM}"
    local c="${_C_CYAN}"

    printf "\n\n\n\n\n\n\n\n"
    _tui_center "${r}${_C_BOLD}SHIELDS DOWN${z}"
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

main() {
    if ! arcade_require_server; then
        echo "  Press any key to exit..."
        read -rsn1
        return 1
    fi

    arcade_get_high_score
    ARCADE_TOKEN_COUNT=0
    arcade_init_pressure
    arcade_set_leak_rate 2

    tput civis 2>/dev/null || true
    tput clear 2>/dev/null || printf "\033[2J"

    # Raw terminal mode -- perl select() handles frame timing
    _TUI_SAVED_STTY=$(stty -g 2>/dev/null || echo "")
    stty -icanon -echo 2>/dev/null || true
    trap 'arcade_flush_buffer; _tui_restore_stty; tput cnorm 2>/dev/null' EXIT

    SCORE=0
    CHAIN=0
    BEST_CHAIN=0
    LEVEL=1
    GAME_OVER=0
    MAX_ENEMIES=5
    SPAWN_INTERVAL=30
    init_level

    local enemy_rate=3
    local trail_decay_rate=8

    local _score_recorded=0

    while true; do
        if [[ "${GAME_OVER}" -eq 1 ]]; then
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
                        A) move_ship ;;                     # Up = thrust
                        C) SHIP_H=$(( (SHIP_H + 15) % 360 )) ;;  # Right = hue +
                        D) SHIP_H=$(( (SHIP_H + 345) % 360 )) ;; # Left = hue -
                    esac
                fi
            elif [[ "${char}" = "q" ]] || [[ "${char}" = "Q" ]]; then
                break
            fi
        fi

        TICK=$((TICK + 1))

        # Pressure gauge
        arcade_check_pressure

        # Enemy movement (modulated by level)
        enemy_rate=$((4 - LEVEL / 3))
        if [[ "${enemy_rate}" -lt 2 ]]; then enemy_rate=2; fi

        if [[ $((TICK % enemy_rate)) -eq 0 ]]; then
            move_enemies
            check_combat
        fi

        # Trail decay
        trail_decay_rate=$((10 - LEVEL))
        if [[ "${trail_decay_rate}" -lt 4 ]]; then trail_decay_rate=4; fi
        if [[ $((TICK % trail_decay_rate)) -eq 0 ]]; then
            decay_trail
        fi

        # Shield recharge (only when no combat damage this frame)
        if [[ $((TICK % 3)) -eq 0 ]]; then
            recharge_shield
        fi

        # Enemy spawning (zone modulates interval)
        case "${ARCADE_PRESSURE_ZONE}" in
            critical) SPAWN_INTERVAL=40 ;;
            low)      SPAWN_INTERVAL=25 ;;
            medium)   SPAWN_INTERVAL=15 ;;
            high)     SPAWN_INTERVAL=8 ;;
        esac

        SPAWN_TIMER=$((SPAWN_TIMER + 1))
        if [[ "${SPAWN_TIMER}" -ge "${SPAWN_INTERVAL}" ]]; then
            spawn_enemy
            SPAWN_TIMER=0
        fi

        # Level progression
        if [[ "${SCORE}" -ge $((LEVEL * 500)) ]]; then
            LEVEL=$((LEVEL + 1))
            MAX_ENEMIES=$((5 + LEVEL))
            if [[ "${MAX_ENEMIES}" -gt 12 ]]; then MAX_ENEMIES=12; fi
            arcade_create_token "level_complete" "${LEVEL}" \
                --base-temp "${ARCADE_PRESET_PULSE_TEMP}" --cooling-rate "${ARCADE_PRESET_PULSE_RATE}"
        fi
    done

    arcade_flush_buffer
    _tui_restore_stty
    tput cnorm 2>/dev/null || true
    tput clear 2>/dev/null || true
}

main "$@"
