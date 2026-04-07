#!/usr/bin/env bash
# ============================================================
#  ARCADE-TOKENS.SH  --  Scoped Token API for Arcade Games
# ============================================================
#  Wraps cue-mem CLI with game-scoped isolation.
#  Every token gets tagged arcade:<game_id> so games never
#  see personal context tokens (urgency, confidence, etc.).
#
#  Source this file:  source lib/arcade-tokens.sh
#
#  Public API  (arcade_ prefix):
#    arcade_require_server   -- abort if cue-vox not on port 3000
#    arcade_create_token     -- create token with arcade:<game_id> tag
#    arcade_buffer_token     -- buffer token for batch flush
#    arcade_flush_buffer     -- flush buffered tokens in one subshell
#    arcade_init_pressure    -- init pressure gauge and buffer
#    arcade_check_pressure   -- leak bucket, set ARCADE_PRESSURE_ZONE
#    arcade_set_leak_rate    -- tune drain speed per game
#    arcade_heartbeat        -- emit session snapshot for cue-vox awareness
#    arcade_list_tokens      -- list only arcade:<game_id> tokens
#    arcade_heat_token       -- heat a game token
#    arcade_get_high_score   -- read highest score for a game
#    arcade_record_score     -- write a score token with metadata
# ============================================================

# Guard against double-sourcing
if [[ "${_ARCADE_TOKENS_LOADED:-}" = "1" ]]; then
    return 0 2>/dev/null || true
fi

# Resolve paths
_ARCADE_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
_ARCADE_CUE_MEM_CLI="${_ARCADE_SCRIPT_DIR}/cue-mem/cli"
_ARCADE_CUE_VOX_PORT="${CUE_VOX_PORT:-3000}"

# Current game id -- set by the game before calling any functions
ARCADE_GAME_ID=""

# Token count tracker (incremented by arcade_create_token)
ARCADE_TOKEN_COUNT=0

# Cached high score (loaded at startup)
ARCADE_HIGH_SCORE=0

# ============================================================
# COOLING RATE PRESETS
# ============================================================
#  Preset    base_temp  cooling_rate  Lifespan   Use case
#  flash     80         9600          30 sec     Rapid events
#  burst     90         5400          60 sec     Power-ups, kills, combos
#  pulse     85         1700          3 min      Level milestones
#  glow      75         450           10 min     Session tokens
#  anchor    95         0.5           ~8 days    High scores

ARCADE_PRESET_FLASH_TEMP=80;  ARCADE_PRESET_FLASH_RATE=9600
ARCADE_PRESET_BURST_TEMP=90;  ARCADE_PRESET_BURST_RATE=5400
ARCADE_PRESET_PULSE_TEMP=85;  ARCADE_PRESET_PULSE_RATE=1700
ARCADE_PRESET_GLOW_TEMP=75;   ARCADE_PRESET_GLOW_RATE=450
ARCADE_PRESET_ANCHOR_TEMP=95;  ARCADE_PRESET_ANCHOR_RATE=0.5

# ============================================================
# BURST BUFFER
# ============================================================
#  Buffers token data in parallel arrays.  arcade_flush_buffer
#  dispatches all entries in a single background subshell.

_ARCADE_BUF_LABELS=()
_ARCADE_BUF_VALUES=()
_ARCADE_BUF_TAGS=()
_ARCADE_BUF_EXTRA=()
_ARCADE_BUF_COUNT=0
_ARCADE_BUF_FLUSH_AT=8

# ============================================================
# PRESSURE GAUGE  (leaky bucket, pure in-memory)
# ============================================================

ARCADE_PRESSURE_RAW=0
ARCADE_PRESSURE_ZONE="medium"
_ARCADE_PRESSURE_LEAK=3

# ============================================================
# SERVER CHECK
# ============================================================

