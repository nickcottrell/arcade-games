#!/usr/bin/env bash
# ============================================================
#  TUI.SH  --  Pure Bash TUI Component Library
# ============================================================
#  BASIC-era screen dialogs, no external deps.
#  No dialog. No whiptail. No ncurses. Just bash.
#
#  Source this file:  source lib/tui.sh
#
#  Public API  (tui_ prefix):
#    tui_banner, tui_panel, tui_progress_start,
#    tui_progress_update, tui_progress_done,
#    tui_confirm, tui_challenge, tui_input, tui_menu,
#    tui_checklist, tui_tree, tui_script
#
#  Internal   (_tui_ prefix):
#    _tui_init, _tui_cleanup, _tui_measure, _tui_read_key
# ============================================================

# Guard against double-sourcing
if [[ "${_TUI_INITIALIZED:-}" = "1" ]]; then
    return 0 2>/dev/null || true
fi

# ============================================================
# INTERNAL STATE
# ============================================================

_TUI_COLS=80
_TUI_ROWS=24
_TUI_COLORS=0
_TUI_INITIALIZED=0
_TUI_SAVED_STTY=""

# Return values (public)
TUI_RESULT=""
TUI_INDEX=-1
TUI_INDICES=()
TUI_PATH=""

# ============================================================
# COLOR CONSTANTS (tput with fallbacks)
# ============================================================

_tui_setup_colors() {
    _TUI_COLORS=$(tput colors 2>/dev/null || echo 0)

    if [[ "${_TUI_COLORS}" -ge 8 ]]; then
        _C_RESET=$(tput sgr0)
        _C_BOLD=$(tput bold)
        _C_DIM=$(tput dim 2>/dev/null || echo "")
        _C_REV=$(tput rev)
        _C_RED=$(tput setaf 1)
        _C_GREEN=$(tput setaf 2)
        _C_YELLOW=$(tput setaf 3)
        _C_BLUE=$(tput setaf 4)
        _C_MAGENTA=$(tput setaf 5)
        _C_CYAN=$(tput setaf 6)
        _C_WHITE=$(tput setaf 7)
    else
        _C_RESET=""
        _C_BOLD=""
        _C_DIM=""
        _C_REV=""
        _C_RED=""
        _C_GREEN=""
        _C_YELLOW=""
        _C_BLUE=""
        _C_MAGENTA=""
        _C_CYAN=""
        _C_WHITE=""
    fi
}

# ============================================================
# BOX-DRAWING CHARACTERS
# ============================================================

_BOX_TL="┌"
_BOX_TR="┐"
_BOX_BL="└"
_BOX_BR="┘"
_BOX_H="─"
_BOX_V="│"
_BOX_T_DOWN="┬"
_BOX_T_UP="┴"
_BOX_T_RIGHT="├"
_BOX_T_LEFT="┤"

# Tree characters
_TREE_BRANCH="├──"
_TREE_LAST="└──"
_TREE_PIPE="│   "
_TREE_SPACE="    "
_TREE_OPEN="[-]"
_TREE_CLOSED="[+]"

# Progress bar characters
_BAR_FULL="█"
_BAR_SHADE3="▓"
_BAR_SHADE2="▒"
_BAR_SHADE1="░"
_BAR_EMPTY="░"

# Checkbox characters
_CHECK_ON="[x]"
_CHECK_OFF="[ ]"

# ============================================================
# KEY CONSTANTS
# ============================================================

_KEY_UP="UP"
_KEY_DOWN="DOWN"
_KEY_LEFT="LEFT"
_KEY_RIGHT="RIGHT"
_KEY_ENTER="ENTER"
_KEY_SPACE="SPACE"
_KEY_ESCAPE="ESCAPE"
_KEY_BACKSPACE="BACKSPACE"
_KEY_TAB="TAB"
_KEY_CHAR="CHAR"

# ============================================================
# INITIALIZATION
# ============================================================

_tui_measure() {
    _TUI_COLS=$(tput cols 2>/dev/null || echo 80)
    _TUI_ROWS=$(tput lines 2>/dev/null || echo 24)
}

_tui_cleanup() {
    # Restore cursor visibility
    tput cnorm 2>/dev/null || true
    # Reset attributes
    printf "%s" "${_C_RESET}" 2>/dev/null || true
    # Restore terminal to sane state
    _tui_restore_stty
    # Belt and suspenders -- if saved stty is gone, at least reset
    stty sane 2>/dev/null || true
}

_tui_init() {
    _tui_setup_colors
    _tui_measure

    # SIGWINCH for terminal resize
    trap '_tui_measure' WINCH

    # EXIT trap for cleanup -- chain with existing traps
    trap '_tui_cleanup' EXIT

    _TUI_INITIALIZED=1
}

# ============================================================
# KEY READING
# ============================================================

_tui_read_key() {
    local char=""
    _TUI_KEY=""
    _TUI_KEY_CHAR=""

    # Save stty and switch to raw mode for reliable escape sequence reading
    if [[ -z "${_TUI_SAVED_STTY}" ]]; then
        _TUI_SAVED_STTY=$(stty -g 2>/dev/null || echo "")
    fi
    stty -icanon -echo min 1 time 0 2>/dev/null || true

    # Read one byte
    IFS= read -rsn1 char

    # Check for escape sequences (arrow keys, etc)
    if [[ "${char}" = $'\x1b' ]]; then
        # Switch to short timeout so we don't block if no sequence follows
        # stty time is in tenths of a second: time 2 = 200ms
        stty min 0 time 2 2>/dev/null || true
        local seq1="" seq2=""
        IFS= read -rsn1 seq1 || true
        if [[ "${seq1}" = "[" ]]; then
            IFS= read -rsn1 seq2 || true
            case "${seq2}" in
                A) _TUI_KEY="${_KEY_UP}" ;;
                B) _TUI_KEY="${_KEY_DOWN}" ;;
                C) _TUI_KEY="${_KEY_RIGHT}" ;;
                D) _TUI_KEY="${_KEY_LEFT}" ;;
                *) _TUI_KEY="${_KEY_ESCAPE}" ;;
            esac
        else
            _TUI_KEY="${_KEY_ESCAPE}"
        fi
        # Restore blocking read for next call
        stty min 1 time 0 2>/dev/null || true
    elif [[ "${char}" = "" ]]; then
        _TUI_KEY="${_KEY_ENTER}"
    elif [[ "${char}" = " " ]]; then
        _TUI_KEY="${_KEY_SPACE}"
    elif [[ "${char}" = $'\x7f' ]] || [[ "${char}" = $'\x08' ]]; then
        _TUI_KEY="${_KEY_BACKSPACE}"
    elif [[ "${char}" = $'\t' ]]; then
        _TUI_KEY="${_KEY_TAB}"
    else
        _TUI_KEY="${_KEY_CHAR}"
        _TUI_KEY_CHAR="${char}"
    fi
}

