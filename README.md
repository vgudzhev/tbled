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
tbled status      pretty-print the live session tiles
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
swift test                   # runs the TbledCore logic unit tests
```

Auto-start via `packaging/com.tbled.app.plist` (a LaunchAgent template).

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
  (so `kill -0` liveness is reliable, not a transient shell). The one path not
  exercised on real hardware — the working/waiting *colour* transitions during
  an authenticated turn — was blocked only by Keychain auth isolation of the
  throwaway config dir, and runs through the byte-identical code path already
  proven. Requires **bash 3.2+** and `jq` (both stock on macOS).

- **MTMR widget — verified logic, needs your Touch Bar to see.** The renderer
  was tested against fixture state (colours, truncation, empty `💤` case). The
  actual Touch Bar display depends on your MTMR install.

- **Native app — written to recipe, _not_ runtime-verified.** `TbledCore` (the
  parsing / stale / PID / dedup logic) has unit tests; the ObjC shim passes a
  clang syntax check. But the app could **not be compiled or run in the build
  environment**: that machine's Command Line Tools Swift toolchain is internally
  broken (`import Foundation` fails — SDK/compiler version mismatch), with no
  Xcode available. Build it with a healthy toolchain (full Xcode, or a repaired
  CLT) before relying on it. The private-API Touch Bar path in particular is
  faithful to Pock/MTMR but unverified on this macOS version — the menu-bar
  mirror is the guaranteed-working fallback.

## Layout

```
bin/tbled-hook        hook handler (one script, all events; atomic writes)
bin/tbled             CLI: status / install / uninstall / reap / dir
mtmr/tbled-strip.sh   MTMR Touch Bar widget (+ mtmr/README.md)
app/                  native SwiftPM Touch Bar app (TbledCore + CDFR shim)
packaging/            LaunchAgent template
```
