#!/usr/bin/env bash
# ============================================================
#  CUE-BUFF-UTIL  --  Buffer cue-sheet inputs offline (VRGB)
# ============================================================
#  Walks a cue-sheet in the terminal with NO model.
#  Captures all user responses to a structured buffer file
#  that can be handed to a model later for action.
#
#  Launch:  rom-launch buff
#  Direct:  bash arcade/roms/cue-buff-util.sh [sheet.yaml]
#  Output:  vault-hot/HOT/cue-buff-out/<slug>-<YYYYMMDD-HHMMSS>.txt
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/lib/tui.sh"
source "${SCRIPT_DIR}/lib/vrgb.sh"

BUFFERED_DIR="${SCRIPT_DIR}/vault-hot/HOT/cue-buff-out"
CUESHEET_DIR="${SCRIPT_DIR}/cue-sheets"

# ============================================================
# STATE
# ============================================================

_BUFF_NAME=""
_BUFF_DESC=""
_BUFF_FORMAT=""

_BUFF_ITEM_IDS=()
_BUFF_ITEM_TYPES=()
_BUFF_ITEM_LABELS=()
_BUFF_ITEM_OPTS=()
_BUFF_ITEM_SCALE_LO=()
_BUFF_ITEM_SCALE_HI=()
_BUFF_ITEM_DETAILS=()
_BUFF_ITEM_DEFAULTS=()
_BUFF_ITEM_PRESSURE_ZONE=()

_BUFF_CUE_IDS=()
_BUFF_CUE_TEXTS=()

_BUFF_VALUES=()
_BUFF_OUTPUT_PATH=""

_PICKED_FILE=""

reset_state() {
    _BUFF_NAME=""
    _BUFF_DESC=""
    _BUFF_FORMAT=""
    _BUFF_ITEM_IDS=()
    _BUFF_ITEM_TYPES=()
    _BUFF_ITEM_LABELS=()
    _BUFF_ITEM_OPTS=()
    _BUFF_ITEM_SCALE_LO=()
    _BUFF_ITEM_SCALE_HI=()
    _BUFF_ITEM_DETAILS=()
    _BUFF_ITEM_DEFAULTS=()
    _BUFF_ITEM_PRESSURE_ZONE=()
    _BUFF_CUE_IDS=()
    _BUFF_CUE_TEXTS=()
    _BUFF_VALUES=()
    _BUFF_OUTPUT_PATH=""
    _PICKED_FILE=""
}

# ============================================================
# CUE-SHEET FILE PICKER
# ============================================================