_tui_restore_stty() {
    if [[ -n "${_TUI_SAVED_STTY}" ]]; then
        stty "${_TUI_SAVED_STTY}" 2>/dev/null || true
        _TUI_SAVED_STTY=""
    fi
}

# ============================================================
# GAME LOOP INPUT (non-blocking, macOS-compatible)
# ============================================================
# macOS Terminal.app + bash 3.2 does not reliably honor
# stty min/time for the read builtin, and read -t 0 is
# bash 4.0+.  We bypass bash entirely and use perl's
# IO::Select (POSIX select()) for sub-second timeouts.
#
# Callers MUST set:  stty -icanon -echo

_GAME_CHAR=""

# Timed non-blocking read for game loops.
# Waits up to _timeout seconds for a single byte on stdin.
# Returns immediately when input arrives; sleeps the full
# timeout when idle (frame pacing).
# Sets _GAME_CHAR to the character read, or "" on timeout.
# Usage: _tui_game_read [timeout_seconds]   (default 0.15)
_tui_game_read() {
    local _timeout="${1:-0.15}"
    _GAME_CHAR=""
    _GAME_CHAR=$(perl -e '
        use IO::Select;
        my $s = IO::Select->new(\*STDIN);
        if ($s->can_read($ARGV[0])) {
            sysread(STDIN, my $ch, 1);
            print $ch;
        }
    ' "${_timeout}" 2>/dev/null) || true
}

# Short-timeout read for escape sequence continuation.
# Terminal emulators send ESC [ X as a burst so the bytes
# are already buffered.  50ms is enough to catch them while
# still returning quickly for a standalone ESC press.
_tui_game_seq_read() {
    _GAME_CHAR=""
    _GAME_CHAR=$(perl -e '
        use IO::Select;
        my $s = IO::Select->new(\*STDIN);
        if ($s->can_read(0.05)) {
            sysread(STDIN, my $ch, 1);
            print $ch;
        }
    ' 2>/dev/null) || true
}

# ============================================================
# INTERNAL HELPERS
# ============================================================

_tui_repeat() {
    local char="$1"
    local count="$2"
    local result=""
    local i=0
    while [[ "${i}" -lt "${count}" ]]; do
        result="${result}${char}"
        i=$((i + 1))
    done
    printf "%s" "${result}"
}

_tui_center() {
    local text="$1"
    local width="${2:-${_TUI_COLS}}"
    # Strip ANSI for length calculation
    local stripped
    stripped=$(printf "%s" "${text}" | sed 's/\x1b\[[0-9;]*m//g')
    local len=${#stripped}
    local pad=$(( (width - len) / 2 ))
    if [[ "${pad}" -lt 0 ]]; then
        pad=0
    fi
    printf "%s%s" "$(_tui_repeat " " "${pad}")" "${text}"
}

_tui_strip_ansi() {
    printf "%s" "$1" | sed 's/\x1b\[[0-9;]*m//g'
}

_tui_strlen() {
    local stripped
    stripped=$(_tui_strip_ansi "$1")
    echo ${#stripped}
}

# Parse color tokens in strings: {green}text{reset}
_tui_colorize() {
    local text="$1"
    text="${text//\{red\}/${_C_RED}}"
    text="${text//\{green\}/${_C_GREEN}}"
    text="${text//\{yellow\}/${_C_YELLOW}}"
    text="${text//\{blue\}/${_C_BLUE}}"
    text="${text//\{magenta\}/${_C_MAGENTA}}"
    text="${text//\{cyan\}/${_C_CYAN}}"
    text="${text//\{white\}/${_C_WHITE}}"
    text="${text//\{bold\}/${_C_BOLD}}"
    text="${text//\{dim\}/${_C_DIM}}"
    text="${text//\{reset\}/${_C_RESET}}"
    printf "%s" "${text}"
}

# ============================================================
# BANNER
# ============================================================

tui_banner() {
    local compact=0
    if [[ "${1:-}" = "--compact" ]]; then
        compact=1
    fi

    _tui_measure

    local v="${_C_MAGENTA}"
    local r="${_C_RED}"
    local g="${_C_GREEN}"
    local b="${_C_BLUE}"
    local w="${_C_WHITE}${_C_BOLD}"
    local d="${_C_DIM}"
    local z="${_C_RESET}"

    if [[ "${compact}" -eq 1 ]]; then
        echo ""
        _tui_center "${w}${_BAR_FULL}${_BAR_FULL}${_BAR_FULL} MAESTRO ${_BAR_FULL}${_BAR_FULL}${_BAR_FULL}${z}  ${v}V${r}R${g}G${b}B${z}"
        _tui_center "${d}Infrastructure Ops Engine${z}"
        echo ""
        echo ""
    else
        echo ""
        _tui_center "${w} __  __               _              ${z}"
        echo ""
        _tui_center "${w}|  \\/  | __ _  ___ ___| |_ _ _ ___   ${z}"
        echo ""
        _tui_center "${w}| |\\/| |/ _  |/ -_|__ |  _| '_/ _ \\  ${z}"
        echo ""
        _tui_center "${w}|_|  |_|\\_,_|\\___|___/\\__|_| \\___/   ${z}"
        echo ""
        _tui_center "${d}$(_tui_repeat "${_BOX_H}" 38)${z}"
        echo ""
        _tui_center "${v}V${r}R${g}G${b}B${z}  ${d}Infrastructure Ops Engine${z}"
        echo ""
        echo ""
    fi
}

# ============================================================
# CURSIVE SCRIPT ANIMATION (Easter Egg)
# ============================================================

tui_script() {
    local static=0
    if [[ "${1:-}" = "--static" ]]; then
        static=1
    fi

    _tui_measure
    tput clear 2>/dev/null || printf "\033[2J\033[H"
    tput civis 2>/dev/null || true

    local v="${_C_MAGENTA}"
    local r="${_C_RED}"
    local g="${_C_GREEN}"
    local b="${_C_BLUE}"
    local w="${_C_WHITE}${_C_BOLD}"
    local d="${_C_DIM}"
    local z="${_C_RESET}"

    # 3D ASCII "Maestro" -- classic BBS/ANSI depth effect
    # From figlet 3-d font, with VRGB gradient tail swoosh
    # Proxy chars: #=bold white  %=magenta  +=red  .=blue  (all single-byte safe)
    # The /  *  characters render as-is (they are the 3D depth)
    local lines=()
    lines[0]=" ****     ****                             **                     "
    lines[1]=" /**/**   **/**                            /**                    "
    lines[2]=" /**//** ** /**  ******    *****   ****** ****** ******  ******   "
    lines[3]=" /** //***  /** //////**  **///** **//// ///**/ //**//* **////**  "
    lines[4]=" /**  //*   /**  ******* /*******//*****   /**   /** / /**   /**  "
    lines[5]=" /**   /    /** **////** /**////  /////**  /**   /**   /**   /**  "
    lines[6]=" /**        /**//********//****** ******   //** /***   //******   "
    lines[7]=" //         //  ////////  ////// //////     //  ///     //////    "
    lines[8]="                                                                  "
    lines[9]="  .+%%###############################################%%+.         "
    lines[10]="                                                                  "

    local num_lines=${#lines[@]}

    # Measure character width (all ASCII, safe for bash 3.2)
    local total_width=${#lines[0]}

    # Calculate left padding for centering
    local pad=$(( (_TUI_COLS - total_width) / 2 ))
    if [[ "${pad}" -lt 0 ]]; then
        pad=0
    fi
    local pad_str=""
    pad_str=$(_tui_repeat " " "${pad}")

    # Reserve vertical space
    echo ""
    local i=0
    while [[ "${i}" -lt "${num_lines}" ]]; do
        echo ""
        i=$((i + 1))
    done

    # Move cursor back to top of reserved space
    printf "\033[%dA" "${num_lines}"

    # Pen-lift pauses at letter boundaries
    # M: 0-14, a: 15-24, e: 25-34, s: 35-41, t: 42-48, r: 49-55, o: 56-65
    local letter_starts="1 15 25 35 42 49 56"

    # Colorize a single character
    # *=bold white(face)  /=cyan(depth/edge)  #=magenta(swoosh body)
    # %=magenta(swoosh)  +=red(swoosh fade)  .=blue(swoosh fade)
    _tui_color_char() {
        local ch="$1"
        case "${ch}" in
            "*") printf "%s*%s" "${w}" "${z}" ;;
            "/") printf "%s/%s" "${_C_CYAN}" "${z}" ;;
            "#") printf "%s%s%s" "${w}" "${_BAR_FULL}" "${z}" ;;
            "%") printf "%s%s%s" "${v}" "${_BAR_SHADE3}" "${z}" ;;
            "+") printf "%s%s%s" "${r}" "${_BAR_SHADE2}" "${z}" ;;
            ".") printf "%s%s%s" "${b}" "${_BAR_SHADE1}" "${z}" ;;
            *)   printf "%s" "${ch}" ;;
        esac
    }

    # Render a single full frame (used by both static and final animation frame)
    _tui_render_frame() {
        local row=0
        while [[ "${row}" -lt "${num_lines}" ]]; do
            local line="${lines[$row]}"
            printf "\r%s" "${pad_str}"
            local ci=0
            while [[ "${ci}" -lt "${#line}" ]]; do
                _tui_color_char "${line:${ci}:1}"
                ci=$((ci + 1))
            done
            tput el 2>/dev/null || true
            echo ""
            row=$((row + 1))
        done
        _tui_center "${v}V${r}R${g}G${b}B${z}"
        echo ""
        _tui_center "${d}Infrastructure Ops Engine${z}"
        echo ""
        echo ""
    }

    if [[ "${static}" -eq 1 ]]; then
        # Skip animation, just render the final frame
        echo ""
        _tui_render_frame
    else
        # Reserve vertical space
        echo ""
        local i=0
        while [[ "${i}" -lt "${num_lines}" ]]; do
            echo ""
            i=$((i + 1))
        done
        printf "\033[%dA" "${num_lines}"

        # Animate: redraw all lines on each frame, revealing one more column
        local col=1
        while [[ "${col}" -le "${total_width}" ]]; do
            if [[ "${col}" -gt 1 ]]; then
                printf "\033[%dA" "${num_lines}"
            fi

            local row=0
            while [[ "${row}" -lt "${num_lines}" ]]; do
                local line="${lines[$row]}"
                local truncated="${line:0:${col}}"
                printf "\r%s" "${pad_str}"
                local ci=0
                while [[ "${ci}" -lt "${#truncated}" ]]; do
                    _tui_color_char "${truncated:${ci}:1}"
                    ci=$((ci + 1))
                done
                tput el 2>/dev/null || true
                echo ""
                row=$((row + 1))
            done

            local is_boundary=0
            for boundary in ${letter_starts}; do
                if [[ "${col}" -eq "${boundary}" ]]; then
                    is_boundary=1
                    break
                fi
            done

            if [[ "${is_boundary}" -eq 1 ]]; then
                sleep 0.1
            else
                sleep 0.02
            fi

            col=$((col + 1))
        done

        # VRGB label fades in
        sleep 0.3
        _tui_center "${v}V${r}R${g}G${b}B${z}"
        echo ""
        sleep 0.15
        _tui_center "${d}Infrastructure Ops Engine${z}"
        echo ""
        echo ""
    fi

    tput cnorm 2>/dev/null || true
}

