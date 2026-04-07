#!/usr/bin/env bash
# ============================================================
#  UNFOLD  --  Dimensional box-expansion platformer
# ============================================================
#  You start in a tiny box. Collect all jewels to dissolve
#  the walls and unfold into a larger dimension. Each level
#  grows the room, adds gravity, platforms, enemies, and
#  new mechanics. The box IS the game.
#
#  Controls: Left/Right move, Up jump, Q quit.
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/lib/tui.sh"
source "${SCRIPT_DIR}/lib/vrgb.sh"
source "${SCRIPT_DIR}/lib/arcade-tokens.sh"

ARCADE_GAME_ID="unfold"

# ============================================================
# DIMENSION DEFINITIONS
# ============================================================
# Each dimension defines the box size, mechanics, and hue.
# Hues walk the color wheel: red -> orange -> yellow -> ...

DIM_WIDTHS=(10 16 24 32 40)
DIM_HEIGHTS=(6 10 14 18 22)
DIM_HUES=(0 30 60 120 210)
DIM_JEWELS=(3 6 10 16 24)
DIM_PLAT_COUNT=(0 3 5 8 12)
DIM_ENEMY_COUNT=(0 0 2 4 6)
DIM_GRAVITY=(0 1 1 1 1)
DIM_WRAP=(0 0 0 1 1)
DIM_MAX=5

# ============================================================
# GAME STATE
# ============================================================

# Current dimension (0-indexed)
DIM=0

# Box geometry
BOX_W=0
BOX_H=0
BOX_HUE=0

# Cell data: flat array, index = y * BOX_W + x
# 0=empty  1=wall  2=platform-hot  3=platform-warm  4=platform-cold
# 5=jewel  6=enemy  11=exit
CELL=()

# Player
PX=0
PY=0
PVY=0          # vertical velocity (positive = falling)
ON_GROUND=0

# Jewels
JEWELS_TOTAL=0
JEWELS_LEFT=0

# Enemies: parallel arrays
ENX=()
ENY=()
EN_DIR=()       # 1=right, -1=left
EN_HUE=()
NUM_ENEMIES=0

# Platforms: track positions for decay
PLAT_X=()
PLAT_Y=()
PLAT_LEN=()
PLAT_HEAT=()    # 3=hot, 2=warm, 1=cold, 0=gone
NUM_PLATS=0

# Scoring
SCORE=0
CHAIN=0
BEST_CHAIN=0
LEVEL=0         # total levels completed (across dimensions)
LIVES=3
TICK=0
GAME_OVER=0

# Exit portal state
EXIT_OPEN=0
EXIT_X=0
EXIT_Y=0

# Dissolve animation state
DISSOLVING=0
DISSOLVE_TICK=0
DISSOLVE_MAX=12

# ============================================================
# CELL HELPERS
# ============================================================

cell_get() {
    local x="$1" y="$2"
    echo "${CELL[$((y * BOX_W + x))]}"
}

cell_set() {
    local x="$1" y="$2" val="$3"
    CELL[$((y * BOX_W + x))]="${val}"
}

is_solid() {
    local x="$1" y="$2"
    if [[ "${x}" -lt 0 ]] || [[ "${x}" -ge "${BOX_W}" ]]; then return 0; fi
    if [[ "${y}" -lt 0 ]] || [[ "${y}" -ge "${BOX_H}" ]]; then return 0; fi
    local c="${CELL[$((y * BOX_W + x))]}"
    if [[ "${c}" -eq 1 ]] || [[ "${c}" -eq 2 ]] || [[ "${c}" -eq 3 ]] || [[ "${c}" -eq 4 ]]; then
        return 0
    fi
    return 1
}

is_wall() {
    local x="$1" y="$2"
    if [[ "${x}" -lt 0 ]] || [[ "${x}" -ge "${BOX_W}" ]]; then return 0; fi
    if [[ "${y}" -lt 0 ]] || [[ "${y}" -ge "${BOX_H}" ]]; then return 0; fi
    local c="${CELL[$((y * BOX_W + x))]}"
    [[ "${c}" -eq 1 ]]
}

# ============================================================
# LEVEL GENERATION
# ============================================================