arcade_require_server() {
    if lsof -ti:"${_ARCADE_CUE_VOX_PORT}" > /dev/null 2>&1; then
        return 0
    fi

    # Server not running -- show friendly TUI message and exit
    local z="${_C_RESET:-}"
    local r="${_C_RED:-}"
    local w="${_C_BOLD:-}${_C_WHITE:-}"
    local d="${_C_DIM:-}"
    local b="${_C_BLUE:-}"

    echo ""
    echo "  ${r}Server Required${z}"
    echo ""
    echo "  ${w}cue-vox${z} must be running on port ${_ARCADE_CUE_VOX_PORT}"
    echo "  for arcade games to create real tokens."
    echo ""
    echo "  ${d}Start it with:${z}"
    echo "    ${b}./maestro.sh start${z}"
    echo ""
    echo "  ${d}Or start everything:${z}"
    echo "    ${b}./maestro.sh up${z}"
    echo ""

    return 1
}

# ============================================================
# TOKEN CREATION
# ============================================================

arcade_create_token() {
    # Usage: arcade_create_token <label> <value> [extra-args...]
    # Automatically adds arcade and arcade:<game_id> tags.
    local label="$1"
    local value="$2"
    shift 2

    if [[ -z "${ARCADE_GAME_ID}" ]]; then
        return 1
    fi

    # Build tag list: always include arcade and arcade:<game_id>
    local extra_tags=""
    local other_args=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --tags)
                shift
                extra_tags="$1"
                ;;
            --tags=*)
                extra_tags="${1#--tags=}"
                ;;
            *)
                other_args+=("$1")
                ;;
        esac
        shift
    done

    local tags="arcade,arcade:${ARCADE_GAME_ID}"
    if [[ -n "${extra_tags}" ]]; then
        tags="${tags},${extra_tags}"
    fi

    # Fire and forget -- run in background so we do not block the game loop
    "${_ARCADE_CUE_MEM_CLI}/createtoken" \
        "arcade_${label}" "${value}" \
        --tags "${tags}" \
        "${other_args[@]}" \
        > /dev/null 2>&1 &

    ARCADE_TOKEN_COUNT=$((ARCADE_TOKEN_COUNT + 1))
}

# ============================================================
# BURST BUFFER OPERATIONS
# ============================================================

arcade_buffer_token() {
    # Usage: arcade_buffer_token <label> <value> [extra-args...]
    # Same API as arcade_create_token but buffers for batch flush.
    local label="$1"
    local value="$2"
    shift 2

    if [[ -z "${ARCADE_GAME_ID}" ]]; then return 1; fi

    local extra_tags=""
    local other_args=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --tags)
                shift
                extra_tags="$1"
                ;;
            --tags=*)
                extra_tags="${1#--tags=}"
                ;;
            *)
                other_args="${other_args} $1"
                ;;
        esac
        shift
    done

    local tags="arcade,arcade:${ARCADE_GAME_ID}"
    if [[ -n "${extra_tags}" ]]; then
        tags="${tags},${extra_tags}"
    fi

    _ARCADE_BUF_LABELS+=("${label}")
    _ARCADE_BUF_VALUES+=("${value}")
    _ARCADE_BUF_TAGS+=("${tags}")
    _ARCADE_BUF_EXTRA+=("${other_args}")
    _ARCADE_BUF_COUNT=$((_ARCADE_BUF_COUNT + 1))

    ARCADE_TOKEN_COUNT=$((ARCADE_TOKEN_COUNT + 1))

    # Pressure: add to bucket
    ARCADE_PRESSURE_RAW=$((ARCADE_PRESSURE_RAW + 100))

    # Auto-flush at threshold
    if [[ "${_ARCADE_BUF_COUNT}" -ge "${_ARCADE_BUF_FLUSH_AT}" ]]; then
        arcade_flush_buffer
    fi
}

