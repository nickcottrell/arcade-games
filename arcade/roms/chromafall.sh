#!/usr/bin/env bash
# ============================================================
#  CHROMAFALL  --  falling color blocks in VRGB colorspace
# ============================================================
#  Stack falling four-cell pieces. Clear lines. Each piece carries
#  a unique hue from the VRGB color wheel.  Cleared lines
#  emit tokens tagged with the dominant hue of that row.
#
#  Controls: Left/Right move, Up rotate, Down soft-drop,
#            Space hard-drop, Q quit.
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/lib/tui.sh"
source "${SCRIPT_DIR}/lib/vrgb.sh"
source "${SCRIPT_DIR}/lib/arcade-tokens.sh"

ARCADE_GAME_ID="chromafall"

# ============================================================
# PLAYFIELD  (10 wide x 20 tall)
# ============================================================

FIELD_W=10
FIELD_H=20

# Flat array: FIELD[y * FIELD_W + x] = piece_id (0=empty, 1-7)
FIELD=()

# ============================================================
# PIECES  (7 four-cell pieces, 4 rotations each)
# ============================================================
# Each rotation encoded as "x0 y0 x1 y1 x2 y2 x3 y3"
# relative to pivot point.

# 1: I  (cyan 180)
P1R0="-1 0 0 0 1 0 2 0"
P1R1="0 -1 0 0 0 1 0 2"
P1R2="-1 0 0 0 1 0 2 0"
P1R3="0 -1 0 0 0 1 0 2"

# 2: O  (yellow 60)
P2R0="0 0 1 0 0 1 1 1"
P2R1="0 0 1 0 0 1 1 1"
P2R2="0 0 1 0 0 1 1 1"
P2R3="0 0 1 0 0 1 1 1"

# 3: T  (purple 270)
P3R0="-1 0 0 0 1 0 0 -1"
P3R1="0 -1 0 0 0 1 1 0"
P3R2="-1 0 0 0 1 0 0 1"
P3R3="0 -1 0 0 0 1 -1 0"

# 4: S  (green 120)
P4R0="0 0 1 0 -1 1 0 1"
P4R1="0 -1 0 0 1 0 1 1"
P4R2="0 0 1 0 -1 1 0 1"
P4R3="0 -1 0 0 1 0 1 1"

# 5: Z  (red 0)
P5R0="-1 0 0 0 0 1 1 1"
P5R1="1 -1 1 0 0 0 0 1"
P5R2="-1 0 0 0 0 1 1 1"
P5R3="1 -1 1 0 0 0 0 1"

# 6: J  (blue 240)
P6R0="-1 -1 -1 0 0 0 1 0"
P6R1="0 -1 1 -1 0 0 0 1"
P6R2="-1 0 0 0 1 0 1 1"
P6R3="0 -1 0 0 -1 1 0 1"

# 7: L  (orange 30)
P7R0="1 -1 -1 0 0 0 1 0"
P7R1="0 -1 0 0 0 1 1 1"
P7R2="-1 0 0 0 1 0 -1 1"
P7R3="-1 -1 0 -1 0 0 0 1"

# HSL per piece  (index 0 unused)
PIECE_H=(0 180 60 270 120 0 240 30)
PIECE_S=(0 80  80 70  70  80 80  80)
PIECE_L=(0 55  55 50  50  50 45  55)

# Pre-computed RGB (filled at init)
_PR=(0) _PG=(0) _PB=(0)

# ============================================================
# GAME STATE
# ============================================================

CUR_PIECE=0   # 1-7
CUR_ROT=0     # 0-3
CUR_X=0
CUR_Y=0

NEXT_PIECE=0

SCORE=0
LINES=0
LEVEL=1
TICK=0
GAME_OVER=0
DROP_RATE=5   # ticks between gravity drops

# Render helper: comma-delimited set of current-piece cell indices
_CUR_CELLS=","

# ============================================================
# PIECE HELPERS
# ============================================================

# Populate _CUR_CELLS for fast render lookup
_precompute_cells() {
    _CUR_CELLS=","
    local var="P${CUR_PIECE}R${CUR_ROT}"
    local rot="${!var}"
    local coords
    read -ra coords <<< "${rot}"
    local i=0
    while [[ "${i}" -lt 8 ]]; do
        local cx=$((CUR_X + coords[i]))
        local cy=$((CUR_Y + coords[i + 1]))
        if [[ "${cy}" -ge 0 ]] && [[ "${cy}" -lt "${FIELD_H}" ]] && \
           [[ "${cx}" -ge 0 ]] && [[ "${cx}" -lt "${FIELD_W}" ]]; then
            _CUR_CELLS="${_CUR_CELLS}$((cy * FIELD_W + cx)),"
        fi
        i=$((i + 2))
    done
}