generate_level() {
    EXIT_OPEN=0
    local dim="${DIM}"
    if [[ "${dim}" -ge "${DIM_MAX}" ]]; then
        dim=$((DIM_MAX - 1))
    fi

    BOX_W="${DIM_WIDTHS[$dim]}"
    BOX_H="${DIM_HEIGHTS[$dim]}"
    BOX_HUE="${DIM_HUES[$dim]}"

    local total=$((BOX_W * BOX_H))
    CELL=()
    local i=0
    while [[ "${i}" -lt "${total}" ]]; do
        CELL[$i]=0
        i=$((i + 1))
    done

    # Walls: border
    local x=0 y=0
    y=0
    while [[ "${y}" -lt "${BOX_H}" ]]; do
        x=0
        while [[ "${x}" -lt "${BOX_W}" ]]; do
            if [[ "${y}" -eq 0 ]] || [[ "${y}" -eq $((BOX_H - 1)) ]] || \
               [[ "${x}" -eq 0 ]] || [[ "${x}" -eq $((BOX_W - 1)) ]]; then
                cell_set "${x}" "${y}" 1
            fi
            x=$((x + 1))
        done
        y=$((y + 1))
    done

    # Floor for gravity dimensions: bottom wall already exists
    # Platforms
    NUM_PLATS=0
    PLAT_X=()
    PLAT_Y=()
    PLAT_LEN=()
    PLAT_HEAT=()

    local plat_target="${DIM_PLAT_COUNT[$dim]}"
    local has_gravity="${DIM_GRAVITY[$dim]}"
    local inner_w=$((BOX_W - 2))
    local inner_h=$((BOX_H - 2))

    if [[ "${has_gravity}" -eq 1 ]] && [[ "${plat_target}" -gt 0 ]]; then
        local p=0
        while [[ "${p}" -lt "${plat_target}" ]]; do
            # Distribute platforms vertically across the inner space
            local py=$((2 + (inner_h - 2) * p / plat_target))
            if [[ "${py}" -ge $((BOX_H - 2)) ]]; then py=$((BOX_H - 3)); fi
            local plen=$((3 + RANDOM % (inner_w / 3 + 1)))
            if [[ "${plen}" -gt $((inner_w - 2)) ]]; then plen=$((inner_w - 2)); fi
            local px=$((1 + RANDOM % (inner_w - plen)))

            PLAT_X+=("${px}")
            PLAT_Y+=("${py}")
            PLAT_LEN+=("${plen}")
            PLAT_HEAT+=(3)

            local pi=0
            while [[ "${pi}" -lt "${plen}" ]]; do
                cell_set $((px + pi)) "${py}" 2
                pi=$((pi + 1))
            done

            NUM_PLATS=$((NUM_PLATS + 1))
            p=$((p + 1))
        done
    fi

    # Place jewels on walkable surfaces
    JEWELS_TOTAL="${DIM_JEWELS[$dim]}"
    JEWELS_LEFT="${JEWELS_TOTAL}"
    local placed=0
    local attempts=0
    while [[ "${placed}" -lt "${JEWELS_TOTAL}" ]] && [[ "${attempts}" -lt 200 ]]; do
        local jx=$((1 + RANDOM % (BOX_W - 2)))
        local jy=$((1 + RANDOM % (BOX_H - 2)))
        local idx=$((jy * BOX_W + jx))

        if [[ "${CELL[$idx]}" -eq 0 ]]; then
            if [[ "${has_gravity}" -eq 0 ]]; then
                # No gravity: jewels can be anywhere open
                CELL[$idx]=5
                placed=$((placed + 1))
            else
                # With gravity: jewel must be above a solid surface
                # and within jump reach (3 cells) of the ground floor
                local below=$((jy + 1))
                if [[ "${below}" -lt "${BOX_H}" ]] && is_solid "${jx}" "${below}"; then
                    # Max reachable height: ground is at BOX_H-2, jump reaches 3 up
                    if [[ "${jy}" -ge $((BOX_H - 5)) ]]; then
                        CELL[$idx]=5
                        placed=$((placed + 1))
                    fi
                fi
            fi
        fi
        attempts=$((attempts + 1))
    done
    JEWELS_TOTAL="${placed}"
    JEWELS_LEFT="${placed}"

    # Enemies
    NUM_ENEMIES=0
    ENX=()
    ENY=()
    EN_DIR=()
    EN_HUE=()

    local enemy_target="${DIM_ENEMY_COUNT[$dim]}"
    local e=0
    while [[ "${e}" -lt "${enemy_target}" ]]; do
        attempts=0
        while [[ "${attempts}" -lt 50 ]]; do
            local ex=$((2 + RANDOM % (BOX_W - 4)))
            local ey=$((1 + RANDOM % (BOX_H - 2)))

            if [[ "${CELL[$((ey * BOX_W + ex))]}" -eq 0 ]]; then
                if [[ "${has_gravity}" -eq 0 ]] || \
                   ([[ $((ey + 1)) -lt "${BOX_H}" ]] && is_solid "${ex}" $((ey + 1))); then
                    ENX+=("${ex}")
                    ENY+=("${ey}")
                    local edir=1
                    if [[ $((RANDOM % 2)) -eq 0 ]]; then edir=-1; fi
                    EN_DIR+=("${edir}")
                    # Enemy hue: complementary to box hue
                    EN_HUE+=("$(( (BOX_HUE + 180) % 360 ))")
                    NUM_ENEMIES=$((NUM_ENEMIES + 1))
                    break
                fi
            fi
            attempts=$((attempts + 1))
        done
        e=$((e + 1))
    done

    # Player start: bottom-center on ground
    PX=$((BOX_W / 2))
    if [[ "${has_gravity}" -eq 1 ]]; then
        PY=$((BOX_H - 2))
        # Walk left until we find ground
        while [[ "${PY}" -gt 1 ]]; do
            if is_solid "${PX}" $((PY + 1)) 2>/dev/null; then
                break
            fi
            PY=$((PY - 1))
        done
    else
        PY=$((BOX_H / 2))
    fi
    PVY=0
    ON_GROUND=1
    TICK=0
}

