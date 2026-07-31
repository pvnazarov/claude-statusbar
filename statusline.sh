#!/bin/bash
set -f

# Percentages arrive as "42.6" and are rounded with printf/awk. Under a locale
# whose decimal separator is a comma (LC_NUMERIC=fr_FR etc.) both reject the
# dot: bash printf errors to stderr — which Claude Code swallows — and awk
# silently truncates, so 42.6 renders as 42%. Force C for numbers only; dates
# still follow LC_TIME.
export LC_NUMERIC=C

input=$(cat)

if [ -z "$input" ]; then
    printf "Claude"
    exit 0
fi

# ── Colors ──────────────────────────────────────────────
blue='\033[38;2;0;153;255m'
orange='\033[38;2;255;176;85m'
green='\033[38;2;0;175;80m'
cyan='\033[38;2;86;182;194m'
red='\033[38;2;255;85;85m'
yellow='\033[38;2;230;200;0m'
white='\033[38;2;220;220;220m'
magenta='\033[38;2;180;140;255m'
dim='\033[2m'
reset='\033[0m'

sep=" ${dim}│${reset} "

# ── Anti-shrink padding ─────────────────────────────────
# A status-line renderer that draws a shorter string than the previous render
# leaves the tail of that previous render on screen — see
# tools/term-test.sh case D, where "value=123456" redrawn as "value=1" still
# reads "value=123456". It looks like "spaces don't paint", but really nothing
# was written over those cells at all.
#
# What prevents that is one property alone: the total width must never shrink.
# The finished line is therefore padded back up to the widest it has been this
# session. Individual fields are NOT padded — that only ever kept columns from
# shifting sideways, which is cosmetic, and it is where all the wasted space
# was. Trailing spaces are invisible, so the anti-shrink pad costs nothing.
#
# Set SL_NO_PAD=1 to turn it off and compare.
pad=true
[ "${SL_NO_PAD:-0}" = "1" ] && pad=false

# ── Helpers ─────────────────────────────────────────────
color_for_pct() {
    local pct=$1
    if [ "$pct" -ge 90 ]; then printf "$red"
    elif [ "$pct" -ge 70 ]; then printf "$yellow"
    elif [ "$pct" -ge 50 ]; then printf "$orange"
    else printf "$green"
    fi
}

build_bar() {
    local pct=$1
    local width=$2
    [ "$pct" -lt 0 ] 2>/dev/null && pct=0
    [ "$pct" -gt 100 ] 2>/dev/null && pct=100

    local filled=$(( pct * width / 100 ))
    local empty=$(( width - filled ))
    local bar_color
    bar_color=$(color_for_pct "$pct")

    local filled_str="" empty_str=""
    for ((i=0; i<filled; i++)); do filled_str+="●"; done
    for ((i=0; i<empty; i++)); do empty_str+="○"; done

    printf "${bar_color}${filled_str}${dim}${empty_str}${reset}"
}

format_epoch_time() {
    local epoch=$1
    local style=$2
    [ -z "$epoch" ] || [ "$epoch" = "null" ] || [ "$epoch" = "0" ] && return

    local result=""
    case "$style" in
        time)
            result=$(date -j -r "$epoch" +"%H:%M" 2>/dev/null)
            [ -z "$result" ] && result=$(date -d "@$epoch" +"%H:%M" 2>/dev/null)
            ;;
        datetime)
            result=$(date -j -r "$epoch" +"%b %-d, %H:%M" 2>/dev/null)
            [ -z "$result" ] && result=$(date -d "@$epoch" +"%b %-d, %H:%M" 2>/dev/null)
            result=$(echo "$result" | tr '[:upper:]' '[:lower:]')
            ;;
        *)
            result=$(date -j -r "$epoch" +"%b %-d" 2>/dev/null)
            [ -z "$result" ] && result=$(date -d "@$epoch" +"%b %-d" 2>/dev/null)
            result=$(echo "$result" | tr '[:upper:]' '[:lower:]')
            ;;
    esac
    printf "%s" "$result"
}

