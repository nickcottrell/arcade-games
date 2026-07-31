#!/usr/bin/env bash
# ============================================================
#  VAULT-QUERY  --  Search and browse the portfolio vault
# ============================================================
#  Interactive TUI for querying the FTS5-indexed vault database.
#  Supports full-text search with BM25 ranking, browsing by
#  tag/era, image browsing, and detail view with markdown body
#  rendering.
#
#  Launch:  rom-launch vault
#  Direct:  bash arcade/roms/vault-query.sh
#  Backend: SQLite FTS5 + filesystem images -- zero external deps
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/lib/tui.sh"
source "${SCRIPT_DIR}/lib/vrgb.sh"

DB_PATH="${SCRIPT_DIR}/vault-cold/vault.db"
IMAGES_DIR="${SCRIPT_DIR}/vault-cold/HOT"
VAULT_CLI="${SCRIPT_DIR}/tools/vault-template/app/cli.py"

if [[ ! -f "${DB_PATH}" ]]; then
    echo ""
    echo "  ${_C_RED}Error:${_C_RESET} Vault database not found at:"
    echo "  ${DB_PATH}"
    echo ""
    echo "  Run ${_C_BOLD}python3 tools/vault-index.py${_C_RESET} to build the index."
    echo ""
    exit 1
fi

# ============================================================
# STATE -- parallel arrays for result lists
# ============================================================

_V_COUNT=0
_V_SLUGS=()
_V_TITLES=()
_V_SUMMARIES=()
_V_TAGS=()
_V_ERAS=()
_V_COMPANIES=()
_V_WORDS=()
_V_SNIPPETS=()

# Detail fields for single entry
_D_SLUG=""
_D_TITLE=""
_D_SUMMARY=""
_D_TAGS=""
_D_CATEGORY=""
_D_ERA=""
_D_COMPANY=""
_D_ROLE=""
_D_STATUS=""
_D_WORDS=0
_D_DATE=""
_D_BODY_LINES=()

# Image state
_I_COUNT=0
_I_FILENAMES=()
_I_SLUGS=()
_I_SIZES=()
_I_FORMATS=()
_I_DESCRIPTIONS=()
_I_WARMTHS=()
_I_PALETTE_NAMES=()
_I_DOMINANTS=()

# Image entry state (grouped by slug)
_IE_COUNT=0
_IE_SLUGS=()
_IE_TITLES=()
_IE_IMAGE_COUNTS=()
_IE_TOTAL_SIZES=()

reset_results() {
    _V_COUNT=0
    _V_SLUGS=()
    _V_TITLES=()
    _V_SUMMARIES=()
    _V_TAGS=()
    _V_ERAS=()
    _V_COMPANIES=()
    _V_WORDS=()
    _V_SNIPPETS=()
}

reset_detail() {
    _D_SLUG=""
    _D_TITLE=""
    _D_SUMMARY=""
    _D_TAGS=""
    _D_CATEGORY=""
    _D_ERA=""
    _D_COMPANY=""
    _D_ROLE=""
    _D_STATUS=""
    _D_WORDS=0
    _D_DATE=""
    _D_BODY_LINES=()
}

reset_images() {
    _I_COUNT=0
    _I_FILENAMES=()
    _I_SLUGS=()
    _I_SIZES=()
    _I_FORMATS=()
    _I_DESCRIPTIONS=()
    _I_WARMTHS=()
    _I_PALETTE_NAMES=()
    _I_DOMINANTS=()
}

reset_image_entries() {
    _IE_COUNT=0
    _IE_SLUGS=()
    _IE_TITLES=()
    _IE_IMAGE_COUNTS=()
    _IE_TOTAL_SIZES=()
}

# ============================================================
# QUERY FUNCTIONS -- thin wrappers around tools/vault-template/app/cli.py
# ============================================================

vault_search() {
    python3 "${VAULT_CLI}" search "$1" --limit "${2:-20}"
}

vault_get_entry() {
    python3 "${VAULT_CLI}" get "$1"
}

vault_list_tags() {
    python3 "${VAULT_CLI}" tags
}

vault_list_eras() {
    python3 "${VAULT_CLI}" eras
}

vault_filter_by_tag() {
    python3 "${VAULT_CLI}" filter --tag "$1"
}

vault_filter_by_era() {
    python3 "${VAULT_CLI}" filter --era "$1"
}