# ============================================================
# PANEL
# ============================================================

tui_panel() {
    local title="$1"
    shift

    # Collect key=value pairs
    local keys=()
    local vals=()
    local max_key_len=0
    local max_val_len=0

    while [[ $# -gt 0 ]]; do
        local pair="$1"
        local key="${pair%%=*}"
        local val="${pair#*=}"
        keys+=("${key}")
        vals+=("${val}")
        if [[ ${#key} -gt ${max_key_len} ]]; then
            max_key_len=${#key}
        fi
        local plain_val
        plain_val=$(_tui_strip_ansi "$(_tui_colorize "${val}")")
        if [[ ${#plain_val} -gt ${max_val_len} ]]; then
            max_val_len=${#plain_val}
        fi
        shift
    done

    # Calculate box width
    local content_width=$(( max_key_len + max_val_len + 5 ))
    local title_len=${#title}
    local min_width=$(( title_len + 6 ))
    if [[ "${content_width}" -lt "${min_width}" ]]; then
        content_width="${min_width}"
    fi
    if [[ "${content_width}" -lt 30 ]]; then
        content_width=30
    fi
    local box_width=$(( content_width + 4 ))

    # Top border with title
    printf "%s" "${_BOX_TL}"
    printf "%s" "$(_tui_repeat "${_BOX_H}" 3)"
    printf " %s " "${title}"
    local remaining=$(( box_width - title_len - 7 ))
    printf "%s" "$(_tui_repeat "${_BOX_H}" "${remaining}")"
    printf "%s\n" "${_BOX_TR}"

    # Empty line
    printf "%s%s%s\n" "${_BOX_V}" "$(_tui_repeat " " $(( box_width - 2 )))" "${_BOX_V}"

    # Key-value rows
    local i=0
    while [[ "${i}" -lt "${#keys[@]}" ]]; do
        local key="${keys[$i]}"
        local val="${vals[$i]}"
        local colored_val
        colored_val=$(_tui_colorize "${val}")
        local plain_val
        plain_val=$(_tui_strip_ansi "${colored_val}")

        # Right-align key
        local key_pad=$(( max_key_len - ${#key} ))
        local val_pad=$(( content_width - max_key_len - ${#plain_val} - 3 ))
        if [[ "${val_pad}" -lt 0 ]]; then
            val_pad=0
        fi

        printf "%s  %s%s:  %s%s  %s\n" \
            "${_BOX_V}" \
            "$(_tui_repeat " " "${key_pad}")" \
            "${key}" \
            "${colored_val}${_C_RESET}" \
            "$(_tui_repeat " " "${val_pad}")" \
            "${_BOX_V}"

        i=$((i + 1))
    done

    # Empty line
    printf "%s%s%s\n" "${_BOX_V}" "$(_tui_repeat " " $(( box_width - 2 )))" "${_BOX_V}"

    # Bottom border
    printf "%s%s%s\n" "${_BOX_BL}" "$(_tui_repeat "${_BOX_H}" $(( box_width - 2 )))" "${_BOX_BR}"
}

# ============================================================
# PROGRESS BAR
# ============================================================

_TUI_PROGRESS_TOTAL=100
_TUI_PROGRESS_LABEL=""
_TUI_PROGRESS_START=0

tui_progress_start() {
    _TUI_PROGRESS_LABEL="$1"
    _TUI_PROGRESS_TOTAL=100
    shift
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --total=*) _TUI_PROGRESS_TOTAL="${1#--total=}" ;;
        esac
        shift
    done
    _TUI_PROGRESS_START=$(date +%s)
    tui_progress_update 0 ""
}

tui_progress_update() {
    local current="$1"
    local status_text="${2:-}"

    local pct=0
    if [[ "${_TUI_PROGRESS_TOTAL}" -gt 0 ]]; then
        pct=$(( current * 100 / _TUI_PROGRESS_TOTAL ))
    fi
    if [[ "${pct}" -gt 100 ]]; then
        pct=100
    fi

    # Bar width: terminal width minus label, percentage, status, padding
    local bar_width=$(( _TUI_COLS - ${#_TUI_PROGRESS_LABEL} - ${#status_text} - 14 ))
    if [[ "${bar_width}" -lt 10 ]]; then
        bar_width=10
    fi

    local filled=$(( pct * bar_width / 100 ))
    local empty=$(( bar_width - filled ))

    # Build bar with gradient edge
    local bar=""
    local f=0
    while [[ "${f}" -lt "${filled}" ]]; do
        bar="${bar}${_BAR_FULL}"
        f=$((f + 1))
    done
    # Gradient edge character
    if [[ "${empty}" -gt 0 ]] && [[ "${filled}" -gt 0 ]]; then
        local edge_pct=$(( (pct * bar_width) % 100 ))
        if [[ "${edge_pct}" -gt 66 ]]; then
            bar="${bar}${_BAR_SHADE3}"
        elif [[ "${edge_pct}" -gt 33 ]]; then
            bar="${bar}${_BAR_SHADE2}"
        else
            bar="${bar}${_BAR_SHADE1}"
        fi
        empty=$((empty - 1))
    fi
    local e=0
    while [[ "${e}" -lt "${empty}" ]]; do
        bar="${bar}${_BAR_EMPTY}"
        e=$((e + 1))
    done

    # Color the filled portion
    printf "\r%s: [${_C_GREEN}%s${_C_RESET}%s] %3d%% %s" \
        "${_TUI_PROGRESS_LABEL}" \
        "$(_tui_repeat "${_BAR_FULL}" "${filled}")" \
        "$(_tui_repeat "${_BAR_EMPTY}" "$((bar_width - filled))")" \
        "${pct}" \
        "${status_text}"

    # Clear to end of line
    tput el 2>/dev/null || true
}

tui_progress_done() {
    local msg="${1:-Done}"
    printf "\r%s: [${_C_GREEN}%s${_C_RESET}] 100%% ${_C_GREEN}%s${_C_RESET}" \
        "${_TUI_PROGRESS_LABEL}" \
        "$(_tui_repeat "${_BAR_FULL}" $(( _TUI_COLS - ${#_TUI_PROGRESS_LABEL} - ${#msg} - 14 )))" \
        "${msg}"
    tput el 2>/dev/null || true
    echo ""
}

# ============================================================
# CONFIRM (Y/N)
# ============================================================

tui_confirm() {
    local prompt="$1"
    local default="yes"
    shift
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --default=*) default="${1#--default=}" ;;
        esac
        shift
    done

    local box_width=$(( ${#prompt} + 12 ))
    if [[ "${box_width}" -lt 40 ]]; then
        box_width=40
    fi

    local inner=$(( box_width - 2 ))

    # Draw box
    echo ""
    printf "%s%s%s\n" "${_BOX_TL}" "$(_tui_repeat "${_BOX_H}" "${inner}")" "${_BOX_TR}"
    printf "%s%s%s\n" "${_BOX_V}" "$(_tui_repeat " " "${inner}")" "${_BOX_V}"

    # Prompt line (centered in box)
    local prompt_pad=$(( (inner - ${#prompt}) / 2 ))
    printf "%s%s%s%s%s\n" \
        "${_BOX_V}" \
        "$(_tui_repeat " " "${prompt_pad}")" \
        "${prompt}" \
        "$(_tui_repeat " " $(( inner - prompt_pad - ${#prompt} )))" \
        "${_BOX_V}"

    printf "%s%s%s\n" "${_BOX_V}" "$(_tui_repeat " " "${inner}")" "${_BOX_V}"

    # Buttons line
    local yes_label="[Y] Yes"
    local no_label="[N] No"
    if [[ "${default}" = "yes" ]]; then
        yes_label="${_C_REV} Y  Yes ${_C_RESET}"
        no_label=" N  No "
    else
        yes_label=" Y  Yes "
        no_label="${_C_REV} N  No ${_C_RESET}"
    fi

    local buttons_text="      ${yes_label}       ${no_label}      "
    local buttons_plain
    buttons_plain=$(_tui_strip_ansi "${buttons_text}")
    local btn_pad=$(( (inner - ${#buttons_plain}) / 2 ))
    if [[ "${btn_pad}" -lt 0 ]]; then
        btn_pad=0
    fi

    printf "%s%s%s%s%s\n" \
        "${_BOX_V}" \
        "$(_tui_repeat " " "${btn_pad}")" \
        "${buttons_text}" \
        "$(_tui_repeat " " $(( inner - btn_pad - ${#buttons_plain} )))" \
        "${_BOX_V}"

    printf "%s%s%s\n" "${_BOX_V}" "$(_tui_repeat " " "${inner}")" "${_BOX_V}"
    printf "%s%s%s\n" "${_BOX_BL}" "$(_tui_repeat "${_BOX_H}" "${inner}")" "${_BOX_BR}"

    # Read single keypress
    while true; do
        _tui_read_key
        case "${_TUI_KEY}" in
            "${_KEY_CHAR}")
                case "${_TUI_KEY_CHAR}" in
                    y|Y)
                        TUI_RESULT="yes"
                        _tui_restore_stty
                        return 0
                        ;;
                    n|N)
                        TUI_RESULT="no"
                        _tui_restore_stty
                        return 1
                        ;;
                esac
                ;;
            "${_KEY_ENTER}")
                _tui_restore_stty
                if [[ "${default}" = "yes" ]]; then
                    TUI_RESULT="yes"
                    return 0
                else
                    TUI_RESULT="no"
                    return 1
                fi
                ;;
            "${_KEY_ESCAPE}")
                TUI_RESULT="no"
                _tui_restore_stty
                return 1
                ;;
        esac
    done
}

# ============================================================
# CALIBRATION CHALLENGE
# ============================================================

tui_challenge() {
    # Locate challenge module: MAESTRO_ROOT env, else derive from BASH_SOURCE
    local _maestro_root="${MAESTRO_ROOT:-}"
    if [[ -z "${_maestro_root}" ]]; then
        _maestro_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    fi
    local challenge_lib="${_maestro_root}/cue-mem/lib"

    # Generate arithmetic challenge -- outputs: prompt, challenge_id, json
    local gen_output
    gen_output=$(python3 -c "
import sys, json
sys.path.insert(0, sys.argv[1])
import challenge
ch = challenge.generate('arithmetic')
print(ch['prompt'])
print(ch['challenge_id'])
print(json.dumps(ch))
" "${challenge_lib}") || {
        echo "  ${_C_RED}Failed to generate challenge${_C_RESET}"
        return 1
    }

    # Parse output lines with bash builtins
    local prompt="" challenge_id="" challenge_json=""
    {
        IFS= read -r prompt
        IFS= read -r challenge_id
        IFS= read -r challenge_json
    } <<< "${gen_output}"

    # Display equation in calibration panel
    tui_panel "Calibration" "Solve=${prompt}"

    # Record start time (python for ms -- macOS date lacks %N)
    local start_ms
    start_ms=$(python3 -c "import time; print(int(time.time() * 1000))")

    # Collect answer
    tui_input "=" || return 1
    local answer="${TUI_RESULT}"

    # Record end time and compute elapsed
    local end_ms elapsed_ms
    end_ms=$(python3 -c "import time; print(int(time.time() * 1000))")
    elapsed_ms=$((end_ms - start_ms))

    # Verify -- outputs: valid|confidence|proof
    local verify_output
    verify_output=$(python3 -c "
import sys, json
sys.path.insert(0, sys.argv[1])
import challenge
ch = json.loads(sys.argv[2])
valid, confidence, proof = challenge.verify(ch, sys.argv[3], int(sys.argv[4]))
print('%s|%.3f|%s' % ('true' if valid else 'false', confidence, proof or ''))
" "${challenge_lib}" "${challenge_json}" "${answer}" "${elapsed_ms}") || {
        echo "  ${_C_RED}Verification error${_C_RESET}"
        return 1
    }

    # Parse pipe-delimited result with parameter expansion
    local valid="${verify_output%%|*}"
    local rest="${verify_output#*|}"
    local confidence="${rest%%|*}"
    local proof="${rest#*|}"

    if [[ "${valid}" != "true" ]]; then
        echo "  ${_C_RED}Incorrect answer.${_C_RESET}"
        return 1
    fi

    echo "  ${_C_DIM}${_C_GREEN}calibrated.${_C_RESET}"
    TUI_RESULT="${confidence}|${proof}|${challenge_id}"
    return 0
}

# ============================================================
# INPUT FIELD
# ============================================================

tui_input() {
    local label="$1"
    shift
    local default_val=""
    local placeholder=""
    local password=0

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --default=*)     default_val="${1#--default=}" ;;
            --placeholder=*) placeholder="${1#--placeholder=}" ;;
            --password)      password=1 ;;
        esac
        shift
    done

    local value="${default_val}"
    local cursor_pos=${#value}

    local field_width=$(( _TUI_COLS - 6 ))
    if [[ "${field_width}" -gt 60 ]]; then
        field_width=60
    fi
    local inner=$(( field_width - 2 ))

    echo ""
    echo "  ${label}:"

    # Draw loop
    while true; do
        # Build display string
        local display="${value}"
        if [[ "${password}" -eq 1 ]] && [[ -n "${value}" ]]; then
            display=$(_tui_repeat "*" ${#value})
        fi
        if [[ -z "${display}" ]] && [[ -n "${placeholder}" ]]; then
            display="${_C_DIM}${placeholder}${_C_RESET}"
        fi

        # Top border
        printf "\r  %s%s%s\n" "${_BOX_TL}" "$(_tui_repeat "${_BOX_H}" "${inner}")" "${_BOX_TR}"

        # Content line with cursor
        local visible="${display}"
        local plain_visible
        plain_visible=$(_tui_strip_ansi "${visible}")
        local content_pad=$(( inner - ${#plain_visible} - 1 ))
        if [[ "${content_pad}" -lt 0 ]]; then
            content_pad=0
        fi
        printf "  %s %s%s%s\n" "${_BOX_V}" "${visible}" "$(_tui_repeat " " "${content_pad}")" "${_BOX_V}"

        # Bottom border
        printf "  %s%s%s" "${_BOX_BL}" "$(_tui_repeat "${_BOX_H}" "${inner}")" "${_BOX_BR}"

        # Move cursor back up to content line for visual cursor
        printf "\033[2A"
        printf "\r"

        # Read key
        _tui_read_key

        case "${_TUI_KEY}" in
            "${_KEY_ENTER}")
                # Move to after the box
                printf "\033[3B\n"
                TUI_RESULT="${value}"
                _tui_restore_stty
                return 0
                ;;
            "${_KEY_ESCAPE}")
                printf "\033[3B\n"
                TUI_RESULT=""
                _tui_restore_stty
                return 1
                ;;
            "${_KEY_BACKSPACE}")
                if [[ ${#value} -gt 0 ]]; then
                    value="${value%?}"
                    cursor_pos=${#value}
                fi
                ;;
            "${_KEY_SPACE}")
                value="${value} "
                cursor_pos=${#value}
                ;;
            "${_KEY_CHAR}")
                value="${value}${_TUI_KEY_CHAR}"
                cursor_pos=${#value}
                ;;
        esac

        # Clear the box lines for redraw (2B = down to bottom border)
        printf "\033[2B"
        printf "\r\033[K\033[1A\033[K\033[1A\033[K"
    done
}

# ============================================================
# MENU (Arrow-key navigable)
# ============================================================

tui_menu() {
    local title="$1"
    shift
    local items=()
    while [[ $# -gt 0 ]]; do
        items+=("$1")
        shift
    done

    local count=${#items[@]}
    if [[ "${count}" -eq 0 ]]; then
        return 1
    fi

    # Measure the real terminal -- the arcade launch path never calls
    # _tui_measure, so without this _TUI_COLS/_TUI_ROWS stay at the 80x24
    # defaults and the width-dependent clip below would be wrong.
    _tui_measure

    local selected=0
    local visible_start=0
    local max_visible=$(( _TUI_ROWS - 6 ))
    if [[ "${max_visible}" -gt "${count}" ]]; then
        max_visible="${count}"
    fi

    tput civis 2>/dev/null || true

    echo ""
    echo "  ${_C_BOLD}${title}${_C_RESET}"
    echo ""

    # Drop an anchor here. Every redraw restores to this point and clears
    # to the end of the screen, then draws fresh -- so the frame never
    # depends on counting how many physical rows the last draw used. Long
    # labels that wrap, scroll indicators, whatever: the clear-to-end wipes
    # them all. No cursor arithmetic to desync.
    tput sc 2>/dev/null || true

    while true; do
        # Calculate visible window
        if [[ "${selected}" -lt "${visible_start}" ]]; then
            visible_start="${selected}"
        fi
        if [[ "${selected}" -ge $(( visible_start + max_visible )) ]]; then
            visible_start=$(( selected - max_visible + 1 ))
        fi

        # Restore to the anchor and clear everything below it before redraw.
        tput rc 2>/dev/null || true
        printf "\033[J"

        # Draw items. Clip each line to the terminal width so a long label
        # can never wrap -- the frame stays one row per item.
        local avail=$(( _TUI_COLS - 7 ))
        local i="${visible_start}"
        local drawn=0
        while [[ "${drawn}" -lt "${max_visible}" ]] && [[ "${i}" -lt "${count}" ]]; do
            local item="${items[$i]}"
            if [[ "${avail}" -gt 0 ]] && [[ "${#item}" -gt "${avail}" ]]; then
                item="${item:0:avail}"
            fi
            if [[ "${i}" -eq "${selected}" ]]; then
                printf "  ${_C_REV} > %s ${_C_RESET}\n" "${item}"
            else
                printf "    %s\n" "${item}"
            fi
            i=$((i + 1))
            drawn=$((drawn + 1))
        done

        # Scroll indicator (only when the list is taller than the window)
        if [[ "${count}" -gt "${max_visible}" ]]; then
            local remaining=$(( count - visible_start - max_visible ))
            if [[ "${remaining}" -gt 0 ]]; then
                printf "  ${_C_DIM}  ... %d more${_C_RESET}\n" "${remaining}"
            fi
        fi

        # Read key
        _tui_read_key

        case "${_TUI_KEY}" in
            "${_KEY_UP}")
                if [[ "${selected}" -gt 0 ]]; then
                    selected=$((selected - 1))
                fi
                ;;
            "${_KEY_DOWN}")
                if [[ "${selected}" -lt $((count - 1)) ]]; then
                    selected=$((selected + 1))
                fi
                ;;
            "${_KEY_ENTER}")
                TUI_RESULT="${items[$selected]}"
                TUI_INDEX="${selected}"
                _tui_restore_stty
                tput cnorm 2>/dev/null || true
                return 0
                ;;
            "${_KEY_ESCAPE}")
                TUI_RESULT=""
                TUI_INDEX=-1
                _tui_restore_stty
                tput cnorm 2>/dev/null || true
                return 1
                ;;
        esac
    done
}

# ============================================================
# CHECKLIST (Space to toggle, Enter to confirm)
# ============================================================

tui_checklist() {
    local title="$1"
    shift
    local items=()
    local checked=()

    while [[ $# -gt 0 ]]; do
        local item="$1"
        if [[ "${item}" = +* ]]; then
            items+=("${item:1}")
            checked+=(1)
        else
            items+=("${item}")
            checked+=(0)
        fi
        shift
    done

    local count=${#items[@]}
    if [[ "${count}" -eq 0 ]]; then
        return 1
    fi

    local selected=0
    local max_visible=$(( _TUI_ROWS - 6 ))
    if [[ "${max_visible}" -gt "${count}" ]]; then
        max_visible="${count}"
    fi
    local visible_start=0

    tput civis 2>/dev/null || true

    echo ""
    echo "  ${_C_BOLD}${title}${_C_RESET}  ${_C_DIM}(space=toggle, enter=confirm)${_C_RESET}"
    echo ""

    while true; do
        # Visible window
        if [[ "${selected}" -lt "${visible_start}" ]]; then
            visible_start="${selected}"
        fi
        if [[ "${selected}" -ge $(( visible_start + max_visible )) ]]; then
            visible_start=$(( selected - max_visible + 1 ))
        fi

        local i="${visible_start}"
        local drawn=0
        while [[ "${drawn}" -lt "${max_visible}" ]] && [[ "${i}" -lt "${count}" ]]; do
            local item="${items[$i]}"
            local check_mark="${_CHECK_OFF}"
            if [[ "${checked[$i]}" -eq 1 ]]; then
                check_mark="${_C_GREEN}${_CHECK_ON}${_C_RESET}"
            fi

            if [[ "${i}" -eq "${selected}" ]]; then
                printf "  ${_C_REV}> %s %s ${_C_RESET}\n" "${check_mark}" "${item}"
            else
                printf "    %s %s\n" "${check_mark}" "${item}"
            fi
            i=$((i + 1))
            drawn=$((drawn + 1))
        done

        _tui_read_key

        local clear_lines="${max_visible}"

        case "${_TUI_KEY}" in
            "${_KEY_UP}")
                if [[ "${selected}" -gt 0 ]]; then
                    selected=$((selected - 1))
                fi
                ;;
            "${_KEY_DOWN}")
                if [[ "${selected}" -lt $((count - 1)) ]]; then
                    selected=$((selected + 1))
                fi
                ;;
            "${_KEY_SPACE}")
                if [[ "${checked[$selected]}" -eq 1 ]]; then
                    checked[$selected]=0
                else
                    checked[$selected]=1
                fi
                ;;
            "${_KEY_ENTER}")
                TUI_RESULT=()
                TUI_INDICES=()
                local j=0
                while [[ "${j}" -lt "${count}" ]]; do
                    if [[ "${checked[$j]}" -eq 1 ]]; then
                        TUI_RESULT+=("${items[$j]}")
                        TUI_INDICES+=("${j}")
                    fi
                    j=$((j + 1))
                done
                _tui_restore_stty
                tput cnorm 2>/dev/null || true
                return 0
                ;;
            "${_KEY_ESCAPE}")
                TUI_RESULT=()
                TUI_INDICES=()
                _tui_restore_stty
                tput cnorm 2>/dev/null || true
                return 1
                ;;
        esac

        printf "\033[%dA" "${clear_lines}"
        local c=0
        while [[ "${c}" -lt "${clear_lines}" ]]; do
            printf "\033[K\033[1B"
            c=$((c + 1))
        done
        printf "\033[%dA" "${clear_lines}"
    done
}

# ============================================================
# TREE NAVIGATOR
# ============================================================

tui_tree() {
    local title="$1"

    # Read tree data from stdin
    local raw_lines=()
    local raw_depths=()
    local raw_labels=()
    local raw_is_branch=()
    local raw_expanded=()
    local line=""

    while IFS= read -r line || [[ -n "${line}" ]]; do
        raw_lines+=("${line}")
        # Calculate depth from leading spaces (2 spaces = 1 level)
        local stripped="${line#"${line%%[! ]*}"}"
        local spaces=$(( ${#line} - ${#stripped} ))
        local depth=$(( spaces / 2 ))
        raw_depths+=("${depth}")

        # Check for branch marker (+)
        local label="${stripped}"
        if [[ "${label}" = +* ]]; then
            label="${label:1}"
            raw_is_branch+=(1)
            raw_expanded+=(1)
        else
            raw_is_branch+=(0)
            raw_expanded+=(0)
        fi
        raw_labels+=("${label}")
    done

    local total=${#raw_labels[@]}
    if [[ "${total}" -eq 0 ]]; then
        return 1
    fi

    local selected=0

    tput civis 2>/dev/null || true

    echo ""
    echo "  ${_C_BOLD}${title}${_C_RESET}  ${_C_DIM}(arrows=navigate, space=expand, enter=select)${_C_RESET}"
    echo ""

    while true; do
        # Build visible items list based on expansion state
        local vis_indices=()
        local vis_prefixes=()

        local idx=0
        while [[ "${idx}" -lt "${total}" ]]; do
            local depth="${raw_depths[$idx]}"

            # Check if any ancestor is collapsed
            local visible=1
            local check_idx=$((idx - 1))
            local check_depth=$((depth - 1))

            while [[ "${check_depth}" -ge 0 ]] && [[ "${check_idx}" -ge 0 ]]; do
                if [[ "${raw_depths[$check_idx]}" -eq "${check_depth}" ]]; then
                    if [[ "${raw_is_branch[$check_idx]}" -eq 1 ]] && [[ "${raw_expanded[$check_idx]}" -eq 0 ]]; then
                        visible=0
                        break
                    fi
                    check_depth=$((check_depth - 1))
                fi
                check_idx=$((check_idx - 1))
            done

            if [[ "${visible}" -eq 1 ]]; then
                # Build tree prefix
                local prefix=""
                local d=0
                while [[ "${d}" -lt "${depth}" ]]; do
                    prefix="${prefix}${_TREE_SPACE}"
                    d=$((d + 1))
                done

                # Is this the last sibling at its depth?
                local is_last=1
                local next_idx=$((idx + 1))
                while [[ "${next_idx}" -lt "${total}" ]]; do
                    if [[ "${raw_depths[$next_idx]}" -lt "${depth}" ]]; then
                        break
                    fi
                    if [[ "${raw_depths[$next_idx]}" -eq "${depth}" ]]; then
                        is_last=0
                        break
                    fi
                    next_idx=$((next_idx + 1))
                done

                if [[ "${depth}" -gt 0 ]]; then
                    if [[ "${is_last}" -eq 1 ]]; then
                        prefix="${prefix}${_TREE_LAST} "
                    else
                        prefix="${prefix}${_TREE_BRANCH} "
                    fi
                fi

                # Branch indicator
                if [[ "${raw_is_branch[$idx]}" -eq 1 ]]; then
                    if [[ "${raw_expanded[$idx]}" -eq 1 ]]; then
                        prefix="${prefix}${_TREE_OPEN} "
                    else
                        prefix="${prefix}${_TREE_CLOSED} "
                    fi
                fi

                vis_indices+=("${idx}")
                vis_prefixes+=("${prefix}")
            fi

            idx=$((idx + 1))
        done

        local vis_count=${#vis_indices[@]}

        # Clamp selected
        if [[ "${selected}" -ge "${vis_count}" ]]; then
            selected=$((vis_count - 1))
        fi
        if [[ "${selected}" -lt 0 ]]; then
            selected=0
        fi

        # Draw visible items
        local draw_i=0
        while [[ "${draw_i}" -lt "${vis_count}" ]]; do
            local real_idx="${vis_indices[$draw_i]}"
            local label="${raw_labels[$real_idx]}"
            local prefix="${vis_prefixes[$draw_i]}"

            if [[ "${draw_i}" -eq "${selected}" ]]; then
                printf "  ${_C_REV}%s%s${_C_RESET}\n" "${prefix}" "${label}"
            else
                printf "  %s%s\n" "${prefix}" "${label}"
            fi
            draw_i=$((draw_i + 1))
        done

        _tui_read_key

        local real_selected="${vis_indices[$selected]}"

        case "${_TUI_KEY}" in
            "${_KEY_UP}")
                if [[ "${selected}" -gt 0 ]]; then
                    selected=$((selected - 1))
                fi
                ;;
            "${_KEY_DOWN}")
                if [[ "${selected}" -lt $((vis_count - 1)) ]]; then
                    selected=$((selected + 1))
                fi
                ;;
            "${_KEY_SPACE}"|"${_KEY_RIGHT}")
                if [[ "${raw_is_branch[$real_selected]}" -eq 1 ]]; then
                    if [[ "${raw_expanded[$real_selected]}" -eq 1 ]]; then
                        raw_expanded[$real_selected]=0
                    else
                        raw_expanded[$real_selected]=1
                    fi
                fi
                ;;
            "${_KEY_LEFT}")
                if [[ "${raw_is_branch[$real_selected]}" -eq 1 ]] && [[ "${raw_expanded[$real_selected]}" -eq 1 ]]; then
                    raw_expanded[$real_selected]=0
                fi
                ;;
            "${_KEY_ENTER}")
                TUI_RESULT="${raw_labels[$real_selected]}"
                TUI_INDEX="${real_selected}"
                # Build path
                TUI_PATH="${raw_labels[$real_selected]}"
                local path_depth="${raw_depths[$real_selected]}"
                local path_idx=$((real_selected - 1))
                while [[ "${path_depth}" -gt 0 ]] && [[ "${path_idx}" -ge 0 ]]; do
                    if [[ "${raw_depths[$path_idx]}" -lt "${path_depth}" ]]; then
                        TUI_PATH="${raw_labels[$path_idx]}/${TUI_PATH}"
                        path_depth="${raw_depths[$path_idx]}"
                    fi
                    path_idx=$((path_idx - 1))
                done
                _tui_restore_stty
                tput cnorm 2>/dev/null || true
                return 0
                ;;
            "${_KEY_ESCAPE}")
                TUI_RESULT=""
                TUI_INDEX=-1
                TUI_PATH=""
                _tui_restore_stty
                tput cnorm 2>/dev/null || true
                return 1
                ;;
        esac

        # Clear and redraw
        printf "\033[%dA" "${vis_count}"
        local c=0
        while [[ "${c}" -lt "${vis_count}" ]]; do
            printf "\033[K\033[1B"
            c=$((c + 1))
        done
        printf "\033[%dA" "${vis_count}"
    done
}

# ============================================================
# SUBMENU (reusable loop: menu + dispatch + clear + wait)
# ============================================================
#
#  Usage:
#    tui_submenu "Title" \
#        "List:_tokens_list" \
#        "Create:_tokens_create" \
#        "Inspect:_tokens_inspect"
#
#  "Back" is appended automatically.
#  Each action runs after tput clear, followed by
#  "Press any key to return..." and another clear.

tui_submenu() {
    local title="$1"
    shift

    local labels=()
    local handlers=()

    while [[ $# -gt 0 ]]; do
        local pair="$1"
        labels+=("${pair%%:*}")
        handlers+=("${pair#*:}")
        shift
    done

    local count=${#labels[@]}
    labels+=("Back")

    while true; do
        tui_menu "${title}" "${labels[@]}" || true

        if [[ "${TUI_INDEX}" -ge "${count}" ]] || [[ "${TUI_INDEX}" -eq -1 ]]; then
            return 0
        fi

        tput clear 2>/dev/null
        ${handlers[${TUI_INDEX}]} || true

        echo ""
        echo "  ${_C_DIM}Press any key to return to menu...${_C_RESET}"
        read -rsn1
        tput clear 2>/dev/null
    done
}

# ============================================================
# INITIALIZE ON SOURCE
# ============================================================

_tui_init
