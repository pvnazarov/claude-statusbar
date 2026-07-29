# claude-statusbar

A compact, single-line status bar for [Claude Code](https://claude.com/claude-code).

It shows, all on **one line**:

```
Opus 4.8 │ ✍️ 18% │ ai (main*) │ ⏱ 12m │ ◑ default │ current ●●●●○○○○○○ 42% ⟳ 10:00pm │ weekly ●○○○○○○○○○ 18% ⟳ jul 30, 10:00am
```

| Segment | Meaning |
|---|---|
| `Opus 4.8` | Active model |
| `✍️ 18%` | Context window used (turns yellow/red as it fills) |
| `ai (main*)` | Current directory + git branch (`*` = uncommitted changes) |
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

## Customizing

Everything is plain bash. A few common tweaks:

- **Colors** — edit the RGB values in the `── Colors ──` block near the top.
- **Bar width** — change `bar_width=10`.
- **Drop a segment** — the final line is assembled in the `── Output ──` block
  from `line1` and `rate_lines`; remove pieces you don't want.
- **Back to multi-line** — this is the single-line variant. To split the rate
  meters onto their own lines again, change the `${sep}` joins in the
  `── Rate limit lines ──` and `── Output ──` blocks back to `\n`.

## Credits

Based on [nilbuild/claude-statusline](https://github.com/nilbuild/claude-statusline),
adapted into a single-line layout.

## License

MIT — see [LICENSE](LICENSE).
