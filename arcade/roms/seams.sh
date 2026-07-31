#!/usr/bin/env bash
# ============================================================
#  SEAMS  --  Find where one color becomes another, and cut
# ============================================================
#  A seam is a boundary. In VRGB a seam is the hue-angle where
#  one named region ends and the next begins. The system asks
#  for a seam ("orange | yellow"); you slide the blade along a
#  live gradient and cut at the boundary.
#
#  A seam is only real if the two sides are different things.
#  Cut where both sides read the same name and you have torn,
#  not seamed.
#
#  Thermodynamics: the field is always cooling. As heat bleeds
#  out the gradient washes toward gray and the seams blur. A
#  clean cut reheats the field; a torn cut bleeds heat. Cut
#  sharp, or the field freezes and the run is over.
#
#  System concept: perceptual hue boundaries. Where humans
#  place the cut is where the 90-degree context switch and the
#  VRGB band edges actually live.
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/lib/tui.sh"
source "${SCRIPT_DIR}/lib/vrgb.sh"
source "${SCRIPT_DIR}/lib/arcade-tokens.sh"

ARCADE_GAME_ID="seams"

# ============================================================
# GEOMETRY
# ============================================================

WIDTH=46          # gradient bar width in columns
SPAN=60           # degrees of hue the bar spans
SPREAD=8          # degrees each side of the blade is sampled for its name

# Canonical band edges (from vrgb_hue_name). Each is a seam
# between two named regions. We stay clear of the 0/360 wrap
# so the window math is linear.
EDGES=(45 75 105 135 165 195 225 255 285 315)

# ============================================================
# GAME STATE
# ============================================================

TARGET=0          # true seam hue for the current round
WINDOW_LO=0       # hue at the left edge of the bar
REGION_A=""       # name of the region on the low side
REGION_B=""       # name of the region on the high side
BLADE=0           # blade column (0 .. WIDTH-1)

HEAT=80           # field temperature; drives saturation; 0 = frozen
SCORE=0
CHAIN=0
BEST_CHAIN=0
LEVEL=1
CUTS=0
SHARP_CUTS=0
TICK=0
GAME_OVER=0

LAST_RESULT=""    # flash line after a cut
LAST_COLOR=""     # ANSI color for the flash line
FLASH=0           # frames the flash line lingers

# ============================================================
# ROUND SETUP
# ============================================================

pick_seam() {
    TARGET="${EDGES[$((RANDOM % ${#EDGES[@]}))]}"

    # Offset the window so the seam is never dead-center.
    local jitter=$(( (RANDOM % 31) - 15 ))   # -15 .. 15
    WINDOW_LO=$(( TARGET - 30 - jitter ))     # seam sits off-center in the bar
    if [[ "${WINDOW_LO}" -lt 0 ]]; then WINDOW_LO=0; fi

    vrgb_hue_name "$(( TARGET - 2 ))"; REGION_A="${VRGB_HUE_NAME}"
    vrgb_hue_name "$(( TARGET + 2 ))"; REGION_B="${VRGB_HUE_NAME}"

    # Start the blade off the seam.
    BLADE=4
}

blade_hue() {
    # Hue under the blade at its current column.
    echo $(( WINDOW_LO + SPAN * BLADE / (WIDTH - 1) ))
}

field_sat() {
    # Saturation follows heat. Cold field washes to gray and
    # the seams blur -- decay you can see.
    local s="${HEAT}"
    if [[ "${s}" -lt 8 ]]; then s=8; fi
    if [[ "${s}" -gt 92 ]]; then s=92; fi
    echo "${s}"
}

# ============================================================
# THE CUT
# ============================================================