arcade_flush_buffer() {
    if [[ "${_ARCADE_BUF_COUNT}" -eq 0 ]]; then return; fi

    # Snapshot to locals
    local labels=("${_ARCADE_BUF_LABELS[@]}")
    local values=("${_ARCADE_BUF_VALUES[@]}")
    local tags=("${_ARCADE_BUF_TAGS[@]}")
    local extras=("${_ARCADE_BUF_EXTRA[@]}")
    local count="${_ARCADE_BUF_COUNT}"

    # Clear buffer immediately
    _ARCADE_BUF_LABELS=()
    _ARCADE_BUF_VALUES=()
    _ARCADE_BUF_TAGS=()
    _ARCADE_BUF_EXTRA=()
    _ARCADE_BUF_COUNT=0

    # Dispatch all in one background subshell (sequential inside)
    (
        local i=0
        while [[ "${i}" -lt "${count}" ]]; do
            "${_ARCADE_CUE_MEM_CLI}/createtoken" \
                "arcade_${labels[$i]}" "${values[$i]}" \
                --tags "${tags[$i]}" \
                ${extras[$i]} \
                > /dev/null 2>&1
            i=$((i + 1))
        done
    ) &
}

# ============================================================
# PRESSURE GAUGE OPERATIONS
# ============================================================

arcade_init_pressure() {
    # Call once at game start.  Zeros counters, sets EXIT trap.
    ARCADE_PRESSURE_RAW=0
    ARCADE_PRESSURE_ZONE="medium"
    _ARCADE_PRESSURE_LEAK=3
    _ARCADE_BUF_LABELS=()
    _ARCADE_BUF_VALUES=()
    _ARCADE_BUF_TAGS=()
    _ARCADE_BUF_EXTRA=()
    _ARCADE_BUF_COUNT=0
    # Safety net: flush on unexpected exit
    trap 'arcade_flush_buffer' EXIT
}

arcade_check_pressure() {
    # Call once per frame.  Leaks the bucket, sets zone.
    ARCADE_PRESSURE_RAW=$((ARCADE_PRESSURE_RAW - _ARCADE_PRESSURE_LEAK))
    if [[ "${ARCADE_PRESSURE_RAW}" -lt 0 ]]; then
        ARCADE_PRESSURE_RAW=0
    fi

    if [[ "${ARCADE_PRESSURE_RAW}" -lt 200 ]]; then
        ARCADE_PRESSURE_ZONE="critical"
    elif [[ "${ARCADE_PRESSURE_RAW}" -lt 500 ]]; then
        ARCADE_PRESSURE_ZONE="low"
    elif [[ "${ARCADE_PRESSURE_RAW}" -lt 1500 ]]; then
        ARCADE_PRESSURE_ZONE="medium"
    else
        ARCADE_PRESSURE_ZONE="high"
    fi
}

arcade_set_leak_rate() {
    _ARCADE_PRESSURE_LEAK="${1:-3}"
}

# ============================================================
# SESSION HEARTBEAT
# ============================================================
#  Emits a flash token with a key=value snapshot of game state.
#  cue-vox can read this to narrate, advise, or react to gameplay.
#
#  Usage: arcade_heartbeat "key1=val1 key2=val2 ..."
#  Call every N ticks (e.g. every 30-50 frames).
#  The token is a flash preset (~30s lifespan) so only the
#  most recent heartbeat is ever warm.
#
#  Convention: games should include at minimum:
#    score, lives, level, and one game-specific metric.
#
#  Example:
#    arcade_heartbeat "score=${SCORE} lives=${LIVES} dim=$((DIM+1)) jewels=${JEWELS_LEFT}/${JEWELS_TOTAL}"

_ARCADE_HEARTBEAT_INTERVAL=40
_ARCADE_HEARTBEAT_COUNTER=0

arcade_set_heartbeat_interval() {
    _ARCADE_HEARTBEAT_INTERVAL="${1:-40}"
}

arcade_heartbeat() {
    # Usage: arcade_heartbeat "state summary string"
    # Only emits if enough ticks have passed since last heartbeat.
    _ARCADE_HEARTBEAT_COUNTER=$((_ARCADE_HEARTBEAT_COUNTER + 1))
    if [[ "${_ARCADE_HEARTBEAT_COUNTER}" -lt "${_ARCADE_HEARTBEAT_INTERVAL}" ]]; then
        return
    fi
    _ARCADE_HEARTBEAT_COUNTER=0

    local snapshot="$1"
    arcade_buffer_token "heartbeat" "${snapshot}" \
        --base-temp "${ARCADE_PRESET_FLASH_TEMP}" --cooling-rate "${ARCADE_PRESET_FLASH_RATE}"
}