# ============================================================
# PHYSICS
# ============================================================

apply_gravity() {
    local dim="${DIM}"
    if [[ "${dim}" -ge "${DIM_MAX}" ]]; then dim=$((DIM_MAX - 1)); fi
    if [[ "${DIM_GRAVITY[$dim]}" -eq 0 ]]; then return; fi

    # Check ground beneath player
    ON_GROUND=0
    if is_solid "${PX}" $((PY + 1)) 2>/dev/null; then
        if [[ "${PVY}" -ge 0 ]]; then
            ON_GROUND=1
            PVY=0
        fi
    fi

    if [[ "${ON_GROUND}" -eq 0 ]]; then
        # Apply gravity: accelerate downward
        PVY=$((PVY + 1))
        if [[ "${PVY}" -gt 3 ]]; then PVY=3; fi

        local new_y=$((PY + PVY))
        # Check collision while falling
        local step=1
        if [[ "${PVY}" -lt 0 ]]; then step=-1; fi
        local cy="${PY}"
        while [[ "${cy}" -ne "${new_y}" ]]; do
            cy=$((cy + step))
            if [[ "${cy}" -lt 1 ]]; then
                cy=1; PVY=0; break
            fi
            if [[ "${cy}" -ge $((BOX_H - 1)) ]]; then
                cy=$((BOX_H - 2)); PVY=0; ON_GROUND=1; break
            fi
            if is_solid "${PX}" "${cy}" 2>/dev/null; then
                if [[ "${step}" -gt 0 ]]; then
                    # Falling -- land on top
                    cy=$((cy - 1))
                    ON_GROUND=1
                else
                    # Rising -- hit ceiling
                    cy=$((cy + 1))
                fi
                PVY=0
                break
            fi
        done
        PY="${cy}"
    fi
}

try_jump() {
    local dim="${DIM}"
    if [[ "${dim}" -ge "${DIM_MAX}" ]]; then dim=$((DIM_MAX - 1)); fi
    if [[ "${DIM_GRAVITY[$dim]}" -eq 0 ]]; then
        # No gravity: up just moves up
        move_player 0 -1
        return
    fi

    if [[ "${ON_GROUND}" -eq 1 ]]; then
        PVY=-3
        ON_GROUND=0
    fi
}

# ============================================================
# MOVEMENT
# ============================================================

move_player() {
    local dx="$1" dy="$2"
    local dim="${DIM}"
    if [[ "${dim}" -ge "${DIM_MAX}" ]]; then dim=$((DIM_MAX - 1)); fi

    local nx=$((PX + dx))
    local ny=$((PY + dy))

    # Wrapping
    if [[ "${DIM_WRAP[$dim]}" -eq 1 ]]; then
        if [[ "${nx}" -lt 1 ]]; then nx=$((BOX_W - 2)); fi
        if [[ "${nx}" -ge $((BOX_W - 1)) ]]; then nx=1; fi
    fi

    # Boundary check
    if [[ "${nx}" -lt 1 ]] || [[ "${nx}" -ge $((BOX_W - 1)) ]]; then return; fi
    if [[ "${ny}" -lt 1 ]] || [[ "${ny}" -ge $((BOX_H - 1)) ]]; then return; fi

    # Wall check
    if is_wall "${nx}" "${ny}"; then return; fi

    # Platform check (can walk on top, not through)
    local nc="${CELL[$((ny * BOX_W + nx))]}"
    if [[ "${nc}" -ge 2 ]] && [[ "${nc}" -le 4 ]]; then
        # Solid platform -- only block if moving sideways into it
        if [[ "${dy}" -eq 0 ]]; then return; fi
    fi

    PX="${nx}"
    PY="${ny}"
    pickup_jewel
    check_exit
    check_enemy_collision
}

