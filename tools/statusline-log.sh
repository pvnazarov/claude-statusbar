#!/usr/bin/env bash
# statusline-log.sh — transparent wrapper around statusline.sh that records
# every render, so we can look at what changed right before an artifact.
#
# Enable:
#   jq '.statusLine.command = "bash \"$HOME/ai/claude-statusbar/tools/statusline-log.sh\""' \
#      ~/.claude/settings.json > /tmp/s.json && mv /tmp/s.json ~/.claude/settings.json
# Disable: set it back to  bash "$HOME/.claude/statusline.sh"
#
# Log:  /tmp/claude/statusline-debug.log   (override with SL_LOG)
# Set SL_LOG_INPUT=1 to also dump the raw stdin payload Claude Code provides.
#
# Then, to find the renders where the bar SHRANK (that is when leftovers show):
#   awk -F'cells=' '{split($2,a," "); if (prev && a[1]+0 < prev+0)
#       print "SHRANK " prev " -> " a[1] ": " $0; prev=a[1]}' \
#       /tmp/claude/statusline-debug.log

set -u

LOG=${SL_LOG:-/tmp/claude/statusline-debug.log}
TARGET=${SL_TARGET:-$HOME/.claude/statusline.sh}
mkdir -p "$(dirname "$LOG")"

input=$(cat)
out=$(printf '%s' "$input" | bash "$TARGET")

# pass through untouched — the wrapper must not change what is rendered
printf '%s' "$out"

{
    plain=$(printf '%s' "$out" | sed $'s/\033\[[0-9;]*m//g')
    cells=$(printf '%s' "$plain" | wc -m | tr -d ' ')
    bytes=$(printf '%s' "$out" | wc -c | tr -d ' ')
    printf '%s cells=%s bytes=%s |%s|\n' \
        "$(date +%H:%M:%S)" "$cells" "$bytes" "$plain"
    if [ "${SL_LOG_INPUT:-0}" = "1" ]; then
        printf '    stdin: %s\n' "$(printf '%s' "$input" | jq -c 'del(.transcript_path)' 2>/dev/null || printf '%s' "$input")"
    fi
} >>"$LOG" 2>/dev/null

exit 0