do_cut() {
    local bh
    bh=$(blade_hue)
    local diff=$(( bh - TARGET ))
    if [[ "${diff}" -lt 0 ]]; then diff=$(( -diff )); fi

    CUTS=$(( CUTS + 1 ))

    local pts=0 reheat=0
    if [[ "${diff}" -le 2 ]]; then
        LAST_RESULT="SHARP SEAM  (${diff} deg)"
        LAST_COLOR="${_C_BOLD}${_C_GREEN}"
        pts=300; reheat=25
        CHAIN=$(( CHAIN + 1 )); SHARP_CUTS=$(( SHARP_CUTS + 1 ))
    elif [[ "${diff}" -le 6 ]]; then
        LAST_RESULT="clean cut  (${diff} deg)"
        LAST_COLOR="${_C_GREEN}"
        pts=150; reheat=15
        CHAIN=$(( CHAIN + 1 ))
    elif [[ "${diff}" -le 12 ]]; then
        LAST_RESULT="rough  (${diff} deg off)"
        LAST_COLOR="${_C_YELLOW}"
        pts=50; reheat=4
        CHAIN=0
    else
        LAST_RESULT="TORN -- same region both sides  (${diff} deg off)"
        LAST_COLOR="${_C_RED}"
        pts=0; reheat=-10
        CHAIN=0
    fi

    local mult=$(( 1 + CHAIN / 3 ))
    SCORE=$(( SCORE + pts * mult ))
    if [[ "${CHAIN}" -gt "${BEST_CHAIN}" ]]; then BEST_CHAIN="${CHAIN}"; fi

    HEAT=$(( HEAT + reheat ))
    if [[ "${HEAT}" -gt 100 ]]; then HEAT=100; fi

    FLASH=10

    # Tuning data: where the human actually placed the seam,
    # relative to the canonical band edge.
    arcade_buffer_token "cut" "${diff}" \
        --tags "tuning:hue_seam,seam:${REGION_A}_${REGION_B}" \
        --base-temp "${ARCADE_PRESET_BURST_TEMP}" --cooling-rate "${ARCADE_PRESET_BURST_RATE}"

    if [[ "${HEAT}" -le 0 ]]; then
        HEAT=0
        GAME_OVER=1
        return
    fi

    # Level up on sustained sharp work; the field cools faster.
    if [[ "${SCORE}" -ge $(( LEVEL * 900 )) ]]; then
        LEVEL=$(( LEVEL + 1 ))
        arcade_buffer_token "level" "${LEVEL}" \
            --tags "tuning:hue_seam" \
            --base-temp "${ARCADE_PRESET_PULSE_TEMP}" --cooling-rate "${ARCADE_PRESET_PULSE_RATE}"
    fi

    pick_seam
}

# ============================================================
# RENDER
# ============================================================

# Build the full colored gradient bar in one awk pass (one fork
# per frame instead of one per column). Emits the ANSI string.
build_bar() {
    local lo="$1" span="$2" width="$3" sat="$4" light="$5"
    awk -v lo="${lo}" -v span="${span}" -v w="${width}" -v s="${sat}" -v l="${light}" 'BEGIN {
        s = s / 100.0
        l = l / 100.0
        for (c = 0; c < w; c++) {
            h = lo + span * c / (w - 1)
            # HSL -> RGB
            cc = (1.0 - (2.0*l - 1.0 > 0 ? 2.0*l - 1.0 : -(2.0*l - 1.0))) * s
            hp = h / 60.0
            hmod = hp - int(hp/2)*2
            x = cc * (1.0 - (hmod - 1.0 > 0 ? hmod - 1.0 : -(hmod - 1.0)))
            m = l - cc / 2.0
            if (hp < 1)      { r = cc+m; g = x+m;  b = 0+m }
            else if (hp < 2) { r = x+m;  g = cc+m; b = 0+m }
            else if (hp < 3) { r = 0+m;  g = cc+m; b = x+m }
            else if (hp < 4) { r = 0+m;  g = x+m;  b = cc+m }
            else if (hp < 5) { r = x+m;  g = 0+m;  b = cc+m }
            else             { r = cc+m; g = 0+m;  b = x+m }
            ri = int(r*255 + 0.5); gi = int(g*255 + 0.5); bi = int(b*255 + 0.5)
            if (ri < 0) ri = 0; if (ri > 255) ri = 255
            if (gi < 0) gi = 0; if (gi > 255) gi = 255
            if (bi < 0) bi = 0; if (bi > 255) bi = 255
            printf "\033[48;2;%d;%d;%dm ", ri, gi, bi
        }
        printf "\033[0m"
    }'
}

