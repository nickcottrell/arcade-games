#!/usr/bin/env bash
# ============================================================
#  VRGB.SH  --  Colorspace Utilities for VRGB Games
# ============================================================
#  Reusable color math: HSL <-> RGB, 24-bit rendering,
#  distance calculations, random generation.
#
#  Source this file:  source lib/vrgb.sh
#
#  Public API  (vrgb_ prefix):
#    vrgb_hsl_to_rgb, vrgb_rgb_to_hsl,
#    vrgb_swatch, vrgb_swatch_hsl,
#    vrgb_hex_from_rgb, vrgb_hex_from_hsl,
#    vrgb_hue_distance, vrgb_color_distance,
#    vrgb_random_color, vrgb_proximity_label,
#    vrgb_gradient_bar
# ============================================================

if [[ "${_VRGB_INITIALIZED:-}" = "1" ]]; then
    return 0 2>/dev/null || true
fi

# ============================================================
# RETURN REGISTERS
# ============================================================

VRGB_R=0
VRGB_G=0
VRGB_B=0
VRGB_H=0
VRGB_S=0
VRGB_L=0
VRGB_HEX=""
VRGB_DIST=0

# ============================================================
# HSL -> RGB
# ============================================================
# Args: H (0-360) S (0-100) L (0-100)
# Sets: VRGB_R, VRGB_G, VRGB_B (0-255)

vrgb_hsl_to_rgb() {
    local h="$1" s="$2" l="$3"
    local result
    result=$(awk -v h="${h}" -v s="${s}" -v l="${l}" 'BEGIN {
        s = s / 100.0
        l = l / 100.0
        if (s == 0) {
            r = l; g = l; b = l
        } else {
            c = (1.0 - (2.0*l - 1.0 > 0 ? 2.0*l - 1.0 : -(2.0*l - 1.0))) * s
            hp = h / 60.0
            hmod = hp - int(hp/2)*2
            x = c * (1.0 - (hmod - 1.0 > 0 ? hmod - 1.0 : -(hmod - 1.0)))
            m = l - c / 2.0
            if (hp < 1)      { r = c+m; g = x+m; b = 0+m }
            else if (hp < 2) { r = x+m; g = c+m; b = 0+m }
            else if (hp < 3) { r = 0+m; g = c+m; b = x+m }
            else if (hp < 4) { r = 0+m; g = x+m; b = c+m }
            else if (hp < 5) { r = x+m; g = 0+m; b = c+m }
            else             { r = c+m; g = 0+m; b = x+m }
        }
        ri = int(r * 255 + 0.5)
        gi = int(g * 255 + 0.5)
        bi = int(b * 255 + 0.5)
        if (ri < 0) ri = 0; if (ri > 255) ri = 255
        if (gi < 0) gi = 0; if (gi > 255) gi = 255
        if (bi < 0) bi = 0; if (bi > 255) bi = 255
        printf "%d %d %d", ri, gi, bi
    }')
    VRGB_R="${result%% *}"
    local rest="${result#* }"
    VRGB_G="${rest%% *}"
    VRGB_B="${rest#* }"
}

# ============================================================
# RGB -> HSL
# ============================================================
# Args: R (0-255) G (0-255) B (0-255)
# Sets: VRGB_H (0-360), VRGB_S (0-100), VRGB_L (0-100)

vrgb_rgb_to_hsl() {
    local r="$1" g="$2" b="$3"
    local result
    result=$(awk -v r="${r}" -v g="${g}" -v b="${b}" 'BEGIN {
        r = r / 255.0; g = g / 255.0; b = b / 255.0
        mx = r; if (g > mx) mx = g; if (b > mx) mx = b
        mn = r; if (g < mn) mn = g; if (b < mn) mn = b
        l = (mx + mn) / 2.0
        if (mx == mn) {
            h = 0; s = 0
        } else {
            d = mx - mn
            s = l > 0.5 ? d / (2.0 - mx - mn) : d / (mx + mn)
            if (mx == r) {
                h = (g - b) / d + (g < b ? 6 : 0)
            } else if (mx == g) {
                h = (b - r) / d + 2
            } else {
                h = (r - g) / d + 4
            }
            h = h * 60
        }
        printf "%d %d %d", int(h + 0.5), int(s * 100 + 0.5), int(l * 100 + 0.5)
    }')
    VRGB_H="${result%% *}"
    local rest="${result#* }"
    VRGB_S="${rest%% *}"
    VRGB_L="${rest#* }"
}

# ============================================================
# HEX ENCODING
# ============================================================

vrgb_hex_from_rgb() {
    printf -v VRGB_HEX "#%02x%02x%02x" "$1" "$2" "$3"
}

vrgb_hex_from_hsl() {
    vrgb_hsl_to_rgb "$1" "$2" "$3"
    vrgb_hex_from_rgb "${VRGB_R}" "${VRGB_G}" "${VRGB_B}"
}

# ============================================================
# RENDERING (24-bit true color ANSI)
# ============================================================

# Render a color swatch block from RGB
# Args: R G B [width] [char]
vrgb_swatch() {
    local r="$1" g="$2" b="$3"
    local width="${4:-6}"
    local ch="${5:-  }"
    local i=0
    printf "\033[48;2;%d;%d;%dm" "${r}" "${g}" "${b}"
    while [[ "${i}" -lt "${width}" ]]; do
        printf "%s" "${ch}"
        i=$((i + 1))
    done
    printf "\033[0m"
}

# Render a color swatch block from HSL
# Args: H S L [width]
vrgb_swatch_hsl() {
    vrgb_hsl_to_rgb "$1" "$2" "$3"
    vrgb_swatch "${VRGB_R}" "${VRGB_G}" "${VRGB_B}" "${4:-6}"
}

