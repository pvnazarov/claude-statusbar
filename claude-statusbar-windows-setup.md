# Installing a Claude Code status bar on Windows

Notes from getting `github.com/pvnazarov/claude-statusbar` working on Windows 11
(2026-07-29). The script itself is fine and cross-platform — **every problem was
Windows environment plumbing**. Read the three traps before installing.

Verified on: Windows 11 Enterprise 10.0.26100, Git for Windows 2.55.0, jq 1.8.2,
Claude Code with `~/.claude/statusline.sh`.

---

## TL;DR — the three traps

| # | Trap | Symptom | Fix |
|---|---|---|---|
| 1 | `jq` not on the *inherited* PATH | Bar renders but model name is blank, context is `0%`, **no limit bars** | Put `jq.exe` in Git's `usr\bin\` |
| 2 | Bare `bash` is the **WSL** launcher, not Git Bash | Status bar blank, or WSL window/error | Use the absolute path to Git's `bash.exe` |
| 3 | `git clone` checks out **CRLF** | `$'\r': command not found`, script dies immediately | Strip CR on install, or set `.gitattributes` |

All three fail *quietly* — the bar still draws, just with everything missing. It
reads like a bug in the script when it isn't.

---

## Trap 1: the PATH is inherited, and it is stale

This is the one that cost the most time, and it is genuinely counter-intuitive.

The script parses **every** value with `jq` — model name, context %, and both
rate-limit meters. With `jq` missing, each call fails and each variable becomes
empty. The rate-limit block is guarded by `if [ -n "$five_hour_pct" ]`, so it is
skipped entirely and you get:

```
(blank) │ ✍️ 0% │ ai │ ◑ default
```

Two compounding reasons `jq` can be missing even when it's installed:

**a) Claude Code inherits its environment from launch time.** Install `jq` via
winget *after* starting Claude Code and the running process never sees the new
PATH. Note that restarting Claude Code may not be enough either — the launcher
itself can hand down a cached environment. Don't trust a restart to prove
anything.

**b) The statusline runs as a non-login, non-interactive shell.** Claude Code
invokes `bash.exe script.sh` directly. That means:

- `/etc/profile` and `~/.bashrc` are **never sourced**
- so `$HOME/bin` is **never added** to PATH — putting `jq.exe` in `~/bin` does *not* work
- the only PATH it gets is Claude Code's inherited Windows PATH, plus the
  `/usr/bin` and `/mingw64/bin` that the msys2 runtime injects when `bash.exe` starts

That last part is the diagnostic key: **if `sed`, `date`, `tr`, `git` and `curl`
work but only `jq` fails, `/usr/bin` is on the effective PATH and the winget
directory is not.** So `/usr/bin` is the reliable install location.

### The fix

```powershell
winget install --id jqlang.jq --exact
```

winget adds its package directory to the *persistent user* PATH, which is not
enough (see above). Copy the binary somewhere always reachable:

```powershell
$jq  = (Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages" -Filter jq.exe -Recurse -Depth 3 | Select-Object -First 1).FullName
$dest = "$env:LOCALAPPDATA\Programs\Git\usr\bin\jq.exe"
Copy-Item $jq $dest
& $dest --version   # expect jq-1.8.2
```

`jq.exe` is a single ~1 MB static binary with no DLL dependencies, so a plain
copy is sufficient.

> **Adjust the Git path for your machine.** A system-wide Git install lives at
> `C:\Program Files\Git\usr\bin` (needs admin to write). Find yours with:
> `(Get-Command git).Source` — then go up one level from `cmd\` or `bin\`.

**Caveat:** a Git for Windows upgrade can wipe `usr\bin` and silently remove
`jq.exe`, breaking the bar the same way. See *Surviving upgrades* below.

### Alternative if you don't want to write into the Git install

Wrap the command in `settings.json` so it fixes its own PATH. More robust across
Git upgrades, uglier to read:

```json
{
  "statusLine": {
    "type": "command",
    "command": "\"C:/Users/<you>/AppData/Local/Programs/Git/bin/bash.exe\" -c \"export PATH=\\\"/c/Users/<you>/AppData/Local/Microsoft/WinGet/Packages/jqlang.jq_Microsoft.Winget.Source_8wekyb3d8bbwe:$PATH\\\"; exec /c/Users/<you>/.claude/statusline.sh\""
  }
}
```

The winget package directory name embeds a version-independent hash, so it is
stable across `jq` updates — but verify it rather than trusting this string.

---

## Trap 2: `bash` does not mean Git Bash

The upstream README says:

```json
"command": "bash \"$HOME/.claude/statusline.sh\""
```

**Do not use this on Windows.** On a default Windows 11 box:

```powershell
PS> Get-Command bash | Select-Object Source
C:\Users\<you>\AppData\Local\Microsoft\WindowsApps\bash.exe   # 0 bytes
```

That is a 0-byte *App Execution Alias* for **WSL**, and it usually wins on PATH
because `WindowsApps` sits near the front. You'd be running the script under a
Linux distro that has no access to your Windows `~/.claude` layout — or getting a
"WSL is not installed" error. `$HOME` is also not reliably set for a process
Claude Code spawns.

### The fix — absolute paths, forward slashes

```json
{
  "statusLine": {
    "type": "command",
    "command": "\"C:/Users/<you>/AppData/Local/Programs/Git/bin/bash.exe\" \"C:/Users/<you>/.claude/statusline.sh\""
  }
}
```

Two things worth copying here:

- **Forward slashes in Windows paths.** Valid in Win32 APIs and it avoids
  double-backslash escaping inside JSON. `C:/Users/...` is far less error-prone
  than `C:\\Users\\...`.
- **Quote each path separately**, escaped as `\"` for JSON. `Program Files` and
  usernames with spaces break unquoted commands.

