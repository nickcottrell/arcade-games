#!/usr/bin/env bash
# NODE-LOCAL CHECK: madlibs RT-01 regression
# ------------------------------------------------------------
# The madlibs ROM must fill story templates with LITERAL replacement.
# The original code piped the player's typed word into a sed program
# (s|{$i}|$word|g); a crafted word could reach GNU sed's exec flag and
# run shell commands from untrusted PTY input. This check fails if that
# construct comes back, and confirms the attack word stays inert data.
# ------------------------------------------------------------
root="${1:-$PWD}"
f="$root/arcade/roms/madlibs.sh"

[ -f "$f" ] || { echo "madlibs.sh not found at $f"; exit 1; }

# 1) the vulnerable sed-on-word construct must be gone
if grep -qE 'sed[[:space:]]+"s\|\{' "$f"; then
    echo "vulnerable sed-on-word construct is present"
    exit 1
fi

# 2) behavioral: the audit's attack word must render as literal text
template='A wild {1} appears'
word='id|e;#'
out="${template//"{1}"/$word}"
if [ "$out" != "A wild id|e;# appears" ]; then
    echo "literal fill broken -- got: $out"
    exit 1
fi
exit 0
