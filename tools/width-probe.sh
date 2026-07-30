#!/usr/bin/env bash
# width-probe.sh — ask THIS terminal how wide it actually draws each glyph the
# status bar uses, then measure the real on-screen size of a full bar.
#
# Run it from an interactive terminal (it needs a tty):
#
#     ! bash ~/ai/claude-statusbar/tools/width-probe.sh
#
# Why: a status line renderer erases/overwrites based on the width it *computed*
# for the previous string. If the terminal draws a glyph wider than the
# renderer assumed, the extra cells never get cleared and you see leftovers of
# the previous bar. This tells us whether that mismatch exists here, and by how
# many cells.

set -u

if [ ! -e /dev/tty ]; then
    echo "width-probe: no /dev/tty — run this from an interactive terminal" >&2
    exit 1
fi

# ── Cursor position report (CSI 6n) ─────────────────────
cpr() { # echoes "row col"
    local old resp ch
    old=$(stty -g </dev/tty)
    stty raw -echo min 0 time 10 </dev/tty
    printf '\033[6n' >/dev/tty
    resp=""
    while IFS= read -r -n1 ch </dev/tty; do
        resp+="$ch"
        [ "$ch" = "R" ] && break
    done
    stty "$old" </dev/tty
    resp=${resp#*\[}          # strip ESC [
    resp=${resp%R}
    printf '%s %s' "${resp%%;*}" "${resp##*;}"
}

cols=$(tput cols)
rows_before=""

measure_glyph() { # label, glyph -> cells
    local glyph="$1" pos col
    printf '\r\033[2K' >/dev/tty
    printf '%s' "$glyph" >/dev/tty
    pos=$(cpr)
    col=${pos##* }
    printf '\r\033[2K' >/dev/tty
    printf '%s' "$(( col - 1 ))"
}

measure_string() { # whole string, may wrap -> total cells
    local s="$1" pos r0 c0 r1 c1
    printf '\r\033[2K' >/dev/tty
    pos=$(cpr); r0=${pos%% *}
    printf '%s' "$s" >/dev/tty
    pos=$(cpr); r1=${pos%% *}; c1=${pos##* }
    printf '\r\033[2K' >/dev/tty
    # if the string wrapped, the terminal may have scrolled; r1-r0 still counts rows used
    printf '%s' "$(( (r1 - r0) * cols + c1 - 1 ))"
}

echo "terminal: TERM=$TERM cols=$cols LANG=${LANG:-unset}"
echo
printf '%-34s %-8s %-8s %s\n' "glyph" "naive" "actual" "verdict"
printf '%-34s %-8s %-8s %s\n' "-----" "-----" "------" "-------"

# label:glyph pairs, one per line (glyphs used by statusline.sh)
probe_one() {
    local label="$1" glyph="$2" naive="$3" actual verdict
    actual=$(measure_glyph "$glyph")
    if [ "$actual" = "$naive" ]; then verdict="ok"
    else verdict=">>> MISMATCH (+$(( actual - naive )) cell)"; fi
    printf '%-34s %-8s %-8s %s\n' "$label" "$naive" "$actual" "$verdict"
}

probe_one "A (baseline ascii)"            "A"    1
probe_one "U+25CF ● bar filled"           "●"    1
probe_one "U+25CB ○ bar empty"            "○"    1
probe_one "U+2502 │ separator"            "│"    1
probe_one "U+25D1 ◑ effort medium"        "◑"    1
probe_one "U+25D4 ◔ effort low"           "◔"    1
probe_one "U+27F3 ⟳ reset marker"         "⟳"    1
probe_one "U+23F1 ⏱ session clock"        "⏱"    1
probe_one "U+270D+FE0F ✍️ context"        "✍️"   1
probe_one "U+26A1 ⚡ skip-perms"           "⚡"    1
probe_one "10x ● (a full bar)"            "●●●●●●●●●●" 10

echo
echo "── full bar ────────────────────────────────────────────"

sample=$(cat <<'EOF'
{"model":{"display_name":"Opus 5 (1M context)"},"cwd":"HOME_CWD",
 "context_window":{"context_window_size":1000000,"current_usage":{"input_tokens":1200,"cache_creation_input_tokens":4000,"cache_read_input_tokens":88000}},
 "session":{"start_time":"2026-07-30T19:05:00Z"},
 "rate_limits":{"five_hour":{"used_percentage":7.4,"resets_at":1785180000},
                "seven_day":{"used_percentage":62.0,"resets_at":1785600000}}}
EOF
)
sample=${sample/HOME_CWD/$PWD}

script="${SL_SCRIPT:-$HOME/.claude/statusline.sh}"
raw=$(printf '%s' "$sample" | bash "$script")
plain=$(printf '%s' "$raw" | sed $'s/\033\[[0-9;]*m//g')

naive_cells=$(printf '%s' "$plain" | wc -m | tr -d ' ')
actual_cells=$(measure_string "$plain")

echo "script          : $script"
echo "naive width     : $naive_cells cells (codepoint count — what a simple calc gives)"
echo "actual width    : $actual_cells cells (measured from the cursor)"
echo "terminal width  : $cols cells"
if [ "$actual_cells" -ne "$naive_cells" ]; then
    echo "  >>> WIDTH MISMATCH of $(( actual_cells - naive_cells )) cells."
    echo "      A renderer clearing '$naive_cells' cells leaves $(( actual_cells - naive_cells )) stale ones behind."
fi
if [ "$actual_cells" -gt "$cols" ]; then
    echo "  >>> The bar does NOT fit on one row: it needs $(( (actual_cells + cols - 1) / cols )) rows."
    echo "      Widen the window past $actual_cells columns and see if the artifacts stop."
fi