# ============================================================
# TOKEN LISTING (filtered to game scope)
# ============================================================

arcade_list_tokens() {
    # Returns JSON array filtered to only arcade:<game_id> tokens.
    # Pipe through python for tag filtering since listtokens has
    # no native tag filter.
    if [[ -z "${ARCADE_GAME_ID}" ]]; then
        echo "[]"
        return
    fi

    local raw
    raw=$("${_ARCADE_CUE_MEM_CLI}/listtokens" --format json 2>/dev/null) || {
        echo "[]"
        return
    }

    # Filter to tokens with arcade:<game_id> in tags
    local game_tag="arcade:${ARCADE_GAME_ID}"
    python3 -c "
import json, sys
tokens = json.loads(sys.stdin.read())
filtered = [t for t in tokens if '${game_tag}' in (t.get('tags') or [])]
print(json.dumps(filtered))
" <<< "${raw}" 2>/dev/null || echo "[]"
}

# ============================================================
# TOKEN HEATING
# ============================================================

arcade_heat_token() {
    # Usage: arcade_heat_token <token_id> [heat_source]
    # Default heat_source: explicit_reference
    local token_id="$1"
    local heat_source="${2:-explicit_reference}"

    "${_ARCADE_CUE_MEM_CLI}/heattoken" \
        "${token_id}" "${heat_source}" \
        > /dev/null 2>&1 &
}

# ============================================================
# HIGH SCORE
# ============================================================

arcade_get_high_score() {
    # Reads the highest arcade_high_score token for this game.
    # Sets ARCADE_HIGH_SCORE global variable.
    if [[ -z "${ARCADE_GAME_ID}" ]]; then
        ARCADE_HIGH_SCORE=0
        return
    fi

    local raw
    raw=$("${_ARCADE_CUE_MEM_CLI}/listtokens" --format json 2>/dev/null) || {
        ARCADE_HIGH_SCORE=0
        return
    }

    local game_tag="arcade:${ARCADE_GAME_ID}"
    ARCADE_HIGH_SCORE=$(python3 -c "
import json, sys
tokens = json.loads(sys.stdin.read())
scores = []
for t in tokens:
    tags = t.get('tags') or []
    if '${game_tag}' in tags and t.get('label') == 'arcade_high_score':
        try:
            scores.append(int(t.get('value', 0)))
        except (ValueError, TypeError):
            pass
print(max(scores) if scores else 0)
" <<< "${raw}" 2>/dev/null) || ARCADE_HIGH_SCORE=0

    if [[ -z "${ARCADE_HIGH_SCORE}" ]]; then
        ARCADE_HIGH_SCORE=0
    fi
}

arcade_record_score() {
    # Usage: arcade_record_score <score> [extra key=val pairs as tags]
    # Creates an arcade_score token.  If score > ARCADE_HIGH_SCORE,
    # also creates/replaces an arcade_high_score pinned token.
    local score="$1"
    shift

    # Flush any buffered tokens before recording score
    arcade_flush_buffer

    local extra_tags=""
    if [[ $# -gt 0 ]]; then
        extra_tags="$*"
        # Convert spaces to commas for tag format
        extra_tags="${extra_tags// /,}"
    fi

    # Always record the score
    arcade_create_token "score" "${score}" \
        --base-temp 60 --cooling-rate 10

    # Check for new high score
    if [[ "${score}" -gt "${ARCADE_HIGH_SCORE}" ]]; then
        ARCADE_HIGH_SCORE="${score}"
        arcade_create_token "high_score" "${score}" \
            --pinned --base-temp 95 --cooling-rate 0.5
    fi
}

# ============================================================
# ANNOUNCEMENTS (delegates to shared lib/announce.sh)
# ============================================================

source "${_ARCADE_SCRIPT_DIR}/lib/announce.sh"

arcade_announce() {
    announce "$1"
}

_ARCADE_TOKENS_LOADED=1