pickup_jewel() {
    local idx=$((PY * BOX_W + PX))
    if [[ "${CELL[$idx]}" -ne 5 ]]; then return; fi

    CELL[$idx]=0
    JEWELS_LEFT=$((JEWELS_LEFT - 1))
    CHAIN=$((CHAIN + 1))
    if [[ "${CHAIN}" -gt "${BEST_CHAIN}" ]]; then BEST_CHAIN="${CHAIN}"; fi

    local mult=$((1 + CHAIN / 3))
    SCORE=$((SCORE + 50 * mult * (DIM + 1)))

    arcade_buffer_token "jewel" "${DIM}" \
        --base-temp "${ARCADE_PRESET_FLASH_TEMP}" --cooling-rate "${ARCADE_PRESET_FLASH_RATE}"

    if [[ "${JEWELS_LEFT}" -le 0 ]] && [[ "${EXIT_OPEN}" -eq 0 ]]; then
        spawn_exit
    fi
}

check_enemy_collision() {
    local i=0
    while [[ "${i}" -lt "${NUM_ENEMIES}" ]]; do
        if [[ "${ENX[$i]}" -eq "${PX}" ]] && [[ "${ENY[$i]}" -eq "${PY}" ]]; then
            player_hit
            return
        fi
        i=$((i + 1))
    done
}

player_hit() {
    CHAIN=0
    LIVES=$((LIVES - 1))
    PX=$((BOX_W / 2))
    PY=$((BOX_H - 2))
    PVY=0

    arcade_buffer_token "hit" "${DIM}" \
        --base-temp "${ARCADE_PRESET_FLASH_TEMP}" --cooling-rate "${ARCADE_PRESET_FLASH_RATE}"

    if [[ "${LIVES}" -le 0 ]]; then
        GAME_OVER=1
    fi
}

spawn_exit() {
    # Place exit portal on a reachable spot
    local dim="${DIM}"
    if [[ "${dim}" -ge "${DIM_MAX}" ]]; then dim=$((DIM_MAX - 1)); fi
    local has_gravity="${DIM_GRAVITY[$dim]}"
    local attempts=0

    while [[ "${attempts}" -lt 200 ]]; do
        local ex=$((1 + RANDOM % (BOX_W - 2)))
        local ey=$((1 + RANDOM % (BOX_H - 2)))
        local idx=$((ey * BOX_W + ex))

        # Must be empty, not on player
        if [[ "${CELL[$idx]}" -eq 0 ]] && ! ([[ "${ex}" -eq "${PX}" ]] && [[ "${ey}" -eq "${PY}" ]]); then
            if [[ "${has_gravity}" -eq 0 ]]; then
                CELL[$idx]=11
                EXIT_X="${ex}"; EXIT_Y="${ey}"; EXIT_OPEN=1
                arcade_announce "Exit open!"
                return
            else
                # Must be above solid, within jump reach
                local below=$((ey + 1))
                if [[ "${below}" -lt "${BOX_H}" ]] && is_solid "${ex}" "${below}" 2>/dev/null; then
                    if [[ "${ey}" -ge $((BOX_H - 5)) ]]; then
                        CELL[$idx]=11
                        EXIT_X="${ex}"; EXIT_Y="${ey}"; EXIT_OPEN=1
                        arcade_announce "Exit open!"
                        return
                    fi
                fi
            fi
        fi
        attempts=$((attempts + 1))
    done

    # Fallback: place near player
    local fx=$((PX + 2))
    if [[ "${fx}" -ge $((BOX_W - 1)) ]]; then fx=$((PX - 2)); fi
    local fy="${PY}"
    CELL[$((fy * BOX_W + fx))]=11
    EXIT_X="${fx}"; EXIT_Y="${fy}"; EXIT_OPEN=1
    arcade_announce "Exit open!"
}

check_exit() {
    if [[ "${EXIT_OPEN}" -eq 1 ]] && [[ "${PX}" -eq "${EXIT_X}" ]] && [[ "${PY}" -eq "${EXIT_Y}" ]]; then
        EXIT_OPEN=0
        DISSOLVING=1
        DISSOLVE_TICK=0
    fi
}

# ============================================================
# STOMP CHECK (land on enemy from above)
# ============================================================

