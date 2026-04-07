#!/usr/bin/env bash
# ============================================================
#  ANNOUNCE.SH  --  Direct TTS via cue-vox /api/speak
# ============================================================
#  Speaks text through cue-vox without going through Claude.
#  Works from any context: game scripts, cue-sheets, CLI, cron.
#
#  Source this file:  source lib/announce.sh
#
#  Usage:
#    announce "Game over. Final score: 1234."
#    announce "Pull pipeline complete. 3 new items."
#
#  Requires cue-vox running on CUE_VOX_PORT (default 3000).
#  Fire-and-forget -- runs in background, never blocks caller.
# ============================================================

if [[ "${_ANNOUNCE_LOADED:-}" = "1" ]]; then
    return 0 2>/dev/null || true
fi

_ANNOUNCE_PORT="${CUE_VOX_PORT:-3000}"

announce() {
    local text="$1"
    if [[ -z "$text" ]]; then return; fi
    curl -s -X POST "http://localhost:${_ANNOUNCE_PORT}/api/speak" \
        --data-urlencode "text=$text" \
        > /dev/null 2>&1 &
}

_ANNOUNCE_LOADED=1
