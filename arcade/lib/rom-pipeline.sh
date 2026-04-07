#!/usr/bin/env bash
# ============================================================
#  ROM-PIPELINE.SH  --  ROM Discovery, Validation & Launch
# ============================================================
#  Manages the arcade ROM catalog: discover games, validate
#  them, promote from active/ to roms/, and launch via a
#  standard pipeline.
#
#  Source this file:  source arcade/lib/rom-pipeline.sh
#
#  Public API  (rom_ prefix):
#    rom_catalog        -- read manifest.json, return ROM entries
#    rom_resolve_path   -- given a slug, resolve to absolute path
#    rom_validate       -- static analysis: shebang, sources, syntax
#    rom_launch         -- resolve -> validate -> server check -> exec
#    rom_discover       -- scan active/*/*.sh and roms/*.sh for games
#    rom_promote        -- copy from active/ to roms/, update manifest
#    rom_menu_items     -- build arrays for tui_menu from manifest
# ============================================================

# Guard against double-sourcing
if [[ "${_ROM_PIPELINE_LOADED:-}" = "1" ]]; then
    return 0 2>/dev/null || true
fi

# ============================================================
# PATH RESOLUTION
# ============================================================

_ROM_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_ROM_ARCADE_DIR="$(cd "${_ROM_LIB_DIR}/.." && pwd)"
_ROM_ROOT_DIR="$(cd "${_ROM_ARCADE_DIR}/.." && pwd)"
_ROM_MANIFEST="${_ROM_ARCADE_DIR}/manifest.json"
_ROM_ROMS_DIR="${_ROM_ARCADE_DIR}/roms"

# Port for server check (same default as arcade-tokens.sh)
_ROM_CUE_VOX_PORT="${CUE_VOX_PORT:-3000}"

# ============================================================
# ROM CATALOG
# ============================================================

rom_catalog() {
    # Read manifest.json and output ROM entries as JSON array.
    if [[ ! -f "${_ROM_MANIFEST}" ]]; then
        echo "[]"
        return 1
    fi

    python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
print(json.dumps(data.get('roms', [])))
" "${_ROM_MANIFEST}" 2>/dev/null || echo "[]"
}

# ============================================================
# PATH RESOLUTION
# ============================================================