check_stomp() {
    local i=0
    while [[ "${i}" -lt "${NUM_ENEMIES}" ]]; do
        # Player directly above enemy, falling
        if [[ "${ENX[$i]}" -eq "${PX}" ]] && [[ "${ENY[$i]}" -eq $((PY + 1)) ]] && \
           [[ "${PVY}" -gt 0 ]]; then
            # Stomp! Check hue proximity for bonus
            vrgb_color_distance "${BOX_HUE}" 70 50 "${EN_HUE[$i]}" 70 50
            local cdist="${VRGB_DIST}"
            local pts=100
            if [[ "${cdist}" -lt 15 ]]; then pts=300; fi

            CHAIN=$((CHAIN + 1))
            if [[ "${CHAIN}" -gt "${BEST_CHAIN}" ]]; then BEST_CHAIN="${CHAIN}"; fi
            local mult=$((1 + CHAIN / 3))
            SCORE=$((SCORE + pts * mult))

            # Remove enemy (swap with last)
            local last=$((NUM_ENEMIES - 1))
            if [[ "${i}" -lt "${last}" ]]; then
                ENX[$i]="${ENX[$last]}"
                ENY[$i]="${ENY[$last]}"
                EN_DIR[$i]="${EN_DIR[$last]}"
                EN_HUE[$i]="${EN_HUE[$last]}"
            fi
            unset "ENX[${last}]" "ENY[${last}]" "EN_DIR[${last}]" "EN_HUE[${last}]"
            ENX=("${ENX[@]+"${ENX[@]}"}")
            ENY=("${ENY[@]+"${ENY[@]}"}")
            EN_DIR=("${EN_DIR[@]+"${EN_DIR[@]}"}")
            EN_HUE=("${EN_HUE[@]+"${EN_HUE[@]}"}")
            NUM_ENEMIES=$((NUM_ENEMIES - 1))

            # Bounce up
            PVY=-2

            arcade_buffer_token "stomp" "${cdist}" \
                --base-temp "${ARCADE_PRESET_BURST_TEMP}" --cooling-rate "${ARCADE_PRESET_BURST_RATE}"
            return
        fi
        i=$((i + 1))
    done
}

# ============================================================
# ENEMY AI
# ============================================================

move_enemies() {
    local i=0
    while [[ "${i}" -lt "${NUM_ENEMIES}" ]]; do
        local ex="${ENX[$i]}"
        local ey="${ENY[$i]}"
        local edir="${EN_DIR[$i]}"

        local nx=$((ex + edir))

        # Turn around at walls or edges
        local should_turn=0
        if [[ "${nx}" -lt 1 ]] || [[ "${nx}" -ge $((BOX_W - 1)) ]]; then
            should_turn=1
        elif is_wall "${nx}" "${ey}"; then
            should_turn=1
        fi

        # Turn around at platform edges (dont walk off)
        local dim="${DIM}"
        if [[ "${dim}" -ge "${DIM_MAX}" ]]; then dim=$((DIM_MAX - 1)); fi
        if [[ "${DIM_GRAVITY[$dim]}" -eq 1 ]] && [[ "${should_turn}" -eq 0 ]]; then
            if ! is_solid "${nx}" $((ey + 1)) 2>/dev/null; then
                should_turn=1
            fi
        fi

        if [[ "${should_turn}" -eq 1 ]]; then
            EN_DIR[$i]=$((-edir))
            nx=$((ex - edir))
            # Validate reversed direction too
            if [[ "${nx}" -lt 1 ]] || [[ "${nx}" -ge $((BOX_W - 1)) ]]; then
                nx="${ex}"
            fi
            if is_wall "${nx}" "${ey}"; then
                nx="${ex}"
            fi
        fi

        ENX[$i]="${nx}"

        # Check collision with player
        if [[ "${nx}" -eq "${PX}" ]] && [[ "${ey}" -eq "${PY}" ]]; then
            player_hit
        fi

        i=$((i + 1))
    done
}

# ============================================================
# PLATFORM DECAY
# ============================================================

decay_platforms() {
    local p=0
    while [[ "${p}" -lt "${NUM_PLATS}" ]]; do
        local heat="${PLAT_HEAT[$p]}"
        if [[ "${heat}" -gt 0 ]]; then
            heat=$((heat - 1))
            PLAT_HEAT[$p]="${heat}"

            local px="${PLAT_X[$p]}"
            local py="${PLAT_Y[$p]}"
            local plen="${PLAT_LEN[$p]}"

            local pi=0
            while [[ "${pi}" -lt "${plen}" ]]; do
                local cx=$((px + pi))
                if [[ "${heat}" -eq 0 ]]; then
                    cell_set "${cx}" "${py}" 0
                else
                    cell_set "${cx}" "${py}" $((5 - heat))
                fi
                pi=$((pi + 1))
            done
        fi
        p=$((p + 1))
    done
}

# ============================================================
# DISSOLVE ANIMATION
# ============================================================