# Check if piece p at rotation r, position px,py fits on the field
_piece_fits() {
    local p="$1" r="$2" px="$3" py="$4"
    local var="P${p}R${r}"
    local rot="${!var}"
    local coords
    read -ra coords <<< "${rot}"
    local i=0
    while [[ "${i}" -lt 8 ]]; do
        local cx=$((px + coords[i]))
        local cy=$((py + coords[i + 1]))
        if [[ "${cx}" -lt 0 ]] || [[ "${cx}" -ge "${FIELD_W}" ]]; then return 1; fi
        if [[ "${cy}" -ge "${FIELD_H}" ]]; then return 1; fi
        if [[ "${cy}" -ge 0 ]]; then
            if [[ "${FIELD[$((cy * FIELD_W + cx))]}" -ne 0 ]]; then return 1; fi
        fi
        i=$((i + 2))
    done
    return 0
}

# Stamp current piece into the field
_lock_piece() {
    local var="P${CUR_PIECE}R${CUR_ROT}"
    local rot="${!var}"
    local coords
    read -ra coords <<< "${rot}"
    local i=0
    while [[ "${i}" -lt 8 ]]; do
        local cx=$((CUR_X + coords[i]))
        local cy=$((CUR_Y + coords[i + 1]))
        if [[ "${cy}" -ge 0 ]] && [[ "${cy}" -lt "${FIELD_H}" ]] && \
           [[ "${cx}" -ge 0 ]] && [[ "${cx}" -lt "${FIELD_W}" ]]; then
            FIELD[$((cy * FIELD_W + cx))]="${CUR_PIECE}"
        fi
        i=$((i + 2))
    done
}

# ============================================================
# LINE CLEARING
# ============================================================

_clear_lines() {
    local cleared=0
    local y=$((FIELD_H - 1))
    while [[ "${y}" -ge 0 ]]; do
        # Check if row is full
        local full=1
        local x=0
        while [[ "${x}" -lt "${FIELD_W}" ]]; do
            if [[ "${FIELD[$((y * FIELD_W + x))]}" -eq 0 ]]; then
                full=0
                break
            fi
            x=$((x + 1))
        done

        if [[ "${full}" -eq 1 ]]; then
            # Find dominant piece type in this row
            local _counts=(0 0 0 0 0 0 0 0)
            x=0
            while [[ "${x}" -lt "${FIELD_W}" ]]; do
                local pid="${FIELD[$((y * FIELD_W + x))]}"
                _counts[$pid]=$((_counts[$pid] + 1))
                x=$((x + 1))
            done
            local _dom=1 _dom_c=0 _ci=1
            while [[ "${_ci}" -le 7 ]]; do
                if [[ "${_counts[$_ci]}" -gt "${_dom_c}" ]]; then
                    _dom="${_ci}"; _dom_c="${_counts[$_ci]}"
                fi
                _ci=$((_ci + 1))
            done

            # Emit token with the dominant hue
            arcade_buffer_token "line_clear" "${PIECE_H[$_dom]}" \
                --base-temp "${ARCADE_PRESET_BURST_TEMP}" --cooling-rate "${ARCADE_PRESET_BURST_RATE}"

            # Shift everything above down by one row
            local sy=$((y - 1))
            while [[ "${sy}" -ge 0 ]]; do
                x=0
                while [[ "${x}" -lt "${FIELD_W}" ]]; do
                    FIELD[$(((sy + 1) * FIELD_W + x))]="${FIELD[$((sy * FIELD_W + x))]}"
                    x=$((x + 1))
                done
                sy=$((sy - 1))
            done
            # Clear top row
            x=0
            while [[ "${x}" -lt "${FIELD_W}" ]]; do
                FIELD[$x]=0
                x=$((x + 1))
            done

            cleared=$((cleared + 1))
            # Re-check same row (shifted content)
        else
            y=$((y - 1))
        fi
    done

    if [[ "${cleared}" -gt 0 ]]; then
        LINES=$((LINES + cleared))
        case "${cleared}" in
            1) SCORE=$((SCORE + 100 * LEVEL)) ;;
            2) SCORE=$((SCORE + 300 * LEVEL)) ;;
            3) SCORE=$((SCORE + 500 * LEVEL)) ;;
            *) SCORE=$((SCORE + 800 * LEVEL)) ;;
        esac
        LEVEL=$((LINES / 10 + 1))
        DROP_RATE=$((6 - LEVEL))
        if [[ "${DROP_RATE}" -lt 1 ]]; then DROP_RATE=1; fi

        if [[ "${cleared}" -ge 4 ]]; then
            arcade_buffer_token "line_clear" "${cleared}" \
                --base-temp "${ARCADE_PRESET_PULSE_TEMP}" --cooling-rate "${ARCADE_PRESET_PULSE_RATE}"
        fi
    fi
}

