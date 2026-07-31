#!/usr/bin/env bash
# ============================================================
#  KENNING  --  Build metaphors by finding shared coordinates
# ============================================================
#  A kenning is a compressed metaphor -- "whale-road" = sea.
#
#  This is a VRGB game in the true sense: color is the ADDRESS,
#  not the point. Two worlds (domains) each hang their words at
#  fixed coordinates on the shared spectrum. Where a word in the
#  top world and a word in the bottom world sit at the SAME
#  coordinate, they mean the same thing in two domains at once --
#  that is a metaphor. Slide the plumb line onto that column,
#  watch both words light up, and bridge them.
#
#  This is the whitepaper's cross-domain interpretation (section
#  7) made playable: one coordinate, read by two schemas. A
#  resonant metaphor is a coordinate that lands near an anchor in
#  BOTH domains. The anchors here are hand-placed -- "designed
#  anchor alignment," exactly as the spec allows.
#
#  System concept: metaphor = shared latent, two interpreters.
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/lib/tui.sh"
source "${SCRIPT_DIR}/lib/vrgb.sh"
source "${SCRIPT_DIR}/lib/arcade-tokens.sh"

ARCADE_GAME_ID="kenning"

# ============================================================
# GEOMETRY
# ============================================================

WIDTH=64          # spectrum width in columns; hue 0..360 maps across it
ROUNDS_TOTAL=4

# ============================================================
# GAME STATE
# ============================================================

ROUND=1
DOM_A=""; DOM_B=""
AW=(); AH=(); AB=()      # world A: word, hue, bridged-flag  (sorted by hue)
BW=(); BH=(); BB=()      # world B
KEN_TOTAL=3              # kennings to find this round
FOUND=0

CUR_COL=0
CUR_HUE=0
A_SEL=0; A_GAP=999
B_SEL=0; B_GAP=999
RESO=999
READY=0

HEAT=85
SCORE=0
CHAIN=0
BEST_CHAIN=0
TOTAL_FOUND=0
TICK=0
GAME_OVER=0
WIN=0

FLASH=""; FLASH_COLOR=""; FLASH_T=0

# ============================================================
# ROUND DATA  (anchors placed so exactly 3 pairs resonate)
# ============================================================

load_round() {
    local r="$1"
    AB=(0 0 0 0); BB=(0 0 0 0); FOUND=0
    case "${r}" in
        1)
            DOM_A="SEA";   AW=(tide depth storm horizon);   AH=(40 120 210 320)
            DOM_B="GRIEF"; BW=(waves despair fury distance); BH=(44 124 270 320)
            ;;
        2)
            DOM_A="FIRE";  AW=(spark blaze ember smoke);     AH=(15 50 90 210)
            DOM_B="ANGER"; BW=(rage flare grudge fume);      BH=(18 50 300 205)
            ;;
        3)
            DOM_A="LIGHT";     AW=(spark dawn beam shadow);      AH=(0 40 180 270)
            DOM_B="KNOWLEDGE"; BW=(insight idea focus doubt);    BH=(43 120 178 268)
            ;;
        4)
            DOM_A="WATER"; AW=(flood drop river still);      AH=(0 90 200 280)
            DOM_B="TIME";  BW=(deluge moment flow pause);    BH=(5 88 203 150)
            ;;
    esac
    KEN_TOTAL=3
}

col_of() {
    # hue -> spectrum column
    echo $(( $1 * WIDTH / 360 ))
}

# ============================================================
# SELECTION  (which pair is the plumb line over, is it resonant)
# ============================================================

update_selection() {
    CUR_HUE=$(( CUR_COL * 360 / WIDTH ))

    A_SEL=0; A_GAP=999
    local i=0
    while [[ "${i}" -lt "${#AW[@]}" ]]; do
        vrgb_hue_distance "${CUR_HUE}" "${AH[$i]}"
        if [[ "${VRGB_DIST}" -lt "${A_GAP}" ]]; then A_GAP="${VRGB_DIST}"; A_SEL="${i}"; fi
        i=$(( i + 1 ))
    done

    B_SEL=0; B_GAP=999
    i=0
    while [[ "${i}" -lt "${#BW[@]}" ]]; do
        vrgb_hue_distance "${CUR_HUE}" "${BH[$i]}"
        if [[ "${VRGB_DIST}" -lt "${B_GAP}" ]]; then B_GAP="${VRGB_DIST}"; B_SEL="${i}"; fi
        i=$(( i + 1 ))
    done

    vrgb_hue_distance "${AH[$A_SEL]}" "${BH[$B_SEL]}"
    RESO="${VRGB_DIST}"

    # Ready when the plumb line is parked on a resonant, unbridged pair.
    READY=0
    if [[ "${A_GAP}" -le 8 ]] && [[ "${RESO}" -le 8 ]] \
       && [[ "${AB[$A_SEL]}" -eq 0 ]] && [[ "${BB[$B_SEL]}" -eq 0 ]]; then
        READY=1
    fi
}