render() {
    printf "\033[H"

    local w="${_C_BOLD}${_C_WHITE}" d="${_C_DIM}" z="${_C_RESET}"
    local g="${_C_GREEN}" y="${_C_YELLOW}" r="${_C_RED}"

    # Title
    printf "${w}SEAMS${z}  ${d}Level %d${z}" "${LEVEL}"
    tput el 2>/dev/null || true
    printf "\n\n"

    # The seam we are asked to find, drawn as its two regions.
    vrgb_swatch_hsl "$(( TARGET - 15 ))" 70 50 3
    printf " ${w}%s${z} ${d}|${z} ${w}%s${z} " "${REGION_A}" "${REGION_B}"
    vrgb_swatch_hsl "$(( TARGET + 15 ))" 70 50 3
    printf "   ${d}slide onto where they meet${z}"
    tput el 2>/dev/null || true
    printf "\n\n"

    # The live gradient bar.
    local sat
    sat=$(field_sat)
    printf "  "
    build_bar "${WINDOW_LO}" "${SPAN}" "${WIDTH}" "${sat}" 50
    printf "\n"

    # Blade caret under the bar.
    printf "  "
    local i=0
    while [[ "${i}" -lt "${WIDTH}" ]]; do
        if [[ "${i}" -eq "${BLADE}" ]]; then
            printf "${w}^${z}"
        else
            printf " "
        fi
        i=$(( i + 1 ))
    done
    tput el 2>/dev/null || true
    printf "\n\n"

    # What the blade separates right now: the two sides, named.
    local bh lh rh
    bh=$(blade_hue)
    lh=$(( bh - SPREAD )); if [[ "${lh}" -lt 0 ]]; then lh=0; fi
    rh=$(( bh + SPREAD )); if [[ "${rh}" -gt 359 ]]; then rh=359; fi
    vrgb_hue_name "${lh}"; local lname="${VRGB_HUE_NAME}"
    vrgb_hue_name "${rh}"; local rname="${VRGB_HUE_NAME}"

    printf "  left "
    vrgb_swatch_hsl "${lh}" 70 50 3
    printf " ${w}%-11s${z}" "${lname}"

    if [[ "${lname}" = "${rname}" ]]; then
        printf "  ${d}(same region -- not a seam)${z}  "
    else
        printf "  ${g}<< seam >>${z}  "
    fi

    printf "right "
    vrgb_swatch_hsl "${rh}" 70 50 3
    printf " ${w}%s${z}" "${rname}"
    tput el 2>/dev/null || true
    printf "\n\n"

    # Live homing: which way is the seam, and how close.
    local bdiff=$(( bh - TARGET )) adir="left"
    if [[ "${bdiff}" -lt 0 ]]; then adir="right"; bdiff=$(( -bdiff )); fi
    printf "  "
    if [[ "${bdiff}" -le 2 ]]; then
        printf "${_C_BOLD}${g}>>>  ON THE SEAM  --  press SPACE to cut  <<<${z}"
    elif [[ "${bdiff}" -le 6 ]]; then
        printf "${g}HOT${z}   ${d}tiny nudge ${adir}${z}"
    elif [[ "${bdiff}" -le 14 ]]; then
        printf "${y}warm${z}   ${d}move ${adir}${z}"
    else
        printf "${r}cold${z}   ${d}the seam is to the ${adir}${z}"
    fi
    tput el 2>/dev/null || true
    printf "\n\n"

    # Heat / thermodynamics bar.
    printf "  ${d}Heat${z} "
    local hb_max=24
    local hb_fill=$(( HEAT * hb_max / 100 ))
    local bi=0
    while [[ "${bi}" -lt "${hb_max}" ]]; do
        if [[ "${bi}" -lt "${hb_fill}" ]]; then
            if [[ "${HEAT}" -le 25 ]]; then printf "${r}${_BAR_FULL}${z}"
            elif [[ "${HEAT}" -le 50 ]]; then printf "${y}${_BAR_FULL}${z}"
            else printf "${g}${_BAR_FULL}${z}"; fi
        else
            printf "${d}${_BAR_EMPTY}${z}"
        fi
        bi=$(( bi + 1 ))
    done
    if [[ "${HEAT}" -le 25 ]]; then
        printf " ${r}freezing${z}"
    fi
    tput el 2>/dev/null || true
    printf "\n"

    # Score line.
    printf "  ${d}Score${z} ${w}%d${z}   ${d}Chain${z} ${w}%d${z}   ${d}High${z} ${w}%d${z}" \
        "${SCORE}" "${CHAIN}" "${ARCADE_HIGH_SCORE}"
    tput el 2>/dev/null || true
    printf "\n\n"

    # Flash line (result of the last cut).
    if [[ "${FLASH}" -gt 0 ]] && [[ -n "${LAST_RESULT}" ]]; then
        printf "  %s%s${z}" "${LAST_COLOR}" "${LAST_RESULT}"
    fi
    tput el 2>/dev/null || true
    printf "\n\n"

    printf "  ${d}<- ->  move blade toward the seam     space  cut     q  quit${z}"
    tput el 2>/dev/null || true
}