vault_all_entries() {
    python3 "${VAULT_CLI}" all
}

vault_images_for_slug() {
    python3 "${VAULT_CLI}" images "$1"
}

vault_all_images() {
    python3 "${VAULT_CLI}" images
}

vault_search_images() {
    python3 "${VAULT_CLI}" search-images "$1"
}

vault_image_entries() {
    python3 "${VAULT_CLI}" image-entries
}

# ============================================================
# BASH RESULT PARSING
# ============================================================

parse_results() {
    local output="$1"
    reset_results

    local _slug="" _title="" _summary="" _tags="" _era="" _company=""
    local _words="" _snippet=""

    while IFS= read -r line; do
        case "${line}" in
            COUNT=*)
                _V_COUNT="${line#COUNT=}"
                ;;
            RESULT_BEGIN)
                _slug="" _title="" _summary="" _tags=""
                _era="" _company="" _words="" _snippet=""
                ;;
            SLUG=*)    _slug="${line#SLUG=}" ;;
            TITLE=*)   _title="${line#TITLE=}" ;;
            SUMMARY=*) _summary="${line#SUMMARY=}" ;;
            TAGS=*)    _tags="${line#TAGS=}" ;;
            ERA=*)     _era="${line#ERA=}" ;;
            COMPANY=*) _company="${line#COMPANY=}" ;;
            WORDS=*)   _words="${line#WORDS=}" ;;
            SNIPPET=*) _snippet="${line#SNIPPET=}" ;;
            RESULT_END)
                _V_SLUGS+=("${_slug}")
                _V_TITLES+=("${_title}")
                _V_SUMMARIES+=("${_summary}")
                _V_TAGS+=("${_tags}")
                _V_ERAS+=("${_era}")
                _V_COMPANIES+=("${_company}")
                _V_WORDS+=("${_words}")
                _V_SNIPPETS+=("${_snippet}")
                ;;
        esac
    done <<< "${output}"
}

parse_entry() {
    local output="$1"
    reset_detail

    while IFS= read -r line; do
        case "${line}" in
            FOUND=0)  return 1 ;;
            SLUG=*)     _D_SLUG="${line#SLUG=}" ;;
            TITLE=*)    _D_TITLE="${line#TITLE=}" ;;
            SUMMARY=*)  _D_SUMMARY="${line#SUMMARY=}" ;;
            TAGS=*)     _D_TAGS="${line#TAGS=}" ;;
            CATEGORY=*) _D_CATEGORY="${line#CATEGORY=}" ;;
            ERA=*)      _D_ERA="${line#ERA=}" ;;
            COMPANY=*)  _D_COMPANY="${line#COMPANY=}" ;;
            ROLE=*)     _D_ROLE="${line#ROLE=}" ;;
            STATUS=*)   _D_STATUS="${line#STATUS=}" ;;
            WORDS=*)    _D_WORDS="${line#WORDS=}" ;;
            DATE=*)     _D_DATE="${line#DATE=}" ;;
            BODY_LINE=*)
                _D_BODY_LINES+=("${line#BODY_LINE=}")
                ;;
        esac
    done <<< "${output}"
}

parse_images() {
    local output="$1"
    reset_images

    local _fname="" _slug="" _size="" _fmt=""
    local _desc="" _warmth="" _palname="" _dominant=""

    while IFS= read -r line; do
        case "${line}" in
            COUNT=*)
                _I_COUNT="${line#COUNT=}"
                ;;
            IMG_BEGIN)
                _fname="" _slug="" _size="" _fmt=""
                _desc="" _warmth="" _palname="" _dominant=""
                ;;
            FILENAME=*)     _fname="${line#FILENAME=}" ;;
            SLUG=*)         _slug="${line#SLUG=}" ;;
            SIZE=*)         _size="${line#SIZE=}" ;;
            FORMAT=*)       _fmt="${line#FORMAT=}" ;;
            DESCRIPTION=*)  _desc="${line#DESCRIPTION=}" ;;
            WARMTH=*)       _warmth="${line#WARMTH=}" ;;
            PALETTE_NAME=*) _palname="${line#PALETTE_NAME=}" ;;
            DOMINANT=*)     _dominant="${line#DOMINANT=}" ;;
            IMG_END)
                _I_FILENAMES+=("${_fname}")
                _I_SLUGS+=("${_slug}")
                _I_SIZES+=("${_size}")
                _I_FORMATS+=("${_fmt}")
                _I_DESCRIPTIONS+=("${_desc}")
                _I_WARMTHS+=("${_warmth}")
                _I_PALETTE_NAMES+=("${_palname}")
                _I_DOMINANTS+=("${_dominant}")
                ;;
        esac
    done <<< "${output}"
}