# `usage_data.limits[]` is the current shape of the oauth/usage response: one
# self-describing entry per limit, tagged with a `group` ("session" for the
# 5-hour window, "weekly") and carrying its own `percent` and `resets_at`. It
# replaces the flat `.five_hour` / `.seven_day*` keys, which the API still sends
# but no longer always fills in.
#
# A group can hold several entries — the weekly limit is reported once per scope
# (per model, per surface) — so take the one furthest along: that is the one
# that will actually stop you.
pick_limit() { # group name → "<percent>\t<resets_at>", empty if the group is absent
    printf '%s' "$usage_data" | jq -r --arg g "$1" '
        [ .limits[]? | select(type == "object" and .group == $g and .percent != null) ]
        | max_by(.percent)
        | select(. != null)
        | "\(.percent)\t\(.resets_at // "")"' 2>/dev/null
}

iso_to_epoch() {
    local iso_str="$1"

    # GNU `date -d ''` means "today at 00:00" rather than failing, so an absent
    # timestamp would render as a plausible-looking past date. Reject it here.
    case "$iso_str" in ''|null) return 1 ;; esac

    local epoch
    epoch=$(date -d "${iso_str}" +%s 2>/dev/null)
    if [ -n "$epoch" ]; then
        echo "$epoch"
        return 0
    fi

    local stripped="${iso_str%%.*}"
    stripped="${stripped%%Z}"
    stripped="${stripped%%+*}"
    stripped="${stripped%%-[0-9][0-9]:[0-9][0-9]}"

    if [[ "$iso_str" == *"Z"* ]] || [[ "$iso_str" == *"+00:00"* ]] || [[ "$iso_str" == *"-00:00"* ]]; then
        epoch=$(env TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%S" "$stripped" +%s 2>/dev/null)
        [ -z "$epoch" ] && epoch=$(env TZ=UTC date -d "${stripped/T/ }" +%s 2>/dev/null)
    else
        epoch=$(date -j -f "%Y-%m-%dT%H:%M:%S" "$stripped" +%s 2>/dev/null)
        [ -z "$epoch" ] && epoch=$(date -d "${stripped/T/ }" +%s 2>/dev/null)
    fi

    if [ -n "$epoch" ]; then
        echo "$epoch"
        return 0
    fi

    return 1
}

# ── Extract JSON data ───────────────────────────────────
model_name=$(echo "$input" | jq -r '.model.display_name // "Claude"')
# Long-context variants come through as e.g. "Opus 5 (1M context)". The word
# adds nothing here and it is the widest model string there is, so it sets the
# padding floor for the whole bar — shorten it to "Opus 5 (1M)".
model_name="${model_name/ context)/)}"

size=$(echo "$input" | jq -r '.context_window.context_window_size // 200000')
[ "$size" -eq 0 ] 2>/dev/null && size=200000

input_tokens=$(echo "$input" | jq -r '.context_window.current_usage.input_tokens // 0')
cache_create=$(echo "$input" | jq -r '.context_window.current_usage.cache_creation_input_tokens // 0')
cache_read=$(echo "$input" | jq -r '.context_window.current_usage.cache_read_input_tokens // 0')
current=$(( input_tokens + cache_create + cache_read ))

if [ "$size" -gt 0 ]; then
    pct_used=$(( current * 100 / size ))
else
    pct_used=0
fi

# Claude Code reports the effort level on stdin. `.effortLevel` in settings.json
# is only written when you pin one there, so reading it alone made the bar say
# "default" no matter what was actually in effect.
effort=$(echo "$input" | jq -r '.effort.level // empty')
if [ -z "$effort" ]; then
    effort="default"
    settings_path="$HOME/.claude/settings.json"
    if [ -f "$settings_path" ]; then
        effort=$(jq -r '.effortLevel // "default"' "$settings_path" 2>/dev/null)
    fi
fi

# ── LINE 1: Model + Effort │ Directory (branch) │ Context % │ Session ──
pct_color=$(color_for_pct "$pct_used")
cwd=$(echo "$input" | jq -r '.cwd // ""')
[ -z "$cwd" ] || [ "$cwd" = "null" ] && cwd=$(pwd)
dirname=$(basename "$cwd")

git_branch=""
git_dirty=""
if git -C "$cwd" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git_branch=$(git -C "$cwd" symbolic-ref --short HEAD 2>/dev/null)
    if [ -n "$(git -C "$cwd" --no-optional-locks status --porcelain 2>/dev/null)" ]; then
        git_dirty="*"
    fi
fi

# Two possible sources, because Claude Code no longer sends
# `session.start_time` — `cost.total_duration_ms` is the wall clock it reports
# now. Relying on the old key alone meant the timer never appeared at all.
session_duration=""
elapsed=""