render_game_over() {
    printf "\033[H"
    local w="${_C_BOLD}${_C_WHITE}" r="${_C_RED}" z="${_C_RESET}" d="${_C_DIM}" c="${_C_CYAN}"

    printf "\n\n\n\n\n"
    _tui_center "${r}${_C_BOLD}THE FIELD FROZE${z}"
    printf "\n\n"
    _tui_center "Score: ${w}${SCORE}${z}   Sharp seams: ${w}${SHARP_CUTS}${z}/${CUTS}   Best chain: ${w}${BEST_CHAIN}${z}"
    printf "\n"
    _tui_center "${d}Tokens: ${c}${ARCADE_TOKEN_COUNT}${z}   ${d}High: ${w}${ARCADE_HIGH_SCORE}${z}"
    printf "\n\n"
    _tui_center "${d}SPACE to continue${z}"
    printf "\n\033[J"
}

# ============================================================
# MAIN LOOP
# ============================================================

main() {
    arcade_get_high_score
    ARCADE_TOKEN_COUNT=0
    arcade_init_pressure

    tput civis 2>/dev/null || true
    tput clear 2>/dev/null || printf "\033[2J"

    _TUI_SAVED_STTY=$(stty -g 2>/dev/null || echo "")
    stty -icanon -echo 2>/dev/null || true
    trap 'arcade_flush_buffer; _tui_restore_stty; tput cnorm 2>/dev/null; stty sane 2>/dev/null || true' EXIT INT TERM

    SCORE=0; CHAIN=0; BEST_CHAIN=0; LEVEL=1
    CUTS=0; SHARP_CUTS=0; HEAT=80; GAME_OVER=0
    pick_seam

    local _recorded=0

    while true; do
        if [[ "${GAME_OVER}" -eq 1 ]]; then
            if [[ "${_recorded}" -eq 0 ]]; then
                arcade_record_score "${SCORE}"
                arcade_announce "The field froze. Score ${SCORE}. ${SHARP_CUTS} sharp seams out of ${CUTS}."
                _recorded=1
            fi
            render_game_over
            local ch=""
            IFS= read -rsn1 ch || true
            if [[ "${ch}" = " " ]]; then break; fi
            continue
        fi

        render

        _tui_game_read 0.12
        local char="${_GAME_CHAR}"

        if [[ -n "${char}" ]]; then
            if [[ "${char}" = $'\x1b' ]]; then
                _tui_game_seq_read; local s1="${_GAME_CHAR}"
                if [[ "${s1}" = "[" ]]; then
                    _tui_game_seq_read; local s2="${_GAME_CHAR}"
                    case "${s2}" in
                        C) if [[ "${BLADE}" -lt $(( WIDTH - 1 )) ]]; then BLADE=$(( BLADE + 1 )); fi ;;
                        D) if [[ "${BLADE}" -gt 0 ]]; then BLADE=$(( BLADE - 1 )); fi ;;
                    esac
                fi
            elif [[ "${char}" = " " ]]; then
                do_cut
            elif [[ "${char}" = "a" ]] || [[ "${char}" = "A" ]]; then
                if [[ "${BLADE}" -gt 0 ]]; then BLADE=$(( BLADE - 1 )); fi
            elif [[ "${char}" = "d" ]] || [[ "${char}" = "D" ]]; then
                if [[ "${BLADE}" -lt $(( WIDTH - 1 )) ]]; then BLADE=$(( BLADE + 1 )); fi
            elif [[ "${char}" = "q" ]] || [[ "${char}" = "Q" ]]; then
                break
            fi
        fi

        TICK=$(( TICK + 1 ))
        if [[ "${FLASH}" -gt 0 ]]; then FLASH=$(( FLASH - 1 )); fi

        # Thermodynamics: the field always cools, faster at higher
        # levels. Idle and it freezes; keep cutting sharp to survive.
        local cool=$(( 1 + LEVEL / 2 ))
        if [[ $(( TICK % 3 )) -eq 0 ]]; then
            HEAT=$(( HEAT - cool ))
            if [[ "${HEAT}" -le 0 ]]; then
                HEAT=0
                GAME_OVER=1
            fi
        fi

        arcade_check_pressure
        arcade_heartbeat "score=${SCORE} heat=${HEAT} level=${LEVEL} chain=${CHAIN} sharp=${SHARP_CUTS}/${CUTS}"
    done

    arcade_flush_buffer
    _tui_restore_stty
    tput cnorm 2>/dev/null || true
    tput clear 2>/dev/null || true
}

main "$@"