# ============================================================
# BRIDGE
# ============================================================

do_pluck() {
    if [[ "${READY}" -eq 1 ]]; then
        local pts=60
        local label="faint"
        if [[ "${RESO}" -le 2 ]]; then pts=300; label="PERFECT RESONANCE"
        elif [[ "${RESO}" -le 5 ]]; then pts=150; label="strong"
        fi

        CHAIN=$(( CHAIN + 1 ))
        if [[ "${CHAIN}" -gt "${BEST_CHAIN}" ]]; then BEST_CHAIN="${CHAIN}"; fi
        local mult=$(( 1 + CHAIN / 3 ))
        SCORE=$(( SCORE + pts * mult ))

        AB[$A_SEL]=1; BB[$B_SEL]=1
        FOUND=$(( FOUND + 1 )); TOTAL_FOUND=$(( TOTAL_FOUND + 1 ))

        HEAT=$(( HEAT + 18 )); if [[ "${HEAT}" -gt 100 ]]; then HEAT=100; fi

        FLASH="KENNING:  ${AW[$A_SEL]} <=> ${BW[$B_SEL]}   ${label}  +$(( pts * mult ))"
        FLASH_COLOR="${_C_BOLD}${_C_GREEN}"; FLASH_T=14

        arcade_buffer_token "kenning" "${RESO}" \
            --tags "tuning:metaphor_resonance,pair:${DOM_A}_${DOM_B}" \
            --base-temp "${ARCADE_PRESET_BURST_TEMP}" --cooling-rate "${ARCADE_PRESET_BURST_RATE}"

        if [[ "${FOUND}" -ge "${KEN_TOTAL}" ]]; then
            advance_round
        fi
    else
        CHAIN=0
        HEAT=$(( HEAT - 8 ))
        FLASH="no bridge -- nothing resonant on this column"
        FLASH_COLOR="${_C_RED}"; FLASH_T=12
        if [[ "${HEAT}" -le 0 ]]; then HEAT=0; GAME_OVER=1; fi
    fi
}

advance_round() {
    if [[ "${ROUND}" -ge "${ROUNDS_TOTAL}" ]]; then
        WIN=1; GAME_OVER=1
        return
    fi
    ROUND=$(( ROUND + 1 ))
    load_round "${ROUND}"
    CUR_COL=0
    arcade_buffer_token "round_clear" "${ROUND}" \
        --tags "tuning:metaphor_resonance" \
        --base-temp "${ARCADE_PRESET_PULSE_TEMP}" --cooling-rate "${ARCADE_PRESET_PULSE_RATE}"
}

# ============================================================
# RENDER
# ============================================================

# Full colored spectrum bar in one awk pass. Saturation follows
# heat, so a cooling span visibly washes toward gray.
build_bar() {
    local sat="$1"
    awk -v w="${WIDTH}" -v s="${sat}" 'BEGIN {
        s = s / 100.0; l = 0.5
        for (c = 0; c < w; c++) {
            h = 360.0 * c / (w - 1)
            cc = (1.0 - (2.0*l - 1.0 > 0 ? 2.0*l - 1.0 : -(2.0*l - 1.0))) * s
            hp = h / 60.0; hmod = hp - int(hp/2)*2
            x = cc * (1.0 - (hmod - 1.0 > 0 ? hmod - 1.0 : -(hmod - 1.0))); m = l - cc/2.0
            if (hp < 1)      { r = cc+m; g = x+m;  b = 0+m }
            else if (hp < 2) { r = x+m;  g = cc+m; b = 0+m }
            else if (hp < 3) { r = 0+m;  g = cc+m; b = x+m }
            else if (hp < 4) { r = 0+m;  g = x+m;  b = cc+m }
            else if (hp < 5) { r = x+m;  g = 0+m;  b = cc+m }
            else             { r = cc+m; g = 0+m;  b = x+m }
            ri = int(r*255+0.5); gi = int(g*255+0.5); bi = int(b*255+0.5)
            printf "\033[48;2;%d;%d;%dm ", ri, gi, bi
        }
        printf "\033[0m"
    }'
}