parse_image_entries() {
    local output="$1"
    reset_image_entries

    local _slug="" _title="" _icount="" _tsize=""

    while IFS= read -r line; do
        case "${line}" in
            COUNT=*)
                _IE_COUNT="${line#COUNT=}"
                ;;
            ENTRY_BEGIN)
                _slug="" _title="" _icount="" _tsize=""
                ;;
            SLUG=*)        _slug="${line#SLUG=}" ;;
            TITLE=*)       _title="${line#TITLE=}" ;;
            IMAGE_COUNT=*) _icount="${line#IMAGE_COUNT=}" ;;
            TOTAL_SIZE=*)  _tsize="${line#TOTAL_SIZE=}" ;;
            ENTRY_END)
                _IE_SLUGS+=("${_slug}")
                _IE_TITLES+=("${_title}")
                _IE_IMAGE_COUNTS+=("${_icount}")
                _IE_TOTAL_SIZES+=("${_tsize}")
                ;;
        esac
    done <<< "${output}"
}

# ============================================================
# TUI SCREENS
# ============================================================

_vault_header() {
    local title="${1:-Vault Query}"
    tput clear 2>/dev/null || printf "\033[2J\033[H"
    echo ""
    vrgb_gradient_bar 45 65 45 190 65 55 "${_TUI_COLS}"
    echo ""
    echo ""
    _tui_center "${_C_BOLD}${title}${_C_RESET}"
    echo ""
}

show_main_menu() {
    _vault_header "Vault Query"
    _tui_center "${_C_DIM}Search and browse the portfolio vault${_C_RESET}"
    echo ""
    echo ""

    if tui_menu "Select an action" \
        "Search" \
        "Browse by Tag" \
        "Browse by Era" \
        "Browse Images" \
        "All Entries" \
        "Quit"; then
        return 0
    else
        return 1
    fi
}

show_result_list() {
    local title="$1"
    local count=${#_V_TITLES[@]}

    if [[ "${count}" -eq 0 ]]; then
        echo ""
        echo "  ${_C_DIM}No results found.${_C_RESET}"
        echo ""
        echo "  ${_C_DIM}Press any key to continue...${_C_RESET}"
        _tui_read_key
        _tui_restore_stty
        return 1
    fi

    local labels=()
    local i=0
    while [[ "${i}" -lt "${count}" ]]; do
        local label="${_V_TITLES[${i}]}"
        if [[ -n "${_V_COMPANIES[${i}]}" ]]; then
            label="${label}  ${_C_DIM}(${_V_COMPANIES[${i}]})${_C_RESET}"
        fi
        labels+=("${label}")
        i=$((i + 1))
    done
    labels+=("Back")

    if tui_menu "${title}" "${labels[@]}"; then
        if [[ "${TUI_INDEX}" -ge "${count}" ]]; then
            return 1
        fi
        return 0
    else
        return 1
    fi
}

# show_detail loops on its actions menu internally.
# Returns when user selects Back or presses Escape.
show_detail() {
    local slug="$1"

    local output
    output="$(vault_get_entry "${slug}")" || {
        echo "  ${_C_RED}Error querying entry.${_C_RESET}"
        echo "  ${_C_DIM}Press any key to continue...${_C_RESET}"
        _tui_read_key
        _tui_restore_stty
        return 1
    }

    if ! parse_entry "${output}"; then
        echo "  ${_C_RED}Entry not found: ${slug}${_C_RESET}"
        echo "  ${_C_DIM}Press any key to continue...${_C_RESET}"
        _tui_read_key
        _tui_restore_stty
        return 1
    fi

    # Check image count for this entry
    local img_output
    img_output="$(vault_images_for_slug "${slug}")" 2>/dev/null || true
    local img_count=0
    local count_line=""
    count_line="$(echo "${img_output}" | head -1)"
    if [[ "${count_line}" = COUNT=* ]]; then
        img_count="${count_line#COUNT=}"
    fi

    while true; do
        _vault_header "${_D_TITLE}"

        # Metadata panel
        local panel_args=()
        [[ -n "${_D_CATEGORY}" ]] && panel_args+=("Category={green}${_D_CATEGORY}{reset}")
        [[ -n "${_D_COMPANY}" ]] && panel_args+=("Company={cyan}${_D_COMPANY}{reset}")
        [[ -n "${_D_ROLE}" ]]    && panel_args+=("Role={yellow}${_D_ROLE}{reset}")
        [[ -n "${_D_ERA}" ]]     && panel_args+=("Era={magenta}${_D_ERA}{reset}")
        [[ -n "${_D_TAGS}" ]]    && panel_args+=("Tags={dim}${_D_TAGS}{reset}")
        [[ "${_D_WORDS}" -gt 0 ]] && panel_args+=("Words=${_D_WORDS}")
        [[ "${img_count}" -gt 0 ]] && panel_args+=("Images={green}${img_count}{reset}")
        [[ -n "${_D_STATUS}" ]]  && panel_args+=("Status=${_D_STATUS}")
        [[ -n "${_D_DATE}" ]]    && panel_args+=("Date=${_D_DATE}")

        tui_panel "${_D_SLUG}" "${panel_args[@]}"

        # Summary
        if [[ -n "${_D_SUMMARY}" ]]; then
            echo ""
            echo "  ${_C_BOLD}Summary${_C_RESET}"
            echo "  ${_D_SUMMARY}"
        fi

        echo ""

        # Build actions menu
        local actions=()
        actions+=("View body text")
        if [[ "${img_count}" -gt 0 ]]; then
            actions+=("View images (${img_count})")
        fi
        actions+=("Back")

        if tui_menu "Actions" "${actions[@]}"; then
            local action="${TUI_RESULT}"
            case "${action}" in
                "View body text")
                    show_body
                    ;;
                "View images"*)
                    parse_images "${img_output}"
                    show_images_for_entry "${slug}"
                    ;;
                "Back")
                    return 0
                    ;;
            esac
        else
            # Escape pressed -- same as Back
            return 0
        fi
    done
}