pick_cuesheet() {
    local files=()
    local labels=()

    [[ -d "${CUESHEET_DIR}" ]] || {
        echo "  ${_C_RED}No cue-sheets directory found.${_C_RESET}" >&2
        exit 1
    }

    local f=""
    while IFS= read -r f; do
        [[ -f "${f}" ]] || continue
        files+=("${f}")
        labels+=("$(basename "${f}")")
    done < <(find "${CUESHEET_DIR}" -maxdepth 1 -name '*.yaml' 2>/dev/null | sort)

    if [[ ${#labels[@]} -eq 0 ]]; then
        echo "  ${_C_RED}No cue-sheets found.${_C_RESET}" >&2
        exit 1
    fi

    if tui_menu "Select a cue-sheet" "${labels[@]}"; then
        _PICKED_FILE="${files[${TUI_INDEX}]}"
    else
        return 1
    fi
}

# ============================================================
# YAML PARSER  (inline Python -> structured line format)
# ============================================================
#
# Output:
#   META_NAME=<name>
#   META_DESC=<description>
#   META_FORMAT=<inputs|steps|cues>
#   ===
#   ITEM_BEGIN / ID= / TYPE= / LABEL= / OPT= / SCALE_*= / DETAIL= / ITEM_END
#   ===
#   CUE_BEGIN / ID= / TEXT= / CUE_END

parse_cuesheet() {
    python3 - "$1" << 'PYEOF'
import yaml, sys, re, json
from pathlib import Path

sheet_path = Path(sys.argv[1]).resolve()
repo_root = sheet_path.parents[1]
pressure_lib = repo_root / "cue-sheets" / "lib"
if str(pressure_lib) not in sys.path:
    sys.path.insert(0, str(pressure_lib))
try:
    from pressure import calculate_system_pressure, pressure_zone, adjust_slider_default
except Exception:
    def calculate_system_pressure(_tokens_dir):
        return 0.0
    def pressure_zone(_pressure):
        return "idle"
    def adjust_slider_default(_pressure, low_default=0.2, high_default=0.8):
        return low_default

with open(sys.argv[1]) as f:
    data = yaml.safe_load(f)

tokens_dir = repo_root / ".claude" / "tokens"
system_pressure = calculate_system_pressure(str(tokens_dir))
system_zone = pressure_zone(system_pressure)

name = str(data.get('name', data.get('cuesheet', 'Untitled')))
desc = str(data.get('description', ''))

if 'inputs' in data:
    fmt = 'inputs'
elif 'steps' in data:
    fmt = 'steps'
elif 'cues' in data:
    fmt = 'cues'
else:
    fmt = 'unknown'

print('META_NAME=' + name)
print('META_DESC=' + desc)
print('META_FORMAT=' + fmt)
print('===')

if fmt == 'inputs':
    for inp in data.get('inputs', []):
        print('ITEM_BEGIN')
        print('ID=' + inp.get('id', 'unknown'))
        itype = inp.get('type', 'text')
        print('TYPE=' + itype)
        print('LABEL=' + str(inp.get('prompt', inp.get('id', ''))))
        if itype == 'slider':
            scale = inp.get('scale', {})
            print('SCALE_LOW=' + scale.get('low', 'low'))
            print('SCALE_HIGH=' + scale.get('high', 'high'))
            if inp.get('pressure_aware', False):
                defaults = inp.get('pressure_defaults', {}) or {}
                low_p = float(defaults.get('low_pressure', 0.2))
                high_p = float(defaults.get('high_pressure', 0.8))
                slider_default = adjust_slider_default(system_pressure, low_default=low_p, high_default=high_p)
                print('SLIDER_DEFAULT=' + str(int(round(slider_default * 100))))
                print('SYSTEM_PRESSURE_ZONE=' + system_zone)
        if itype == 'choice':
            for o in inp.get('options', []):
                print('OPT=' + str(o))
        print('ITEM_END')

elif fmt == 'steps':
    for i, step in enumerate(data.get('steps', [])):
        sid = 'step_' + str(i + 1)
        sname = step.get('name', step.get('action', sid))
        sprompt = step.get('prompt', step.get('content', ''))
        print('ITEM_BEGIN')
        print('ID=' + sid)
        print('TYPE=step_prompt')
        print('LABEL=' + str(sname))
        if sprompt:
            print('DETAIL=' + sprompt.strip().replace('\n', '<BR>'))
        print('ITEM_END')

elif fmt == 'cues':
    for cue in data.get('cues', []):
        cid = cue.get('id', 'unknown')
        text = cue.get('text', '')
        has_input = False

        choice_m = re.search(r'\[CHOICE:\s*(.+?)\]', text)
        yesno_m = re.search(r'\[YES_NO:\s*(.+?)\]', text)
        input_m = re.search(r'\[INPUT:\s*(\{.+?\})\]', text)

        if choice_m:
            parts = [p.strip() for p in choice_m.group(1).split('|')]
            print('ITEM_BEGIN')
            print('ID=' + cid)
            print('TYPE=choice')
            print('LABEL=' + parts[0])
            for o in parts[1:]:
                print('OPT=' + o)
            print('ITEM_END')
            has_input = True
        elif yesno_m:
            print('ITEM_BEGIN')
            print('ID=' + cid)
            print('TYPE=yes_no')
            print('LABEL=' + yesno_m.group(1).strip())
            print('ITEM_END')
            has_input = True
        elif input_m:
            try:
                inp_d = json.loads(input_m.group(1))
                itype = inp_d.get('type', 'text')
                iq = inp_d.get('question', cid)
                print('ITEM_BEGIN')
                print('ID=' + cid)
                print('TYPE=' + itype)
                print('LABEL=' + iq)
                if itype == 'slider':
                    sc = inp_d.get('scale', {})
                    print('SCALE_LOW=' + sc.get('low', 'low'))
                    print('SCALE_HIGH=' + sc.get('high', 'high'))
                    if inp_d.get('pressure_aware', False):
                        defaults = inp_d.get('pressure_defaults', {}) or {}
                        low_p = float(defaults.get('low_pressure', 0.2))
                        high_p = float(defaults.get('high_pressure', 0.8))
                        slider_default = adjust_slider_default(system_pressure, low_default=low_p, high_default=high_p)
                        print('SLIDER_DEFAULT=' + str(int(round(slider_default * 100))))
                        print('SYSTEM_PRESSURE_ZONE=' + system_zone)
                print('ITEM_END')
                has_input = True
            except Exception:
                pass

        if 'input' in cue and not has_input:
            ci = cue['input']
            itype = ci.get('type', 'text')
            iq = ci.get('question', cid)
            print('ITEM_BEGIN')
            print('ID=' + cid)
            print('TYPE=' + itype)
            print('LABEL=' + iq)
            if itype == 'slider':
                sc = ci.get('scale', {})
                print('SCALE_LOW=' + sc.get('low', 'low'))
                print('SCALE_HIGH=' + sc.get('high', 'high'))
                if ci.get('pressure_aware', False):
                    defaults = ci.get('pressure_defaults', {}) or {}
                    low_p = float(defaults.get('low_pressure', 0.2))
                    high_p = float(defaults.get('high_pressure', 0.8))
                    slider_default = adjust_slider_default(system_pressure, low_default=low_p, high_default=high_p)
                    print('SLIDER_DEFAULT=' + str(int(round(slider_default * 100))))
                    print('SYSTEM_PRESSURE_ZONE=' + system_zone)
            print('ITEM_END')

print('===')

for cue in data.get('cues', []):
    cid = cue.get('id', 'unknown')
    obj = cue.get('objective', cue.get('text', ''))
    if obj:
        print('CUE_BEGIN')
        print('ID=' + cid)
        print('TEXT=' + obj.replace('\n', ' ').strip())
        print('CUE_END')
PYEOF
}

# ============================================================
# PARSE OUTPUT INTO ARRAYS
# ============================================================

load_parsed() {
    local parsed="$1"
    local section=0
    local _id="" _type="" _label="" _detail=""
    local _scale_lo="" _scale_hi="" _opts="" _slider_default="" _pressure_zone=""
    local _cid="" _ctext=""

    while IFS= read -r line; do
        if [[ "${line}" = "===" ]]; then
            section=$((section + 1))
            continue
        fi
        case "${section}" in
            0)
                case "${line}" in
                    META_NAME=*)   _BUFF_NAME="${line#META_NAME=}" ;;
                    META_DESC=*)   _BUFF_DESC="${line#META_DESC=}" ;;
                    META_FORMAT=*) _BUFF_FORMAT="${line#META_FORMAT=}" ;;
                esac
                ;;
            1)
                case "${line}" in
                    ITEM_BEGIN)
                        _id="" _type="" _label="" _detail=""
                        _scale_lo="" _scale_hi="" _opts="" _slider_default="" _pressure_zone=""
                        ;;
                    ID=*)         _id="${line#ID=}" ;;
                    TYPE=*)       _type="${line#TYPE=}" ;;
                    LABEL=*)      _label="${line#LABEL=}" ;;
                    OPT=*)
                        if [[ -n "${_opts}" ]]; then
                            _opts="${_opts}|${line#OPT=}"
                        else
                            _opts="${line#OPT=}"
                        fi
                        ;;
                    SCALE_LOW=*)  _scale_lo="${line#SCALE_LOW=}" ;;
                    SCALE_HIGH=*) _scale_hi="${line#SCALE_HIGH=}" ;;
                    SLIDER_DEFAULT=*) _slider_default="${line#SLIDER_DEFAULT=}" ;;
                    SYSTEM_PRESSURE_ZONE=*) _pressure_zone="${line#SYSTEM_PRESSURE_ZONE=}" ;;
                    DETAIL=*)     _detail="${line#DETAIL=}" ;;
                    ITEM_END)
                        _BUFF_ITEM_IDS+=("${_id}")
                        _BUFF_ITEM_TYPES+=("${_type}")
                        _BUFF_ITEM_LABELS+=("${_label}")
                        _BUFF_ITEM_OPTS+=("${_opts}")
                        _BUFF_ITEM_SCALE_LO+=("${_scale_lo}")
                        _BUFF_ITEM_SCALE_HI+=("${_scale_hi}")
                        _BUFF_ITEM_DETAILS+=("${_detail}")
                        _BUFF_ITEM_DEFAULTS+=("${_slider_default}")
                        _BUFF_ITEM_PRESSURE_ZONE+=("${_pressure_zone}")
                        ;;
                esac
                ;;
            2)
                case "${line}" in
                    CUE_BEGIN) _cid="" _ctext="" ;;
                    ID=*)      _cid="${line#ID=}" ;;
                    TEXT=*)    _ctext="${line#TEXT=}" ;;
                    CUE_END)
                        _BUFF_CUE_IDS+=("${_cid}")
                        _BUFF_CUE_TEXTS+=("${_ctext}")
                        ;;
                esac
                ;;
        esac
    done <<< "${parsed}"
}