session_start=$(echo "$input" | jq -r '.session.start_time // empty')
if [ -n "$session_start" ] && [ "$session_start" != "null" ]; then
    start_epoch=$(iso_to_epoch "$session_start")
    [ -n "$start_epoch" ] && elapsed=$(( $(date +%s) - start_epoch ))
fi

if [ -z "$elapsed" ]; then
    duration_ms=$(echo "$input" | jq -r '.cost.total_duration_ms // empty | floor' 2>/dev/null)
    case "$duration_ms" in
        ''|*[!0-9]*) ;;
        *) elapsed=$(( duration_ms / 1000 )) ;;
    esac
fi

# A clock skew between the two machines can make that negative; show nothing
# rather than "⏱ -42m".
if [ -n "$elapsed" ] && [ "$elapsed" -ge 0 ] 2>/dev/null; then
    if [ "$elapsed" -ge 3600 ]; then
        session_duration="$(( elapsed / 3600 ))h$(( (elapsed % 3600) / 60 ))m"
    elif [ "$elapsed" -ge 60 ]; then
        session_duration="$(( elapsed / 60 ))m"
    else
        session_duration="${elapsed}s"
    fi
fi

skip_perms=""
parent_cmd=$(ps -o args= -p "$PPID" 2>/dev/null)
if [[ "$parent_cmd" == *"--dangerously-skip-permissions"* ]]; then
    skip_perms="⚡  "
fi

# Model and effort read as one phrase ("Opus 5 (1M) high"), so they share a
# segment; their colours keep them distinguishable without a divider.
line1="${blue}${model_name}${reset}"

line1+=" "
effort_fmt="$effort"
case "$effort" in
    high)   line1+="${magenta}${effort_fmt}${reset}" ;;
    medium) line1+="${dim}${effort_fmt}${reset}" ;;
    low)    line1+="${dim}${effort_fmt}${reset}" ;;
    *)      line1+="${dim}${effort_fmt}${reset}" ;;
esac

line1+="${sep}"
line1+="${skip_perms}${cyan}${dirname}${reset}"
if [ -n "$git_branch" ]; then
    # dirty marker sits outside the parens so it does not render as "(main )"
    line1+=" ${green}(${git_branch})${reset}${red}${git_dirty}${reset}"
fi

line1+="${sep}"
line1+="✍️ ${pct_color}${pct_used}%${reset}"

if [ -n "$session_duration" ]; then
    line1+="${sep}"
    line1+="${dim}⏱ ${reset}${white}${session_duration}${reset}"
fi

# ── Rate limits from stdin (primary) ───────────────────
# Taken one limit at a time, because Claude Code sends whichever it has: the
# payload currently carries `five_hour` and no `seven_day` at all. Treating
# stdin as all-or-nothing meant a present `five_hour` suppressed the API call
# that is the only source of the weekly figure, so the weekly meter never
# rendered.
five_hour_pct=""
five_hour_reset_epoch=""
seven_day_pct=""
seven_day_reset_epoch=""

stdin_five_pct=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
if [ -n "$stdin_five_pct" ]; then
    five_hour_pct=$(printf '%s' "$stdin_five_pct" | awk '{printf "%.0f", $1}')
    five_hour_reset_epoch=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
fi

stdin_seven_pct=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
if [ -n "$stdin_seven_pct" ]; then
    seven_day_pct=$(printf '%s' "$stdin_seven_pct" | awk '{printf "%.0f", $1}')
    seven_day_reset_epoch=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')
fi

# ── Fallback: API call (cached) ────────────────────────
# Consulted for whichever meters stdin did not supply — in practice the weekly
# one, every render. The 60s cache keeps that to one request a minute.
cache_file="/tmp/claude/statusline-usage-cache.json"
cache_max_age=60
mkdir -p /tmp/claude

usage_data=""
extra_enabled="false"

