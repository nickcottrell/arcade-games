#!/usr/bin/env bash
# ============================================================
#  MADLIBS  --  Classic word game, no model required
# ============================================================
#  Picks a random story, prompts for words, reads the result
#  aloud via cue-vox TTS. Pure terminal fun.
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/lib/announce.sh"

ARCADE_GAME_ID="madlibs"
ROM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# -- load story data --
source "${ROM_DIR}/madlibs-stories.sh"

# -- colors (inline, no tui.sh dependency) --
C_RESET="\033[0m"
C_BOLD="\033[1m"
C_DIM="\033[2m"
C_CYAN="\033[36m"
C_YELLOW="\033[33m"
C_GREEN="\033[32m"
C_MAGENTA="\033[35m"
C_WHITE="\033[37m"

# -- state --
CURRENT=-1
WORDS=()

# --------------------------------------------------------
pick_story() {
    CURRENT=$(( RANDOM % STORY_COUNT ))
    WORDS=()
}

# --------------------------------------------------------
show_header() {
    clear
    printf "${C_BOLD}${C_CYAN}"
    printf "  __  __           _   _     _ _         \n"
    printf " |  \\/  | __ _  __| | | |   (_) |__  ___ \n"
    printf " | |\\/| |/ _\` |/ _\` | | |   | | '_ \\/ __|\n"
    printf " | |  | | (_| | (_| | | |___| | |_) \\__ \\\\\n"
    printf " |_|  |_|\\__,_|\\__,_| |_____|_|_.__/|___/\n"
    printf "${C_RESET}\n"
}

# --------------------------------------------------------
prompt_words() {
    local title="${STORY_TITLE[$CURRENT]}"
    local prompts_str="${STORY_PROMPTS[$CURRENT]}"

    show_header
    printf "  ${C_BOLD}${C_MAGENTA}Story: %s${C_RESET}\n\n" "$title"
    announce "Mad Libs: $title"

    # split prompts on pipe
    IFS='|' read -ra PROMPT_LIST <<< "$prompts_str"
    local count=${#PROMPT_LIST[@]}
    local i=0

    WORDS=()
    for prompt in "${PROMPT_LIST[@]}"; do
        i=$(( i + 1 ))
        printf "  ${C_DIM}(%d/%d)${C_RESET} ${C_YELLOW}%s:${C_RESET} " "$i" "$count" "$prompt"
        local word=""
        read -r word
        if [[ -z "$word" ]]; then word="???"; fi
        WORDS+=("$word")
    done
}

# --------------------------------------------------------
fill_template() {
    local template="${STORY_TEMPLATE[$CURRENT]}"
    local result="$template"
    local i=1
    for word in "${WORDS[@]}"; do
        # literal placeholder replacement: the typed word is treated as data, never
        # as a sed program (a crafted word could otherwise reach GNU sed's exec flag
        # and run shell commands from untrusted PTY input -- RT-01)
        result="${result//"{$i}"/$word}"
        i=$(( i + 1 ))
    done
    echo "$result"
}

# --------------------------------------------------------
show_story() {
    local filled
    filled="$(fill_template)"

    show_header
    local title="${STORY_TITLE[$CURRENT]}"
    printf "  ${C_BOLD}${C_MAGENTA}%s${C_RESET}\n" "$title"
    printf "  ${C_DIM}────────────────────────────────────────${C_RESET}\n\n"

    # word-wrap at ~50 chars with indent
    echo "$filled" | fold -s -w 50 | while IFS= read -r line; do
        printf "  ${C_WHITE}%s${C_RESET}\n" "$line"
    done

    printf "\n  ${C_DIM}────────────────────────────────────────${C_RESET}\n"

    # speak it
    announce "$filled"

    printf "\n  ${C_GREEN}[N]${C_RESET}ext story   ${C_GREEN}[Q]${C_RESET}uit\n\n"
}

# --------------------------------------------------------
wait_for_choice() {
    while true; do
        printf "  ${C_CYAN}> ${C_RESET}"
        local ch=""
        read -r -n 1 ch
        printf "\n"
        case "$ch" in
            n|N) return 0 ;;
            q|Q) return 1 ;;
            *)   printf "  ${C_DIM}Press N or Q${C_RESET}\n" ;;
        esac
    done
}

# --------------------------------------------------------
#  main loop
# --------------------------------------------------------
main() {
    while true; do
        pick_story
        prompt_words
        show_story
        if ! wait_for_choice; then
            printf "\n  ${C_DIM}Thanks for playing!${C_RESET}\n\n"
            announce "Thanks for playing Mad Libs!"
            break
        fi
    done
}

main