show_body() {
    local line_count=${#_D_BODY_LINES[@]}
    if [[ "${line_count}" -eq 0 ]]; then
        echo ""
        echo "  ${_C_DIM}No body text available.${_C_RESET}"
        echo ""
        echo "  ${_C_DIM}Press any key to go back...${_C_RESET}"
        _tui_read_key
        _tui_restore_stty
        return 0
    fi

    _vault_header "${_D_TITLE} -- Body"

    local i=0
    while [[ "${i}" -lt "${line_count}" ]]; do
        local bline="${_D_BODY_LINES[${i}]}"
        case "${bline}" in
            "# "*)
                echo "  ${_C_BOLD}${_C_WHITE}${bline}${_C_RESET}"
                ;;
            "## "*)
                echo "  ${_C_BOLD}${_C_CYAN}${bline}${_C_RESET}"
                ;;
            "### "*)
                echo "  ${_C_BOLD}${_C_GREEN}${bline}${_C_RESET}"
                ;;
            "- "*|"* "*)
                echo "  ${_C_DIM}${bline}${_C_RESET}"
                ;;
            "")
                echo ""
                ;;
            *)
                echo "  ${bline}"
                ;;
        esac
        i=$((i + 1))
    done

    echo ""
    vrgb_gradient_bar 190 65 55 45 65 45 "${_TUI_COLS}"
    echo ""
    echo ""
    echo "  ${_C_DIM}Press any key to go back...${_C_RESET}"
    _tui_read_key
    _tui_restore_stty
}

# ---- Image screens ----

