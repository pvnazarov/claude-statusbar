# CLAUDE.md

Guidance for Claude Code instances working in this repo.

## What this is

A single bash script (`statusline.sh`) that Claude Code invokes to render its
status bar. It reads a JSON payload on **stdin** and prints one ANSI-coloured
line. Every value is parsed with `jq`.

## Read this before debugging an install

**On Windows, read [`claude-statusbar-windows-setup.md`](claude-statusbar-windows-setup.md) first.**

Reported failures on Windows have so far been **environment problems, not script
bugs**. Do not start editing `statusline.sh` in response to a broken bar. The
three known causes, all of which fail *silently* — the bar still renders, just
with values missing:

| Symptom | Actual cause | Confirm with |
|---|---|---|
| Blank model name, `0%` context, **no rate-limit meters** | `jq` not on the inherited PATH | `bash -c 'command -v jq'` |
| Nothing renders, or a WSL error | bare `bash` resolves to the WSL launcher, not Git Bash | `Get-Command bash \| Select Source` |
| `$'\r': command not found` | file checked out with CRLF endings | `file statusline.sh` |

Key non-obvious facts, each of which has cost real debugging time:

- The statusline runs as a **non-login, non-interactive** shell. `/etc/profile`
  and `~/.bashrc` are never sourced, so `$HOME/bin` is **not** on PATH. Claude
  Code also passes down the environment from *when it was launched* — installing
  a dependency afterwards does not help, and restarting may not either.
- **Claude Code swallows the statusline's stderr.** A broken script looks like a
  cosmetic glitch. Always reproduce by piping a saved JSON payload into the
  script by hand; that is where the real error appears. See the "Verify it
  properly" section of the Windows guide for a ready-made payload.
- `chmod` is a no-op for permissions on NTFS. Use `icacls` on Windows.

## Conventions

- **`*.sh` must keep LF line endings.** CRLF breaks the script on every POSIX
  shell including Git Bash. If you add shell files, verify with
  `file <name>` — it must not report `with CRLF line terminators`.
- The script deliberately supports **both** BSD (`date -j -r`) and GNU
  (`date -d @`) date syntax so it works on macOS, Linux and Git Bash. Preserve
  both code paths; do not "simplify" one away.
- `ps -o args=` (used to show a `⚡` for `--dangerously-skip-permissions`) is
  unsupported by Git Bash's `ps`. It fails silently and the indicator simply
  never appears. This is intentional and harmless — not a bug to fix.
- Rate limits come from stdin when Claude Code provides them, and otherwise from
  the `oauth/usage` API, cached 60s. **Both paths must keep working**; test each
  separately when touching that logic.
- The API response carries the same numbers in two shapes, and **both fallbacks
  must keep working** — real accounts are served each of them:
  - `limits[]`, the current one: an entry per limit with `group`
    (`session` / `weekly`), `percent` and `resets_at`. Read via `pick_limit`.
  - the flat `.five_hour` / `.seven_day*` keys.

  A weekly limit appears **once per scope** (`seven_day_opus`,
  `seven_day_cowork`, …) and plain `.seven_day` is then `null` — reading only
  that key pinned the weekly meter at 0%. Both paths take the furthest-along
  entry. Test with `limits[]` present, absent, and malformed; a saved response
  from `/tmp/claude/statusline-usage-cache.json` edited with `jq` is enough.
- **`export LC_NUMERIC=C` at the top must stay.** Percentages arrive as `42.6`
  and are rounded with `printf`/`awk`, which under a comma-decimal locale
  (`LC_NUMERIC=fr_FR` etc.) reject the dot: bash `printf` errors to stderr —
  swallowed, so invisible — and `awk` silently truncates, so `42.6` renders as
  `42%`. It scopes to numbers only; dates still follow `LC_TIME`.
- `iso_to_epoch` rejects an empty or `null` argument up front, because GNU
  `date -d ''` resolves to *today at 00:00* rather than failing. Without that
  guard a missing `resets_at` renders as a convincing past date.
- **The output must never get shorter than the previous render.** A renderer that
  draws a shorter string does not necessarily erase the tail of the old one, so
  stale characters remain on screen — see the "Redraw artifacts" section of the
  README. Every variable-width field is therefore padded to a fixed width via
  `padstr`/`padnum`, and the finished line is padded up to the widest seen this
  session. If you add a segment, pad it; if you change one, keep its width
  fixed. `SL_NO_PAD=1` disables the padding for comparison.

## Testing changes

There is no test suite. Before committing a change to `statusline.sh`, exercise
all three input cases by hand and check for empty stderr:

1. stdin payload **with** `rate_limits` → both meters render
2. same payload with `rate_limits` removed → meters come from the API fallback
3. empty stdin → prints the literal `Claude`, exits 0

If you touched the fallback parsing, run case 2 against several shapes of the
cached response — `limits[]` present, deleted, and set to something that isn't
an array; weekly present only as `seven_day_<scope>`; `resets_at: null`; no
weekly data at all. Each must render sane values, omit what it cannot know, and
leave stderr empty.