# ============================================================
# SPAWNING
# ============================================================

_spawn_piece() {
    CUR_PIECE="${NEXT_PIECE}"
    NEXT_PIECE=$((1 + RANDOM % 7))
    CUR_ROT=0
    CUR_X=$((FIELD_W / 2))
    CUR_Y=0

    if ! _piece_fits "${CUR_PIECE}" "${CUR_ROT}" "${CUR_X}" "${CUR_Y}"; then
        GAME_OVER=1
    fi
}

# ============================================================
# INIT
# ============================================================

_init_colors() {
    _PR=(0); _PG=(0); _PB=(0)
    local i=1
    while [[ "${i}" -le 7 ]]; do
        vrgb_hsl_to_rgb "${PIECE_H[$i]}" "${PIECE_S[$i]}" "${PIECE_L[$i]}"
        _PR+=("${VRGB_R}"); _PG+=("${VRGB_G}"); _PB+=("${VRGB_B}")
        i=$((i + 1))
    done
}

init_game() {
    FIELD=()
    local total=$((FIELD_W * FIELD_H))
    local i=0
    while [[ "${i}" -lt "${total}" ]]; do
        FIELD[$i]=0
        i=$((i + 1))
    done

    NEXT_PIECE=$((1 + RANDOM % 7))
    _spawn_piece
    NEXT_PIECE=$((1 + RANDOM % 7))

    SCORE=0
    LINES=0
    LEVEL=1
    TICK=0
    GAME_OVER=0
    DROP_RATE=5
}

# ============================================================
# RENDER
# ============================================================

render() {
    _precompute_cells
    printf "\033[H"

    local w="${_C_BOLD}${_C_WHITE}" d="${_C_DIM}" z="${_C_RESET}"
    local r="${_C_RED}" g="${_C_GREEN}"

    printf "${w}CHROMAFALL${z}  ${d}Level %d${z}\n\n" "${LEVEL}"

    local y=0
    while [[ "${y}" -lt "${FIELD_H}" ]]; do
        printf "${_C_BLUE}${_BAR_FULL}${z}"
        local x=0
        while [[ "${x}" -lt "${FIELD_W}" ]]; do
            local idx=$((y * FIELD_W + x))
            local cell="${FIELD[$idx]}"

            if [[ "${_CUR_CELLS}" = *",${idx},"* ]]; then
                # Active piece -- bright
                printf "\033[38;2;%d;%d;%dm${_BAR_FULL}\033[0m" \
                    "${_PR[$CUR_PIECE]}" "${_PG[$CUR_PIECE]}" "${_PB[$CUR_PIECE]}"
            elif [[ "${cell}" -ne 0 ]]; then
                # Placed piece -- slightly dimmer
                printf "\033[38;2;%d;%d;%dm${_BAR_SHADE3}\033[0m" \
                    "${_PR[$cell]}" "${_PG[$cell]}" "${_PB[$cell]}"
            else
                printf " "
            fi
            x=$((x + 1))
        done
        printf "${_C_BLUE}${_BAR_FULL}${z}"

        # Side panel
        case "${y}" in
            1) printf "  ${d}Next${z}" ;;
            3) printf "  "
               printf "\033[38;2;%d;%d;%dm${_BAR_FULL}${_BAR_FULL}${_BAR_FULL}${_BAR_FULL}\033[0m" \
                   "${_PR[$NEXT_PIECE]}" "${_PG[$NEXT_PIECE]}" "${_PB[$NEXT_PIECE]}" ;;
            6)  printf "  Score ${w}%d${z}" "${SCORE}" ;;
            8)  printf "  Lines ${w}%d${z}" "${LINES}" ;;
            10) printf "  Level ${w}%d${z}" "${LEVEL}" ;;
            13) printf "  ${d}Tokens ${_C_CYAN}%d${z}" "${ARCADE_TOKEN_COUNT}" ;;
            14) printf "  ${d}High ${w}%d${z}" "${ARCADE_HIGH_SCORE}" ;;
        esac

        tput el 2>/dev/null || true
        printf "\n"
        y=$((y + 1))
    done

    # Bottom wall
    printf "${_C_BLUE}"
    local bx=0
    while [[ "${bx}" -lt $((FIELD_W + 2)) ]]; do
        printf "${_BAR_FULL}"
        bx=$((bx + 1))
    done
    printf "${z}"
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

    printf "${d}Arrows move  Up rotate  Space drop  Q quit${z}"
    tput el 2>/dev/null || true
}