# ============================================================
# TUI INTERACTION
# ============================================================

collect_inputs() {
    local count=${#_BUFF_ITEM_IDS[@]}
    if [[ "${count}" -eq 0 ]]; then
        echo ""
        echo "  ${_C_DIM}No inputs to collect.${_C_RESET}"
        return 0
    fi

    local i=0
    while [[ "${i}" -lt "${count}" ]]; do
        local id="${_BUFF_ITEM_IDS[${i}]}"
        local itype="${_BUFF_ITEM_TYPES[${i}]}"
        local label="${_BUFF_ITEM_LABELS[${i}]}"
        local opts="${_BUFF_ITEM_OPTS[${i}]}"
        local scale_lo="${_BUFF_ITEM_SCALE_LO[${i}]}"
        local scale_hi="${_BUFF_ITEM_SCALE_HI[${i}]}"
        local detail="${_BUFF_ITEM_DETAILS[${i}]}"
        local slider_default="${_BUFF_ITEM_DEFAULTS[${i}]}"
        local pressure_zone="${_BUFF_ITEM_PRESSURE_ZONE[${i}]}"

        echo ""
        echo "  ${_C_DIM}[$(( i + 1 ))/${count}]${_C_RESET}  ${_C_BOLD}${id}${_C_RESET}"

        case "${itype}" in
            text|number)
                if tui_input "${label}"; then
                    _BUFF_VALUES+=("${TUI_RESULT}")
                else
                    _BUFF_VALUES+=("")
                fi
                ;;
            choice)
                local menu_items=()
                IFS='|' read -ra menu_items <<< "${opts}"
                if tui_menu "${label}" "${menu_items[@]+"${menu_items[@]}"}"; then
                    _BUFF_VALUES+=("${TUI_RESULT}")
                else
                    _BUFF_VALUES+=("")
                fi
                ;;
            yes_no)
                if tui_confirm "${label}"; then
                    _BUFF_VALUES+=("yes")
                else
                    _BUFF_VALUES+=("no")
                fi
                ;;
            slider)
                local pressure_label=""
                if [[ -n "${pressure_zone}" ]]; then
                    pressure_label="  ${_C_DIM}(system: ${pressure_zone})${_C_RESET}"
                fi
                local scale_label="${label}  ${_C_DIM}(${scale_lo} 0..100 ${scale_hi})${_C_RESET}${pressure_label}"
                local placeholder="0-100"
                if [[ -n "${slider_default}" ]]; then
                    placeholder="default ${slider_default}"
                fi
                if tui_input "${scale_label}" --placeholder="${placeholder}"; then
                    local chosen="${TUI_RESULT}"
                    if [[ -z "${chosen}" && -n "${slider_default}" ]]; then
                        chosen="${slider_default}"
                    fi
                    _BUFF_VALUES+=("${chosen}")
                else
                    _BUFF_VALUES+=("")
                fi
                ;;
            step_prompt)
                if [[ -n "${detail}" ]]; then
                    local newline=$'\n'
                    local display="${detail//<BR>/${newline}}"
                    echo ""
                    while IFS= read -r dline; do
                        echo "    ${_C_DIM}${dline}${_C_RESET}"
                    done <<< "${display}"
                fi
                if tui_input "${label}"; then
                    _BUFF_VALUES+=("${TUI_RESULT}")
                else
                    _BUFF_VALUES+=("")
                fi
                ;;
            *)
                if tui_input "${label}"; then
                    _BUFF_VALUES+=("${TUI_RESULT}")
                else
                    _BUFF_VALUES+=("")
                fi
                ;;
        esac

        i=$((i + 1))
    done
}