---

## Trap 3: `git clone` gives you CRLF, and bash chokes

If `core.autocrlf=true` (the Git for Windows installer's default — check with
`git config --global core.autocrlf`), every clone converts LF to CRLF on
checkout:

```bash
$ git -C claude-statusbar ls-files --eol statusline.sh
i/lf    w/crlf  attr/    statusline.sh      # index LF, working tree CRLF
```

A shell script with CRLF endings fails on the shebang and then on essentially
every line: `$'\r': command not found`, `syntax error near unexpected token`.
Note that `file` reports this plainly — `with CRLF line terminators` — which is a
fast way to confirm it.

### The fix at install time

```bash
tr -d '\r' < statusline.sh > ~/.claude/statusline.sh
chmod +x ~/.claude/statusline.sh
file ~/.claude/statusline.sh   # must NOT say "with CRLF line terminators"
```

### The durable fix — `.gitattributes`

If you fork or vendor the repo, commit a `.gitattributes` so line endings are
correct for everyone regardless of their `core.autocrlf`:

```gitattributes
# Shell scripts must keep LF or they break on any POSIX shell, incl. Git Bash
*.sh text eol=lf
statusline.sh text eol=lf
```

Then re-normalize the working tree once:

```bash
git add --renormalize .
git commit -m "Force LF endings for shell scripts"
```

This is the right fix for the upstream repo too — worth a PR if it's your fork.

---

## Full install, start to finish

```powershell
# 0. Prerequisites (bash, curl, git, coreutils all come from Git for Windows)
winget install --id Git.Git --exact
winget install --id jqlang.jq --exact

# 1. Make jq reachable by a non-login bash (see Trap 1)
$gitRoot = Split-Path (Split-Path (Get-Command git).Source)      # ...\Git
$jq = (Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages" -Filter jq.exe -Recurse -Depth 3 | Select-Object -First 1).FullName
Copy-Item $jq "$gitRoot\usr\bin\jq.exe"

# 2. Get the script
git clone --depth 1 https://github.com/pvnazarov/claude-statusbar.git "$env:TEMP\csb"
```

```bash
# 3. Install with LF endings (see Trap 3) — run in Git Bash
tr -d '\r' < "$TEMP/csb/statusline.sh" > ~/.claude/statusline.sh
chmod +x ~/.claude/statusline.sh
```

4. Add to `~/.claude/settings.json` — absolute path to **Git's** bash (Trap 2):

```json
{
  "statusLine": {
    "type": "command",
    "command": "\"C:/Users/<you>/AppData/Local/Programs/Git/bin/bash.exe\" \"C:/Users/<you>/.claude/statusline.sh\""
  }
}
```

5. Verify before restarting Claude Code (next section).

---

## Verify it properly

Don't judge by looking at the bar — test the script directly with a fake payload.
This catches all three traps in one shot and shows you the actual stderr, which
Claude Code hides.

```bash
cat > /tmp/sl-test.json <<'EOF'
{"model":{"display_name":"Opus 5"},"cwd":"C:/Users/me/proj",
 "context_window":{"context_window_size":200000,
   "current_usage":{"input_tokens":5000,"cache_read_input_tokens":40000,"cache_creation_input_tokens":1000}},
 "session":{"start_time":"2026-07-29T02:00:00Z"},
 "rate_limits":{"five_hour":{"used_percentage":42.5,"resets_at":1785000000},
                "seven_day":{"used_percentage":11.2,"resets_at":1785400000}}}
EOF

"C:/Users/<you>/AppData/Local/Programs/Git/bin/bash.exe" ~/.claude/statusline.sh < /tmp/sl-test.json
```

Expect a full line with both meters and **no error output**:

```
Opus 5 │ ✍️ 23% │ proj │ ⏱ 22m │ ◑ default │ current ●●●●○○○○○○  42% ⟳ 7:20pm │ weekly ●○○○○○○○○○  11% ⟳ jul 30, 10:26am
```

Three cases worth testing separately:

| Test | How | Expect |
|---|---|---|
| stdin rate limits | payload above | both meters |
| API fallback | `jq 'del(.rate_limits)' sl-test.json \| bash ~/.claude/statusline.sh` | both meters, from your real usage |
| empty input | `bash ~/.claude/statusline.sh < /dev/null` | literal `Claude`, exit 0 |

The API fallback path matters independently: it calls
`https://api.anthropic.com/api/oauth/usage` with the OAuth token from
`~/.claude/.credentials.json` and caches to
`/tmp/claude/statusline-usage-cache.json` for 60s. On Windows, Git Bash maps
`/tmp` to the Windows temp directory, so that file is really at:

```
%LOCALAPPDATA%\Temp\claude\statusline-usage-cache.json
```

(Confirm on any machine with `cd /tmp && pwd -W`.) If the meters look frozen,
delete it. Note this is the *same* tree Claude Code uses for its own scratchpad
directories, so don't wipe `%LOCALAPPDATA%\Temp\claude\` wholesale — remove just
the one file.

To prove the PATH fix specifically, scrub the winget directory from PATH and
re-run — it should still work:

```bash
export PATH="$(echo "$PATH" | tr ':' '\n' | grep -v WinGet | paste -sd: -)"
bash ~/.claude/statusline.sh < /tmp/sl-test.json
```

---

## Troubleshooting

| Symptom | Cause | Check |
|---|---|---|
| Blank model, `0%`, no meters | `jq` missing (Trap 1) | `bash -c 'command -v jq'` |
| `$'\r': command not found` | CRLF (Trap 3) | `file ~/.claude/statusline.sh` |
| Nothing at all / WSL error | bare `bash` = WSL (Trap 2) | `Get-Command bash \| Select Source` |
| Line 1 fine, meters missing | stdin has no `rate_limits` **and** API fallback failed | run the fallback test above |
| Meters stuck at old values | 60s cache | `rm /tmp/claude/statusline-usage-cache.json` |
| Worked yesterday, not today | Git upgrade wiped `usr\bin\jq.exe` | re-copy `jq.exe` |
| `⏱` shows negative seconds | clock/timezone skew in `start_time` | cosmetic; ignore |

**Debugging rule:** Claude Code swallows the statusline's stderr. Always
reproduce by piping a saved payload into the script by hand — that's where the
real error message lives.

---

## Surviving upgrades

`jq.exe` in `<GitRoot>\usr\bin` is the pragmatic fix but is not upgrade-proof.
Options, roughly in order of preference:

1. **Re-check after any Git update.** Cheapest. Run the verify command above.
2. **Wrap the PATH in `settings.json`** (Trap 1, alternative) — survives Git
   upgrades, but breaks if the winget package path changes.
3. **Keep a private `bin` and reference it explicitly.** Put `jq.exe` in
   `~/.claude/bin\` and prepend that in the `settings.json` `-c` wrapper. Fully
   under your control, outside both Git's and winget's install trees. Do **not**
   rely on `~/bin` being auto-added — it isn't, for a non-login shell.

---

## Multi-machine setups

`~/.claude/settings.json` lives outside any repo and is not synced by file-sync
tools, so **this install must be repeated on every machine** — putting the script
in a synced folder does not carry the configuration with it.

Git can also be installed per-user (`%LOCALAPPDATA%\Programs\Git`) on one machine
and system-wide (`C:\Program Files\Git`) on another, so the `bash.exe` path in
`settings.json` legitimately differs between them. Don't copy that value between
machines — discover it:

```powershell
(Get-Command git).Source                    # -> ...\Git\cmd\git.exe
$env:LOCALAPPDATA                           # user-install root
(Get-Command jq -ErrorAction SilentlyContinue).Source
```

---

## Dependency reference

The script needs all of these on the **effective** (inherited + msys-injected)
PATH:

| Tool | Source on Windows | Notes |
|---|---|---|
| `bash` | Git for Windows `bin\bash.exe` | must be Git's, not WSL |
| `jq` | winget `jqlang.jq` | the one that's typically missing |
| `curl` | Git `mingw64\bin` | API fallback only |
| `git` | Git `cmd` | branch/dirty indicator |
| `date`, `sed`, `tr`, `awk`, `basename`, `stat` | Git `usr\bin` | present by default |

The script handles both BSD (`date -j -r`) and GNU (`date -d @`) date syntax, so
the Git Bash GNU path works without modification. `ps -o args=` (used to detect
`--dangerously-skip-permissions` and show a `⚡`) is not supported by Git Bash's
`ps` — it fails silently and the indicator just never appears. Harmless.

---

## Sources

- Script: <https://github.com/pvnazarov/claude-statusbar> (commit `8620159`)
- Upstream: <https://github.com/nilbuild/claude-statusline>
- Usage endpoint: `GET https://api.anthropic.com/api/oauth/usage`
  (Bearer token, header `anthropic-beta: oauth-2025-04-20`)