show_image_list() {
    local title="$1"
    local count=${#_I_FILENAMES[@]}

    if [[ "${count}" -eq 0 ]]; then
        echo ""
        echo "  ${_C_DIM}No images found.${_C_RESET}"
        echo ""
        echo "  ${_C_DIM}Press any key to go back...${_C_RESET}"
        _tui_read_key
        _tui_restore_stty
        return 1
    fi

    local labels=()
    local i=0
    while [[ "${i}" -lt "${count}" ]]; do
        local meta_parts="${_I_SLUGS[${i}]}"
        # Show warmth + palette_name when available, otherwise fall back to size
        if [[ -n "${_I_WARMTHS[${i}]:-}" && -n "${_I_PALETTE_NAMES[${i}]:-}" ]]; then
            meta_parts="${meta_parts} / ${_I_WARMTHS[${i}]} / ${_I_PALETTE_NAMES[${i}]}"
        else
            meta_parts="${meta_parts} / ${_I_SIZES[${i}]}"
        fi
        local label="${_I_FILENAMES[${i}]}  ${_C_DIM}(${meta_parts})${_C_RESET}"
        labels+=("${label}")
        i=$((i + 1))
    done
    labels+=("Back")

    if tui_menu "${title}" "${labels[@]}"; then
        if [[ "${TUI_INDEX}" -ge "${count}" ]]; then
            return 1
        fi
        return 0
    else
        return 1
    fi
}

show_image_detail() {
    local idx="$1"
    local fname="${_I_FILENAMES[${idx}]}"
    local slug="${_I_SLUGS[${idx}]}"
    local size="${_I_SIZES[${idx}]}"
    local fmt="${_I_FORMATS[${idx}]}"
    local desc="${_I_DESCRIPTIONS[${idx}]:-}"
    local warmth="${_I_WARMTHS[${idx}]:-}"
    local palname="${_I_PALETTE_NAMES[${idx}]:-}"
    local dominant="${_I_DOMINANTS[${idx}]:-}"
    local fpath="${IMAGES_DIR}/${slug}/${fname}"

    while true; do
        _vault_header "${fname}"

        local panel_args=()
        panel_args+=("File={green}${fname}{reset}")
        panel_args+=("Entry={cyan}${slug}{reset}")
        panel_args+=("Format={yellow}${fmt}{reset}")
        panel_args+=("Size={magenta}${size}{reset}")
        [[ -n "${desc}" ]]     && panel_args+=("Description={dim}${desc}{reset}")
        [[ -n "${warmth}" ]]   && panel_args+=("Warmth={yellow}${warmth}{reset}")
        [[ -n "${palname}" ]]  && panel_args+=("Palette={green}${palname}{reset}")
        [[ -n "${dominant}" ]] && panel_args+=("Dominant={cyan}${dominant}{reset}")
        panel_args+=("Path={dim}${fpath}{reset}")

        tui_panel "${slug}/${fname}" "${panel_args[@]}"

        echo ""

        if tui_menu "Actions" "Open in viewer" "Copy path" "Back"; then
            case "${TUI_INDEX}" in
                0)
                    # Open with system viewer
                    open "${fpath}" 2>/dev/null || {
                        echo "  ${_C_RED}Could not open file.${_C_RESET}"
                        echo "  ${_C_DIM}Press any key to continue...${_C_RESET}"
                        _tui_read_key
                        _tui_restore_stty
                    }
                    ;;
                1)
                    # Copy path to clipboard
                    printf "%s" "${fpath}" | pbcopy 2>/dev/null || {
                        echo "  ${_C_RED}Could not copy to clipboard.${_C_RESET}"
                    }
                    echo ""
                    echo "  ${_C_GREEN}Path copied to clipboard.${_C_RESET}"
                    echo "  ${_C_DIM}Press any key to continue...${_C_RESET}"
                    _tui_read_key
                    _tui_restore_stty
                    ;;
                2)
                    return 0
                    ;;
            esac
        else
            return 0
        fi
    done
}

show_images_for_entry() {
    local slug="$1"

    while true; do
        _vault_header "Images: ${slug}  ${_C_DIM}(${_I_COUNT})${_C_RESET}"

        if show_image_list "Select an image"; then
            show_image_detail "${TUI_INDEX}"
        else
            return 0
        fi
    done
}

# ============================================================
# FLOW FUNCTIONS
# ============================================================

# Shared helper: loops over result list + detail.
# Escape from detail returns to result list.
# Escape from result list returns to caller.
_browse_results() {
    local header_title="$1"

    while true; do
        _vault_header "${header_title}  ${_C_DIM}(${_V_COUNT} found)${_C_RESET}"

        if show_result_list "Select an entry"; then
            local selected_slug="${_V_SLUGS[${TUI_INDEX}]}"
            show_detail "${selected_slug}"
        else
            return 0
        fi
    done
}