# ============================================================
# WRITE BUFFER
# ============================================================

write_buffer() {
    local source_file="$1"
    local slug
    slug=$(echo "${_BUFF_NAME}" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd 'a-z0-9-')
    local timestamp
    timestamp=$(date +"%Y%m%d-%H%M%S")
    local buffer_file="${BUFFERED_DIR}/${slug}-${timestamp}.txt"
    local now
    now=$(date +"%Y-%m-%d %H:%M:%S")

    {
        echo "==[ CUE-BUFF ]==========================================="
        echo "Source: ${source_file}"
        echo "Buffered: ${now}"
        echo "Name: ${_BUFF_NAME}"
        echo "Description: ${_BUFF_DESC}"
        echo "========================================================="
        echo ""

        local icount=${#_BUFF_ITEM_IDS[@]}
        if [[ "${icount}" -gt 0 ]]; then
            echo "==[ INPUTS ]=============================================="
            local i=0
            while [[ "${i}" -lt "${icount}" ]]; do
                echo "${_BUFF_ITEM_IDS[${i}]} = ${_BUFF_VALUES[${i}]}"
                i=$((i + 1))
            done
            echo "========================================================="
            echo ""
        fi

        local ccount=${#_BUFF_CUE_IDS[@]}
        if [[ "${ccount}" -gt 0 ]]; then
            echo "==[ CUES ]================================================"
            local j=0
            while [[ "${j}" -lt "${ccount}" ]]; do
                echo "[$(( j + 1 ))] ${_BUFF_CUE_IDS[${j}]}"
                echo "    ${_BUFF_CUE_TEXTS[${j}]}"
                echo ""
                j=$((j + 1))
            done
            echo "========================================================="
            echo ""
        fi

        echo "==[ FULL CUESHEET ]======================================="
        cat "${source_file}"
        echo ""
        echo "========================================================="
    } > "${buffer_file}"

    _BUFF_OUTPUT_PATH="${buffer_file}"
}

# ============================================================
# RUN ONE SHEET
# ============================================================

run_sheet() {
    local yaml_file="$1"

    if [[ ! -f "${yaml_file}" ]]; then
        echo "  ${_C_RED}Error:${_C_RESET} File not found: ${yaml_file}" >&2
        return 1
    fi

    # Parse YAML
    local parsed
    parsed=$(parse_cuesheet "${yaml_file}") || {
        echo "  ${_C_RED}Error:${_C_RESET} Failed to parse: ${yaml_file}" >&2
        return 1
    }
    load_parsed "${parsed}"

    # VRGB header
    echo ""
    vrgb_gradient_bar 270 65 45 190 65 55 "${_TUI_COLS}"
    echo ""
    echo ""
    _tui_center "${_C_BOLD}${_BUFF_NAME}${_C_RESET}"
    echo ""
    if [[ -n "${_BUFF_DESC}" ]]; then
        _tui_center "${_C_DIM}${_BUFF_DESC}${_C_RESET}"
        echo ""
    fi
    echo ""

    # Collect inputs
    collect_inputs

    # Write buffer
    echo ""
    vrgb_gradient_bar 190 65 55 270 65 45 "${_TUI_COLS}"
    echo ""

    write_buffer "${yaml_file}"

    tui_panel "Buffer Written" \
        "File=${_BUFF_OUTPUT_PATH}" \
        "Inputs={green}${#_BUFF_ITEM_IDS[@]}{reset}" \
        "Cues={cyan}${#_BUFF_CUE_IDS[@]}{reset}" \
        "Format=${_BUFF_FORMAT}"

    echo ""
}

# ============================================================
# HOME SCREEN
# ============================================================

show_home() {
    tput clear 2>/dev/null || printf "\033[2J\033[H"
    echo ""
    vrgb_gradient_bar 270 65 45 190 65 55 "${_TUI_COLS}"
    echo ""
    echo ""
    _tui_center "${_C_BOLD}CUE-BUFF${_C_RESET}"
    echo ""
    _tui_center "${_C_DIM}Buffer cue-sheet inputs offline${_C_RESET}"
    echo ""
    _tui_center "${_C_DIM}[Esc] Back${_C_RESET}"
    echo ""
    echo ""
}

# ============================================================
# MAIN
# ============================================================

mkdir -p "${BUFFERED_DIR}"

# Direct invocation with argument: run once
if [[ -n "${1:-}" ]]; then
    if [[ "$1" = "--help" ]] || [[ "$1" = "-h" ]]; then
        echo ""
        echo "  ${_C_BOLD}cue-buff-util${_C_RESET} -- Buffer cue-sheet inputs offline"
        echo ""
        echo "  Usage: cue-buff-util [cuesheet.yaml]"
        echo "  Launch: rom-launch buff"
        echo ""
        exit 0
    fi
    run_sheet "$1"
    exit 0
fi

# Interactive mode: loop with file picker
while true; do
    reset_state
    show_home

    if ! pick_cuesheet; then
        # Escape pressed -- hand off to main maestro menu
        exec bash "${SCRIPT_DIR}/maestro.sh" interactive
    fi

    run_sheet "${_PICKED_FILE}"

    # Wait for keypress before returning to selection
    echo ""
    echo "  ${_C_DIM}Press any key to return to selection...${_C_RESET}"
    _tui_read_key
    _tui_restore_stty
done