# Draw one world's words at their coordinates. Bridged words dim
# with a check; the selected word lights up (reverse) only when
# the pair is resonant -- lighting up IS the metaphor firing.
render_band() {
    local side="$1"
    local n words hues brs sel
    if [[ "${side}" = "A" ]]; then
        words=("${AW[@]}"); hues=("${AH[@]}"); brs=("${AB[@]}"); sel="${A_SEL}"
    else
        words=("${BW[@]}"); hues=("${BH[@]}"); brs=("${BB[@]}"); sel="${B_SEL}"
    fi
    n="${#words[@]}"

    printf "  "
    local pos=0 i=0
    while [[ "${i}" -lt "${n}" ]]; do
        local col
        col=$(col_of "${hues[$i]}")
        if [[ "${col}" -lt "${pos}" ]]; then col="${pos}"; fi
        while [[ "${pos}" -lt "${col}" ]]; do printf " "; pos=$(( pos + 1 )); done

        local wrd="${words[$i]}"
        if [[ "${brs[$i]}" -eq 1 ]]; then
            printf "${_C_DIM}%s+${_C_RESET}" "${wrd}"
            pos=$(( pos + ${#wrd} + 1 ))
        elif [[ "${i}" -eq "${sel}" ]] && [[ "${READY}" -eq 1 ]]; then
            vrgb_hsl_to_rgb "${hues[$i]}" 80 60
            printf "\033[7m\033[38;2;%d;%d;%dm${_C_BOLD}%s\033[0m" "${VRGB_R}" "${VRGB_G}" "${VRGB_B}" "${wrd}"
            pos=$(( pos + ${#wrd} ))
        else
            vrgb_hsl_to_rgb "${hues[$i]}" 70 58
            printf "\033[38;2;%d;%d;%dm%s\033[0m" "${VRGB_R}" "${VRGB_G}" "${VRGB_B}" "${wrd}"
            pos=$(( pos + ${#wrd} ))
        fi
        i=$(( i + 1 ))
    done
    tput el 2>/dev/null || true
    printf "\n"
}

render() {
    printf "\033[H"
    local w="${_C_BOLD}${_C_WHITE}" d="${_C_DIM}" z="${_C_RESET}"
    local g="${_C_GREEN}" y="${_C_YELLOW}" r="${_C_RED}"

    printf "${w}KENNING${z}  ${d}round %d/%d${z}   ${w}%s${z} ${d}(top)${z}  ${d}bridges to${z}  ${w}%s${z} ${d}(bottom)${z}   ${d}found ${g}%d${z}${d}/%d${z}" \
        "${ROUND}" "${ROUNDS_TOTAL}" "${DOM_A}" "${DOM_B}" "${FOUND}" "${KEN_TOTAL}"
    tput el 2>/dev/null || true
    printf "\n\n"

    # Top world.
    render_band "A"

    # Shared spectrum axis.
    printf "  "
    build_bar "${HEAT}"
    printf "\n"

    # Plumb line -- green bridge marker when a resonant pair is under it.
    printf "  "
    local i=0
    while [[ "${i}" -lt "${WIDTH}" ]]; do
        if [[ "${i}" -eq "${CUR_COL}" ]]; then
            if [[ "${READY}" -eq 1 ]]; then printf "${_C_BOLD}${g}|${z}"; else printf "${w}^${z}"; fi
        else
            printf " "
        fi
        i=$(( i + 1 ))
    done
    tput el 2>/dev/null || true
    printf "\n"

    # Bottom world.
    render_band "B"
    printf "\n"

    # Readout: the pair under the line and whether it resonates.
    printf "  ${d}%s:${z}${w}%s${z}  ${d}<=>${z}  ${d}%s:${z}${w}%s${z}   " \
        "${DOM_A}" "${AW[$A_SEL]}" "${DOM_B}" "${BW[$B_SEL]}"
    if [[ "${READY}" -eq 1 ]]; then
        if [[ "${RESO}" -le 2 ]]; then
            printf "${_C_BOLD}${g}RESONANT -- press SPACE to bridge${z}"
        else
            printf "${g}resonant -- SPACE to bridge${z}"
        fi
    elif [[ "${AB[$A_SEL]}" -eq 1 ]] || [[ "${BB[$B_SEL]}" -eq 1 ]]; then
        printf "${d}already bridged${z}"
    else
        printf "${d}no resonance here -- keep sliding${z}"
    fi
    tput el 2>/dev/null || true
    printf "\n\n"

    # Flash line.
    if [[ "${FLASH_T}" -gt 0 ]] && [[ -n "${FLASH}" ]]; then
        printf "  %s%s${z}" "${FLASH_COLOR}" "${FLASH}"
    fi
    tput el 2>/dev/null || true
    printf "\n\n"

    # Heat + score.
    printf "  ${d}Warmth${z} "
    local hb_max=20 hb_fill=$(( HEAT * 20 / 100 )) bi=0
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
    printf "   ${d}Score${z} ${w}%d${z}   ${d}Chain${z} ${w}%d${z}   ${d}High${z} ${w}%d${z}" \
        "${SCORE}" "${CHAIN}" "${ARCADE_HIGH_SCORE}"
    tput el 2>/dev/null || true
    printf "\n\n"

    printf "  ${d}<- ->  slide the plumb line     space  bridge     q  quit${z}"
    tput el 2>/dev/null || true
}

render_end() {
    printf "\033[H"
    local w="${_C_BOLD}${_C_WHITE}" g="${_C_GREEN}" r="${_C_RED}" z="${_C_RESET}" d="${_C_DIM}" c="${_C_CYAN}"
    printf "\n\n\n\n\n"
    if [[ "${WIN}" -eq 1 ]]; then
        _tui_center "${g}${_C_BOLD}ALL BRIDGED${z}"
        printf "\n\n"
        _tui_center "Every metaphor found across ${ROUNDS_TOTAL} worlds."
    else
        _tui_center "${r}${_C_BOLD}THE SPAN WENT COLD${z}"
        printf "\n\n"
        _tui_center "Kennings bridged: ${w}${TOTAL_FOUND}${z}"
    fi
    printf "\n"
    _tui_center "Score: ${w}${SCORE}${z}   Best chain: ${w}${BEST_CHAIN}${z}"
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

    ROUND=1; SCORE=0; CHAIN=0; BEST_CHAIN=0; HEAT=85
    TOTAL_FOUND=0; GAME_OVER=0; WIN=0; CUR_COL=0
    load_round 1

    local _recorded=0

    while true; do
        if [[ "${GAME_OVER}" -eq 1 ]]; then
            if [[ "${_recorded}" -eq 0 ]]; then
                arcade_record_score "${SCORE}"
                if [[ "${WIN}" -eq 1 ]]; then
                    arcade_announce "All bridged. Every metaphor found. Score ${SCORE}."
                else
                    arcade_announce "The span went cold. ${TOTAL_FOUND} kennings bridged. Score ${SCORE}."
                fi
                _recorded=1
            fi
            render_end
            local ch=""; IFS= read -rsn1 ch || true
            if [[ "${ch}" = " " ]]; then break; fi
            continue
        fi

        update_selection
        render

        _tui_game_read 0.12
        local char="${_GAME_CHAR}"

        if [[ -n "${char}" ]]; then
            if [[ "${char}" = $'\x1b' ]]; then
                _tui_game_seq_read; local s1="${_GAME_CHAR}"
                if [[ "${s1}" = "[" ]]; then
                    _tui_game_seq_read; local s2="${_GAME_CHAR}"
                    case "${s2}" in
                        C) if [[ "${CUR_COL}" -lt $(( WIDTH - 1 )) ]]; then CUR_COL=$(( CUR_COL + 1 )); fi ;;
                        D) if [[ "${CUR_COL}" -gt 0 ]]; then CUR_COL=$(( CUR_COL - 1 )); fi ;;
                    esac
                fi
            elif [[ "${char}" = " " ]]; then
                do_pluck
            elif [[ "${char}" = "a" ]] || [[ "${char}" = "A" ]]; then
                if [[ "${CUR_COL}" -gt 0 ]]; then CUR_COL=$(( CUR_COL - 1 )); fi
            elif [[ "${char}" = "d" ]] || [[ "${char}" = "D" ]]; then
                if [[ "${CUR_COL}" -lt $(( WIDTH - 1 )) ]]; then CUR_COL=$(( CUR_COL + 1 )); fi
            elif [[ "${char}" = "q" ]] || [[ "${char}" = "Q" ]]; then
                break
            fi
        fi

        TICK=$(( TICK + 1 ))
        if [[ "${FLASH_T}" -gt 0 ]]; then FLASH_T=$(( FLASH_T - 1 )); fi

        # Gentle cooling -- a good bridge more than pays it back.
        if [[ $(( TICK % 4 )) -eq 0 ]]; then
            HEAT=$(( HEAT - 1 ))
            if [[ "${HEAT}" -le 0 ]]; then HEAT=0; GAME_OVER=1; fi
        fi

        arcade_check_pressure
        arcade_heartbeat "score=${SCORE} round=${ROUND}/${ROUNDS_TOTAL} found=${FOUND}/${KEN_TOTAL} heat=${HEAT}"
    done

    arcade_flush_buffer
    _tui_restore_stty
    tput cnorm 2>/dev/null || true
    tput clear 2>/dev/null || true
}

main "$@"