update_dissolve() {
    if [[ "${DISSOLVING}" -eq 0 ]]; then return; fi

    DISSOLVE_TICK=$((DISSOLVE_TICK + 1))

    # Phase 1: walls decay (ticks 1-4)
    if [[ "${DISSOLVE_TICK}" -le 4 ]]; then
        # Replace wall cells with decay stage based on tick
        local x=0 y=0
        y=0
        while [[ "${y}" -lt "${BOX_H}" ]]; do
            x=0
            while [[ "${x}" -lt "${BOX_W}" ]]; do
                if [[ "${CELL[$((y * BOX_W + x))]}" -eq 1 ]] || \
                   [[ "${CELL[$((y * BOX_W + x))]}" -ge 7 ]]; then
                    # 7=hot-wall, 8=warm-wall, 9=cold-wall
                    CELL[$((y * BOX_W + x))]=$((6 + DISSOLVE_TICK))
                fi
                x=$((x + 1))
            done
            y=$((y + 1))
        done
    fi

    # Phase 2: transition to next dimension
    if [[ "${DISSOLVE_TICK}" -ge "${DISSOLVE_MAX}" ]]; then
        DISSOLVING=0
        DISSOLVE_TICK=0
        LEVEL=$((LEVEL + 1))
        DIM=$((DIM + 1))

        arcade_announce "Dimension $((DIM + 1)). Score: ${SCORE}."

        arcade_create_token "unfold" "${DIM}" \
            --base-temp "${ARCADE_PRESET_PULSE_TEMP}" --cooling-rate "${ARCADE_PRESET_PULSE_RATE}"

        generate_level
    fi
}

# ============================================================
# RENDER
# ============================================================