render_game_over() {
    printf "\033[H"
    local w="${_C_BOLD}${_C_WHITE}" r="${_C_RED}" z="${_C_RESET}" d="${_C_DIM}"
    local c="${_C_CYAN}"

    printf "\n\n\n\n\n\n\n\n\n"
    _tui_center "${r}${_C_BOLD}STACK OVERFLOW${z}"
    printf "\n\n"
    _tui_center "Score: ${w}${SCORE}${z}   Lines: ${w}${LINES}${z}   Level: ${w}${LEVEL}${z}"
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

    _init_colors

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
                arcade_announce "Game over. Score: ${SCORE}. ${LINES} lines cleared. Level ${LEVEL}."
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

        # Non-blocking input via perl select()
        _tui_game_read 0.15
        local char="${_GAME_CHAR}"

        if [[ -n "${char}" ]]; then
            if [[ "${char}" = $'\x1b' ]]; then
                _tui_game_seq_read; local s1="${_GAME_CHAR}"
                if [[ "${s1}" = "[" ]]; then
                    _tui_game_seq_read; local s2="${_GAME_CHAR}"
                    case "${s2}" in
                        A) # Up = rotate clockwise
                            local nr=$(( (CUR_ROT + 1) % 4 ))
                            if _piece_fits "${CUR_PIECE}" "${nr}" "${CUR_X}" "${CUR_Y}"; then
                                CUR_ROT="${nr}"
                            # Wall kick: try one cell left, then right
                            elif _piece_fits "${CUR_PIECE}" "${nr}" $((CUR_X - 1)) "${CUR_Y}"; then
                                CUR_ROT="${nr}"; CUR_X=$((CUR_X - 1))
                            elif _piece_fits "${CUR_PIECE}" "${nr}" $((CUR_X + 1)) "${CUR_Y}"; then
                                CUR_ROT="${nr}"; CUR_X=$((CUR_X + 1))
                            fi
                            ;;
                        B) # Down = soft drop
                            if _piece_fits "${CUR_PIECE}" "${CUR_ROT}" "${CUR_X}" $((CUR_Y + 1)); then
                                CUR_Y=$((CUR_Y + 1))
                                SCORE=$((SCORE + 1))
                            fi
                            ;;
                        C) # Right
                            if _piece_fits "${CUR_PIECE}" "${CUR_ROT}" $((CUR_X + 1)) "${CUR_Y}"; then
                                CUR_X=$((CUR_X + 1))
                            fi
                            ;;
                        D) # Left
                            if _piece_fits "${CUR_PIECE}" "${CUR_ROT}" $((CUR_X - 1)) "${CUR_Y}"; then
                                CUR_X=$((CUR_X - 1))
                            fi
                            ;;
                    esac
                fi
            elif [[ "${char}" = "q" ]] || [[ "${char}" = "Q" ]]; then
                break
            elif [[ "${char}" = " " ]]; then
                # Space = hard drop
                while _piece_fits "${CUR_PIECE}" "${CUR_ROT}" "${CUR_X}" $((CUR_Y + 1)); do
                    CUR_Y=$((CUR_Y + 1))
                    SCORE=$((SCORE + 2))
                done
                _lock_piece
                _clear_lines
                _spawn_piece
                TICK=0
                continue
            fi
        fi

        TICK=$((TICK + 1))

        # Pressure gauge
        arcade_check_pressure

        # Gravity
        if [[ $((TICK % DROP_RATE)) -eq 0 ]]; then
            if _piece_fits "${CUR_PIECE}" "${CUR_ROT}" "${CUR_X}" $((CUR_Y + 1)); then
                CUR_Y=$((CUR_Y + 1))
            else
                _lock_piece
                _clear_lines
                _spawn_piece
            fi
        fi
    done

    arcade_flush_buffer
    _tui_restore_stty
    tput cnorm 2>/dev/null || true
    tput clear 2>/dev/null || true
}

main "$@"
