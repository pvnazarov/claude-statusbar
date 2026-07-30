#!/usr/bin/env bash
# redraw-test.sh — EXPERIMENT 2: a throwaway status line whose only job is to
# prove whether spaces paint inside Claude Code's status bar.
#
# Point statusLine.command at this (see tools/select.sh), then type a few
# messages so the bar re-renders, and watch the three fields.
#
# Deliberately kept SHORT (~60 cols) and pure ASCII so window width and
# glyph width are ruled out as variables.
#
#   A[...]  a 3-wide gap marching right, drawn with SPACES
#   B[...]  the same gap, drawn with '.'            <- control
#   C[...]  a shrinking number, right-padded with SPACES
#
# Read it like this:
#   B animates but A stays solid '############'  -> SPACES DO NOT PAINT (confirmed)
#   C keeps showing stale digits (e.g. '123456' when n says it should be '1')
#                                                -> same bug, in the form you hit
#   both animate cleanly                         -> spaces are fine; the cause is
#                                                   elsewhere (width/wrap)
#
# Modes, via SL_TEST:
#   plain (default)  as described above
#   erase            same, but prefixed with ESC[K  -> does it fix it?
#   bg               gap spaces carry an explicit SGR (ESC[49m) -> does an
#                    *attributed* space paint when a bare one does not?
#   dots             every gap is '.' -> pure control, must always animate
#
# Reset the frame counter with:  rm -f /tmp/claude/redraw-test.count

set -u

mode=${SL_TEST:-plain}
counter=/tmp/claude/redraw-test.count
mkdir -p /tmp/claude

n=0
[ -f "$counter" ] && n=$(cat "$counter" 2>/dev/null)
case "$n" in ''|*[!0-9]*) n=0 ;; esac
n=$(( n + 1 ))
printf '%s' "$n" > "$counter"

field_w=12
gap_w=3
pos=$(( (n - 1) % (field_w - gap_w + 1) ))

# gap filler per mode
case "$mode" in
    dots) fill_a='...' ;;
    bg)   fill_a=$'\033[49m   \033[0m' ;;
    *)    fill_a='   ' ;;
esac

build() { # pos, filler -> field string
    local p=$1 fill=$2 s=""
    local i
    for ((i=0; i<field_w; i++)); do
        if [ "$i" -eq "$p" ]; then s+="$fill"; i=$(( i + gap_w - 1 ))
        else s+="#"; fi
    done
    printf '%s' "$s"
}

a=$(build "$pos" "$fill_a")
b=$(build "$pos" '...')

# shrinking number: 123456 -> 12345 -> ... -> 1 -> 123456, space-padded to 6
digits=$(( 6 - ((n - 1) % 6) ))
num=$(printf '123456' | cut -c1-"$digits")
c=$(printf '%-6s' "$num")

out=$(printf 'n=%03d A[%s] B[%s] C[%s] mode=%s' "$n" "$a" "$b" "$c" "$mode")

case "$mode" in
    erase) printf '\033[K%s' "$out" ;;
    *)     printf '%s' "$out" ;;
esac

exit 0