# Render text with foreground color from RGB
# Args: R G B text
vrgb_fg() {
    printf "\033[38;2;%d;%d;%dm%s\033[0m" "$1" "$2" "$3" "$4"
}

# ============================================================
# DISTANCE CALCULATIONS
# ============================================================

# Angular distance on hue wheel (0-180)
# Args: H1 H2
vrgb_hue_distance() {
    local h1="$1" h2="$2"
    local diff=$((h1 - h2))
    if [[ "${diff}" -lt 0 ]]; then
        diff=$((-diff))
    fi
    if [[ "${diff}" -gt 180 ]]; then
        diff=$((360 - diff))
    fi
    VRGB_DIST="${diff}"
}

# Weighted color distance (0-100 scale)
# Hue weighted more heavily since it is perceptually dominant
# Args: H1 S1 L1 H2 S2 L2
vrgb_color_distance() {
    local h1="$1" s1="$2" l1="$3" h2="$4" s2="$5" l2="$6"
    VRGB_DIST=$(awk -v h1="${h1}" -v s1="${s1}" -v l1="${l1}" \
                    -v h2="${h2}" -v s2="${s2}" -v l2="${l2}" 'BEGIN {
        hd = h1 - h2
        if (hd < 0) hd = -hd
        if (hd > 180) hd = 360 - hd
        sd = s1 - s2
        if (sd < 0) sd = -sd
        ld = l1 - l2
        if (ld < 0) ld = -ld
        # Normalize: hue to 0-100, sat and light already 0-100
        hn = hd * 100.0 / 180.0
        # Weighted euclidean
        dist = sqrt(hn*hn*0.4 + sd*sd*0.3 + ld*ld*0.3)
        printf "%d", int(dist + 0.5)
    }')
}

# ============================================================
# PROXIMITY LABELS
# ============================================================

# Convert a distance (0-100) to a proximity word
# Args: distance
# Returns via VRGB_LABEL
VRGB_LABEL=""

vrgb_proximity_label() {
    local dist="$1"
    if [[ "${dist}" -le 5 ]]; then
        VRGB_LABEL="exact"
    elif [[ "${dist}" -le 15 ]]; then
        VRGB_LABEL="hot"
    elif [[ "${dist}" -le 30 ]]; then
        VRGB_LABEL="warm"
    elif [[ "${dist}" -le 50 ]]; then
        VRGB_LABEL="cool"
    else
        VRGB_LABEL="cold"
    fi
}

# Dimension-specific proximity for a single value difference
# Args: diff (absolute)  max_range
vrgb_dimension_proximity() {
    local diff="$1" max_range="$2"
    local pct=$((diff * 100 / max_range))
    vrgb_proximity_label "${pct}"
}

# ============================================================
# RANDOM COLOR GENERATION
# ============================================================

# Generate a random visually-distinct color
# Avoids very dark/light and very desaturated colors
# Sets: VRGB_H, VRGB_S, VRGB_L
vrgb_random_color() {
    VRGB_H=$((RANDOM % 360))
    VRGB_S=$((40 + RANDOM % 50))
    VRGB_L=$((30 + RANDOM % 40))
}

# Generate a fully random color (full range)
vrgb_random_color_full() {
    VRGB_H=$((RANDOM % 360))
    VRGB_S=$((RANDOM % 101))
    VRGB_L=$((RANDOM % 101))
}

# ============================================================
# GRADIENT BAR
# ============================================================

# Render a horizontal gradient bar between two HSL colors
# Args: H1 S1 L1 H2 S2 L2 width
vrgb_gradient_bar() {
    local h1="$1" s1="$2" l1="$3"
    local h2="$4" s2="$5" l2="$6"
    local width="${7:-20}"

    local i=0
    while [[ "${i}" -lt "${width}" ]]; do
        local t_h=$((h1 + (h2 - h1) * i / width))
        local t_s=$((s1 + (s2 - s1) * i / width))
        local t_l=$((l1 + (l2 - l1) * i / width))
        vrgb_hsl_to_rgb "${t_h}" "${t_s}" "${t_l}"
        printf "\033[48;2;%d;%d;%dm " "${VRGB_R}" "${VRGB_G}" "${VRGB_B}"
        i=$((i + 1))
    done
    printf "\033[0m"
}

# ============================================================
# HUEWHEEL LABELS
# ============================================================

VRGB_HUE_NAME=""

vrgb_hue_name() {
    local h="$1"
    if [[ "${h}" -lt 15 ]] || [[ "${h}" -ge 345 ]]; then
        VRGB_HUE_NAME="red"
    elif [[ "${h}" -lt 45 ]]; then
        VRGB_HUE_NAME="orange"
    elif [[ "${h}" -lt 75 ]]; then
        VRGB_HUE_NAME="yellow"
    elif [[ "${h}" -lt 105 ]]; then
        VRGB_HUE_NAME="chartreuse"
    elif [[ "${h}" -lt 135 ]]; then
        VRGB_HUE_NAME="green"
    elif [[ "${h}" -lt 165 ]]; then
        VRGB_HUE_NAME="spring"
    elif [[ "${h}" -lt 195 ]]; then
        VRGB_HUE_NAME="cyan"
    elif [[ "${h}" -lt 225 ]]; then
        VRGB_HUE_NAME="azure"
    elif [[ "${h}" -lt 255 ]]; then
        VRGB_HUE_NAME="blue"
    elif [[ "${h}" -lt 285 ]]; then
        VRGB_HUE_NAME="violet"
    elif [[ "${h}" -lt 315 ]]; then
        VRGB_HUE_NAME="magenta"
    else
        VRGB_HUE_NAME="rose"
    fi
}

# ============================================================
# INIT
# ============================================================

_VRGB_INITIALIZED=1