if [ -z "$five_hour_pct" ] || [ -z "$seven_day_pct" ]; then
    needs_refresh=true

    if [ -f "$cache_file" ]; then
        cache_mtime=$(stat -c %Y "$cache_file" 2>/dev/null || stat -f %m "$cache_file" 2>/dev/null)
        now=$(date +%s)
        cache_age=$(( now - cache_mtime ))
        if [ "$cache_age" -lt "$cache_max_age" ]; then
            needs_refresh=false
            usage_data=$(cat "$cache_file" 2>/dev/null)
        fi
    fi

    if $needs_refresh; then
        token=""
        if [ -n "$CLAUDE_CODE_OAUTH_TOKEN" ]; then
            token="$CLAUDE_CODE_OAUTH_TOKEN"
        elif command -v security >/dev/null 2>&1; then
            blob=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null)
            if [ -n "$blob" ]; then
                token=$(echo "$blob" | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null)
            fi
        fi
        if [ -z "$token" ] || [ "$token" = "null" ]; then
            creds_file="${HOME}/.claude/.credentials.json"
            if [ -f "$creds_file" ]; then
                token=$(jq -r '.claudeAiOauth.accessToken // empty' "$creds_file" 2>/dev/null)
            fi
        fi
        if [ -z "$token" ] || [ "$token" = "null" ]; then
            if command -v secret-tool >/dev/null 2>&1; then
                blob=$(timeout 2 secret-tool lookup service "Claude Code-credentials" 2>/dev/null)
                if [ -n "$blob" ]; then
                    token=$(echo "$blob" | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null)
                fi
            fi
        fi

        if [ -n "$token" ] && [ "$token" != "null" ]; then
            response=$(curl -s --max-time 5 \
                -H "Accept: application/json" \
                -H "Content-Type: application/json" \
                -H "Authorization: Bearer $token" \
                -H "anthropic-beta: oauth-2025-04-20" \
                -H "User-Agent: claude-code/2.1.34" \
                "https://api.anthropic.com/api/oauth/usage" 2>/dev/null)
            if [ -n "$response" ] && echo "$response" | jq -e '.five_hour' >/dev/null 2>&1; then
                usage_data="$response"
                echo "$response" > "$cache_file"
            fi
        fi
        if [ -z "$usage_data" ] && [ -f "$cache_file" ]; then
            usage_data=$(cat "$cache_file" 2>/dev/null)
        fi
    fi

elif [ -f "$cache_file" ]; then
    # Both meters came from stdin. No request — but the cached response still
    # says whether extra usage is enabled.
    usage_data=$(cat "$cache_file" 2>/dev/null)
fi

