# tbled — Claude Code status lights on the MacBook Pro Touch Bar

One coloured tile per Claude Code session, live on the Touch Bar (or the menu
bar, or MTMR). Inspired by [cled](https://github.com/latent-spaces/cled), which
does the same for RGB keyboards via OpenRGB — tbled adapts the idea to the 2019
MacBook Pro Touch Bar and drives it from **Claude Code hooks** instead of
scraping terminals.

```
🔴 my-api    🟡 webapp    🟢 infra
 working      waiting      ready
```

| Colour | State    | Meaning                                                    |
|--------|----------|------------------------------------------------------------|
| 🔴 red    | working  | Claude is mid-turn (thinking, running tools, editing)      |
| 🟡 yellow | waiting  | blocked on you (permission prompt / question)              |
| 🟢 green  | ready    | turn finished, session idle                                |
| ⚪ dim    | stale    | no activity for > 20 min (probably abandoned)              |

## Features

- **Live status at a glance** — Know the state of all Claude Code sessions without switching windows
- **Multiple sessions** — Track 3+ projects simultaneously with color-coded tiles
- **Smart state detection** — Automatically detects working/waiting/ready/stale states from hook events
- **Touch Bar + Menu Bar** — Renders on Touch Bar (primary) with menu bar fallback for non-Touch-Bar Macs
- **Session names** — Tiles show each session's name (honours `/rename`; otherwise Claude's derived name), so two sessions in the same repo stay distinct
- **Catches every session** — `tbled sync` also reads Claude's own live session files, so sessions started *before* you installed the hooks (or in a config dir without them) still show up (busy/waiting/idle → 🔴/🟡/🟢)
- **Tap to focus** — Click a tile to jump directly to that session's terminal tab
- **Zero overhead** — State stored in files (no daemon), hooks integrate with Claude Code's native event system

## How it works

Two decoupled halves talking through a state directory — no sockets, no daemon:

```
Claude Code session(s)                         renderer
  │ hooks (tbled-hook)                            │ reads
  ▼                                               ▼
~/.tbled/sessions/<session_id>.json  ◄─────  tbled status  (CLI)
                                             MTMR widget    (Touch Bar, today)
                                             tbled-touchbar (native app)
```

Each hook event maps to a state and the hook writes the session's JSON file
atomically. The event → state mapping:

| Hook event                              | Effect                                  |
|-----------------------------------------|-----------------------------------------|
| `SessionStart`                          | create file, `ready`                    |
| `UserPromptSubmit`                      | `working`                               |
| `PreToolUse` / `PostToolUse` / batch    | `working` + keep-alive                  |
| `Notification` (`permission_prompt`, `elicitation_dialog`, `agent_needs_input`) | `waiting` |
| `Notification` (`idle_prompt`)          | `ready`                                 |
| `Notification` (other, e.g. `agent_completed`) | keep-alive only — never repaints  |
| `Stop`                                  | `ready`                                 |
| `SessionEnd`                            | delete file                             |

The last row matters: a subagent finishing mid-turn fires `agent_completed`, and
we deliberately *don't* let that flip a red (working) tile to yellow.

## Quick start

```sh
# 1. Wire the hooks into whichever Claude config dir(s) you use.
./bin/tbled install --config-dir ~/.claude-personal --config-dir ~/.claude-work

# 2. In another terminal, watch live status:
watch -n1 ./bin/tbled status      # or: while true; do clear; ./bin/tbled status; sleep 1; done

# 3. Start Claude Code sessions in a few repos and watch the colours change.
```

`install` backs up each `settings.json` first, is idempotent (safe to re-run),
and copies `tbled-hook` + `tbled` into `~/.tbled/bin`. Remove everything with:

```sh
./bin/tbled uninstall --config-dir ~/.claude-personal --config-dir ~/.claude-work
```

`install`/`uninstall` default to `$CLAUDE_CONFIG_DIR` (or `~/.claude`) when you
pass no `--config-dir`.

### CLI

```
tbled status      pretty-print the live session tiles (auto-runs sync)
tbled sync        import Claude's own live sessions (works without hooks)
tbled install     wire hooks into settings.json (backs up, idempotent)
tbled uninstall   remove them again
tbled reap        delete session files for dead / expired sessions
tbled dir         print the state directory (~/.tbled)
```

## Renderers

### MTMR (Touch Bar, works today)

The fastest path to real Touch Bar tiles with zero compilation — see
[`mtmr/README.md`](mtmr/README.md). A one-line shell widget renders the strip.

### Native app (`app/`)