render() {
    printf "\033[H"

    local w="${_C_BOLD}${_C_WHITE}" d="${_C_DIM}" z="${_C_RESET}"
    local r="${_C_RED}" g="${_C_GREEN}"

    # Title
    vrgb_hue_name "${BOX_HUE}"
    printf "${w}UNFOLD${z}  ${d}Dim %d${z}  " "$((DIM + 1))"
    vrgb_hsl_to_rgb "${BOX_HUE}" 70 50
    vrgb_swatch "${VRGB_R}" "${VRGB_G}" "${VRGB_B}" 2
    printf " ${d}%s${z}\n\n" "${VRGB_HUE_NAME}"

    # Pre-compute box wall color
    local wall_r=0 wall_g=0 wall_b=0
    vrgb_hsl_to_rgb "${BOX_HUE}" 70 50
    wall_r="${VRGB_R}"; wall_g="${VRGB_G}"; wall_b="${VRGB_B}"

    # Complementary hue for jewels
    local jewel_hue=$(( (BOX_HUE + 180) % 360 ))
    local jewel_r=0 jewel_g=0 jewel_b=0
    vrgb_hsl_to_rgb "${jewel_hue}" 80 60
    jewel_r="${VRGB_R}"; jewel_g="${VRGB_G}"; jewel_b="${VRGB_B}"

    # Center the box horizontally
    local pad=$(( (_TUI_COLS - BOX_W) / 2 ))
    if [[ "${pad}" -lt 0 ]]; then pad=0; fi
    local pad_str=""
    local pi=0
    while [[ "${pi}" -lt "${pad}" ]]; do
        pad_str="${pad_str} "
        pi=$((pi + 1))
    done

    local y=0
    while [[ "${y}" -lt "${BOX_H}" ]]; do
        printf "%s" "${pad_str}"
        local x=0
        while [[ "${x}" -lt "${BOX_W}" ]]; do
            local idx=$((y * BOX_W + x))

            # Player
            if [[ "${x}" -eq "${PX}" ]] && [[ "${y}" -eq "${PY}" ]] && [[ "${DISSOLVING}" -eq 0 ]]; then
                printf "\033[38;2;%d;%d;%dm${_C_BOLD}@\033[0m" "${wall_r}" "${wall_g}" "${wall_b}"
                x=$((x + 1))
                continue
            fi

            # Enemy
            local found_enemy=0
            if [[ "${DISSOLVING}" -eq 0 ]]; then
                local ei=0
                while [[ "${ei}" -lt "${NUM_ENEMIES}" ]]; do
                    if [[ "${ENX[$ei]}" -eq "${x}" ]] && [[ "${ENY[$ei]}" -eq "${y}" ]]; then
                        found_enemy=1
                        vrgb_hsl_to_rgb "${EN_HUE[$ei]}" 70 50
                        printf "\033[38;2;%d;%d;%dm${_C_BOLD}W\033[0m" "${VRGB_R}" "${VRGB_G}" "${VRGB_B}"
                        break
                    fi
                    ei=$((ei + 1))
                done
            fi

            if [[ "${found_enemy}" -eq 1 ]]; then
                x=$((x + 1))
                continue
            fi

            local c="${CELL[$idx]}"
            case "${c}" in
                0) printf " " ;;
                1) # Wall
                    printf "\033[38;2;%d;%d;%dm${_BAR_FULL}\033[0m" "${wall_r}" "${wall_g}" "${wall_b}" ;;
                2) # Platform hot
                    printf "\033[38;2;%d;%d;%dm${_BAR_FULL}\033[0m" "${wall_r}" "${wall_g}" "${wall_b}" ;;
                3) # Platform warm
                    printf "\033[38;2;%d;%d;%dm${_BAR_SHADE3}\033[0m" "${wall_r}" "${wall_g}" "${wall_b}" ;;
                4) # Platform cold
                    printf "\033[38;2;%d;%d;%dm${_BAR_SHADE1}\033[0m" "${wall_r}" "${wall_g}" "${wall_b}" ;;
                5) # Jewel (diamond glyph)
                    if [[ $((TICK % 4)) -lt 2 ]]; then
                        printf "\033[38;2;%d;%d;%dm\033[1m*\033[0m" "${jewel_r}" "${jewel_g}" "${jewel_b}"
                    else
                        printf "\033[38;2;255;255;255m\033[1m*\033[0m"
                    fi ;;
                7) # Dissolving wall: hot
                    vrgb_hsl_to_rgb "${BOX_HUE}" 70 45
                    printf "\033[38;2;%d;%d;%dm${_BAR_SHADE3}\033[0m" "${VRGB_R}" "${VRGB_G}" "${VRGB_B}" ;;
                8) # Dissolving wall: warm
                    vrgb_hsl_to_rgb "${BOX_HUE}" 50 35
                    printf "\033[38;2;%d;%d;%dm${_BAR_SHADE2}\033[0m" "${VRGB_R}" "${VRGB_G}" "${VRGB_B}" ;;
                9) # Dissolving wall: cold
                    vrgb_hsl_to_rgb "${BOX_HUE}" 30 25
                    printf "\033[38;2;%d;%d;%dm${_BAR_SHADE1}\033[0m" "${VRGB_R}" "${VRGB_G}" "${VRGB_B}" ;;
                10) printf " " ;;  # Dissolved
                11) # Exit portal -- pulsing
                    if [[ $((TICK % 6)) -lt 3 ]]; then
                        printf "\033[38;2;255;220;50m\033[1mE\033[0m"
                    else
                        printf "\033[38;2;255;255;200m\033[1mE\033[0m"
                    fi ;;
                *) printf " " ;;
            esac
            x=$((x + 1))
        done
        tput el 2>/dev/null || true
        printf "\n"
        y=$((y + 1))
    done

    # HUD below box
    printf "\n"

    # Jewel counter
    printf "${pad_str}"
    if [[ "${EXIT_OPEN}" -eq 1 ]]; then
        printf "\033[38;2;255;220;50m\033[1mFIND THE EXIT\033[0m"
    else
        printf "${d}Jewels${z} "
        local ji=0
        while [[ "${ji}" -lt "${JEWELS_TOTAL}" ]]; do
            if [[ "${ji}" -lt $((JEWELS_TOTAL - JEWELS_LEFT)) ]]; then
                printf "\033[38;2;%d;%d;%dm${_BAR_FULL}\033[0m" "${jewel_r}" "${jewel_g}" "${jewel_b}"
            else
                printf "${d}${_BAR_EMPTY}${z}"
            fi
            ji=$((ji + 1))
        done
    fi
    tput el 2>/dev/null || true
    printf "\n"

    # Score + lives
    printf "${pad_str}"
    printf "Score ${w}%d${z}  Chain ${w}%d${z}" "${SCORE}" "${CHAIN}"
    printf "  Lives "
    local li=0
    while [[ "${li}" -lt "${LIVES}" ]]; do
        printf "${r}${_BAR_FULL}${z}"
        li=$((li + 1))
    done
    tput el 2>/dev/null || true
    printf "\n"

    # Tokens + pressure
    printf "${pad_str}"
    printf "${d}Tokens: ${_C_CYAN}%d${z}  ${d}High: ${w}%d${z}" "${ARCADE_TOKEN_COUNT}" "${ARCADE_HIGH_SCORE}"
    tput el 2>/dev/null || true
    printf "\n"

    printf "${pad_str}"
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

    # Controls hint
    printf "${pad_str}"
    local dim="${DIM}"
    if [[ "${dim}" -ge "${DIM_MAX}" ]]; then dim=$((DIM_MAX - 1)); fi
    if [[ "${DIM_GRAVITY[$dim]}" -eq 1 ]]; then
        printf "${d}L/R move  Up jump  Q quit${z}"
    else
        printf "${d}Arrows move  Q quit${z}"
    fi
    tput el 2>/dev/null || true
}

