#!/usr/bin/env bash
# select.sh — switch ~/.claude/settings.json statusLine.command between the
# real status bar and the debug harnesses, with a backup on first use.
#
#   bash tools/select.sh real            # back to normal
#   bash tools/select.sh log             # real bar + per-render log
#   bash tools/select.sh test            # redraw experiment (plain)
#   bash tools/select.sh test erase      # redraw experiment, ESC[K variant
#   bash tools/select.sh test bg
#   bash tools/select.sh test dots
#   bash tools/select.sh show            # print the current setting
#
# Changes take effect on the next status-line render (no restart needed).

set -eu

settings="$HOME/.claude/settings.json"
tools="$HOME/ai/claude-statusbar/tools"
backup="$settings.statusline-backup"

[ -f "$settings" ] || { echo "no $settings" >&2; exit 1; }
[ -f "$backup" ] || cp "$settings" "$backup"

what=${1:-show}
variant=${2:-}

case "$what" in
    show)
        jq -r '.statusLine.command' "$settings"
        exit 0 ;;
    real) cmd='bash "$HOME/.claude/statusline.sh"' ;;
    log)  cmd="bash \"$tools/statusline-log.sh\"" ;;
    test)
        if [ -n "$variant" ]; then cmd="SL_TEST=$variant bash \"$tools/redraw-test.sh\""
        else cmd="bash \"$tools/redraw-test.sh\""; fi
        rm -f /tmp/claude/redraw-test.count ;;
    *) echo "usage: select.sh real|log|test [plain|erase|bg|dots]|show" >&2; exit 2 ;;
esac

tmp=$(mktemp)
jq --arg c "$cmd" '.statusLine.command = $c' "$settings" > "$tmp"
mv "$tmp" "$settings"
echo "statusLine.command = $(jq -r '.statusLine.command' "$settings")"
echo "(original settings backed up at $backup)"