rom_resolve_path() {
    # Given a slug, resolve to absolute file path.
    # Outputs absolute path to stdout.  Returns 1 if not found.
    local slug="$1"

    if [[ ! -f "${_ROM_MANIFEST}" ]]; then
        return 1
    fi

    local resolved
    resolved=$(python3 -c "
import json, sys
slug = sys.argv[1]
root = sys.argv[2]
arcade = sys.argv[3]
with open(sys.argv[4]) as f:
    data = json.load(f)
for rom in data.get('roms', []):
    if rom['slug'] == slug:
        file_name = rom.get('file') or rom.get('rom')
        if not file_name:
            sys.exit(1)
        location = rom.get('location', 'roms')
        if location == 'roms':
            print(arcade + '/roms/' + file_name)
        else:
            print(root + '/' + rom.get('active_path', ''))
        sys.exit(0)
sys.exit(1)
" "${slug}" "${_ROM_ROOT_DIR}" "${_ROM_ARCADE_DIR}" "${_ROM_MANIFEST}" 2>/dev/null) || return 1

    echo "${resolved}"
}

# ============================================================
# VALIDATION
# ============================================================

rom_validate() {
    # Static analysis on a ROM file.
    # Returns 0 if valid, 1 if issues found.
    # Prints issues to stderr.
    local file_path="$1"
    local issues=0

    if [[ ! -f "${file_path}" ]]; then
        echo "  not found: ${file_path}" >&2
        return 1
    fi

    # Check shebang
    local first_line
    first_line=$(head -1 "${file_path}")
    if [[ "${first_line}" != "#!/usr/bin/env bash" ]]; then
        echo "  missing shebang: ${file_path}" >&2
        issues=1
    fi

    # Check that it sources tui.sh
    if ! grep -q 'source.*lib/tui\.sh' "${file_path}" 2>/dev/null; then
        echo "  does not source lib/tui.sh: ${file_path}" >&2
        issues=1
    fi

    # Check SCRIPT_DIR resolution
    if ! grep -q 'SCRIPT_DIR=' "${file_path}" 2>/dev/null; then
        echo "  no SCRIPT_DIR: ${file_path}" >&2
        issues=1
    fi

    # Syntax check
    if ! bash -n "${file_path}" 2>/dev/null; then
        echo "  syntax error: ${file_path}" >&2
        issues=1
    fi

    return "${issues}"
}

# ============================================================
# LAUNCH
# ============================================================

rom_launch() {
    # Full pipeline: resolve -> validate -> server check -> exec
    local slug="$1"

    local file_path
    file_path=$(rom_resolve_path "${slug}") || {
        echo "Unknown ROM: ${slug}" >&2
        return 1
    }

    rom_validate "${file_path}" || {
        echo "ROM validation failed: ${slug}" >&2
        return 1
    }

    # Check if game requires server
    local needs_server
    needs_server=$(python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
for rom in data.get('roms', []):
    if rom['slug'] == sys.argv[2]:
        print('1' if rom.get('requires_server', False) else '0')
        sys.exit(0)
print('0')
" "${_ROM_MANIFEST}" "${slug}" 2>/dev/null)

    if [[ "${needs_server}" = "1" ]]; then
        if ! lsof -ti:"${_ROM_CUE_VOX_PORT}" > /dev/null 2>&1; then
            echo "cue-vox not running -- ${slug} needs it for token creation" >&2
            echo "Start with: ./maestro.sh start" >&2
            return 1
        fi
    fi

    exec bash "${file_path}"
}

rom_run() {
    # Same as rom_launch but returns to caller (no exec).
    # Used by the arcade shell so ROMs return to the menu.
    local slug="$1"

    local file_path
    file_path=$(rom_resolve_path "${slug}") || {
        echo "Unknown ROM: ${slug}" >&2
        return 1
    }

    rom_validate "${file_path}" || {
        echo "ROM validation failed: ${slug}" >&2
        return 1
    }

    local needs_server
    needs_server=$(python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
for rom in data.get('roms', []):
    if rom['slug'] == sys.argv[2]:
        print('1' if rom.get('requires_server', False) else '0')
        sys.exit(0)
print('0')
" "${_ROM_MANIFEST}" "${slug}" 2>/dev/null)

    if [[ "${needs_server}" = "1" ]]; then
        if ! lsof -ti:"${_ROM_CUE_VOX_PORT}" > /dev/null 2>&1; then
            echo "cue-vox not running -- ${slug} needs it for token creation" >&2
            echo "Start with: ./maestro.sh start" >&2
            return 1
        fi
    fi

    bash "${file_path}"
}

# ============================================================
# DISCOVERY
# ============================================================

rom_discover() {
    # Scan active/*/*.sh and roms/*.sh for game files.
    # Heuristic: any .sh that sources lib/tui.sh.
    # Outputs slug:path pairs to stdout.
    local scan_dirs=("${_ROM_ROMS_DIR}" "${_ROM_ROOT_DIR}/ACTIVE")

    for dir in "${scan_dirs[@]}"; do
        [[ -d "${dir}" ]] || continue
        while IFS= read -r -d '' file; do
            if grep -q 'source.*lib/tui\.sh' "${file}" 2>/dev/null; then
                local name
                name=$(basename "${file}" .sh)
                echo "${name}:${file}"
            fi
        done < <(find "${dir}" -name '*.sh' -print0 2>/dev/null)
    done
}

# ============================================================
# PROMOTE
# ============================================================

rom_promote() {
    # Copy a ROM from active/ to roms/ and update manifest.
    local slug="$1"

    local src_path
    src_path=$(rom_resolve_path "${slug}") || {
        echo "Unknown ROM: ${slug}" >&2
        return 1
    }

    # Check current location
    local current_location
    current_location=$(python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
for rom in data.get('roms', []):
    if rom['slug'] == sys.argv[2]:
        print(rom['location'])
        sys.exit(0)
" "${_ROM_MANIFEST}" "${slug}" 2>/dev/null)

    if [[ "${current_location}" = "roms" ]]; then
        echo "Already promoted: ${slug}" >&2
        return 0
    fi

    local filename
    filename=$(basename "${src_path}")
    local dest_path="${_ROM_ROMS_DIR}/${filename}"

    mkdir -p "${_ROM_ROMS_DIR}"
    cp "${src_path}" "${dest_path}"
    chmod +x "${dest_path}"

    # Fix SCRIPT_DIR if game only goes up one level (needs two for roms/)
    python3 -c "
import sys
path = sys.argv[1]
with open(path) as f:
    content = f.read()
old = 'SCRIPT_DIR=\"\$(cd \"\$(dirname \"\${BASH_SOURCE[0]}\")/..\" && pwd)\"'
new = 'SCRIPT_DIR=\"\$(cd \"\$(dirname \"\${BASH_SOURCE[0]}\")/../..\" && pwd)\"'
if old in content:
    content = content.replace(old, new)
    with open(path, 'w') as f:
        f.write(content)
" "${dest_path}"

    # Update manifest
    python3 -c "
import json, sys
manifest_path = sys.argv[1]
slug = sys.argv[2]
with open(manifest_path) as f:
    data = json.load(f)
for rom in data.get('roms', []):
    if rom['slug'] == slug:
        rom['location'] = 'roms'
        rom['status'] = 'promoted'
        break
with open(manifest_path, 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
" "${_ROM_MANIFEST}" "${slug}"

    echo "Promoted ${slug} -> ${dest_path}"
}

# ============================================================
# MENU ITEMS
# ============================================================

# Global arrays populated by rom_menu_items
ROM_MENU_LABELS=()
ROM_MENU_SLUGS=()

rom_menu_items() {
    # Build arrays for tui_menu from manifest.
    # Populates ROM_MENU_LABELS and ROM_MENU_SLUGS global arrays.
    ROM_MENU_LABELS=()
    ROM_MENU_SLUGS=()

    [[ -f "${_ROM_MANIFEST}" ]] || return 1

    local entries
    entries=$(python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
for rom in data.get('roms', []):
    if not rom.get('file') and not rom.get('rom'):
        continue
    loc = 'ROM' if rom.get('location', 'roms') == 'roms' else 'DEV'
    title = rom.get('title') or rom.get('name') or rom.get('slug')
    print(rom['slug'])
    print('{:<16s} - {} [{}]'.format(title, rom.get('description', ''), loc))
" "${_ROM_MANIFEST}" 2>/dev/null) || return 1

    while IFS= read -r slug && IFS= read -r label; do
        ROM_MENU_SLUGS+=("${slug}")
        ROM_MENU_LABELS+=("${label}")
    done <<< "${entries}"
}

_ROM_PIPELINE_LOADED=1