A SwiftPM menu-bar agent that draws a persistent Control-Strip item plus an
expandable strip of named tiles, and mirrors them as coloured dots in the menu
bar (the always-works fallback, useful on non-Touch-Bar Macs). Touch Bar access
uses the same private `DFRFoundation` recipe as [Pock](https://github.com/pigigaldi/Pock)
and MTMR, isolated in a small ObjC shim and guarded so it degrades to no-ops
where those entry points are unavailable.

```sh
cd app
swift build -c release       # needs a working Swift toolchain (see caveat)
swift run tbled-selftest     # verify the TbledCore logic (works under CLT-only)
swift test                   # full XCTest suite (needs Xcode for XCTest)
```

#### Run it — one-word on/off

`tbled-app` builds/stages the binary and controls the running app. `tbled install`
stages it to `~/.tbled/bin`; you can also run it straight from `./bin/tbled-app`.

```sh
# one-time: build a release binary and stage it to ~/.tbled/bin/tbled-touchbar
./bin/tbled-app build ./app

# then control it with one word
tbled-app on                 # launch (Touch Bar tiles + menu-bar mirror)
tbled-app off                # stop
tbled-app toggle             # flip on/off
tbled-app status             # on / off
tbled-app restart
```

By default it takes over the Touch Bar's **app region** (replacing the focused
app's own bar). For a compact dot in the **Control Strip** (right, by brightness)
instead, set the mode:

```sh
TBLED_TOUCHBAR_MODE=strip tbled-app on
```

#### Add to `~/.zshrc`

Put `~/.tbled/bin` on your `PATH` and alias the toggle, so you can flip it from
anywhere by typing `tb`:

```sh
# tbled — Touch Bar status lights
export PATH="$HOME/.tbled/bin:$PATH"
alias tb='tbled-app toggle'
```

Reload with `source ~/.zshrc` (or open a new terminal), then just type **`tb`**.
For a global hotkey, add a *Run Shell Script* action running
`$HOME/.tbled/bin/tbled-app toggle` in **Shortcuts.app** and assign it a key.

Auto-start on login via `packaging/com.tbled.app.plist` (a LaunchAgent template).

## Configuration

Thresholds are environment-overridable (read by the CLI and MTMR widget):

| Variable            | Default | Meaning                         |
|---------------------|---------|---------------------------------|
| `TBLED_DIR`         | `~/.tbled` | state directory               |
| `TBLED_STALE_SECS`  | `1200`  | inactivity → dim/stale          |
| `TBLED_HIDE_SECS`   | `7200`  | inactivity → hidden / reaped    |

## Verification status (what's actually been tested)

Being precise about this, because parts run on hardware I can drive and parts
don't:

- **Pipeline (`bin/tbled-hook`, `bin/tbled`) — verified.** The full state
  machine was exercised with real hook payloads (ready→working→waiting→ready,
  the `agent_completed`-stays-working rule, dedup, stale/dead detection, reap,
  and idempotent install/uninstall that preserves existing hooks). A **real
  headless Claude Code session** confirmed the two things simulation can't: the
  installed (argv-less) hook receives the event via **stdin** and writes the
  correct state, and the recorded PID is the **durable Claude Code process**
  (so `kill -0` liveness is reliable, not a transient shell). The working/waiting
  *colour* transitions were later confirmed **live**, against a real interactive
  session running with the hooks installed. Requires **bash 3.2+** and `jq`
  (both stock on macOS).

- **MTMR widget — verified logic, needs your Touch Bar to see.** The renderer
  was tested against fixture state (colours, truncation, empty `💤` case). The
  actual Touch Bar display depends on your MTMR install.

- **Native app — compiles and its logic is tested; Touch Bar rendering not yet
  verified.** The whole package **builds cleanly** (`swift build` → a linked
  `tbled-touchbar` binary; the ObjC DFR shim compiles and links). `TbledCore`
  (parsing / stale / PID / dedup — the bug-prone part) passes **12/12 checks**
  via `swift run tbled-selftest`, an XCTest-free runner that works under Command
  Line Tools alone. (The XCTest suite in `Tests/` needs full Xcode.) What is
  *not* yet verified is the actual on-screen rendering: the menu-bar mirror and
  the private-API Touch Bar path have not been observed running on this macOS
  version — the private entry points are faithful to Pock/MTMR and guarded to
  degrade to no-ops, with the menu-bar mirror as the fallback.

## Layout

```
bin/tbled-hook        hook handler (one script, all events; atomic writes)
bin/tbled             CLI: status / install / uninstall / reap / dir
mtmr/tbled-strip.sh   MTMR Touch Bar widget (+ mtmr/README.md)
app/                  native SwiftPM Touch Bar app (TbledCore + CDFR shim)
packaging/            LaunchAgent template
```