if [ -n "$usage_data" ] && echo "$usage_data" | jq -e . >/dev/null 2>&1; then
    # Only ever fills the gaps: anything stdin already provided wins, as it is
    # live where this is up to 60s old.
    if [ -z "$five_hour_pct" ]; then
        five=$(pick_limit session)
        if [ -n "$five" ]; then
            five_hour_pct=$(printf '%s' "${five%%$'\t'*}" | awk '{printf "%.0f", $1}')
            five_hour_reset_epoch=$(iso_to_epoch "${five#*$'\t'}")
        else
            five_hour_pct=$(echo "$usage_data" | jq -r '.five_hour.utilization // 0' | awk '{printf "%.0f", $1}')
            five_hour_reset_epoch=$(iso_to_epoch "$(echo "$usage_data" | jq -r '.five_hour.resets_at // empty')")
        fi
    fi

    if [ -z "$seven_day_pct" ]; then
        week=$(pick_limit weekly)
        if [ -n "$week" ]; then
            seven_day_pct=$(printf '%s' "${week%%$'\t'*}" | awk '{printf "%.0f", $1}')
            seven_day_reset_epoch=$(iso_to_epoch "${week#*$'\t'}")
        else
            # Legacy shape. `.seven_day` itself is null on accounts whose weekly
            # limit is reported per scope (`seven_day_opus`, `seven_day_cowork`,
            # …), which used to read as a flat 0% — so scan all of them.
            weekly_legacy=$(echo "$usage_data" | jq -c '
                [ to_entries[]
                  | select(.key | startswith("seven_day"))
                  | .value
                  | select(type == "object" and .utilization != null) ]
                | max_by(.utilization) // empty')
            if [ -n "$weekly_legacy" ]; then
                seven_day_pct=$(echo "$weekly_legacy" | jq -r '.utilization' | awk '{printf "%.0f", $1}')
                seven_day_reset_epoch=$(iso_to_epoch "$(echo "$weekly_legacy" | jq -r '.resets_at // empty')")
            fi
        fi
    fi

    extra_enabled=$(echo "$usage_data" | jq -r '.extra_usage.is_enabled // false')
fi

# ── Rate limit lines ────────────────────────────────────
rate_lines=""
bar_width=10

if [ -n "$five_hour_pct" ]; then
    five_hour_reset=$(format_epoch_time "$five_hour_reset_epoch" "time")
    five_hour_bar=$(build_bar "$five_hour_pct" "$bar_width")
    five_hour_pct_color=$(color_for_pct "$five_hour_pct")
    five_hour_pct_fmt="$five_hour_pct"

    rate_lines+="${orange}5h${reset} ${five_hour_bar} ${five_hour_pct_color}${five_hour_pct_fmt}%${reset}"
    [ -n "$five_hour_reset" ] && rate_lines+=" ${dim}⟳${reset} ${white}${five_hour_reset}${reset}"
fi

if [ -n "$seven_day_pct" ]; then
    seven_day_reset=$(format_epoch_time "$seven_day_reset_epoch" "date")
    seven_day_bar=$(build_bar "$seven_day_pct" "$bar_width")
    seven_day_pct_color=$(color_for_pct "$seven_day_pct")
    seven_day_pct_fmt="$seven_day_pct"

    [ -n "$rate_lines" ] && rate_lines+="${sep}"
    rate_lines+="${orange}7d${reset} ${seven_day_bar} ${seven_day_pct_color}${seven_day_pct_fmt}%${reset}"
    [ -n "$seven_day_reset" ] && rate_lines+=" ${dim}⟳${reset} ${white}${seven_day_reset}${reset}"
fi

if [ "$extra_enabled" = "true" ] && [ -n "$usage_data" ]; then
    extra_pct=$(echo "$usage_data" | jq -r '.extra_usage.utilization // 0' | awk '{printf "%.0f", $1}')
    extra_used=$(echo "$usage_data" | jq -r '.extra_usage.used_credits // 0' | awk '{printf "%.2f", $1/100}')
    extra_limit=$(echo "$usage_data" | jq -r '.extra_usage.monthly_limit // 0' | awk '{printf "%.2f", $1/100}')
    extra_bar=$(build_bar "$extra_pct" "$bar_width")
    extra_pct_color=$(color_for_pct "$extra_pct")

    extra_reset=$(date -v+1m -v1d +"%b %-d" 2>/dev/null | tr '[:upper:]' '[:lower:]')
    if [ -z "$extra_reset" ]; then
        extra_reset=$(date -d "$(date +%Y-%m-01) +1 month" +"%b %-d" 2>/dev/null | tr '[:upper:]' '[:lower:]')
    fi

    [ -n "$rate_lines" ] && rate_lines+="${sep}"
    rate_lines+="${white}extra${reset} ${extra_bar} ${extra_pct_color}\$${extra_used}${dim}/${reset}${white}\$${extra_limit}${reset} ${dim}⟳${reset} ${white}${extra_reset}${reset}"
fi

# ── Output ──────────────────────────────────────────────
out="$line1"
[ -n "$rate_lines" ] && out+="${sep}${rate_lines}"

rendered=$(printf "%b" "$out")

if $pad; then
    # The model name, directory and branch have no bounded width — they still
    # change length when you /model, cd, or check out another branch. So
    # remember the widest this bar has been and pad back up to it: the string
    # as a whole can then never get shorter. Trailing spaces are invisible, so
    # this costs nothing on screen.
    plain=$(printf '%s' "$rendered" | sed $'s/\033\[[0-9;]*m//g')
    w=$(printf '%s' "$plain" | wc -m | tr -d ' ')

    state_dir=/tmp/claude
    mkdir -p "$state_dir" 2>/dev/null
    sid=$(printf '%s' "$input" | jq -r '.session_id // .session.id // "default"' 2>/dev/null)
    case "$sid" in ''|null) sid="default" ;; esac
    sid=$(printf '%s' "$sid" | tr -c 'A-Za-z0-9._-' '_')
    width_file="$state_dir/statusline-width.$sid"

    max_w=0
    [ -f "$width_file" ] && max_w=$(cat "$width_file" 2>/dev/null)
    case "$max_w" in ''|*[!0-9]*) max_w=0 ;; esac

    if [ "$w" -gt "$max_w" ]; then
        max_w=$w
        printf '%s' "$w" > "$width_file" 2>/dev/null
    fi

    n=$(( max_w - w ))
    # Without per-field padding the natural width swings much further — a
    # vanishing weekly meter alone is ~25 cells — so this backstop, which only
    # exists to stop one pathological outlier from padding forever, has to sit
    # well above the widest plausible swing.
    [ "$n" -gt 160 ] && n=160
    while [ "$n" -gt 0 ]; do rendered+=" "; n=$(( n - 1 )); done
fi

printf '%s' "$rendered"

exit 0