do_search() {
    _vault_header "Search"
    if ! tui_input "Enter search query"; then
        return 0
    fi

    local query="${TUI_RESULT}"
    if [[ -z "${query}" ]]; then
        return 0
    fi

    _vault_header "Results: ${query}"
    echo "  ${_C_DIM}Searching...${_C_RESET}"

    local output
    output="$(vault_search "${query}")" || {
        echo "  ${_C_RED}Search failed.${_C_RESET}"
        echo "  ${_C_DIM}Press any key to go back...${_C_RESET}"
        _tui_read_key
        _tui_restore_stty
        return 0
    }

    parse_results "${output}"
    _browse_results "Results: ${query}"
}

do_browse_tags() {
    _vault_header "Browse by Tag"
    echo "  ${_C_DIM}Loading tags...${_C_RESET}"

    local tag_output
    tag_output="$(vault_list_tags)" || {
        echo "  ${_C_RED}Failed to load tags.${_C_RESET}"
        echo "  ${_C_DIM}Press any key to go back...${_C_RESET}"
        _tui_read_key
        _tui_restore_stty
        return 0
    }

    local tags=()
    while IFS= read -r tag; do
        [[ -n "${tag}" ]] && tags+=("${tag}")
    done <<< "${tag_output}"

    if [[ ${#tags[@]} -eq 0 ]]; then
        echo "  ${_C_DIM}No tags found.${_C_RESET}"
        echo "  ${_C_DIM}Press any key to go back...${_C_RESET}"
        _tui_read_key
        _tui_restore_stty
        return 0
    fi

    local tag_count=${#tags[@]}

    while true; do
        _vault_header "Browse by Tag"

        if tui_menu "Select a tag" "${tags[@]}" "Back"; then
            if [[ "${TUI_INDEX}" -ge "${tag_count}" ]]; then
                return 0
            fi
        else
            return 0
        fi

        local selected_tag="${TUI_RESULT}"

        _vault_header "Tag: ${selected_tag}"
        echo "  ${_C_DIM}Filtering...${_C_RESET}"

        local output
        output="$(vault_filter_by_tag "${selected_tag}")" || {
            echo "  ${_C_RED}Filter failed.${_C_RESET}"
            echo "  ${_C_DIM}Press any key to go back...${_C_RESET}"
            _tui_read_key
            _tui_restore_stty
            continue
        }

        parse_results "${output}"
        _browse_results "Tag: ${selected_tag}"
    done
}

do_browse_eras() {
    _vault_header "Browse by Era"
    echo "  ${_C_DIM}Loading eras...${_C_RESET}"

    local era_output
    era_output="$(vault_list_eras)" || {
        echo "  ${_C_RED}Failed to load eras.${_C_RESET}"
        echo "  ${_C_DIM}Press any key to go back...${_C_RESET}"
        _tui_read_key
        _tui_restore_stty
        return 0
    }

    local eras=()
    while IFS= read -r era; do
        [[ -n "${era}" ]] && eras+=("${era}")
    done <<< "${era_output}"

    if [[ ${#eras[@]} -eq 0 ]]; then
        echo "  ${_C_DIM}No eras found.${_C_RESET}"
        echo "  ${_C_DIM}Press any key to go back...${_C_RESET}"
        _tui_read_key
        _tui_restore_stty
        return 0
    fi

    local era_count=${#eras[@]}

    while true; do
        _vault_header "Browse by Era"

        if tui_menu "Select an era" "${eras[@]}" "Back"; then
            if [[ "${TUI_INDEX}" -ge "${era_count}" ]]; then
                return 0
            fi
        else
            return 0
        fi

        local selected_era="${TUI_RESULT}"

        _vault_header "Era: ${selected_era}"
        echo "  ${_C_DIM}Filtering...${_C_RESET}"

        local output
        output="$(vault_filter_by_era "${selected_era}")" || {
            echo "  ${_C_RED}Filter failed.${_C_RESET}"
            echo "  ${_C_DIM}Press any key to go back...${_C_RESET}"
            _tui_read_key
            _tui_restore_stty
            continue
        }

        parse_results "${output}"
        _browse_results "Era: ${selected_era}"
    done
}

do_browse_images() {
    while true; do
        _vault_header "Browse Images"
        _tui_center "${_C_DIM}Search and browse vault images${_C_RESET}"
        echo ""
        echo ""

        if tui_menu "Select an action" \
            "Search images" \
            "Browse by entry" \
            "Slideshow" \
            "All images" \
            "Back"; then
            case "${TUI_INDEX}" in
                0) _do_image_search ;;
                1) _do_images_by_entry ;;
                2) _do_slideshow ;;
                3) _do_all_images ;;
                4) return 0 ;;
            esac
        else
            return 0
        fi
    done
}

_do_image_search() {
    _vault_header "Image Search"
    if ! tui_input "Search by content, filename, or slug"; then
        return 0
    fi

    local query="${TUI_RESULT}"
    if [[ -z "${query}" ]]; then
        return 0
    fi

    _vault_header "Image Results: ${query}"
    echo "  ${_C_DIM}Searching...${_C_RESET}"

    local output
    output="$(vault_search_images "${query}")" || {
        echo "  ${_C_RED}Image search failed.${_C_RESET}"
        echo "  ${_C_DIM}Press any key to go back...${_C_RESET}"
        _tui_read_key
        _tui_restore_stty
        return 0
    }

    parse_images "${output}"
    _browse_image_list "Image Results: ${query}"
}

_do_images_by_entry() {
    _vault_header "Images by Entry"
    echo "  ${_C_DIM}Loading...${_C_RESET}"

    local output
    output="$(vault_image_entries)" || {
        echo "  ${_C_RED}Failed to load entries.${_C_RESET}"
        echo "  ${_C_DIM}Press any key to go back...${_C_RESET}"
        _tui_read_key
        _tui_restore_stty
        return 0
    }

    parse_image_entries "${output}"

    if [[ "${_IE_COUNT}" -eq 0 ]]; then
        echo "  ${_C_DIM}No entries with images.${_C_RESET}"
        echo "  ${_C_DIM}Press any key to go back...${_C_RESET}"
        _tui_read_key
        _tui_restore_stty
        return 0
    fi

    while true; do
        _vault_header "Images by Entry  ${_C_DIM}(${_IE_COUNT} entries)${_C_RESET}"

        # Build labels: title (N images, size)
        local labels=()
        local i=0
        while [[ "${i}" -lt "${_IE_COUNT}" ]]; do
            local label="${_IE_TITLES[${i}]}  ${_C_DIM}(${_IE_IMAGE_COUNTS[${i}]} images, ${_IE_TOTAL_SIZES[${i}]})${_C_RESET}"
            labels+=("${label}")
            i=$((i + 1))
        done

        labels+=("Back")

        if tui_menu "Select an entry" "${labels[@]}"; then
            if [[ "${TUI_INDEX}" -ge "${_IE_COUNT}" ]]; then
                return 0
            fi

            local sel_slug="${_IE_SLUGS[${TUI_INDEX}]}"

            local img_output
            img_output="$(vault_images_for_slug "${sel_slug}")" || continue
            parse_images "${img_output}"
            _browse_image_list "Images: ${sel_slug}"
        else
            return 0
        fi
    done
}

_do_all_images() {
    _vault_header "All Images"
    echo "  ${_C_DIM}Loading...${_C_RESET}"

    local output
    output="$(vault_all_images)" || {
        echo "  ${_C_RED}Failed to load images.${_C_RESET}"
        echo "  ${_C_DIM}Press any key to go back...${_C_RESET}"
        _tui_read_key
        _tui_restore_stty
        return 0
    }

    parse_images "${output}"
    _browse_image_list "All Images"
}

# Shared helper: loops over image list + detail.
# Escape from detail returns to image list.
# Escape from image list returns to caller.
_browse_image_list() {
    local header_title="$1"

    while true; do
        _vault_header "${header_title}  ${_C_DIM}(${_I_COUNT})${_C_RESET}"

        if show_image_list "Select an image"; then
            show_image_detail "${TUI_INDEX}"
        else
            return 0
        fi
    done
}

_do_slideshow() {
    _vault_header "Slideshow"
    echo "  ${_C_DIM}Loading entries with images...${_C_RESET}"

    local output
    output="$(vault_image_entries)" || {
        echo "  ${_C_RED}Failed to load entries.${_C_RESET}"
        echo "  ${_C_DIM}Press any key to go back...${_C_RESET}"
        _tui_read_key
        _tui_restore_stty
        return 0
    }

    parse_image_entries "${output}"

    if [[ "${_IE_COUNT}" -eq 0 ]]; then
        echo "  ${_C_DIM}No entries with images.${_C_RESET}"
        echo "  ${_C_DIM}Press any key to go back...${_C_RESET}"
        _tui_read_key
        _tui_restore_stty
        return 0
    fi

    # Pick entry
    local labels=()
    local i=0
    while [[ "${i}" -lt "${_IE_COUNT}" ]]; do
        local label="${_IE_TITLES[${i}]}  ${_C_DIM}(${_IE_IMAGE_COUNTS[${i}]} images)${_C_RESET}"
        labels+=("${label}")
        i=$((i + 1))
    done
    labels+=("Back")

    while true; do
        _vault_header "Slideshow  ${_C_DIM}(pick an entry)${_C_RESET}"

        if tui_menu "Select an entry" "${labels[@]}"; then
            if [[ "${TUI_INDEX}" -ge "${_IE_COUNT}" ]]; then
                return 0
            fi

            local sel_slug="${_IE_SLUGS[${TUI_INDEX}]}"
            local sel_title="${_IE_TITLES[${TUI_INDEX}]}"

            local img_output
            img_output="$(vault_images_for_slug "${sel_slug}")" || continue
            parse_images "${img_output}"

            if [[ "${_I_COUNT}" -eq 0 ]]; then
                continue
            fi

            # Slideshow loop
            local slide_idx=0
            while true; do
                local fname="${_I_FILENAMES[${slide_idx}]}"
                local slug="${_I_SLUGS[${slide_idx}]}"
                local desc="${_I_DESCRIPTIONS[${slide_idx}]:-}"
                local warmth="${_I_WARMTHS[${slide_idx}]:-}"
                local palname="${_I_PALETTE_NAMES[${slide_idx}]:-}"
                local dominant="${_I_DOMINANTS[${slide_idx}]:-}"
                local fpath="${IMAGES_DIR}/${slug}/${fname}"

                local display_num=$((slide_idx + 1))
                _vault_header "${sel_title}  ${_C_DIM}(${display_num}/${_I_COUNT})${_C_RESET}"

                local panel_args=()
                panel_args+=("File={green}${fname}{reset}")
                [[ -n "${desc}" ]]     && panel_args+=("Description={dim}${desc}{reset}")
                [[ -n "${warmth}" ]]   && panel_args+=("Warmth={yellow}${warmth}{reset}")
                [[ -n "${palname}" ]]  && panel_args+=("Palette={green}${palname}{reset}")
                [[ -n "${dominant}" ]] && panel_args+=("Dominant={cyan}${dominant}{reset}")

                tui_panel "${slug}/${fname}" "${panel_args[@]}"
                echo ""

                # Build nav menu
                local nav=()
                if [[ "${_I_COUNT}" -gt 1 ]]; then
                    nav+=("Next")
                    nav+=("Previous")
                fi
                nav+=("Open in Viewer")
                nav+=("Back")

                if tui_menu "Navigate" "${nav[@]}"; then
                    case "${TUI_RESULT}" in
                        "Next")
                            slide_idx=$(( (slide_idx + 1) % _I_COUNT ))
                            ;;
                        "Previous")
                            slide_idx=$(( (slide_idx - 1 + _I_COUNT) % _I_COUNT ))
                            ;;
                        "Open in Viewer")
                            open "${fpath}" 2>/dev/null || {
                                echo "  ${_C_RED}Could not open file.${_C_RESET}"
                                echo "  ${_C_DIM}Press any key to continue...${_C_RESET}"
                                _tui_read_key
                                _tui_restore_stty
                            }
                            ;;
                        "Back")
                            break
                            ;;
                    esac
                else
                    break
                fi
            done
        else
            return 0
        fi
    done
}

do_all_entries() {
    _vault_header "All Entries"
    echo "  ${_C_DIM}Loading...${_C_RESET}"

    local output
    output="$(vault_all_entries)" || {
        echo "  ${_C_RED}Failed to load entries.${_C_RESET}"
        echo "  ${_C_DIM}Press any key to go back...${_C_RESET}"
        _tui_read_key
        _tui_restore_stty
        return 0
    }

    parse_results "${output}"
    _browse_results "All Entries"
}

# ============================================================
# MAIN
# ============================================================

while true; do
    if show_main_menu; then
        case "${TUI_INDEX}" in
            0) do_search ;;
            1) do_browse_tags ;;
            2) do_browse_eras ;;
            3) do_browse_images ;;
            4) do_all_entries ;;
            5) exit 0 ;;
        esac
    else
        exit 0
    fi
done
