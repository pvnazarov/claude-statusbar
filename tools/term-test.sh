#!/usr/bin/env bash
# term-test.sh — EXPERIMENT 1: is the terminal at fault, or whatever is
# feeding it? Claude Code is not involved here at all.
#
#     ! bash ~/ai/claude-statusbar/tools/term-test.sh
#
# Each case draws a solid row of '#', waits, then redraws a shorter/gapped
# version WITHOUT any erase. Watch which cases leave leftovers behind.
#
#   case A  overwrites with literal spaces  -> a working terminal CLEARS them
#   case B  moves the cursor forward instead -> nothing is painted, '#' SURVIVE
#   case C  uses ESC[K (erase to end of line) -> always clears
#
# Whichever case LOOKS LIKE YOUR BUG identifies the mechanism:
#   looks like A (leftovers where spaces were) -> the TERMINAL fails to paint
#                                                 spaces: a real terminal bug
#   looks like B                               -> the terminal is fine; the
#                                                 renderer is emitting cursor
#                                                 moves, not spaces
#   C clean but A dirty                        -> ESC[K is our workaround

set -u
pause=${PAUSE:-1.4}

hr() { printf '%s\n' "------------------------------------------------------------"; }
step() { printf '\n%s\n' "$1"; }

step "case A — redraw with LITERAL SPACES (expect: gap appears, # cleared)"
printf '  ####################'
sleep "$pause"
printf '\r  #####          #####'
sleep "$pause"
printf '\n'

step "case B — redraw with CURSOR-FORWARD ESC[10C (expect: # SURVIVE the gap)"
printf '  ####################'
sleep "$pause"
printf '\r  #####\033[10C#####'
sleep "$pause"
printf '\n'

step "case C — redraw after ESC[K (expect: fully clean)"
printf '  ####################'
sleep "$pause"
printf '\r\033[K  #####          #####'
sleep "$pause"
printf '\n'

step "case D — SHRINKING NUMBER, no erase (expect: trailing digits survive)"
printf '  value=123456'
sleep "$pause"
printf '\r  value=1'
sleep "$pause"
printf '\n'

step "case E — same, padded so the string never shrinks (expect: clean)"
printf '  value=123456'
sleep "$pause"
printf '\r  value=1     '
sleep "$pause"
printf '\n'

hr
echo "Which case matched your status-bar symptom? A / B / D"
