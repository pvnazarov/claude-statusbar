# claude-statusbar

A compact, single-line status bar for [Claude Code](https://claude.com/claude-code).

It shows, all on **one line**:

```
Opus 4.8 │ ✍️  18% │ ai (main)* │ ⏱ 12m   │ ◑ default │ current ●●●●○○○○○○  42% ⟳ 10:00pm │ weekly ●○○○○○○○○○  18% ⟳ jul 30, 10:00am
```

| Segment | Meaning |
|---|---|
| `Opus 4.8` | Active model — long-context variants are shortened, so `Opus 5 (1M context)` shows as `Opus 5 (1M)` |
| `✍️ 18%` | Context window used (turns yellow/red as it fills) |
| `ai (main)*` | Current directory + git branch (`*` = uncommitted changes) |
| `⏱ 12m` | Session duration |
| `◑ default` | Reasoning effort level |
| `current …` | 5-hour rate-limit usage + reset time |
| `weekly …` | 7-day rate-limit usage + reset time |
| `extra …` | Extra-usage credits (only shown if enabled) |

Colors: green → orange → yellow → red as any meter fills.

## Install

1. Copy the script into your Claude config directory:

   ```bash
   cp statusline.sh ~/.claude/statusline.sh
   chmod +x ~/.claude/statusline.sh
   ```

2. Point Claude Code at it. Add this to `~/.claude/settings.json`:

   ```json
   {
     "statusLine": {
       "type": "command",
       "command": "bash \"$HOME/.claude/statusline.sh\""
     }
   }
   ```

3. Start (or restart) Claude Code — the bar renders under the prompt.

> **On Windows, follow [`claude-statusbar-windows-setup.md`](claude-statusbar-windows-setup.md) instead.**
> The steps above need three changes: bare `bash` resolves to the WSL launcher
> rather than Git Bash, `jq` usually isn't on the PATH the status bar actually
> inherits, and `git clone` checks the script out with CRLF endings. All three
> fail silently — the bar renders with everything missing.

## Requirements

- `bash`, `jq`, `curl`, `git`, `date` (standard on macOS and most Linux distros)
- Works on macOS (BSD `date`) and Linux (GNU `date`) — both code paths are handled.
- Windows: works under Git Bash, but needs setup — see
  [`claude-statusbar-windows-setup.md`](claude-statusbar-windows-setup.md).

## How rate-limit data works

Recent Claude Code versions pass rate-limit info directly on stdin, and the
script uses that first. If it isn't present, the script falls back to the
authenticated `oauth/usage` API endpoint and caches the result in
`/tmp/claude/statusline-usage-cache.json` for 60 seconds so it stays fast.

That API response has changed shape, and the script reads it in this order:

1. **`limits[]`** — the current form: one self-describing entry per limit,
   tagged with a `group` (`session` for the 5-hour window, `weekly`) and
   carrying its own `percent` and `resets_at`.
2. **The flat `.five_hour` / `.seven_day` keys** — still sent, but no longer
   always filled in.

The weekly limit is reported **once per scope** — per model and per surface, as
`seven_day_opus`, `seven_day_cowork` and so on, with plain `.seven_day` left
`null`. The bar shows whichever scope is furthest along, since that is the one
that will actually stop you. (Reading only `.seven_day`, as earlier versions
did, made the weekly meter sit at a permanent `0%`.)

The `weekly` meter therefore reflects one scope, not your account as a whole.
Inspect the raw response to see them all:

```bash
jq '.limits, (to_entries[] | select(.key | startswith("seven_day")))' \
  /tmp/claude/statusline-usage-cache.json
```

## Redraw artifacts (leftovers from the previous render)

If the bar shows stale characters — a percentage reading `123%` when it should
read `12%`, or old text where the new bar has blank space — the cause is that a
status-line renderer which draws a **shorter** string than last time does not
necessarily erase the tail of the previous one. It looks like "spaces don't
paint", but in fact nothing was written over those cells at all.

The script therefore never lets its output shrink: every variable-width field
is padded to a fixed width (so each field stays at a constant column), and the
finished line is padded up to the widest it has been this session, tracked in
`/tmp/claude/statusline-width.<session>`. Trailing spaces are invisible, so
this costs nothing on screen.

Run with `SL_NO_PAD=1` to disable the padding and compare.

`tools/` holds the diagnostics used to pin this down:

| Tool | What it does |
|---|---|
| `term-test.sh` | Draws over itself using spaces vs. cursor-forward vs. `ESC[K`, so you can see which mechanism matches your artifact. Needs a tty. |
| `width-probe.sh` | Asks your terminal, via cursor-position reports, how wide it *actually* draws each glyph, and measures the real width of a full bar. Flags any mismatch against the naive count. |
| `redraw-test.sh` | A throwaway status line that marches a gap across a field of `#` — one drawn with spaces, one with dots — to test whether spaces paint inside the panel itself. |
| `statusline-log.sh` | Transparent wrapper that logs every render with its cell count to `/tmp/claude/statusline-debug.log`. |
| `select.sh` | Switches `statusLine.command` between the real bar and the harnesses above. |

Worth knowing if you change the glyphs: `●`, `○`, `│` and `◑` are East-Asian
*Ambiguous* width, meaning the terminal decides whether they occupy one cell or
two, and `✍️` is an emoji-presentation sequence (U+270D + U+FE0F) that many
terminals draw two cells wide. `width-probe.sh` will tell you what yours does.

## Customizing

Everything is plain bash. A few common tweaks:

- **Colors** — edit the RGB values in the `── Colors ──` block near the top.
- **Bar width** — change `bar_width=10`.
- **Drop a segment** — the final line is assembled in the `── Output ──` block
  from `line1` and `rate_lines`; remove pieces you don't want.
- **Back to multi-line** — this is the single-line variant. To split the rate
  meters onto their own lines again, change the `${sep}` joins in the
  `── Rate limit lines ──` and `── Output ──` blocks back to `\n`.
- **Model name** — it is printed as Claude Code reports it, minus the
  `(1M context)` → `(1M)` shortening applied just after `display_name` is read.

## Credits

Based on [nilbuild/claude-statusline](https://github.com/nilbuild/claude-statusline),
adapted into a single-line layout.

## License

MIT — see [LICENSE](LICENSE).