render_game_over() {
    printf "\033[H"
    local w="${_C_BOLD}${_C_WHITE}" r="${_C_RED}" z="${_C_RESET}" d="${_C_DIM}"
    local c="${_C_CYAN}"

    printf "\n\n\n\n\n\n\n\n"
    _tui_center "${r}${_C_BOLD}COLLAPSED${z}"
    printf "\n\n"
    _tui_center "Score: ${w}${SCORE}${z}   Dimension: ${w}$((DIM + 1))${z}   Best Chain: ${w}${BEST_CHAIN}${z}"
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

    _TUI_SAVED_STTY=$(stty -g 2>/dev/null || echo "")
    stty -icanon -echo 2>/dev/null || true
    trap 'arcade_flush_buffer; _tui_restore_stty; tput cnorm 2>/dev/null' EXIT

    SCORE=0
    CHAIN=0
    BEST_CHAIN=0
    LIVES=3
    LEVEL=0
    DIM=0
    GAME_OVER=0

    generate_level

    local enemy_rate=4
    local decay_rate=40
    local _score_recorded=0

    while true; do
        if [[ "${GAME_OVER}" -eq 1 ]]; then
            if [[ "${_score_recorded}" -eq 0 ]]; then
                arcade_record_score "${SCORE}"
                arcade_announce "Game over. Score: ${SCORE}. Dimension $((DIM + 1)). Best chain: ${BEST_CHAIN}."
                _score_recorded=1
            fi

            render_game_over

            local ch=""
            IFS= read -rsn1 ch || true
            if [[ "${ch}" = " " ]]; then
                break
            fi
            continue
        fi

        render

        _tui_game_read 0.12
        local char="${_GAME_CHAR}"

        if [[ "${DISSOLVING}" -eq 0 ]] && [[ -n "${char}" ]]; then
            if [[ "${char}" = $'\x1b' ]]; then
                _tui_game_seq_read; local s1="${_GAME_CHAR}"
                if [[ "${s1}" = "[" ]] || [[ "${s1}" = "O" ]]; then
                    _tui_game_seq_read; local s2="${_GAME_CHAR}"
                    local dim="${DIM}"
                    if [[ "${dim}" -ge "${DIM_MAX}" ]]; then dim=$((DIM_MAX - 1)); fi
                    case "${s2}" in
                        A) try_jump ;;
                        B) if [[ "${DIM_GRAVITY[$dim]}" -eq 0 ]]; then
                               move_player 0 1
                           fi ;;
                        C) move_player 1 0 ;;
                        D) move_player -1 0 ;;
                    esac
                fi
            elif [[ "${char}" = " " ]]; then
                try_jump
            elif [[ "${char}" = "w" ]] || [[ "${char}" = "W" ]]; then
                try_jump
            elif [[ "${char}" = "a" ]] || [[ "${char}" = "A" ]]; then
                move_player -1 0
            elif [[ "${char}" = "s" ]] || [[ "${char}" = "S" ]]; then
                local dim="${DIM}"
                if [[ "${dim}" -ge "${DIM_MAX}" ]]; then dim=$((DIM_MAX - 1)); fi
                if [[ "${DIM_GRAVITY[$dim]}" -eq 0 ]]; then move_player 0 1; fi
            elif [[ "${char}" = "d" ]] || [[ "${char}" = "D" ]]; then
                move_player 1 0
            elif [[ "${char}" = "q" ]] || [[ "${char}" = "Q" ]]; then
                break
            fi
        fi

        TICK=$((TICK + 1))

        arcade_check_pressure

        # Heartbeat: let cue-vox see game state
        arcade_heartbeat "score=${SCORE} lives=${LIVES} dim=$((DIM + 1)) jewels=${JEWELS_LEFT}/${JEWELS_TOTAL} chain=${CHAIN} pressure=${ARCADE_PRESSURE_ZONE}"

        # Dissolve animation
        if [[ "${DISSOLVING}" -eq 1 ]]; then
            update_dissolve
            continue
        fi

        # Physics
        local dim="${DIM}"
        if [[ "${dim}" -ge "${DIM_MAX}" ]]; then dim=$((DIM_MAX - 1)); fi
        if [[ "${DIM_GRAVITY[$dim]}" -eq 1 ]]; then
            if [[ $((TICK % 2)) -eq 0 ]]; then
                apply_gravity
                check_stomp
            fi
        fi

        # Enemies
        enemy_rate=$((5 - DIM))
        if [[ "${enemy_rate}" -lt 2 ]]; then enemy_rate=2; fi
        if [[ $((TICK % enemy_rate)) -eq 0 ]]; then
            move_enemies
        fi

        # Platform decay (only in dimensions with platforms)
        if [[ "${NUM_PLATS}" -gt 0 ]]; then
            decay_rate=$((50 - DIM * 8))
            if [[ "${decay_rate}" -lt 15 ]]; then decay_rate=15; fi
            # Pressure modulation
            if [[ "${ARCADE_PRESSURE_ZONE}" = "critical" ]]; then
                decay_rate=$((decay_rate - 5))
                if [[ "${decay_rate}" -lt 8 ]]; then decay_rate=8; fi
            fi
            if [[ $((TICK % decay_rate)) -eq 0 ]]; then
                decay_platforms
            fi
        fi
    done

    arcade_flush_buffer
    _tui_restore_stty
    tput cnorm 2>/dev/null || true
    tput clear 2>/dev/null || true
}

main "$@"
